import 'dart:collection';
import 'dart:math';

import '../models/app_state.dart';

/// Data for a single breath from the VitalPro sensor
class BreathData {
  final DateTime timestamp;
  final double ve; // L/min
  final double vt; // Tidal volume
  final double br; // Breathing rate

  BreathData({
    required this.timestamp,
    required this.ve,
    this.vt = 0,
    this.br = 0,
  });
}

/// Result of CUSUM analysis for UI display
class CusumStatus {
  final double cusumScore;
  final double cusumThreshold; // H value
  final double filteredVe;
  final double? binAvgVe; // Latest bin average (for trend line)
  final bool alarmTriggered;
  final DateTime? alarmTime;

  CusumStatus({
    required this.cusumScore,
    required this.cusumThreshold,
    required this.filteredVe,
    this.binAvgVe,
    required this.alarmTriggered,
    this.alarmTime,
  });

  /// 0-1 scale for color interpolation
  double get normalizedScore => 
      cusumThreshold > 0 ? (cusumScore / cusumThreshold).clamp(0.0, 1.5) : 0;

  /// Color zones: green (0-0.5H), yellow (0.5-1H), red (>1H)
  String get zone {
    if (normalizedScore < 0.5) return 'green';
    if (normalizedScore < 1.0) return 'yellow';
    return 'red';
  }
}

/// Real-time CUSUM processor with user-input baseline
/// 
/// Key features:
/// - No blanking/calibration period
/// - Baseline VE provided by user from prior ramp test
/// - Two-stage filtering: median filter + time binning
/// - Starts accumulating after median filter warm-up (~5-10 breaths)
class CusumProcessor {
  // User-provided baseline
  final double baselineVe;
  final RunType runType;

  // CUSUM parameters
  final double hMultiplier;
  final double slackMultiplier;
  
  // Filtering parameters
  final int medianWindowSize;
  final double binSizeSec;

  // Derived parameters (calculated in constructor)
  late final double _sigma;
  late final double _k; // Slack
  late final double _h; // Threshold

  // State
  final Queue<double> _veBuffer = Queue<double>();
  final List<double> _binBuffer = [];
  DateTime? _binStartTime;
  DateTime? _startTime;

  double _cusumScore = 0.0;
  double _peakCusum = 0.0;
  bool _alarmTriggered = false;
  DateTime? _alarmTime;

  double _latestFilteredVe = 0.0;
  double? _latestBinAvgVe;

  // Track bin averages for trend line
  final List<BinDataPoint> _binHistory = [];

  CusumProcessor({
    required this.baselineVe,
    required this.runType,
    this.hMultiplier = 5.0,
    this.slackMultiplier = 0.5,
    this.medianWindowSize = 9,
    this.binSizeSec = 4.0,
  }) {
    // Sigma as percentage of baseline: 10% for VT1, 5% for VT2
    final sigmaPct = runType == RunType.vt1SteadyState ? 10.0 : 5.0;
    _sigma = (sigmaPct / 100.0) * baselineVe;
    _k = slackMultiplier * _sigma;
    _h = hMultiplier * _sigma;
  }

  // Getters
  double get cusumScore => _cusumScore;
  double get peakCusum => _peakCusum;
  double get threshold => _h;
  bool get alarmTriggered => _alarmTriggered;
  DateTime? get alarmTime => _alarmTime;
  double get latestFilteredVe => _latestFilteredVe;
  double? get latestBinAvgVe => _latestBinAvgVe;
  List<BinDataPoint> get binHistory => List.unmodifiable(_binHistory);

  bool get isWarmedUp => _veBuffer.length >= medianWindowSize;

  /// Process a new breath
  CusumStatus processBreath(BreathData breath) {
    _startTime ??= breath.timestamp;

    // Stage 1: Median filter (per breath)
    _veBuffer.addLast(breath.ve);
    if (_veBuffer.length > medianWindowSize) {
      _veBuffer.removeFirst();
    }

    // Only compute median once we have enough samples
    if (_veBuffer.length >= medianWindowSize) {
      _latestFilteredVe = _medianFilter(_veBuffer.toList());
    } else {
      _latestFilteredVe = breath.ve;
    }

    // Stage 2: Time binning
    _binStartTime ??= breath.timestamp;
    _binBuffer.add(_latestFilteredVe);

    final binElapsedSec = 
        breath.timestamp.difference(_binStartTime!).inMilliseconds / 1000.0;

    // Process when bin is complete (every 4 seconds)
    if (binElapsedSec >= binSizeSec && _binBuffer.isNotEmpty) {
      final binAvgVe = _binBuffer.reduce((a, b) => a + b) / _binBuffer.length;
      _latestBinAvgVe = binAvgVe;

      // Record bin for trend line
      final elapsedSec = 
          breath.timestamp.difference(_startTime!).inMilliseconds / 1000.0;
      _binHistory.add(BinDataPoint(
        timestamp: breath.timestamp,
        elapsedSec: elapsedSec,
        avgVe: binAvgVe,
      ));

      // CUSUM update (only after median filter warmed up)
      if (isWarmedUp) {
        _updateCusum(binAvgVe);
      }

      // Reset bin buffer
      _binBuffer.clear();
      _binStartTime = breath.timestamp;
    }

    return CusumStatus(
      cusumScore: _cusumScore,
      cusumThreshold: _h,
      filteredVe: _latestFilteredVe,
      binAvgVe: _latestBinAvgVe,
      alarmTriggered: _alarmTriggered,
      alarmTime: _alarmTime,
    );
  }

  /// Update CUSUM with new bin average
  void _updateCusum(double binAvgVe) {
    // Residual: how much VE exceeds baseline
    final residual = binAvgVe - baselineVe;

    // One-sided upper CUSUM (detects VE rising above baseline)
    _cusumScore = max(0, _cusumScore + residual - _k);
    _peakCusum = max(_peakCusum, _cusumScore);

    // Check for alarm
    if (_cusumScore >= _h && !_alarmTriggered) {
      _alarmTriggered = true;
      _alarmTime = DateTime.now();
    }
  }

  /// Reset for new interval (VT2 runs)
  void resetForNewInterval() {
    _veBuffer.clear();
    _binBuffer.clear();
    _binStartTime = null;
    _startTime = null;
    _cusumScore = 0.0;
    _peakCusum = 0.0;
    _alarmTriggered = false;
    _alarmTime = null;
    _latestFilteredVe = 0.0;
    _latestBinAvgVe = null;
    _binHistory.clear();
  }

  /// Full reset
  void reset() {
    resetForNewInterval();
  }

  /// Median filter helper
  double _medianFilter(List<double> values) {
    if (values.isEmpty) return 0;
    if (values.length == 1) return values[0];

    final sorted = List<double>.from(values)..sort();
    final mid = sorted.length ~/ 2;

    if (sorted.length.isOdd) {
      return sorted[mid];
    } else {
      return (sorted[mid - 1] + sorted[mid]) / 2;
    }
  }
}

/// A single bin data point for trend line visualization
class BinDataPoint {
  final DateTime timestamp;
  final double elapsedSec;
  final double avgVe;

  BinDataPoint({
    required this.timestamp,
    required this.elapsedSec,
    required this.avgVe,
  });
}
