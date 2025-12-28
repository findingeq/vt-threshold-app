import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

enum RunType { vt1SteadyState, vt2Intervals }

class RunConfig {
  final RunType runType;
  final double speedMph;
  final int numIntervals;
  final double intervalDurationMin;
  final double recoveryDurationMin;
  final double thresholdVe; // VT1 VE or VT2 VE based on run type
  final double warmupDurationMin; // 0 = no warmup
  final double cooldownDurationMin; // 0 = no cooldown
  final double vt1Ve; // Always needed for warmup/cooldown

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
  });

  bool get hasWarmup => warmupDurationMin > 0;
  bool get hasCooldown => cooldownDurationMin > 0;

  /// Duration of one full cycle (interval + recovery) in seconds
  double get cycleDurationSec =>
      (intervalDurationMin + recoveryDurationMin) * 60.0;

  /// Duration of interval only in seconds
  double get intervalDurationSec => intervalDurationMin * 60.0;

  /// Duration of recovery only in seconds
  double get recoveryDurationSec => recoveryDurationMin * 60.0;
}

class AppState extends ChangeNotifier {
  final Box _box;

  // Sensor connection status
  bool _breathingSensorConnected = false;
  bool _hrSensorConnected = false;
  int _breathingSensorBattery = 0;
  int _hrSensorBattery = 0;

  // Persisted VT thresholds
  double _vt1Ve = 60.0; // Default L/min
  double _vt2Ve = 80.0; // Default L/min

  // Current run config (set when starting workout)
  RunConfig? _currentRun;

  AppState(this._box) {
    _loadPersistedSettings();
  }

  // Getters
  bool get breathingSensorConnected => _breathingSensorConnected;
  bool get hrSensorConnected => _hrSensorConnected;
  int get breathingSensorBattery => _breathingSensorBattery;
  int get hrSensorBattery => _hrSensorBattery;
  double get vt1Ve => _vt1Ve;
  double get vt2Ve => _vt2Ve;
  RunConfig? get currentRun => _currentRun;

  bool get sensorsReady => _breathingSensorConnected && _hrSensorConnected;

  // Load persisted settings
  void _loadPersistedSettings() {
    _vt1Ve = _box.get('vt1_ve', defaultValue: 60.0);
    _vt2Ve = _box.get('vt2_ve', defaultValue: 80.0);
    notifyListeners();
  }

  // Update VT1 VE threshold
  Future<void> setVt1Ve(double value) async {
    _vt1Ve = value;
    await _box.put('vt1_ve', value);
    notifyListeners();
  }

  // Update VT2 VE threshold
  Future<void> setVt2Ve(double value) async {
    _vt2Ve = value;
    await _box.put('vt2_ve', value);
    notifyListeners();
  }

  // Sensor connection methods (to be implemented with flutter_blue_plus)
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

  // Set current run configuration
  void setCurrentRun(RunConfig config) {
    _currentRun = config;
    notifyListeners();
  }

  void clearCurrentRun() {
    _currentRun = null;
    notifyListeners();
  }
}
