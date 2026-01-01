import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../theme/app_theme.dart';
import 'countdown_screen.dart';
import 'workout_screen.dart';

class RunFormatScreen extends StatefulWidget {
  const RunFormatScreen({super.key});

  @override
  State<RunFormatScreen> createState() => _RunFormatScreenState();
}

class _RunFormatScreenState extends State<RunFormatScreen>
    with SingleTickerProviderStateMixin {
  RunType _runType = RunType.vt1SteadyState;
  double _speedMph = 7.5;
  int _numIntervals = 12;
  double _intervalDurationMin = 4.0;
  double _recoveryDurationMin = 1.0;
  double _steadyStateDurationMin = 30.0;
  double _warmupDurationMin = 0.0;
  double _cooldownDurationMin = 0.0;
  double _warmupSpeedMph = 5.0;
  double _cooldownSpeedMph = 5.0;

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _startWorkout() {
    final appState = context.read<AppState>();

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
      recoveryDurationMin:
          _runType == RunType.vt2Intervals ? _recoveryDurationMin : 0.0,
      thresholdVe: thresholdVe,
      warmupDurationMin: _warmupDurationMin,
      cooldownDurationMin: _cooldownDurationMin,
      vt1Ve: appState.vt1Ve,
      warmupSpeedMph: _warmupSpeedMph,
      cooldownSpeedMph: _cooldownSpeedMph,
    );

    appState.setCurrentRun(config);

    final firstPhase =
        config.hasWarmup ? WorkoutPhase.warmup : WorkoutPhase.workout;
    final title = config.hasWarmup ? 'Start Warmup' : 'Start Workout';

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            CountdownScreen(nextPhase: firstPhase, title: title),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Consumer<AppState>(
            builder: (context, appState, _) {
              return Column(
                children: [
                  // Header
                  _buildHeader(),

                  // Content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 24),

                          // Run Type Toggle
                          _buildRunTypeToggle(),

                          const SizedBox(height: 24),

                          // Threshold Display
                          _buildThresholdDisplay(appState),

                          const SizedBox(height: 32),

                          // Speed
                          _buildSectionLabel('SPEED'),
                          const SizedBox(height: 12),
                          _buildValueControl(
                            value: _speedMph,
                            unit: 'mph',
                            icon: Icons.speed,
                            color: AppTheme.accentPurple,
                            min: 1.0,
                            max: 15.0,
                            step: 0.1,
                            onChanged: (v) => setState(() => _speedMph = v),
                          ),

                          const SizedBox(height: 32),

                          // Duration/Intervals
                          if (_runType == RunType.vt1SteadyState) ...[
                            _buildSectionLabel('DURATION'),
                            const SizedBox(height: 12),
                            _buildValueControl(
                              value: _steadyStateDurationMin,
                              unit: 'min',
                              icon: Icons.timer_outlined,
                              color: AppTheme.accentBlue,
                              min: 5.0,
                              max: 120.0,
                              step: 1.0,
                              onChanged: (v) =>
                                  setState(() => _steadyStateDurationMin = v),
                            ),
                          ],

                          if (_runType == RunType.vt2Intervals) ...[
                            _buildSectionLabel('INTERVALS'),
                            const SizedBox(height: 12),
                            _buildIntervalsCard(),
                          ],

                          const SizedBox(height: 32),

                          // Warmup/Cooldown
                          _buildSectionLabel('WARMUP & COOLDOWN'),
                          const SizedBox(height: 12),
                          _buildWarmupCooldownCard(),

                          const SizedBox(height: 100),
                        ],
                      ),
                    ),
                  ),

                  // Go Button
                  _buildGoButton(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 24, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back_ios,
              color: AppTheme.textSecondary,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'VT ANALYZER',
                  style: AppTheme.labelLarge.copyWith(
                    color: AppTheme.textMuted,
                    letterSpacing: 2,
                  ),
                ),
                Text('Run Format', style: AppTheme.headlineLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRunTypeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildToggleOption(
              label: 'VT1 Steady',
              icon: Icons.trending_flat,
              isSelected: _runType == RunType.vt1SteadyState,
              onTap: () => setState(() => _runType = RunType.vt1SteadyState),
            ),
          ),
          Expanded(
            child: _buildToggleOption(
              label: 'VT2 Intervals',
              icon: Icons.show_chart,
              isSelected: _runType == RunType.vt2Intervals,
              onTap: () => setState(() => _runType = RunType.vt2Intervals),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleOption({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accentBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? AppTheme.textPrimary : AppTheme.textMuted,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTheme.titleMedium.copyWith(
                color: isSelected ? AppTheme.textPrimary : AppTheme.textMuted,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThresholdDisplay(AppState appState) {
    final threshold =
        _runType == RunType.vt1SteadyState ? appState.vt1Ve : appState.vt2Ve;
    final label = _runType == RunType.vt1SteadyState ? 'VT1' : 'VT2';
    final color = _runType == RunType.vt1SteadyState
        ? AppTheme.accentBlue
        : AppTheme.accentOrange;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
            child: Text(
              label,
              style: AppTheme.labelLarge.copyWith(color: color),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Threshold: ${threshold.toStringAsFixed(1)}',
            style: AppTheme.titleLarge.copyWith(color: color),
          ),
          const SizedBox(width: 4),
          Text(
            'L/min',
            style: AppTheme.bodyMedium.copyWith(color: color.withOpacity(0.7)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: AppTheme.labelLarge.copyWith(letterSpacing: 1.5),
      ),
    );
  }

  Widget _buildValueControl({
    required double value,
    required String unit,
    required IconData icon,
    required Color color,
    required double min,
    required double max,
    required double step,
    required ValueChanged<double> onChanged,
    bool isInteger = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration,
      child: Row(
        children: [
          // Icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 16),

          // Minus
          _buildCircleButton(
            icon: Icons.remove,
            enabled: value > min,
            onTap: () => onChanged((value - step).clamp(min, max)),
          ),

          // Value
          Expanded(
            child: GestureDetector(
              onTap: () => _showValueEditor(
                value: value,
                unit: unit,
                min: min,
                max: max,
                onChanged: onChanged,
                isInteger: isInteger,
              ),
              child: Column(
                children: [
                  Text(
                    isInteger
                        ? value.toInt().toString()
                        : value.toStringAsFixed(1),
                    style: AppTheme.headlineMedium,
                  ),
                  Text(unit, style: AppTheme.labelSmall),
                ],
              ),
            ),
          ),

          // Plus
          _buildCircleButton(
            icon: Icons.add,
            enabled: value < max,
            onTap: () => onChanged((value + step).clamp(min, max)),
          ),
        ],
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppTheme.surfaceCardLight,
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.borderSubtle),
        ),
        child: Icon(
          icon,
          color: enabled ? AppTheme.textSecondary : AppTheme.textDisabled,
          size: 22,
        ),
      ),
    );
  }

  Widget _buildIntervalsCard() {
    final totalMin = _numIntervals * (_intervalDurationMin + _recoveryDurationMin);
    final hours = (totalMin / 60).floor();
    final mins = (totalMin % 60).round();
    final timeStr = hours > 0 ? '${hours}h ${mins}m' : '${mins}m';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.cardDecoration,
      child: Column(
        children: [
          // Number of intervals
          _buildCompactValueRow(
            label: 'Intervals',
            value: _numIntervals.toDouble(),
            unit: '',
            min: 1,
            max: 20,
            step: 1,
            isInteger: true,
            onChanged: (v) => setState(() => _numIntervals = v.toInt()),
          ),
          const SizedBox(height: 16),
          const Divider(color: AppTheme.borderSubtle),
          const SizedBox(height: 16),

          // Interval duration
          _buildCompactValueRow(
            label: 'Work',
            value: _intervalDurationMin,
            unit: 'min',
            min: 1.0,
            max: 10.0,
            step: 0.5,
            onChanged: (v) => setState(() => _intervalDurationMin = v),
          ),
          const SizedBox(height: 16),

          // Recovery duration
          _buildCompactValueRow(
            label: 'Recovery',
            value: _recoveryDurationMin,
            unit: 'min',
            min: 0.5,
            max: 5.0,
            step: 0.5,
            onChanged: (v) => setState(() => _recoveryDurationMin = v),
          ),
          const SizedBox(height: 16),
          const Divider(color: AppTheme.borderSubtle),
          const SizedBox(height: 12),

          // Total time
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.timer, size: 18, color: AppTheme.textMuted),
              const SizedBox(width: 8),
              Text(
                'Total: $timeStr',
                style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactValueRow({
    required String label,
    required double value,
    required String unit,
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
          child: Text(label, style: AppTheme.bodyLarge),
        ),
        _buildSmallCircleButton(
          icon: Icons.remove,
          enabled: value > min,
          onTap: () => onChanged((value - step).clamp(min, max)),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 60,
          child: Text(
            isInteger
                ? value.toInt().toString()
                : value.toStringAsFixed(1),
            textAlign: TextAlign.center,
            style: AppTheme.titleLarge,
          ),
        ),
        const SizedBox(width: 8),
        _buildSmallCircleButton(
          icon: Icons.add,
          enabled: value < max,
          onTap: () => onChanged((value + step).clamp(min, max)),
        ),
        if (unit.isNotEmpty)
          SizedBox(
            width: 40,
            child: Text(
              unit,
              style: AppTheme.labelSmall,
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  Widget _buildSmallCircleButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppTheme.surfaceCardLight,
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.borderSubtle),
        ),
        child: Icon(
          icon,
          color: enabled ? AppTheme.textSecondary : AppTheme.textDisabled,
          size: 18,
        ),
      ),
    );
  }

  Widget _buildWarmupCooldownCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.cardDecoration,
      child: Column(
        children: [
          // Warmup
          _buildCompactValueRow(
            label: 'Warmup',
            value: _warmupDurationMin,
            unit: 'min',
            min: 0.0,
            max: 30.0,
            step: 1.0,
            onChanged: (v) => setState(() => _warmupDurationMin = v),
          ),
          if (_warmupDurationMin > 0) ...[
            const SizedBox(height: 12),
            _buildCompactValueRow(
              label: '  Speed',
              value: _warmupSpeedMph,
              unit: 'mph',
              min: 1.0,
              max: 10.0,
              step: 0.1,
              onChanged: (v) => setState(() => _warmupSpeedMph = v),
            ),
          ],
          const SizedBox(height: 16),
          const Divider(color: AppTheme.borderSubtle),
          const SizedBox(height: 16),

          // Cooldown
          _buildCompactValueRow(
            label: 'Cooldown',
            value: _cooldownDurationMin,
            unit: 'min',
            min: 0.0,
            max: 30.0,
            step: 1.0,
            onChanged: (v) => setState(() => _cooldownDurationMin = v),
          ),
          if (_cooldownDurationMin > 0) ...[
            const SizedBox(height: 12),
            _buildCompactValueRow(
              label: '  Speed',
              value: _cooldownSpeedMph,
              unit: 'mph',
              min: 1.0,
              max: 10.0,
              step: 0.1,
              onChanged: (v) => setState(() => _cooldownSpeedMph = v),
            ),
          ],

          if (_warmupDurationMin > 0 || _cooldownDurationMin > 0) ...[
            const SizedBox(height: 16),
            Text(
              'Uses VT1 threshold',
              style: AppTheme.labelSmall.copyWith(color: AppTheme.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGoButton() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.background.withOpacity(0),
            AppTheme.background,
          ],
        ),
      ),
      child: GestureDetector(
        onTap: _startWorkout,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            gradient: AppTheme.greenGradient,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accentGreen.withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Center(
            child: Text(
              'GO',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
                letterSpacing: 4,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showValueEditor({
    required double value,
    required String unit,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    bool isInteger = false,
  }) {
    final controller = TextEditingController(
      text: isInteger ? value.toInt().toString() : value.toStringAsFixed(1),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        ),
        title: Text('Enter Value', style: AppTheme.titleLarge),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
          ],
          style: AppTheme.headlineMedium,
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            suffixText: unit,
            suffixStyle: AppTheme.bodyMedium,
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textMuted),
            ),
          ),
          TextButton(
            onPressed: () {
              final parsed = double.tryParse(controller.text);
              if (parsed != null) {
                onChanged(parsed.clamp(min, max));
              }
              Navigator.pop(ctx);
            },
            child: Text(
              'OK',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.accentBlue),
            ),
          ),
        ],
      ),
    );
  }
}
