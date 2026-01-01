import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum RunType { moderate, heavy, severe }

class RunConfig {
  final RunType runType;
  final double speedMph;
  final int numIntervals;
  final double intervalDurationMin;
  final double recoveryDurationMin;
  final double thresholdVe;
  final double warmupDurationMin;
  final double cooldownDurationMin;
  final double vt1Ve;
  final double warmupSpeedMph;
  final double cooldownSpeedMph;

  RunConfig({
    required this.runType,
    required this.speedMph,
    this.numIntervals = 1,
    this.intervalDurationMin = 4.0,
    this.recoveryDurationMin = 1.0,
    required this.thresholdVe,
    this.warmupDurationMin = 0.0,
    this.cooldownDurationMin = 0.0,
    required this.vt1Ve,
    this.warmupSpeedMph = 5.0,
    this.cooldownSpeedMph = 5.0,
  });

  bool get hasWarmup => warmupDurationMin > 0;
  bool get hasCooldown => cooldownDurationMin > 0;
  double get cycleDurationSec => (intervalDurationMin + recoveryDurationMin) * 60.0;
  double get intervalDurationSec => intervalDurationMin * 60.0;
  double get recoveryDurationSec => recoveryDurationMin * 60.0;

  /// Create a copy with modified speed for a specific phase
  RunConfig copyWithSpeed({
    double? speedMph,
    double? warmupSpeedMph,
    double? cooldownSpeedMph,
  }) {
    return RunConfig(
      runType: runType,
      speedMph: speedMph ?? this.speedMph,
      numIntervals: numIntervals,
      intervalDurationMin: intervalDurationMin,
      recoveryDurationMin: recoveryDurationMin,
      thresholdVe: thresholdVe,
      warmupDurationMin: warmupDurationMin,
      cooldownDurationMin: cooldownDurationMin,
      vt1Ve: vt1Ve,
      warmupSpeedMph: warmupSpeedMph ?? this.warmupSpeedMph,
      cooldownSpeedMph: cooldownSpeedMph ?? this.cooldownSpeedMph,
    );
  }
}

class AppState extends ChangeNotifier {
  // Storage keys
  static const String _vt1VeKey = 'vt1_ve';
  static const String _vt2VeKey = 'vt2_ve';

  // Sensor connection status
  bool _breathingSensorConnected = false;
  bool _hrSensorConnected = false;
  int _breathingSensorBattery = 0;
  int _hrSensorBattery = 0;

  // VT thresholds (persisted to SharedPreferences)
  double _vt1Ve = 60.0;
  double _vt2Ve = 80.0;

  // Current run config
  RunConfig? _currentRun;

  // Getters
  bool get breathingSensorConnected => _breathingSensorConnected;
  bool get hrSensorConnected => _hrSensorConnected;
  int get breathingSensorBattery => _breathingSensorBattery;
  int get hrSensorBattery => _hrSensorBattery;
  double get vt1Ve => _vt1Ve;
  double get vt2Ve => _vt2Ve;
  RunConfig? get currentRun => _currentRun;
  bool get sensorsReady => _breathingSensorConnected && _hrSensorConnected;

  /// Load persisted VT thresholds from storage
  Future<void> loadPersistedValues() async {
    final prefs = await SharedPreferences.getInstance();
    _vt1Ve = prefs.getDouble(_vt1VeKey) ?? 60.0;
    _vt2Ve = prefs.getDouble(_vt2VeKey) ?? 80.0;
    notifyListeners();
  }

  Future<void> setVt1Ve(double value) async {
    _vt1Ve = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_vt1VeKey, value);
    notifyListeners();
  }

  Future<void> setVt2Ve(double value) async {
    _vt2Ve = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_vt2VeKey, value);
    notifyListeners();
  }

  void setBreathingSensorConnected(bool connected, {int battery = 0}) {
    _breathingSensorConnected = connected;
    _breathingSensorBattery = battery;
    notifyListeners();
  }

  void setHrSensorConnected(bool connected, {int battery = 0}) {
    _hrSensorConnected = connected;
    _hrSensorBattery = battery;
    notifyListeners();
  }

  void setCurrentRun(RunConfig config) {
    _currentRun = config;
    notifyListeners();
  }

  void clearCurrentRun() {
    _currentRun = null;
    notifyListeners();
  }
}
