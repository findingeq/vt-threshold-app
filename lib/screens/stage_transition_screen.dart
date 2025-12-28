import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import 'countdown_screen.dart';
import 'workout_screen.dart';

/// Screen shown between workout stages, requiring user to press a button to continue
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
    return Consumer<AppState>(
      builder: (context, appState, _) {
        final config = appState.currentRun;
        if (config == null) {
          return const Scaffold(
            body: Center(child: Text('No workout configured')),
          );
        }

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
                  const SizedBox(height: 48),

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

                  const SizedBox(height: 64),

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

                  // Cancel button
                  TextButton(
                    onPressed: () {
                      Navigator.popUntil(context, (route) => route.isFirst);
                    },
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
}
