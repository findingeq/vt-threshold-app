import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/app_state.dart';
import 'ble_service.dart';

/// A single breath data point for export - captures all raw bytes
class BreathDataPoint {
  final DateTime timestamp;
  final double elapsedSec;
  final List<int> rawBytes;
  final String rawHex;
  final int? hr;

  BreathDataPoint({
    required this.timestamp,
    required this.elapsedSec,
    required this.rawBytes,
    required this.rawHex,
    this.hr,
  });

  /// Get CSV header for dynamic number of bytes
  static String getCsvHeader(int maxBytes) {
    final byteHeaders = List.generate(maxBytes, (i) => 'byte$i').join(',');
    return 'timestamp,elapsed_sec,hr,raw_hex,$byteHeaders';
  }

  String toCsvRow(int maxBytes) {
    final ts = timestamp.toIso8601String();
    final elapsed = elapsedSec.toStringAsFixed(3);
    final hrStr = hr?.toString() ?? '';

    // Pad bytes to maxBytes length
    final paddedBytes = List<int>.filled(maxBytes, 0);
    for (int i = 0; i < rawBytes.length && i < maxBytes; i++) {
      paddedBytes[i] = rawBytes[i];
    }
    final bytesStr = paddedBytes.join(',');

    return '$ts,$elapsed,$hrStr,$rawHex,$bytesStr';
  }
}

/// Workout metadata for export
class WorkoutMetadata {
  final DateTime date;
  final String phase; // warmup, workout, cooldown
  final String runType; // vt1, vt2
  final int? numIntervals;
  final double? intervalDurationMin;
  final double? recoveryDurationMin;
  final double speedMph;
  final double vt1Threshold;
  final double vt2Threshold;
  final double phaseDurationMin;

  WorkoutMetadata({
    required this.date,
    required this.phase,
    required this.runType,
    this.numIntervals,
    this.intervalDurationMin,
    this.recoveryDurationMin,
    required this.speedMph,
    required this.vt1Threshold,
    required this.vt2Threshold,
    required this.phaseDurationMin,
  });

  String toCsvHeader() {
    final lines = <String>[
      '# Date: ${date.toIso8601String().split('T')[0]}',
      '# Phase: $phase',
      '# Run Type: $runType',
      '# Speed: ${speedMph.toStringAsFixed(1)} mph',
      '# VT1 Threshold: ${vt1Threshold.toStringAsFixed(1)} L/min',
      '# VT2 Threshold: ${vt2Threshold.toStringAsFixed(1)} L/min',
      '# Phase Duration: ${phaseDurationMin.toStringAsFixed(1)} min',
    ];

    if (runType == 'vt2' && phase == 'workout') {
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
  DateTime? _startTime;
  int _currentHr = 0;

  List<BreathDataPoint> get dataPoints => List.unmodifiable(_dataPoints);
  bool get hasData => _dataPoints.isNotEmpty;
  int get dataPointCount => _dataPoints.length;

  /// Start a new workout recording session
  void startRecording({
    required String phase,
    required RunConfig runConfig,
    required double vt1Ve,
    required double vt2Ve,
    required double phaseDurationMin,
    required double speedMph,
  }) {
    _dataPoints.clear();
    _startTime = DateTime.now();

    // Determine run type for this phase
    // Warmups and cooldowns are always saved as VT1
    String runType;
    if (phase == 'warmup' || phase == 'cooldown') {
      runType = 'vt1';
    } else {
      runType = runConfig.runType == RunType.vt1SteadyState ? 'vt1' : 'vt2';
    }

    _metadata = WorkoutMetadata(
      date: _startTime!,
      phase: phase,
      runType: runType,
      numIntervals: runConfig.runType == RunType.vt2Intervals ? runConfig.numIntervals : null,
      intervalDurationMin: runConfig.runType == RunType.vt2Intervals ? runConfig.intervalDurationMin : null,
      recoveryDurationMin: runConfig.runType == RunType.vt2Intervals ? runConfig.recoveryDurationMin : null,
      speedMph: speedMph,
      vt1Threshold: vt1Ve,
      vt2Threshold: vt2Ve,
      phaseDurationMin: phaseDurationMin,
    );

    notifyListeners();
  }

  /// Update current heart rate (called from HR sensor stream)
  void updateHeartRate(int hr) {
    _currentHr = hr;
  }

  /// Add a breath data point from sensor
  void addBreathData(VitalProData data) {
    if (_startTime == null) return;

    final elapsed = data.timestamp.difference(_startTime!).inMilliseconds / 1000.0;

    _dataPoints.add(BreathDataPoint(
      timestamp: data.timestamp,
      elapsedSec: elapsed,
      rawBytes: data.rawBytes,
      rawHex: data.rawHex,
      hr: _currentHr > 0 ? _currentHr : null,
    ));

    notifyListeners();
  }

  /// Stop recording
  void stopRecording() {
    // Recording stopped, data is ready for export
    notifyListeners();
  }

  /// Generate CSV content
  String generateCsv() {
    if (_metadata == null) return '';

    // Find max bytes across all data points
    int maxBytes = 0;
    for (final point in _dataPoints) {
      if (point.rawBytes.length > maxBytes) {
        maxBytes = point.rawBytes.length;
      }
    }
    // Default to at least 16 bytes
    if (maxBytes < 16) maxBytes = 16;

    final buffer = StringBuffer();

    // Write metadata header
    buffer.writeln(_metadata!.toCsvHeader());
    buffer.writeln('#');

    // Write column headers
    buffer.writeln(BreathDataPoint.getCsvHeader(maxBytes));

    // Write data rows
    for (final point in _dataPoints) {
      buffer.writeln(point.toCsvRow(maxBytes));
    }

    return buffer.toString();
  }

  /// Generate filename for export
  String generateFilename() {
    if (_metadata == null) return 'workout.csv';

    final date = _metadata!.date.toIso8601String().split('T')[0];
    final phase = _metadata!.phase;
    final runType = _metadata!.runType;

    return '${date}_${runType}_$phase.csv';
  }

  /// Export data to a CSV file and share
  Future<void> exportCsv() async {
    if (_metadata == null || _dataPoints.isEmpty) {
      debugPrint('No data to export');
      return;
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

  /// Clear all data
  void clear() {
    _dataPoints.clear();
    _metadata = null;
    _startTime = null;
    _currentHr = 0;
    notifyListeners();
  }
}
