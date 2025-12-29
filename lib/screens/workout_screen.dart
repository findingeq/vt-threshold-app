import 'dart:async';
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../processors/cusum_processor.dart';
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

  // Workout state
  bool _isPaused = false;
  bool _isFinished = false;
  DateTime? _startTime;
  Timer? _timer;
  Timer? _simulationTimer;

  // Current interval tracking (for VT2)
  int _currentInterval = 1;
  bool _inRecovery = false;
  double _cycleElapsedSec = 0;

  // Real-time data
  double _currentHr = 0;
  CusumStatus? _latestStatus;

  // Current speed (can be modified during workout)
  late double _currentSpeedMph;

  // Chart data
  final List<BinDataPoint> _binPoints = [];

  // LOESS calculator for smooth trend line (higher bandwidth = smoother)
  final LoessCalculator _loess = LoessCalculator(bandwidth: 0.4);

  // Chart x-axis range
  double _chartXMin = 0;
  double _chartXMax = 600; // 10 min default for VT1

  @override
  void initState() {
    super.initState();
    _initWorkout();
  }

  void _initWorkout() {
    final appState = context.read<AppState>();
    final currentRun = appState.currentRun;
    if (currentRun == null) {
      // Navigate back if no run config - prevents crash
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pop(context);
        }
      });
      return;
    }
    _runConfig = currentRun;

    // Determine threshold, speed, and run type behavior based on phase
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
        _useVt1Behavior = _runConfig.runType == RunType.vt1SteadyState;
        _currentSpeedMph = _runConfig.speedMph;
        // For VT2, total duration is numIntervals * cycleDuration
        if (_runConfig.runType == RunType.vt2Intervals) {
          _phaseDurationSec = _runConfig.numIntervals * _runConfig.cycleDurationSec;
        } else {
          _phaseDurationSec = _runConfig.intervalDurationMin * 60;
        }
        break;
    }

    _cusumProcessor = CusumProcessor(
      baselineVe: _currentThresholdVe,
      runType: _useVt1Behavior ? RunType.vt1SteadyState : _runConfig.runType,
    );

    // Set initial chart x-axis range based on phase behavior
    if (_useVt1Behavior) {
      // VT1-style: Rolling 10 min window
      _chartXMax = 600;
    } else {
      // VT2: Show full cycle (interval + recovery)
      _chartXMax = _runConfig.cycleDurationSec;
    }

    _startWorkout();
  }

  void _startWorkout() {
    _startTime = DateTime.now();

    // Update timer every 100ms for smooth UI
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_isPaused && !_isFinished) {
        _updateElapsedTime();
      }
    });

    // Simulate breath data (replace with real Bluetooth data)
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      if (!_isPaused && !_isFinished) {
        _simulateBreath();
      }
    });
  }

  void _updateElapsedTime() {
    final startTime = _startTime;
    if (startTime == null) return;

    final elapsed = DateTime.now().difference(startTime).inMilliseconds / 1000.0;

    // Check if phase is complete
    if (elapsed >= _phaseDurationSec) {
      _onPhaseComplete();
      return;
    }

    if (!_useVt1Behavior) {
      // VT2 interval tracking
      final cycleDuration = _runConfig.cycleDurationSec;
      final cycleNum = (elapsed / cycleDuration).floor();
      _cycleElapsedSec = elapsed - (cycleNum * cycleDuration);

      final newInterval = cycleNum + 1;
      final newInRecovery = _cycleElapsedSec >= _runConfig.intervalDurationSec;

      // Detect interval transition
      if (newInterval != _currentInterval) {
        _onNewInterval(newInterval);
      } else if (newInRecovery != _inRecovery) {
        _inRecovery = newInRecovery;
      }

      _currentInterval = newInterval;
    } else {
      // VT1-style: Rolling window update
      if (elapsed > 600) {
        _chartXMin = elapsed - 600;
        _chartXMax = elapsed;
      }
    }

    setState(() {});
  }

  void _onPhaseComplete() {
    _timer?.cancel();
    _simulationTimer?.cancel();

    switch (widget.phase) {
      case WorkoutPhase.warmup:
        // Warmup complete → transition screen → user presses button → countdown → workout
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
        // Workout complete → transition screen → cooldown (if configured) or finish
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
          setState(() {
            _isFinished = true;
          });
        }
        break;
      case WorkoutPhase.cooldown:
        // Cooldown complete → finish
        setState(() {
          _isFinished = true;
        });
        break;
    }
  }

  void _onNewInterval(int newInterval) {
    // Reset CUSUM for new interval
    _cusumProcessor.resetForNewInterval();

    // Clear chart data for new cycle
    _breathPoints.clear();
    _binPoints.clear();

    _inRecovery = false;
  }

  void _simulateBreath() {
    final startTime = _startTime;
    if (startTime == null) return;

    // Simulate realistic VE data
    final elapsed = DateTime.now().difference(startTime).inMilliseconds / 1000.0;
    final baseline = _currentThresholdVe;

    // Simulate ramp-up, steady state, and potential drift
    double targetVe;
    if (!_useVt1Behavior) {
      // VT2 intervals behavior
      if (_inRecovery) {
        targetVe = baseline * 0.4; // Low VE during recovery
      } else if (_cycleElapsedSec < 60) {
        // Ramp up during first minute
        targetVe = baseline * 0.4 + (baseline * 0.5) * (_cycleElapsedSec / 60);
      } else {
        // Near threshold with some drift
        targetVe = baseline * 0.9 + (baseline * 0.05) * ((_cycleElapsedSec - 60) / 60);
      }
    } else {
      // VT1/warmup/cooldown: steady state after ramp
      if (elapsed < 120) {
        targetVe = baseline * 0.4 + (baseline * 0.45) * (elapsed / 120);
      } else {
        targetVe = baseline * 0.85;
      }
    }

    // Add noise
    final noise = (Random().nextDouble() - 0.5) * baseline * 0.15;
    final ve = targetVe + noise;

    // Simulate HR
    _currentHr = 120 + (ve / baseline) * 40 + Random().nextDouble() * 5;

    // Process breath
    final breath = BreathData(
      timestamp: DateTime.now(),
      ve: ve.clamp(10, 200),
    );

    final status = _cusumProcessor.processBreath(breath);
    _latestStatus = status;

    // Add bin point if available (binned averages are the data points)
    final binHistory = _cusumProcessor.binHistory;
    if (binHistory.isNotEmpty) {
      final latestBin = binHistory.last;
      final binX = !_useVt1Behavior
          ? latestBin.elapsedSec % _runConfig.cycleDurationSec
          : latestBin.elapsedSec;

      // Only add if it's a new bin
      if (_binPoints.isEmpty || _binPoints.last.elapsedSec != binX) {
        _binPoints.add(BinDataPoint(
          timestamp: latestBin.timestamp,
          elapsedSec: binX,
          avgVe: latestBin.avgVe,
        ));
      }
    }

    // Trim old data for VT1-style rolling window
    if (_useVt1Behavior && elapsed > 600) {
      final cutoff = elapsed - 600;
      _binPoints.removeWhere((p) => p.elapsedSec < cutoff);
    }

    setState(() {});
  }

  void _togglePause() {
    setState(() {
      _isPaused = !_isPaused;
    });
  }

  void _finishWorkout() {
    _timer?.cancel();
    _simulationTimer?.cancel();
    setState(() {
      _isFinished = true;
    });
  }

  void _endWorkout() {
    // Check if this is a multi-stage workout with more stages after current
    final hasMoreStages = _hasMoreStages();

    if (hasMoreStages) {
      // Multi-stage: show options to end current stage or entire session
      _showMultiStageEndDialog();
    } else {
      // Final stage or single-stage: just confirm and finish
      _showSimpleEndDialog();
    }
  }

  bool _hasMoreStages() {
    switch (widget.phase) {
      case WorkoutPhase.warmup:
        // Warmup always has workout after it
        return true;
      case WorkoutPhase.workout:
        // Workout has cooldown after it if configured
        return _runConfig.hasCooldown;
      case WorkoutPhase.cooldown:
        // Cooldown is always the last stage
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
        title: const Text('End Session?'),
        content: Text('Do you want to end just the $stageName or the entire session?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _endCurrentStage();
            },
            child: Text('End $stageName', style: const TextStyle(color: Colors.orange)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _finishWorkout();
            },
            child: const Text('End Entire Session', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showSimpleEndDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End Workout?'),
        content: const Text('Are you sure you want to end this workout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _finishWorkout();
            },
            child: const Text('End', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _endCurrentStage() {
    // End the current stage and show transition to next stage
    // This behaves the same as if the stage completed normally
    _timer?.cancel();
    _simulationTimer?.cancel();

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
        // This shouldn't happen since cooldown has no more stages
        _finishWorkout();
        break;
    }
  }

  Color _getBackgroundColor() {
    if (_latestStatus == null) return Colors.green[100] ?? Colors.green;

    // Only show grey during VT2 recovery periods
    if (!_useVt1Behavior && _inRecovery) return Colors.grey[300] ?? Colors.grey;

    switch (_latestStatus!.zone) {
      case 'green':
        return Colors.green[100] ?? Colors.green;
      case 'yellow':
        return Colors.yellow[200] ?? Colors.yellow;
      case 'red':
        return Colors.red[200] ?? Colors.red;
      default:
        return Colors.green[100] ?? Colors.green;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _simulationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final startTime = _startTime;
    final elapsed = startTime != null
        ? DateTime.now().difference(startTime).inSeconds
        : 0;

    String appBarTitle;
    switch (widget.phase) {
      case WorkoutPhase.warmup:
        appBarTitle = 'Warmup';
        break;
      case WorkoutPhase.cooldown:
        appBarTitle = 'Cooldown';
        break;
      case WorkoutPhase.workout:
        appBarTitle = _runConfig.runType == RunType.vt1SteadyState
            ? 'VT1 Run'
            : 'VT2 Intervals';
        break;
    }

    return Scaffold(
      backgroundColor: _getBackgroundColor(),
      appBar: AppBar(
        title: Text(appBarTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Timer and Interval Display
              _buildTimerSection(elapsed),

              const SizedBox(height: 16),

              // HR and VE Display
              _buildMetricsRow(),

              const SizedBox(height: 16),

              // VE Chart
              Expanded(child: _buildVeChart()),

              const SizedBox(height: 16),

              // Control Buttons
              if (!_isFinished) _buildControlButtons(),
              if (_isFinished) _buildFinishedButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimerSection(int elapsed) {
    String timerText;
    String? subText;

    if (!_useVt1Behavior && widget.phase == WorkoutPhase.workout) {
      // VT2 intervals: Show countdown for current interval or recovery
      final cycleElapsed = _cycleElapsedSec.toInt();
      int remaining;

      if (_inRecovery) {
        // Recovery: countdown from recovery duration
        final recoveryElapsed = cycleElapsed - _runConfig.intervalDurationSec.toInt();
        remaining = (_runConfig.recoveryDurationSec - recoveryElapsed).toInt();
        subText = 'Recovery $_currentInterval/${_runConfig.numIntervals}';
      } else {
        // Interval: countdown from interval duration
        remaining = (_runConfig.intervalDurationSec - cycleElapsed).toInt();
        subText = 'Interval $_currentInterval/${_runConfig.numIntervals}';
      }

      remaining = remaining.clamp(0, 9999);
      final mins = remaining ~/ 60;
      final secs = remaining % 60;
      timerText = '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    } else {
      // VT1/warmup/cooldown: Show countdown for the phase
      final remaining = (_phaseDurationSec - elapsed).clamp(0, 9999).toInt();
      final mins = remaining ~/ 60;
      final secs = remaining % 60;
      timerText = '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';

      // Show phase name for warmup/cooldown
      if (widget.phase == WorkoutPhase.warmup) {
        final totalMins = _runConfig.warmupDurationMin.toInt();
        subText = 'Warmup ($totalMins min)';
      } else if (widget.phase == WorkoutPhase.cooldown) {
        final totalMins = _runConfig.cooldownDurationMin.toInt();
        subText = 'Cooldown ($totalMins min)';
      }
    }

    return Column(
      children: [
        Text(
          timerText,
          style: const TextStyle(
            fontSize: 64,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
        if (subText != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: _inRecovery ? Colors.grey : Colors.blue,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              subText,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMetricsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildMetricCard(
          icon: Icons.favorite,
          value: _currentHr.toInt().toString(),
          unit: 'bpm',
          color: Colors.red,
        ),
        _buildMetricCard(
          icon: Icons.air,
          value: (_latestStatus?.binAvgVe ?? 0).toStringAsFixed(1),
          unit: 'L/min',
          color: Colors.blue,
        ),
        _buildTappableMetricCard(
          icon: Icons.directions_run,
          value: _currentSpeedMph.toStringAsFixed(1),
          unit: 'mph',
          color: Colors.purple,
          onTap: _showSpeedChangeDialog,
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String value,
    required String unit,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            unit,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTappableMetricCard({
    required IconData icon,
    required String value,
    required String unit,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3), width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  unit,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.edit, size: 10, color: Colors.grey[400]),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showSpeedChangeDialog() {
    double newSpeed = _currentSpeedMph;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Change Speed'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${newSpeed.toStringAsFixed(1)} mph',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: newSpeed > 1.0
                        ? () => setDialogState(() => newSpeed -= 0.5)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                    iconSize: 36,
                  ),
                  const SizedBox(width: 24),
                  IconButton(
                    onPressed: newSpeed < 15.0
                        ? () => setDialogState(() => newSpeed += 0.5)
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                    iconSize: 36,
                  ),
                ],
              ),
              if (!_useVt1Behavior && widget.phase == WorkoutPhase.workout)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    'This will apply to all remaining intervals',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _updateSpeed(newSpeed);
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  void _updateSpeed(double newSpeed) {
    setState(() {
      _currentSpeedMph = newSpeed;
    });

    // Update the RunConfig in AppState for data tracking
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
    // Determine y-axis range
    double yMin = 0;
    double yMax = _currentThresholdVe * 1.5;

    if (_binPoints.isNotEmpty) {
      final maxVe = _binPoints.map((p) => p.avgVe).reduce(max);
      yMax = max(yMax, maxVe * 1.2);
    }

    // Calculate LOESS smoothed values for trend line
    final loessValues = _loess.smooth(_binPoints);
    final loessSpots = <FlSpot>[];
    for (var i = 0; i < _binPoints.length; i++) {
      loessSpots.add(FlSpot(_binPoints[i].elapsedSec, loessValues[i]));
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: LineChart(
        LineChartData(
          minX: _chartXMin,
          maxX: _chartXMax,
          minY: yMin,
          maxY: yMax,
          gridData: FlGridData(
            show: true,
            horizontalInterval: 20,
            verticalInterval: 60,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.grey[200] ?? Colors.grey,
              strokeWidth: 1,
            ),
            getDrawingVerticalLine: (value) => FlLine(
              color: Colors.grey[200] ?? Colors.grey,
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 60,
                getTitlesWidget: (value, meta) {
                  final min = (value / 60).floor();
                  return Text(
                    '${min}m',
                    style: const TextStyle(fontSize: 10),
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
                    style: const TextStyle(fontSize: 10),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            // Threshold line (red dashed)
            LineChartBarData(
              spots: [
                FlSpot(_chartXMin, _currentThresholdVe),
                FlSpot(_chartXMax, _currentThresholdVe),
              ],
              isCurved: false,
              color: Colors.red.withOpacity(0.5),
              barWidth: 2,
              dotData: const FlDotData(show: false),
              dashArray: [8, 4],
            ),
            // Faint dots: binned VE averages (the raw data points)
            LineChartBarData(
              spots: _binPoints.map((p) => FlSpot(p.elapsedSec, p.avgVe)).toList(),
              isCurved: false,
              color: Colors.transparent,
              barWidth: 0,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, bar, index) {
                  return FlDotCirclePainter(
                    radius: 3,
                    color: Colors.blue.withOpacity(0.3),
                    strokeWidth: 0,
                  );
                },
              ),
            ),
            // LOESS trend line: smooth curve showing true VE drift
            LineChartBarData(
              spots: loessSpots,
              isCurved: true,
              curveSmoothness: 0.3,
              color: Colors.blue,
              barWidth: 3,
              dotData: const FlDotData(show: false),
            ),
          ],
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              // Threshold label
              if (!_useVt1Behavior)
                HorizontalLine(
                  y: _currentThresholdVe,
                  color: Colors.red.withOpacity(0.1),
                  strokeWidth: 0,
                  label: HorizontalLineLabel(
                    show: true,
                    labelResolver: (_) => 'Threshold',
                    style: TextStyle(
                      color: Colors.red[400],
                      fontSize: 10,
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
          child: ElevatedButton.icon(
            onPressed: _togglePause,
            icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
            label: Text(_isPaused ? 'Resume' : 'Pause'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _endWorkout,
            icon: const Icon(Icons.stop),
            label: const Text('End'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFinishedButtons() {
    return Column(
      children: [
        const Text(
          'Workout Complete!',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () {
            // TODO: Implement upload to cloud
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Upload feature coming soon')),
            );
          },
          icon: const Icon(Icons.cloud_upload),
          label: const Text('Upload'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () {
            Navigator.popUntil(context, (route) => route.isFirst);
          },
          child: const Text('Back to Home'),
        ),
      ],
    );
  }
}
