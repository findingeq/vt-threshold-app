import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/app_state.dart';
import 'vitalpro_parser.dart';

/// A single breath data point for export
/// Contains parsed VitalPro data with tick-based timing
class BreathDataPoint {
  final DateTime timestamp;   // Wall clock time (anchored)
  final double elapsedSec;    // Elapsed seconds from tick counter (resets per phase)
  final int ve;               // Minute Ventilation (L/min)
  final int? hr;              // Heart rate (bpm) if available
  final String phase;         // Phase: warmup, workout, cooldown
  final bool isRecovery;      // True if this is during a recovery period (intervals only)
  final double speed;         // Speed in mph at time of recording

  BreathDataPoint({
    required this.timestamp,
    required this.elapsedSec,
    required this.ve,
    this.hr,
    required this.phase,
    this.isRecovery = false,
    required this.speed,
  });

  /// CSV header
  static String getCsvHeader() {
    return 'timestamp,elapsed_sec,VE,HR,phase,speed';
  }

  String toCsvRow() {
    // Format timestamp as ISO 8601 with milliseconds
    final ts = timestamp.toUtc().toIso8601String();
    final elapsed = elapsedSec.toStringAsFixed(3);
    final hrStr = hr?.toString() ?? '';

    return '$ts,$elapsed,$ve,$hrStr,$phase,${speed.toStringAsFixed(1)}';
  }
}

/// Summary statistics for a phase
class PhaseSummary {
  final String phase;
  final double avgHr;
  final double avgVe;
  final double? terminalSlopePct; // % VE drift per minute (intervals only)
  final int dataPointCount;

  PhaseSummary({
    required this.phase,
    required this.avgHr,
    required this.avgVe,
    this.terminalSlopePct,
    required this.dataPointCount,
  });
}

/// Workout metadata for export
class WorkoutMetadata {
  final DateTime date;
  final String runType; // moderate, heavy, severe
  final int? numIntervals;
  final double? intervalDurationMin;
  final double? recoveryDurationMin;
  final double speedMph;
  final double vt1Threshold;
  final double vt2Threshold;

  WorkoutMetadata({
    required this.date,
    required this.runType,
    this.numIntervals,
    this.intervalDurationMin,
    this.recoveryDurationMin,
    required this.speedMph,
    required this.vt1Threshold,
    required this.vt2Threshold,
  });

  String toCsvHeader() {
    final lines = <String>[
      '# Date: ${date.toIso8601String().split('T')[0]}',
      '# Run Type: $runType',
      '# Speed: ${speedMph.toStringAsFixed(1)} mph',
      '# VT1 Threshold: ${vt1Threshold.toStringAsFixed(1)} L/min',
      '# VT2 Threshold: ${vt2Threshold.toStringAsFixed(1)} L/min',
    ];

    // Include interval info for all run types
    if (numIntervals != null) {
      lines.add('# Intervals: $numIntervals');
      lines.add('# Interval Duration: ${intervalDurationMin?.toStringAsFixed(1)} min');
      lines.add('# Recovery Duration: ${recoveryDurationMin?.toStringAsFixed(1)} min');
    }

    return lines.join('\n');
  }
}

/// Service for collecting and exporting workout data
class WorkoutDataService extends ChangeNotifier {
  final List<BreathDataPoint> _dataPoints = [];
  WorkoutMetadata? _metadata;
  int _currentHr = 0;
  String _currentPhase = '';
  bool _currentIsRecovery = false;
  RunConfig? _runConfig;
  double _currentSpeed = 0.0;

  List<BreathDataPoint> get dataPoints => List.unmodifiable(_dataPoints);
  bool get hasData => _dataPoints.isNotEmpty;
  int get dataPointCount => _dataPoints.length;

  /// Start or continue a workout recording session
  /// Does NOT clear data - accumulates across phases
  void startRecording({
    required String phase,
    required RunConfig runConfig,
    required double vt1Ve,
    required double vt2Ve,
    required double phaseDurationMin,
    required double speedMph,
  }) {
    _currentPhase = phase;
    _currentHr = 0;
    _currentIsRecovery = false;
    _runConfig = runConfig;
    _currentSpeed = speedMph;

    // Only create metadata on first phase (don't overwrite)
    if (_metadata == null) {
      String runType;
      switch (runConfig.runType) {
        case RunType.moderate:
          runType = 'moderate';
          break;
        case RunType.heavy:
          runType = 'heavy';
          break;
        case RunType.severe:
          runType = 'severe';
          break;
      }
      _metadata = WorkoutMetadata(
        date: DateTime.now(),
        runType: runType,
        numIntervals: runConfig.numIntervals,
        intervalDurationMin: runConfig.intervalDurationMin,
        recoveryDurationMin: runConfig.recoveryDurationMin,
        speedMph: speedMph,
        vt1Threshold: vt1Ve,
        vt2Threshold: vt2Ve,
      );
    }

    notifyListeners();
  }

  /// Update current heart rate (called from HR sensor stream)
  void updateHeartRate(int hr) {
    _currentHr = hr;
  }

  /// Update recovery state (called during interval workouts)
  void setRecoveryState(bool isRecovery) {
    _currentIsRecovery = isRecovery;
  }

  /// Get current speed
  double get currentSpeed => _currentSpeed;

  /// Update current speed (called when user changes speed mid-workout)
  void setSpeed(double speed) {
    _currentSpeed = speed;
    notifyListeners();
  }

  // Track last data point time for gap detection and interpolation
  double? _lastDataElapsedSec;
  int? _lastDataVe;

  /// Add a parsed breath data point with app-side elapsed time
  /// The appElapsedSec parameter ensures data syncs with app timer, not device timer
  /// When there's a gap (sensor disconnect), interpolated points are created
  void addBreathData(VitalProBreathData data, {double? appElapsedSec}) {
    // Use app-side elapsed time if provided, otherwise fall back to device time
    final elapsedSec = appElapsedSec ?? data.elapsedSec;

    // Detect gap and interpolate if needed
    if (_lastDataElapsedSec != null && _lastDataVe != null) {
      final gap = elapsedSec - _lastDataElapsedSec!;

      // If gap is larger than 5 seconds, interpolate
      if (gap > 5.0) {
        final numPoints = (gap / 3.0).floor(); // One point every 3 seconds
        final veStart = _lastDataVe!.toDouble();
        final veEnd = data.veRaw.toDouble();

        for (int i = 1; i < numPoints; i++) {
          final t = i / numPoints;
          final interpolatedTime = _lastDataElapsedSec! + (gap * t);
          final interpolatedVe = (veStart + (veEnd - veStart) * t).round();

          _dataPoints.add(BreathDataPoint(
            timestamp: DateTime.now(), // Approximate timestamp
            elapsedSec: interpolatedTime,
            ve: interpolatedVe,
            hr: _currentHr > 0 ? _currentHr : null,
            phase: _currentPhase,
            isRecovery: _currentIsRecovery,
            speed: _currentSpeed,
          ));
        }
      }
    }

    // Add the actual data point
    _dataPoints.add(BreathDataPoint(
      timestamp: data.timestamp,
      elapsedSec: elapsedSec,
      ve: data.veRaw,
      hr: _currentHr > 0 ? _currentHr : null,
      phase: _currentPhase,
      isRecovery: _currentIsRecovery,
      speed: _currentSpeed,
    ));

    // Update tracking for next gap detection
    _lastDataElapsedSec = elapsedSec;
    _lastDataVe = data.veRaw;

    notifyListeners();
  }

  /// Reset phase tracking (call when starting new phase)
  void resetPhaseTracking() {
    _lastDataElapsedSec = null;
    _lastDataVe = null;
  }

  /// Get data points for a specific phase
  List<BreathDataPoint> getPhaseData(String phase) {
    return _dataPoints.where((p) => p.phase == phase).toList();
  }

  /// Get data points for interval portions only (excludes recovery)
  List<BreathDataPoint> getIntervalOnlyData(String phase) {
    return _dataPoints.where((p) => p.phase == phase && !p.isRecovery).toList();
  }

  /// Calculate summary statistics for a phase
  PhaseSummary? calculatePhaseSummary(String phase) {
    final isIntervalWorkout = (_runConfig?.numIntervals ?? 0) > 1 && phase == 'workout';

    // For interval workouts, only use interval data (exclude recovery)
    final phaseData = isIntervalWorkout ? getIntervalOnlyData(phase) : getPhaseData(phase);

    if (phaseData.isEmpty) return null;

    // Calculate average HR (only from points with HR data)
    final hrPoints = phaseData.where((p) => p.hr != null).toList();
    final avgHr = hrPoints.isEmpty
        ? 0.0
        : hrPoints.map((p) => p.hr!).reduce((a, b) => a + b) / hrPoints.length;

    // Calculate average VE
    final avgVe = phaseData.map((p) => p.ve).reduce((a, b) => a + b) / phaseData.length;

    // Calculate terminal slope for interval workouts
    double? terminalSlopePct;
    if (isIntervalWorkout && _runConfig != null) {
      terminalSlopePct = _calculateTerminalSlope(phaseData);
    }

    return PhaseSummary(
      phase: phase,
      avgHr: avgHr,
      avgVe: avgVe,
      terminalSlopePct: terminalSlopePct,
      dataPointCount: phaseData.length,
    );
  }

  /// Calculate terminal slope: % VE drift per minute in last 30 seconds of each interval
  double? _calculateTerminalSlope(List<BreathDataPoint> intervalData) {
    if (_runConfig == null || intervalData.isEmpty) return null;

    final intervalDurationSec = _runConfig!.intervalDurationSec;
    final terminalWindowSec = 30.0;
    final terminalStartSec = intervalDurationSec - terminalWindowSec;

    if (terminalStartSec <= 0) return null; // Interval too short

    // Group data by interval (using elapsed time modulo cycle duration)
    // For each interval, find points in the terminal window
    final cycleDurationSec = _runConfig!.cycleDurationSec;
    final numIntervals = _runConfig!.numIntervals;

    final slopes = <double>[];

    for (int i = 0; i < numIntervals; i++) {
      final cycleStart = i * cycleDurationSec;
      final terminalStart = cycleStart + terminalStartSec;
      final terminalEnd = cycleStart + intervalDurationSec;

      // Get points in this interval's terminal window
      final terminalPoints = intervalData.where((p) {
        // Calculate absolute elapsed time accounting for phase
        return p.elapsedSec >= terminalStart && p.elapsedSec < terminalEnd;
      }).toList();

      if (terminalPoints.length < 2) continue;

      // Sort by elapsed time
      terminalPoints.sort((a, b) => a.elapsedSec.compareTo(b.elapsedSec));

      // Get VE at start and end of terminal window
      final startVe = terminalPoints.first.ve.toDouble();
      final endVe = terminalPoints.last.ve.toDouble();
      final timeDiffMin = (terminalPoints.last.elapsedSec - terminalPoints.first.elapsedSec) / 60.0;

      if (startVe <= 0 || timeDiffMin <= 0) continue;

      // Calculate % drift per minute: ((end - start) / start) * 100 / timeDiffMin
      final pctDriftPerMin = ((endVe - startVe) / startVe) * 100.0 / timeDiffMin;
      slopes.add(pctDriftPerMin);
    }

    if (slopes.isEmpty) return null;

    // Return average slope across all intervals
    return slopes.reduce((a, b) => a + b) / slopes.length;
  }

  /// Stop recording
  void stopRecording() {
    // Recording stopped, data is ready for export
    notifyListeners();
  }

  /// Generate CSV content
  String generateCsv() {
    if (_metadata == null) return '';

    final buffer = StringBuffer();

    // Write metadata header
    buffer.writeln(_metadata!.toCsvHeader());
    buffer.writeln('#');

    // Write column headers
    buffer.writeln(BreathDataPoint.getCsvHeader());

    // Write data rows
    for (final point in _dataPoints) {
      buffer.writeln(point.toCsvRow());
    }

    return buffer.toString();
  }

  /// Generate filename for export
  String generateFilename() {
    if (_metadata == null) return 'vitalpro_export.csv';

    final date = _metadata!.date.toIso8601String().split('T')[0];
    final runType = _metadata!.runType;

    return '${date}_${runType}_session.csv';
  }

  /// Export data to a CSV file and share
  Future<void> exportCsv() async {
    if (_metadata == null || _dataPoints.isEmpty) {
      debugPrint('No data to export');
      throw Exception('No workout data to export. Complete a workout first.');
    }

    try {
      // Get temporary directory
      final directory = await getTemporaryDirectory();
      final filename = generateFilename();
      final file = File('${directory.path}/$filename');

      // Write CSV content
      final csvContent = generateCsv();
      await file.writeAsString(csvContent);

      debugPrint('Saved CSV to: ${file.path}');
      debugPrint('Data points: ${_dataPoints.length}');

      // Share the file
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'VT Threshold Workout Data',
      );
    } catch (e) {
      debugPrint('Export error: $e');
      rethrow;
    }
  }

  /// Cloud API base URL
  static const String _cloudBaseUrl = 'https://web-production-11d09.up.railway.app';
  static const String _cloudApiUrl = '$_cloudBaseUrl/api/upload';

  /// Fetches calibrated parameters from the cloud
  Future<Map<String, dynamic>?> fetchCalibratedParams(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$_cloudBaseUrl/api/calibration/params?user_id=$userId'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'vt1_ve': data['vt1_ve']?.toDouble(),
          'vt2_ve': data['vt2_ve']?.toDouble(),
          'sigma_pct_moderate': data['sigma_pct_moderate']?.toDouble(),
          'sigma_pct_heavy': data['sigma_pct_heavy']?.toDouble(),
          'sigma_pct_severe': data['sigma_pct_severe']?.toDouble(),
          'last_updated': data['last_updated'],
        };
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching calibrated params: $e');
      return null;
    }
  }

  /// Syncs a manual threshold change to the cloud
  /// This resets the Bayesian anchor to the new value
  Future<bool> syncThresholdToCloud(String userId, String threshold, double value) async {
    try {
      final response = await http.post(
        Uri.parse('$_cloudBaseUrl/api/calibration/set-ve-threshold'
            '?user_id=$userId&threshold=$threshold&value=$value'),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error syncing threshold to cloud: $e');
      return false;
    }
  }

  /// Upload data to cloud storage
  Future<void> uploadToCloud({String? userId}) async {
    if (_metadata == null || _dataPoints.isEmpty) {
      debugPrint('No data to upload');
      throw Exception('No workout data to upload. Complete a workout first.');
    }

    try {
      final csvContent = generateCsv();
      final filename = generateFilename();

      debugPrint('Uploading to cloud: $filename');
      debugPrint('Data points: ${_dataPoints.length}');
      debugPrint('User ID: $userId');

      final response = await http.post(
        Uri.parse(_cloudApiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'filename': filename,
          'csv_content': csvContent,
          if (userId != null && userId.isNotEmpty) 'user_id': userId,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('Upload successful');
      } else {
        throw Exception('Upload failed: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('Upload error: $e');
      rethrow;
    }
  }

  /// Clear all data
  void clear() {
    _dataPoints.clear();
    _metadata = null;
    _currentHr = 0;
    _currentPhase = '';
    _currentIsRecovery = false;
    _runConfig = null;
    _currentSpeed = 0.0;
    _lastDataElapsedSec = null;
    _lastDataVe = null;
    notifyListeners();
  }
}
