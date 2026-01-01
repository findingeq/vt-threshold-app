import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'workout_screen.dart';

class CountdownScreen extends StatefulWidget {
  final WorkoutPhase nextPhase;
  final String title;

  const CountdownScreen({
    super.key,
    required this.nextPhase,
    required this.title,
  });

  @override
  State<CountdownScreen> createState() => _CountdownScreenState();
}

class _CountdownScreenState extends State<CountdownScreen>
    with TickerProviderStateMixin {
  int _countdown = 5;
  Timer? _timer;

  late AnimationController _pulseController;
  late AnimationController _scaleController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // Pulse animation for the glow
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.3, end: 0.6).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Scale animation for number change
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOut),
    );

    _startCountdown();
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown <= 1) {
        timer.cancel();
        _timer = null;
        if (mounted) {
          _navigateToNextPhase();
        }
      } else {
        if (mounted) {
          // Trigger scale animation
          _scaleController.forward().then((_) {
            _scaleController.reverse();
          });
          setState(() {
            _countdown--;
          });
        }
      }
    });
  }

  void _navigateToNextPhase() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            WorkoutScreen(phase: widget.nextPhase),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Title
              Text(
                widget.title.toUpperCase(),
                style: AppTheme.labelLarge.copyWith(
                  letterSpacing: 3,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(height: 60),

              // Countdown circle with glow
              AnimatedBuilder(
                animation: Listenable.merge([_pulseAnimation, _scaleAnimation]),
                builder: (context, child) {
                  return Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppTheme.accentBlue.withOpacity(0.2),
                          AppTheme.accentBlue.withOpacity(0.05),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.accentBlue
                              .withOpacity(_pulseAnimation.value),
                          blurRadius: 60,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.surfaceCard,
                          border: Border.all(
                            color: AppTheme.accentBlue.withOpacity(0.5),
                            width: 3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.accentBlue.withOpacity(0.3),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Transform.scale(
                            scale: _scaleAnimation.value,
                            child: Text(
                              _countdown.toString(),
                              style: const TextStyle(
                                fontSize: 80,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 60),

              // Progress dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final isActive = (5 - _countdown) > index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: isActive ? 12 : 8,
                    height: isActive ? 12 : 8,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive
                          ? AppTheme.accentBlue
                          : AppTheme.surfaceCardLight,
                      border: Border.all(
                        color: isActive
                            ? AppTheme.accentBlue
                            : AppTheme.borderSubtle,
                      ),
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                color: AppTheme.accentBlue.withOpacity(0.5),
                                blurRadius: 8,
                              ),
                            ]
                          : null,
                    ),
                  );
                }),
              ),

              const SizedBox(height: 40),

              // Get ready text
              Text(
                'Get ready...',
                style: AppTheme.bodyLarge.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
