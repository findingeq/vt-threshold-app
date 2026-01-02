import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/workout_data_service.dart';
import '../theme/app_theme.dart';

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
  static const String _sigmaModeratePctKey = 'sigma_pct_moderate';
  static const String _sigmaHeavyPctKey = 'sigma_pct_heavy';
  static const String _sigmaSeverePctKey = 'sigma_pct_severe';
  static const String _userIdKey = 'calibration_user_id';

  // Sensor connection status
  bool _breathingSensorConnected = false;
  bool _hrSensorConnected = false;
  int _breathingSensorBattery = 0;
  int _hrSensorBattery = 0;

  // VT thresholds (persisted to SharedPreferences)
  double _vt1Ve = 60.0;
  double _vt2Ve = 80.0;

  // Sigma values for CUSUM sensitivity (persisted)
  double _sigmaPctModerate = 10.0;
  double _sigmaPctHeavy = 5.0;
  double _sigmaPctSevere = 5.0;

  // User ID for cloud sync (persisted)
  String? _userId;

  // Current run config
  RunConfig? _currentRun;

  // Getters
  bool get breathingSensorConnected => _breathingSensorConnected;
  bool get hrSensorConnected => _hrSensorConnected;
  int get breathingSensorBattery => _breathingSensorBattery;
  int get hrSensorBattery => _hrSensorBattery;
  double get vt1Ve => _vt1Ve;
  double get vt2Ve => _vt2Ve;
  double get sigmaPctModerate => _sigmaPctModerate;
  double get sigmaPctHeavy => _sigmaPctHeavy;
  double get sigmaPctSevere => _sigmaPctSevere;
  String get userId => _userId ?? '';
  RunConfig? get currentRun => _currentRun;
  bool get sensorsReady => _breathingSensorConnected && _hrSensorConnected;

  /// Load persisted values from storage
  Future<void> loadPersistedValues() async {
    final prefs = await SharedPreferences.getInstance();

    // Load VT thresholds
    _vt1Ve = prefs.getDouble(_vt1VeKey) ?? 60.0;
    _vt2Ve = prefs.getDouble(_vt2VeKey) ?? 80.0;

    // Load sigma values
    _sigmaPctModerate = prefs.getDouble(_sigmaModeratePctKey) ?? 10.0;
    _sigmaPctHeavy = prefs.getDouble(_sigmaHeavyPctKey) ?? 5.0;
    _sigmaPctSevere = prefs.getDouble(_sigmaSeverePctKey) ?? 5.0;

    // Get or create user ID
    _userId = prefs.getString(_userIdKey);
    if (_userId == null) {
      _userId = _generateUUID();
      await prefs.setString(_userIdKey, _userId!);
    }

    notifyListeners();
  }

  /// Generate a UUID v4
  String _generateUUID() {
    final random = Random();
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replaceAllMapped(
      RegExp(r'[xy]'),
      (match) {
        final r = random.nextInt(16);
        final v = match.group(0) == 'x' ? r : (r & 0x3 | 0x8);
        return v.toRadixString(16);
      },
    );
  }

  /// Set VT1 threshold (local + cloud sync)
  Future<void> setVt1Ve(double value) async {
    _vt1Ve = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_vt1VeKey, value);
    notifyListeners();

    // Sync to cloud (resets Bayesian anchor)
    if (_userId != null) {
      final service = WorkoutDataService();
      await service.syncThresholdToCloud(_userId!, 'vt1', value);
    }
  }

  /// Set VT2 threshold (local + cloud sync)
  Future<void> setVt2Ve(double value) async {
    _vt2Ve = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_vt2VeKey, value);
    notifyListeners();

    // Sync to cloud (resets Bayesian anchor)
    if (_userId != null) {
      final service = WorkoutDataService();
      await service.syncThresholdToCloud(_userId!, 'vt2', value);
    }
  }

  /// Set sigma values (local only, called during cloud sync)
  Future<void> _setSigmaValues({
    double? moderate,
    double? heavy,
    double? severe,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    if (moderate != null) {
      _sigmaPctModerate = moderate;
      await prefs.setDouble(_sigmaModeratePctKey, moderate);
    }
    if (heavy != null) {
      _sigmaPctHeavy = heavy;
      await prefs.setDouble(_sigmaHeavyPctKey, heavy);
    }
    if (severe != null) {
      _sigmaPctSevere = severe;
      await prefs.setDouble(_sigmaSeverePctKey, severe);
    }

    notifyListeners();
  }

  /// Sync calibrated params from cloud
  /// Call this on app launch
  Future<void> syncFromCloud(BuildContext? context) async {
    if (_userId == null) return;

    final service = WorkoutDataService();
    final calibrated = await service.fetchCalibratedParams(_userId!);

    if (calibrated == null) return;

    // Check for significant VE threshold changes (>= 1 L/min)
    final vt1Cloud = calibrated['vt1_ve'] as double?;
    final vt2Cloud = calibrated['vt2_ve'] as double?;

    final vt1Change = vt1Cloud != null ? (vt1Cloud - _vt1Ve).abs() : 0.0;
    final vt2Change = vt2Cloud != null ? (vt2Cloud - _vt2Ve).abs() : 0.0;

    if ((vt1Change >= 1.0 || vt2Change >= 1.0) && context != null) {
      // Show confirmation dialog for VE thresholds
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surfaceCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          ),
          title: Text(
            'Update Thresholds?',
            style: AppTheme.titleLarge,
          ),
          content: Text(
            'Cloud calibration suggests:\n'
            'VT1: ${vt1Cloud?.toStringAsFixed(1) ?? _vt1Ve.toStringAsFixed(1)} L/min\n'
            'VT2: ${vt2Cloud?.toStringAsFixed(1) ?? _vt2Ve.toStringAsFixed(1)} L/min\n\n'
            'Apply these changes?',
            style: AppTheme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Keep Current',
                style: AppTheme.bodyMedium.copyWith(color: AppTheme.textMuted),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Apply',
                style: AppTheme.bodyMedium.copyWith(color: AppTheme.accentBlue),
              ),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        // Apply without re-syncing to cloud (values already there)
        final prefs = await SharedPreferences.getInstance();
        if (vt1Cloud != null) {
          _vt1Ve = vt1Cloud;
          await prefs.setDouble(_vt1VeKey, vt1Cloud);
        }
        if (vt2Cloud != null) {
          _vt2Ve = vt2Cloud;
          await prefs.setDouble(_vt2VeKey, vt2Cloud);
        }
        notifyListeners();
      }
    }

    // Sigma values are applied silently (no user prompt)
    await _setSigmaValues(
      moderate: calibrated['sigma_pct_moderate'] as double?,
      heavy: calibrated['sigma_pct_heavy'] as double?,
      severe: calibrated['sigma_pct_severe'] as double?,
    );
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
