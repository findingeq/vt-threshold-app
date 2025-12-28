import 'package:flutter/foundation.dart';

enum RunType { vt1SteadyState, vt2Intervals }

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
  double get cycleDurationSec => (intervalDurationMin + recoveryDurationMin) * 60.0;
  double get intervalDurationSec => intervalDurationMin * 60.0;
  double get recoveryDurationSec => recoveryDurationMin * 60.0;
}

class AppState extends ChangeNotifier {
  // Sensor connection status
  bool _breathingSensorConnected = false;
  bool _hrSensorConnected = false;
  int _breathingSensorBattery = 0;
  int _hrSensorBattery = 0;

  // VT thresholds (in-memory only - will reset on app restart)
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

  Future<void> setVt1Ve(double value) async {
    _vt1Ve = value;
    notifyListeners();
  }

  Future<void> setVt2Ve(double value) async {
    _vt2Ve = value;
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
