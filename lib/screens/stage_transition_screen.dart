import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../services/workout_data_service.dart';
import 'countdown_screen.dart';
import 'workout_screen.dart';

/// Screen shown between workout stages, showing summary stats and requiring user to continue
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
        return ''; // No previous phase
      case WorkoutPhase.workout:
        return 'warmup';
      case WorkoutPhase.cooldown:
        return 'workout';
    }
  }

  void _startNextPhase(BuildContext context) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => CountdownScreen(
          nextPhase: nextPhase,
          title: _getTitle(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AppState, WorkoutDataService>(
      builder: (context, appState, dataService, _) {
        final config = appState.currentRun;
        if (config == null) {
          return const Scaffold(
            body: Center(child: Text('No workout configured')),
          );
        }

        // Get summary for the completed phase
        final completedPhaseName = _getCompletedPhaseName();
        final summary = completedPhaseName.isNotEmpty
            ? dataService.calculatePhaseSummary(completedPhaseName)
            : null;

        return Scaffold(
          backgroundColor: Colors.blue[50],
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Completed stage message
                  Text(
                    _getCompletedStageMessage(),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Summary stats for completed phase
                  if (summary != null) _buildSummaryCard(summary, config),

                  const SizedBox(height: 32),

                  // Next stage info
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Up Next',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _getNextStageDescription(config),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 48),

                  // Start button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _startNextPhase(context),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _getTitle(),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // End Session / Export button
                  TextButton(
                    onPressed: () => _showEndSessionDialog(context, dataService),
                    child: const Text(
                      'End Session',
                      style: TextStyle(color: Colors.red),
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
    final isVt2Workout = config.runType == RunType.vt2Intervals && summary.phase == 'workout';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            '${summary.phase[0].toUpperCase()}${summary.phase.substring(1)} Summary',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
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
                color: Colors.red,
              ),
              _buildStatItem(
                icon: Icons.air,
                label: 'Avg VE',
                value: '${summary.avgVe.toStringAsFixed(1)} L/min',
                color: Colors.blue,
              ),
            ],
          ),
          // Show terminal slope for VT2 workouts
          if (isVt2Workout && summary.terminalSlopePct != null) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            _buildStatItem(
              icon: Icons.trending_up,
              label: 'Terminal Slope',
              value: '${summary.terminalSlopePct! >= 0 ? '+' : ''}${summary.terminalSlopePct!.toStringAsFixed(1)}%/min',
              color: summary.terminalSlopePct! > 0 ? Colors.orange : Colors.green,
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
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  void _showEndSessionDialog(BuildContext context, WorkoutDataService dataService) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End Session'),
        content: const Text('Do you want to export your data before ending?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              dataService.clear();
              Navigator.popUntil(context, (route) => route.isFirst);
            },
            child: const Text('Discard Data', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await dataService.exportCsv();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('CSV exported successfully'),
                      backgroundColor: Colors.green,
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
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Export & End', style: TextStyle(color: Colors.green)),
          ),
        ],
      ),
    );
  }
}
