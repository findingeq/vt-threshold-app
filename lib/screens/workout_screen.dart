import 'dart:async';
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../processors/cusum_processor.dart';
import '../services/ble_service.dart';
import '../services/vitalpro_parser.dart';
import '../services/workout_data_service.dart';
import '../theme/app_theme.dart';
import 'countdown_screen.dart';
import 'stage_transition_screen.dart';

enum WorkoutPhase { warmup, workout, cooldown }

class WorkoutScreen extends StatefulWidget {
  final WorkoutPhase phase;

  const WorkoutScreen({super.key, required this.phase});

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  late CusumProcessor _cusumProcessor;
  late RunConfig _runConfig;
  late bool _useVt1Behavior;
  late double _phaseDurationSec;
  late double _currentThresholdVe;

  final VitalProParser _vitalProParser = VitalProParser();

  bool _isPaused = false;
  bool _isFinished = false;
  DateTime? _startTime;
  DateTime? _pauseStartTime; // When pause was pressed
  Duration _totalPausedDuration = Duration.zero; // Accumulated pause time
  Timer? _timer;
  Timer? _simulationTimer;
  StreamSubscription<VitalProData>? _bleSubscription;
  StreamSubscription<int>? _hrSubscription;
  bool _usingSensorData = false;

  int _currentInterval = 1;
  bool _inRecovery = false;
  double _cycleElapsedSec = 0;

  double _currentHr = 0;
  CusumStatus? _latestStatus;

  late double _currentSpeedMph;

  final List<BinDataPoint> _binPoints = [];
  final LoessCalculator _loess = LoessCalculator(bandwidth: 0.4);

  double _chartXMin = 0;
  double _chartXMax = 600;
  double _chartYMax = 0; // Fixed Y-axis max (set once based on threshold)

  @override
  void initState() {
    super.initState();
    _initWorkout();
  }

  void _initWorkout() {
    final appState = context.read<AppState>();
    final currentRun = appState.currentRun;
    if (currentRun == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
      return;
    }
    _runConfig = currentRun;

    switch (widget.phase) {
      case WorkoutPhase.warmup:
        _currentThresholdVe = _runConfig.vt1Ve;
        _useVt1Behavior = true;
        _phaseDurationSec = _runConfig.warmupDurationMin * 60;
        _currentSpeedMph = _runConfig.warmupSpeedMph;
        break;
      case WorkoutPhase.cooldown:
        _currentThresholdVe = _runConfig.vt1Ve;
        _useVt1Behavior = true;
        _phaseDurationSec = _runConfig.cooldownDurationMin * 60;
        _currentSpeedMph = _runConfig.cooldownSpeedMph;
        break;
      case WorkoutPhase.workout:
        _currentThresholdVe = _runConfig.thresholdVe;
        // All run types now support intervals - only use VT1 behavior for warmup/cooldown
        _useVt1Behavior = _runConfig.numIntervals <= 1;
        _currentSpeedMph = _runConfig.speedMph;
        _phaseDurationSec =
            _runConfig.numIntervals * _runConfig.cycleDurationSec;
        break;
    }

    _cusumProcessor = CusumProcessor(
      baselineVe: _currentThresholdVe,
      runType: _useVt1Behavior ? RunType.moderate : _runConfig.runType,
    );

    if (_useVt1Behavior) {
      _chartXMax = 600;
    } else {
      _chartXMax = _runConfig.cycleDurationSec;
    }

    // Set fixed Y-axis max based on threshold (won't change during workout)
    _chartYMax = _currentThresholdVe * 1.8;

    _startWorkout();
  }

  void _startWorkout() {
    _startTime = DateTime.now();

    String phaseName;
    switch (widget.phase) {
      case WorkoutPhase.warmup:
        phaseName = 'warmup';
        break;
      case WorkoutPhase.cooldown:
        phaseName = 'cooldown';
        break;
      case WorkoutPhase.workout:
        phaseName = 'workout';
        break;
    }

    _vitalProParser.reset();

    final appState = context.read<AppState>();
    final dataService = context.read<WorkoutDataService>();
    dataService.startRecording(
      phase: phaseName,
      runConfig: _runConfig,
      vt1Ve: appState.vt1Ve,
      vt2Ve: appState.vt2Ve,
      phaseDurationMin: _phaseDurationSec / 60.0,
      speedMph: _currentSpeedMph,
    );

    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_isPaused && !_isFinished) {
        _updateElapsedTime();
      }
    });

    final bleService = context.read<BleService>();
    bleService.setWorkoutActive(true);

    if (bleService.hrSensorConnected) {
      _hrSubscription = bleService.hrDataStream.listen((hr) {
        _currentHr = hr.toDouble();
        dataService.updateHeartRate(hr);
      });
    }

    if (bleService.breathingSensorConnected) {
      _usingSensorData = true;
      _bleSubscription = bleService.breathingDataStream.listen((data) {
        if (!_isPaused && !_isFinished) {
          _processRealBreathData(data);
        }
      });
    } else {
      _usingSensorData = false;
      _simulationTimer =
          Timer.periodic(const Duration(milliseconds: 1200), (_) {
        if (!_isPaused && !_isFinished) {
          _simulateBreath();
        }
      });
    }
  }

  void _processRealBreathData(VitalProData data) {
    final startTime = _startTime;
    if (startTime == null) return;

    final parsed = _vitalProParser.parse(data.rawBytes);
    if (parsed == null) return;

    final dataService = context.read<WorkoutDataService>();
    dataService.addBreathData(parsed);

    final bleService = context.read<BleService>();
    final ve = parsed.veRaw.toDouble();
    if (!bleService.hrSensorConnected && ve > 0) {
      _currentHr = 100 + (ve / _currentThresholdVe) * 60;
    }

    if (ve > 0) {
      final breath = BreathData(
        timestamp: parsed.timestamp,
        ve: ve.clamp(1, 200),
      );

      final status = _cusumProcessor.processBreath(breath);
      _latestStatus = status;

      final binHistory = _cusumProcessor.binHistory;
      if (binHistory.isNotEmpty) {
        final latestBin = binHistory.last;
        final binX = !_useVt1Behavior
            ? latestBin.elapsedSec % _runConfig.cycleDurationSec
            : latestBin.elapsedSec;

        if (_binPoints.isEmpty || _binPoints.last.elapsedSec != binX) {
          _binPoints.add(BinDataPoint(
            timestamp: latestBin.timestamp,
            elapsedSec: binX,
            avgVe: latestBin.avgVe,
          ));
        }
      }
    }

    final elapsed = parsed.elapsedSec;
    if (_useVt1Behavior && elapsed > 600) {
      final cutoff = elapsed - 600;
      _binPoints.removeWhere((p) => p.elapsedSec < cutoff);
      // Update chart bounds based on data point time (not wall-clock)
      _chartXMin = cutoff;
      _chartXMax = elapsed;
    }

    setState(() {});
  }

  void _updateElapsedTime() {
    final startTime = _startTime;
    if (startTime == null) return;

    // Calculate elapsed time minus total paused duration
    final rawElapsed = DateTime.now().difference(startTime);
    final elapsed =
        (rawElapsed - _totalPausedDuration).inMilliseconds / 1000.0;

    if (elapsed >= _phaseDurationSec) {
      _onPhaseComplete();
      return;
    }

    if (!_useVt1Behavior) {
      final cycleDuration = _runConfig.cycleDurationSec;
      final cycleNum = (elapsed / cycleDuration).floor();
      _cycleElapsedSec = elapsed - (cycleNum * cycleDuration);

      final newInterval = cycleNum + 1;
      final newInRecovery =
          _cycleElapsedSec >= _runConfig.intervalDurationSec;

      if (newInterval != _currentInterval) {
        _onNewInterval(newInterval);
      } else if (newInRecovery != _inRecovery) {
        _inRecovery = newInRecovery;
        final dataService = context.read<WorkoutDataService>();
        dataService.setRecoveryState(_inRecovery);
      }

      _currentInterval = newInterval;
    }
    // Note: Chart bounds for VT1 mode are updated in _processRealBreathData
    // based on actual data point times (not wall-clock) to avoid time drift

    setState(() {});
  }

  void _onPhaseComplete() {
    _timer?.cancel();
    _simulationTimer?.cancel();
    _bleSubscription?.cancel();
    _hrSubscription?.cancel();

    final dataService = context.read<WorkoutDataService>();
    dataService.stopRecording();

    switch (widget.phase) {
      case WorkoutPhase.warmup:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const StageTransitionScreen(
              nextPhase: WorkoutPhase.workout,
            ),
          ),
        );
        break;
      case WorkoutPhase.workout:
        if (_runConfig.hasCooldown) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => const StageTransitionScreen(
                nextPhase: WorkoutPhase.cooldown,
              ),
            ),
          );
        } else {
          setState(() => _isFinished = true);
        }
        break;
      case WorkoutPhase.cooldown:
        setState(() => _isFinished = true);
        break;
    }
  }

  void _onNewInterval(int newInterval) {
    _cusumProcessor.resetForNewInterval();
    _binPoints.clear();
    _inRecovery = false;
  }

  void _simulateBreath() {
    final startTime = _startTime;
    if (startTime == null) return;

    // Calculate elapsed time minus paused duration
    final rawElapsed = DateTime.now().difference(startTime);
    final elapsed =
        (rawElapsed - _totalPausedDuration).inMilliseconds / 1000.0;
    final baseline = _currentThresholdVe;

    double targetVe;
    if (!_useVt1Behavior) {
      if (_inRecovery) {
        targetVe = baseline * 0.4;
      } else if (_cycleElapsedSec < 60) {
        targetVe = baseline * 0.4 + (baseline * 0.5) * (_cycleElapsedSec / 60);
      } else {
        targetVe =
            baseline * 0.9 + (baseline * 0.05) * ((_cycleElapsedSec - 60) / 60);
      }
    } else {
      if (elapsed < 120) {
        targetVe = baseline * 0.4 + (baseline * 0.45) * (elapsed / 120);
      } else {
        targetVe = baseline * 0.85;
      }
    }

    final noise = (Random().nextDouble() - 0.5) * baseline * 0.15;
    final ve = targetVe + noise;

    _currentHr = 120 + (ve / baseline) * 40 + Random().nextDouble() * 5;

    final breath = BreathData(
      timestamp: DateTime.now(),
      ve: ve.clamp(10, 200),
    );

    final status = _cusumProcessor.processBreath(breath);
    _latestStatus = status;

    final binHistory = _cusumProcessor.binHistory;
    if (binHistory.isNotEmpty) {
      final latestBin = binHistory.last;
      final binX = !_useVt1Behavior
          ? latestBin.elapsedSec % _runConfig.cycleDurationSec
          : latestBin.elapsedSec;

      if (_binPoints.isEmpty || _binPoints.last.elapsedSec != binX) {
        _binPoints.add(BinDataPoint(
          timestamp: latestBin.timestamp,
          elapsedSec: binX,
          avgVe: latestBin.avgVe,
        ));
      }
    }

    if (_useVt1Behavior && elapsed > 600) {
      final cutoff = elapsed - 600;
      _binPoints.removeWhere((p) => p.elapsedSec < cutoff);
      // Update chart bounds based on data point time (not wall-clock)
      _chartXMin = cutoff;
      _chartXMax = elapsed;
    }

    setState(() {});
  }

  void _togglePause() {
    setState(() {
      if (_isPaused) {
        // Resuming - calculate how long we were paused and add to total
        if (_pauseStartTime != null) {
          _totalPausedDuration +=
              DateTime.now().difference(_pauseStartTime!);
          _pauseStartTime = null;
        }
        _isPaused = false;
      } else {
        // Pausing - record when we started pausing
        _pauseStartTime = DateTime.now();
        _isPaused = true;
      }
    });
  }

  void _finishWorkout() {
    _timer?.cancel();
    _simulationTimer?.cancel();
    _bleSubscription?.cancel();
    _hrSubscription?.cancel();

    final bleService = context.read<BleService>();
    bleService.setWorkoutActive(false);

    final dataService = context.read<WorkoutDataService>();
    dataService.stopRecording();

    setState(() => _isFinished = true);
  }

  void _endWorkout() {
    final hasMoreStages = _hasMoreStages();
    if (hasMoreStages) {
      _showMultiStageEndDialog();
    } else {
      _showSimpleEndDialog();
    }
  }

  bool _hasMoreStages() {
    switch (widget.phase) {
      case WorkoutPhase.warmup:
        return true;
      case WorkoutPhase.workout:
        return _runConfig.hasCooldown;
      case WorkoutPhase.cooldown:
        return false;
    }
  }

  String _getCurrentStageName() {
    switch (widget.phase) {
      case WorkoutPhase.warmup:
        return 'Warmup';
      case WorkoutPhase.workout:
        return 'Workout';
      case WorkoutPhase.cooldown:
        return 'Cooldown';
    }
  }

  void _showMultiStageEndDialog() {
    final stageName = _getCurrentStageName();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        ),
        title: Text('End Session?', style: AppTheme.titleLarge),
        content: Text(
          'Do you want to end just the $stageName or the entire session?',
          style: AppTheme.bodyLarge,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: AppTheme.bodyMedium.copyWith(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _endCurrentStage();
            },
            child: Text('End $stageName',
                style: AppTheme.bodyMedium
                    .copyWith(color: AppTheme.accentOrange)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _finishWorkout();
            },
            child: Text('End Entire Session',
                style:
                    AppTheme.bodyMedium.copyWith(color: AppTheme.accentRed)),
          ),
        ],
      ),
    );
  }

  void _showSimpleEndDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        ),
        title: Text('End Workout?', style: AppTheme.titleLarge),
        content: Text('Are you sure you want to end this workout?',
            style: AppTheme.bodyLarge),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: AppTheme.bodyMedium.copyWith(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _finishWorkout();
            },
            child: Text('End',
                style:
                    AppTheme.bodyMedium.copyWith(color: AppTheme.accentRed)),
          ),
        ],
      ),
    );
  }

  void _endCurrentStage() {
    _timer?.cancel();
    _simulationTimer?.cancel();
    _bleSubscription?.cancel();
    _hrSubscription?.cancel();

    final dataService = context.read<WorkoutDataService>();
    dataService.stopRecording();

    switch (widget.phase) {
      case WorkoutPhase.warmup:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const StageTransitionScreen(
              nextPhase: WorkoutPhase.workout,
            ),
          ),
        );
        break;
      case WorkoutPhase.workout:
        if (_runConfig.hasCooldown) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => const StageTransitionScreen(
                nextPhase: WorkoutPhase.cooldown,
              ),
            ),
          );
        }
        break;
      case WorkoutPhase.cooldown:
        _finishWorkout();
        break;
    }
  }

  Color _getZoneColor() {
    if (_latestStatus == null) return AppTheme.zoneGreen;
    if (!_useVt1Behavior && _inRecovery) return AppTheme.zoneRecovery;

    switch (_latestStatus!.zone) {
      case 'green':
        return AppTheme.zoneGreen;
      case 'yellow':
        return AppTheme.zoneYellow;
      case 'red':
        return AppTheme.zoneRed;
      default:
        return AppTheme.zoneGreen;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _simulationTimer?.cancel();
    _bleSubscription?.cancel();
    _hrSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final startTime = _startTime;
    // Calculate elapsed time minus paused duration for display
    final rawElapsed = startTime != null
        ? DateTime.now().difference(startTime)
        : Duration.zero;
    final elapsed = (rawElapsed - _totalPausedDuration).inSeconds;

    // Get zone-based background color
    final zoneColor = _getZoneColor();
    Color backgroundColor;
    if (_isFinished) {
      backgroundColor = AppTheme.background;
    } else if (zoneColor == AppTheme.zoneGreen) {
      backgroundColor = AppTheme.accentGreen.withOpacity(0.25);
    } else if (zoneColor == AppTheme.zoneYellow) {
      backgroundColor = AppTheme.accentYellow.withOpacity(0.25);
    } else if (zoneColor == AppTheme.zoneRed) {
      backgroundColor = AppTheme.accentRed.withOpacity(0.25);
    } else if (zoneColor == AppTheme.zoneRecovery) {
      backgroundColor = AppTheme.textMuted.withOpacity(0.15);
    } else {
      backgroundColor = AppTheme.background;
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        color: backgroundColor,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // Header
                      _buildHeader(),

                      const SizedBox(height: 16),

                      // Timer
                      _buildTimerSection(elapsed),

                      // Reconnection status
                      _buildReconnectionStatus(),

                      const SizedBox(height: 20),

                      // Metrics (hide when finished)
                      if (!_isFinished) _buildMetricsRow(),

                      if (!_isFinished) const SizedBox(height: 20),

                      // Chart (hide when finished to show summary instead)
                      if (!_isFinished) Expanded(child: _buildVeChart()),

                      if (!_isFinished) const SizedBox(height: 20),

                      // Controls or Finished section
                      if (!_isFinished) _buildControlButtons(),
                      if (_isFinished) Expanded(child: _buildFinishedSection()),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    String title;
    switch (widget.phase) {
      case WorkoutPhase.warmup:
        title = 'WARMUP';
        break;
      case WorkoutPhase.cooldown:
        title = 'COOLDOWN';
        break;
      case WorkoutPhase.workout:
        switch (_runConfig.runType) {
          case RunType.moderate:
            title = 'MODERATE RUN';
            break;
          case RunType.heavy:
            title = 'HEAVY RUN';
            break;
          case RunType.severe:
            title = 'SEVERE RUN';
            break;
        }
        break;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: AppTheme.labelLarge.copyWith(
            letterSpacing: 2,
            color: AppTheme.textMuted,
          ),
        ),
        if (widget.phase == WorkoutPhase.workout && _runConfig.numIntervals > 1)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _inRecovery
                  ? AppTheme.surfaceCardLight
                  : AppTheme.accentBlue.withOpacity(0.2),
              borderRadius: BorderRadius.circular(AppTheme.radiusCircular),
              border: Border.all(
                color: _inRecovery
                    ? AppTheme.borderSubtle
                    : AppTheme.accentBlue.withOpacity(0.5),
              ),
            ),
            child: Text(
              _inRecovery
                  ? 'Recovery $_currentInterval/${_runConfig.numIntervals}'
                  : 'Interval $_currentInterval/${_runConfig.numIntervals}',
              style: AppTheme.labelLarge.copyWith(
                color: _inRecovery ? AppTheme.textMuted : AppTheme.accentBlue,
                letterSpacing: 0,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTimerSection(int elapsed) {
    String timerText;

    if (!_useVt1Behavior && widget.phase == WorkoutPhase.workout) {
      final cycleElapsed = _cycleElapsedSec.toInt();
      int remaining;

      if (_inRecovery) {
        final recoveryElapsed =
            cycleElapsed - _runConfig.intervalDurationSec.toInt();
        remaining = (_runConfig.recoveryDurationSec - recoveryElapsed).toInt();
      } else {
        remaining = (_runConfig.intervalDurationSec - cycleElapsed).toInt();
      }

      remaining = remaining.clamp(0, 9999);
      final mins = remaining ~/ 60;
      final secs = remaining % 60;
      timerText =
          '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    } else {
      final remaining = (_phaseDurationSec - elapsed).clamp(0, 9999).toInt();
      final mins = remaining ~/ 60;
      final secs = remaining % 60;
      timerText =
          '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }

    return Text(
      timerText,
      style: TextStyle(
        fontSize: 72,
        fontWeight: FontWeight.w700,
        color: AppTheme.textPrimary,
        letterSpacing: -2,
        height: 1,
      ),
    );
  }

  Widget _buildReconnectionStatus() {
    final bleService = context.watch<BleService>();
    final isReconnecting =
        bleService.isReconnectingBreathing || bleService.isReconnectingHr;

    if (!isReconnecting) return const SizedBox.shrink();

    String message = 'Reconnecting';
    if (bleService.isReconnectingBreathing && bleService.isReconnectingHr) {
      message = 'Reconnecting sensors...';
    } else if (bleService.isReconnectingBreathing) {
      message = 'Reconnecting breathing sensor...';
    } else if (bleService.isReconnectingHr) {
      message = 'Reconnecting HR sensor...';
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.accentOrange.withOpacity(0.15),
        borderRadius: BorderRadius.circular(AppTheme.radiusCircular),
        border: Border.all(color: AppTheme.accentOrange.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.accentOrange,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            message,
            style: AppTheme.labelLarge.copyWith(
              color: AppTheme.accentOrange,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsRow() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Row(
        children: [
          // HR
          Expanded(
            child: _buildCompactMetric(
              label: 'HR',
              value: _currentHr.toInt().toString(),
              color: AppTheme.accentRed,
            ),
          ),
          Container(width: 1, height: 32, color: AppTheme.borderSubtle),
          // VE
          Expanded(
            child: _buildCompactMetric(
              label: 'VE',
              value: (_latestStatus?.binAvgVe ?? 0).round().toString(),
              color: AppTheme.accentBlue,
            ),
          ),
          Container(width: 1, height: 32, color: AppTheme.borderSubtle),
          // Speed with +/- buttons
          Expanded(
            flex: 2,
            child: _buildSpeedControl(),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactMetric({
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: AppTheme.labelSmall.copyWith(color: color, letterSpacing: 0),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w400,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildSpeedControl() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Minus button
        GestureDetector(
          onTap: _currentSpeedMph > 1.0
              ? () => _updateSpeed(_currentSpeedMph - 0.1)
              : null,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _currentSpeedMph > 1.0
                  ? AppTheme.accentPurple.withOpacity(0.15)
                  : AppTheme.surfaceCardLight,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.remove,
              size: 16,
              color: _currentSpeedMph > 1.0
                  ? AppTheme.accentPurple
                  : AppTheme.textDisabled,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Value
        Text(
          'SPEED',
          style: AppTheme.labelSmall.copyWith(
            color: AppTheme.accentPurple,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          _currentSpeedMph.toStringAsFixed(1),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w400,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(width: 8),
        // Plus button
        GestureDetector(
          onTap: _currentSpeedMph < 15.0
              ? () => _updateSpeed(_currentSpeedMph + 0.1)
              : null,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _currentSpeedMph < 15.0
                  ? AppTheme.accentPurple.withOpacity(0.15)
                  : AppTheme.surfaceCardLight,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.add,
              size: 16,
              color: _currentSpeedMph < 15.0
                  ? AppTheme.accentPurple
                  : AppTheme.textDisabled,
            ),
          ),
        ),
      ],
    );
  }

  void _updateSpeed(double newSpeed) {
    newSpeed = (newSpeed * 10).round() / 10;
    setState(() => _currentSpeedMph = newSpeed);

    final dataService = context.read<WorkoutDataService>();
    dataService.setSpeed(newSpeed);

    final appState = context.read<AppState>();
    RunConfig updatedConfig;

    switch (widget.phase) {
      case WorkoutPhase.warmup:
        updatedConfig = _runConfig.copyWithSpeed(warmupSpeedMph: newSpeed);
        break;
      case WorkoutPhase.cooldown:
        updatedConfig = _runConfig.copyWithSpeed(cooldownSpeedMph: newSpeed);
        break;
      case WorkoutPhase.workout:
        updatedConfig = _runConfig.copyWithSpeed(speedMph: newSpeed);
        break;
    }

    appState.setCurrentRun(updatedConfig);
    _runConfig = updatedConfig;
  }

  Widget _buildVeChart() {
    // Use fixed Y-axis bounds to prevent chart shifting during workout
    const double yMin = 0;
    final double yMax = _chartYMax;

    final loessValues = _loess.smooth(_binPoints);
    final loessSpots = <FlSpot>[];
    for (var i = 0; i < _binPoints.length; i++) {
      loessSpots.add(FlSpot(_binPoints[i].elapsedSec, loessValues[i]));
    }

    final recoveryAnnotations = <VerticalRangeAnnotation>[];
    if (!_useVt1Behavior) {
      final intervalDurationSec = _runConfig.intervalDurationSec;
      final cycleDurationSec = _runConfig.cycleDurationSec;
      recoveryAnnotations.add(VerticalRangeAnnotation(
        x1: intervalDurationSec,
        x2: cycleDurationSec,
        color: AppTheme.surfaceCardLight.withOpacity(0.5),
      ));
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      padding: const EdgeInsets.fromLTRB(8, 20, 20, 12),
      child: LineChart(
        LineChartData(
          minX: _chartXMin,
          maxX: _chartXMax,
          minY: yMin,
          maxY: yMax,
          lineTouchData: const LineTouchData(enabled: false),
          rangeAnnotations: RangeAnnotations(
            verticalRangeAnnotations: recoveryAnnotations,
          ),
          gridData: FlGridData(
            show: true,
            horizontalInterval: 20,
            verticalInterval: 60,
            getDrawingHorizontalLine: (value) => FlLine(
              color: AppTheme.borderSubtle,
              strokeWidth: 1,
            ),
            getDrawingVerticalLine: (value) => FlLine(
              color: AppTheme.borderSubtle,
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 60,
                reservedSize: 30,
                getTitlesWidget: (value, meta) {
                  // Skip labels too close to edges to prevent bunching
                  if (value < meta.min + 30 || value > meta.max - 30) {
                    return const SizedBox.shrink();
                  }
                  final min = (value / 60).round();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '$min',
                      style: AppTheme.labelSmall,
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 20,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toInt().toString(),
                    style: AppTheme.labelSmall,
                  );
                },
              ),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            // Threshold line
            LineChartBarData(
              spots: [
                FlSpot(_chartXMin, _currentThresholdVe),
                FlSpot(_chartXMax, _currentThresholdVe),
              ],
              isCurved: false,
              color: AppTheme.accentRed.withOpacity(0.6),
              barWidth: 2,
              dotData: const FlDotData(show: false),
              dashArray: [8, 4],
            ),
            // Data points (faint)
            LineChartBarData(
              spots: _binPoints
                  .map((p) => FlSpot(p.elapsedSec, p.avgVe))
                  .toList(),
              isCurved: false,
              color: Colors.transparent,
              barWidth: 0,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, bar, index) {
                  return FlDotCirclePainter(
                    radius: 3,
                    color: AppTheme.accentBlue.withOpacity(0.3),
                    strokeWidth: 0,
                  );
                },
              ),
            ),
            // LOESS trend line with glow effect
            LineChartBarData(
              spots: loessSpots,
              isCurved: true,
              curveSmoothness: 0.3,
              color: AppTheme.accentBlue,
              barWidth: 3,
              dotData: const FlDotData(show: false),
              shadow: Shadow(
                color: AppTheme.accentBlue.withOpacity(0.5),
                blurRadius: 12,
              ),
            ),
          ],
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              if (!_useVt1Behavior)
                HorizontalLine(
                  y: _currentThresholdVe,
                  color: Colors.transparent,
                  strokeWidth: 0,
                  label: HorizontalLineLabel(
                    show: true,
                    labelResolver: (_) => 'Threshold',
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.accentRed.withOpacity(0.8),
                    ),
                  ),
                ),
            ],
          ),
        ),
        duration: const Duration(milliseconds: 100),
      ),
    );
  }

  Widget _buildControlButtons() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: _togglePause,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: AppTheme.accentOrange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                border:
                    Border.all(color: AppTheme.accentOrange.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isPaused ? Icons.play_arrow : Icons.pause,
                    color: AppTheme.accentOrange,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isPaused ? 'Resume' : 'Pause',
                    style: AppTheme.titleMedium
                        .copyWith(color: AppTheme.accentOrange),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: _endWorkout,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: AppTheme.accentRed.withOpacity(0.15),
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                border: Border.all(color: AppTheme.accentRed.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.stop, color: AppTheme.accentRed),
                  const SizedBox(width: 8),
                  Text(
                    'End',
                    style:
                        AppTheme.titleMedium.copyWith(color: AppTheme.accentRed),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFinishedSection() {
    final dataService = context.watch<WorkoutDataService>();

    String phaseName;
    switch (widget.phase) {
      case WorkoutPhase.warmup:
        phaseName = 'warmup';
        break;
      case WorkoutPhase.cooldown:
        phaseName = 'cooldown';
        break;
      case WorkoutPhase.workout:
        phaseName = 'workout';
        break;
    }
    final summary = dataService.calculatePhaseSummary(phaseName);
    final isIntervalWorkout =
        _runConfig.numIntervals > 1 && phaseName == 'workout';

    return Column(
      children: [
        Text(
          'SESSION COMPLETE',
          style: AppTheme.labelLarge.copyWith(
            letterSpacing: 3,
            color: AppTheme.accentGreen,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${dataService.dataPointCount} samples recorded',
          style: AppTheme.bodyMedium,
        ),

        if (summary != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(color: AppTheme.accentGreen.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatItem(
                      icon: Icons.favorite,
                      label: 'Avg HR',
                      value: summary.avgHr > 0
                          ? '${summary.avgHr.toStringAsFixed(0)} bpm'
                          : '--',
                      color: AppTheme.accentRed,
                    ),
                    _buildStatItem(
                      icon: Icons.air,
                      label: 'Avg VE',
                      value: '${summary.avgVe.toStringAsFixed(1)} L/min',
                      color: AppTheme.accentBlue,
                    ),
                  ],
                ),
                if (isIntervalWorkout && summary.terminalSlopePct != null) ...[
                  const SizedBox(height: 12),
                  const Divider(color: AppTheme.borderSubtle),
                  const SizedBox(height: 12),
                  _buildStatItem(
                    icon: Icons.trending_up,
                    label: 'Terminal Slope',
                    value:
                        '${summary.terminalSlopePct! >= 0 ? '+' : ''}${summary.terminalSlopePct!.toStringAsFixed(1)}%/min',
                    color: summary.terminalSlopePct! > 0
                        ? AppTheme.accentOrange
                        : AppTheme.accentGreen,
                  ),
                ],
              ],
            ),
          ),
        ],

        const SizedBox(height: 16),

        // Action buttons
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: dataService.hasData
                    ? () async {
                        try {
                          await dataService.exportCsv();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('CSV exported successfully'),
                                backgroundColor: AppTheme.accentGreen,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Export failed: $e'),
                                backgroundColor: AppTheme.accentRed,
                              ),
                            );
                          }
                        }
                      }
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.accentBlue.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    border:
                        Border.all(color: AppTheme.accentBlue.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.download, color: AppTheme.accentBlue),
                      const SizedBox(width: 8),
                      Text(
                        'Export',
                        style: AppTheme.titleMedium
                            .copyWith(color: AppTheme.accentBlue),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: dataService.hasData
                    ? () async {
                        try {
                          await dataService.uploadToCloud();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Uploaded successfully'),
                                backgroundColor: AppTheme.accentGreen,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Upload failed: $e'),
                                backgroundColor: AppTheme.accentRed,
                              ),
                            );
                          }
                        }
                      }
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.accentGreen.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    border: Border.all(
                        color: AppTheme.accentGreen.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_upload, color: AppTheme.accentGreen),
                      const SizedBox(width: 8),
                      Text(
                        'Upload',
                        style: AppTheme.titleMedium
                            .copyWith(color: AppTheme.accentGreen),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        TextButton(
          onPressed: () {
            dataService.clear();
            Navigator.popUntil(context, (route) => route.isFirst);
          },
          child: Text(
            'Back to Home',
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textMuted),
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(label, style: AppTheme.labelSmall),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTheme.titleMedium.copyWith(color: color),
        ),
      ],
    );
  }
}
