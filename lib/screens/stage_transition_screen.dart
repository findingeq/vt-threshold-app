import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../services/workout_data_service.dart';
import '../theme/app_theme.dart';
import 'countdown_screen.dart';
import 'workout_screen.dart';

class StageTransitionScreen extends StatelessWidget {
  final WorkoutPhase nextPhase;

  const StageTransitionScreen({
    super.key,
    required this.nextPhase,
  });

  String _getTitle() {
    switch (nextPhase) {
      case WorkoutPhase.warmup:
        return 'Start Warmup';
      case WorkoutPhase.workout:
        return 'Start Workout';
      case WorkoutPhase.cooldown:
        return 'Start Cooldown';
    }
  }

  String _getNextStageDescription(RunConfig config) {
    switch (nextPhase) {
      case WorkoutPhase.warmup:
        return '${config.warmupDurationMin.toInt()} min warmup';
      case WorkoutPhase.workout:
        if (config.runType == RunType.vt2Intervals) {
          return '${config.numIntervals}x${config.intervalDurationMin.toInt()} min intervals';
        } else {
          return '${config.intervalDurationMin.toInt()} min steady state';
        }
      case WorkoutPhase.cooldown:
        return '${config.cooldownDurationMin.toInt()} min cooldown';
    }
  }

  String _getCompletedStageMessage() {
    switch (nextPhase) {
      case WorkoutPhase.warmup:
        return 'Ready to begin';
      case WorkoutPhase.workout:
        return 'Warmup Complete!';
      case WorkoutPhase.cooldown:
        return 'Workout Complete!';
    }
  }

  String _getCompletedPhaseName() {
    switch (nextPhase) {
      case WorkoutPhase.warmup:
        return '';
      case WorkoutPhase.workout:
        return 'warmup';
      case WorkoutPhase.cooldown:
        return 'workout';
    }
  }

  void _startNextPhase(BuildContext context) {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            CountdownScreen(nextPhase: nextPhase, title: _getTitle()),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AppState, WorkoutDataService>(
      builder: (context, appState, dataService, _) {
        final config = appState.currentRun;
        if (config == null) {
          return Scaffold(
            backgroundColor: AppTheme.background,
            body: Center(
              child: Text(
                'No workout configured',
                style: AppTheme.bodyLarge,
              ),
            ),
          );
        }

        final completedPhaseName = _getCompletedPhaseName();
        final summary = completedPhaseName.isNotEmpty
            ? dataService.calculatePhaseSummary(completedPhaseName)
            : null;

        return Scaffold(
          backgroundColor: AppTheme.background,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Success indicator
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppTheme.accentGreen.withOpacity(0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.accentGreen.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      Icons.check,
                      color: AppTheme.accentGreen,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Completed stage message
                  Text(
                    _getCompletedStageMessage(),
                    style: AppTheme.headlineLarge.copyWith(
                      color: AppTheme.accentGreen,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Summary stats
                  if (summary != null) _buildSummaryCard(summary, config),

                  const SizedBox(height: 32),

                  // Next stage info
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: AppTheme.cardDecoration,
                    child: Column(
                      children: [
                        Text(
                          'UP NEXT',
                          style: AppTheme.labelLarge.copyWith(
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _getNextStageDescription(config),
                          style: AppTheme.headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Start button
                  GestureDetector(
                    onTap: () => _startNextPhase(context),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      decoration: BoxDecoration(
                        gradient: AppTheme.greenGradient,
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusMedium),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.accentGreen.withOpacity(0.4),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          _getTitle(),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // End Session button
                  TextButton(
                    onPressed: () =>
                        _showEndSessionDialog(context, dataService),
                    child: Text(
                      'End Session',
                      style: AppTheme.bodyMedium
                          .copyWith(color: AppTheme.accentRed),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummaryCard(PhaseSummary summary, RunConfig config) {
    final isVt2Workout =
        config.runType == RunType.vt2Intervals && summary.phase == 'workout';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppTheme.accentGreen.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            '${summary.phase[0].toUpperCase()}${summary.phase.substring(1)} Summary',
            style: AppTheme.labelLarge.copyWith(letterSpacing: 1),
          ),
          const SizedBox(height: 16),
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
          if (isVt2Workout && summary.terminalSlopePct != null) ...[
            const SizedBox(height: 16),
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
              subtitle: 'VE drift in last 30s of intervals',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    String? subtitle,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(label, style: AppTheme.labelSmall),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTheme.titleMedium.copyWith(color: color),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: AppTheme.labelSmall.copyWith(
              fontSize: 9,
              color: AppTheme.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  void _showEndSessionDialog(
      BuildContext context, WorkoutDataService dataService) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        ),
        title: Text('End Session', style: AppTheme.titleLarge),
        content: Text(
          'Do you want to export your data before ending?',
          style: AppTheme.bodyLarge,
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
              Navigator.pop(ctx);
              dataService.clear();
              Navigator.popUntil(context, (route) => route.isFirst);
            },
            child: Text(
              'Discard',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.accentRed),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await dataService.exportCsv();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('CSV exported successfully'),
                      backgroundColor: AppTheme.accentGreen,
                    ),
                  );
                  dataService.clear();
                  Navigator.popUntil(context, (route) => route.isFirst);
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Export failed: $e'),
                      backgroundColor: AppTheme.accentRed,
                    ),
                  );
                }
              }
            },
            child: Text(
              'Export',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.accentBlue),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await dataService.uploadToCloud();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Uploaded successfully'),
                      backgroundColor: AppTheme.accentGreen,
                    ),
                  );
                  dataService.clear();
                  Navigator.popUntil(context, (route) => route.isFirst);
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Upload failed: $e'),
                      backgroundColor: AppTheme.accentRed,
                    ),
                  );
                }
              }
            },
            child: Text(
              'Upload',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.accentGreen),
            ),
          ),
        ],
      ),
    );
  }
}
