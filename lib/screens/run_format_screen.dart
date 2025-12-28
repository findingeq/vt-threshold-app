import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import 'workout_screen.dart';
import 'countdown_screen.dart';

class RunFormatScreen extends StatefulWidget {
  const RunFormatScreen({super.key});

  @override
  State<RunFormatScreen> createState() => _RunFormatScreenState();
}

class _RunFormatScreenState extends State<RunFormatScreen> {
  RunType _runType = RunType.vt1SteadyState;
  double _speedMph = 7.5;
  int _numIntervals = 12;
  double _intervalDurationMin = 4.0;
  double _recoveryDurationMin = 1.0;
  double _steadyStateDurationMin = 30.0;
  double _warmupDurationMin = 0.0;
  double _cooldownDurationMin = 0.0;

  void _startWorkout() {
    final appState = context.read<AppState>();

    // Get the appropriate threshold based on run type
    final thresholdVe = _runType == RunType.vt1SteadyState
        ? appState.vt1Ve
        : appState.vt2Ve;

    final config = RunConfig(
      runType: _runType,
      speedMph: _speedMph,
      numIntervals: _runType == RunType.vt2Intervals ? _numIntervals : 1,
      intervalDurationMin: _runType == RunType.vt2Intervals
          ? _intervalDurationMin
          : _steadyStateDurationMin,
      recoveryDurationMin: _runType == RunType.vt2Intervals
          ? _recoveryDurationMin
          : 0.0,
      thresholdVe: thresholdVe,
      warmupDurationMin: _warmupDurationMin,
      cooldownDurationMin: _cooldownDurationMin,
      vt1Ve: appState.vt1Ve,
    );

    appState.setCurrentRun(config);

    // Determine first phase
    if (config.hasWarmup) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const WorkoutScreen(phase: WorkoutPhase.warmup),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const WorkoutScreen(phase: WorkoutPhase.workout),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Run Format'),
        centerTitle: true,
      ),
      body: Consumer<AppState>(
        builder: (context, appState, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Run Type Selection
                _buildSectionHeader('Run Type'),
                const SizedBox(height: 12),
                _buildRunTypeSelector(),

                const SizedBox(height: 32),

                // Threshold display
                _buildThresholdDisplay(appState),

                const SizedBox(height: 32),

                // Speed input (common to both)
                _buildSectionHeader('Speed'),
                const SizedBox(height: 12),
                _buildNumberInput(
                  value: _speedMph,
                  label: 'Speed',
                  suffix: 'mph',
                  min: 1.0,
                  max: 15.0,
                  step: 0.1,
                  onChanged: (v) => setState(() => _speedMph = v),
                ),

                const SizedBox(height: 32),

                // VT1-specific: Duration only
                if (_runType == RunType.vt1SteadyState) ...[
                  _buildSectionHeader('Duration'),
                  const SizedBox(height: 12),
                  _buildNumberInput(
                    value: _steadyStateDurationMin,
                    label: 'Duration',
                    suffix: 'min',
                    min: 5.0,
                    max: 120.0,
                    step: 5.0,
                    onChanged: (v) => setState(() => _steadyStateDurationMin = v),
                  ),
                ],

                // VT2-specific: Intervals config
                if (_runType == RunType.vt2Intervals) ...[
                  _buildSectionHeader('Interval Structure'),
                  const SizedBox(height: 12),
                  _buildNumberInput(
                    value: _numIntervals.toDouble(),
                    label: 'Number of Intervals',
                    suffix: '',
                    min: 1,
                    max: 20,
                    step: 1,
                    onChanged: (v) => setState(() => _numIntervals = v.toInt()),
                    isInteger: true,
                  ),
                  const SizedBox(height: 16),
                  _buildNumberInput(
                    value: _intervalDurationMin,
                    label: 'Interval Duration',
                    suffix: 'min',
                    min: 1.0,
                    max: 10.0,
                    step: 1.0,
                    onChanged: (v) => setState(() => _intervalDurationMin = v),
                  ),
                  const SizedBox(height: 16),
                  _buildNumberInput(
                    value: _recoveryDurationMin,
                    label: 'Recovery Duration',
                    suffix: 'min',
                    min: 0.5,
                    max: 5.0,
                    step: 0.5,
                    onChanged: (v) => setState(() => _recoveryDurationMin = v),
                  ),
                  const SizedBox(height: 16),
                  _buildTotalTimeDisplay(),
                ],

                const SizedBox(height: 32),

                // Warmup/Cooldown Section
                _buildSectionHeader('Warmup & Cooldown (Optional)'),
                const SizedBox(height: 12),
                _buildNumberInput(
                  value: _warmupDurationMin,
                  label: 'Warmup',
                  suffix: 'min',
                  min: 0.0,
                  max: 30.0,
                  step: 5.0,
                  onChanged: (v) => setState(() => _warmupDurationMin = v),
                ),
                const SizedBox(height: 16),
                _buildNumberInput(
                  value: _cooldownDurationMin,
                  label: 'Cooldown',
                  suffix: 'min',
                  min: 0.0,
                  max: 30.0,
                  step: 5.0,
                  onChanged: (v) => setState(() => _cooldownDurationMin = v),
                ),
                if (_warmupDurationMin > 0 || _cooldownDurationMin > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Warmup and cooldown use VT1 threshold',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                  ),

                const SizedBox(height: 48),

                // Go Button
                ElevatedButton(
                  onPressed: _startWorkout,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text(
                    'GO',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
    );
  }

  Widget _buildRunTypeSelector() {
    return SegmentedButton<RunType>(
      segments: const [
        ButtonSegment(
          value: RunType.vt1SteadyState,
          label: Text('VT1 Steady State'),
          icon: Icon(Icons.trending_flat),
        ),
        ButtonSegment(
          value: RunType.vt2Intervals,
          label: Text('VT2 Intervals'),
          icon: Icon(Icons.show_chart),
        ),
      ],
      selected: {_runType},
      onSelectionChanged: (selected) {
        setState(() => _runType = selected.first);
      },
    );
  }

  Widget _buildThresholdDisplay(AppState appState) {
    final threshold = _runType == RunType.vt1SteadyState
        ? appState.vt1Ve
        : appState.vt2Ve;
    final label = _runType == RunType.vt1SteadyState ? 'VT1' : 'VT2';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.speed, color: Colors.blue),
          const SizedBox(width: 12),
          Text(
            '$label Threshold: ${threshold.toStringAsFixed(1)} L/min',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.blue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberInput({
    required double value,
    required String label,
    required String suffix,
    required double min,
    required double max,
    required double step,
    required ValueChanged<double> onChanged,
    bool isInteger = false,
  }) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(label),
        ),
        IconButton(
          onPressed: value > min
              ? () => onChanged((value - step).clamp(min, max))
              : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 80,
          child: Text(
            isInteger
                ? value.toInt().toString()
                : value.toStringAsFixed(1),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          onPressed: value < max
              ? () => onChanged((value + step).clamp(min, max))
              : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
        SizedBox(
          width: 40,
          child: Text(suffix),
        ),
      ],
    );
  }

  Widget _buildTotalTimeDisplay() {
    final totalMin = _numIntervals * (_intervalDurationMin + _recoveryDurationMin);
    final hours = (totalMin / 60).floor();
    final mins = (totalMin % 60).round();

    String timeStr;
    if (hours > 0) {
      timeStr = '${hours}h ${mins}m';
    } else {
      timeStr = '${mins}m';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.timer, size: 20, color: Colors.grey),
          const SizedBox(width: 8),
          Text(
            'Total workout time: $timeStr',
            style: TextStyle(color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }
}
