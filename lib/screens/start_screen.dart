import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import '../services/ble_service.dart';
import '../services/workout_data_service.dart';
import '../theme/app_theme.dart';
import 'run_format_screen.dart';

class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TextEditingController _vt1Controller;
  late TextEditingController _vt2Controller;
  bool _initialized = false;
  bool _connectingBreathing = false;
  bool _connectingHr = false;

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _vt1Controller = TextEditingController();
    _vt2Controller = TextEditingController();

    _animController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _animController.forward();

    // Sync calibrated params from cloud after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncFromCloud();
    });
  }

  Future<void> _syncFromCloud() async {
    final appState = context.read<AppState>();
    await appState.syncFromCloud(context);

    // Update controllers if values changed from cloud sync
    if (mounted) {
      setState(() {
        _vt1Controller.text = appState.vt1Ve.toStringAsFixed(1);
        _vt2Controller.text = appState.vt2Ve.toStringAsFixed(1);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Note: We no longer clear data on resume - this was causing the
    // "no workout configured" bug when transitioning between phases.
    // Data is cleared after successful upload or when starting a new workout.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Only initialize controllers once, don't clear workout data here
    // Data clearing is now handled explicitly after upload or on new workout start
    final appState = context.read<AppState>();

    if (!_initialized) {
      _vt1Controller.text = appState.vt1Ve.toString();
      _vt2Controller.text = appState.vt2Ve.toString();
      _initialized = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _vt1Controller.dispose();
    _vt2Controller.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _saveVt1(String value) async {
    final parsed = double.tryParse(value);
    if (parsed != null && parsed > 0) {
      await context.read<AppState>().setVt1Ve(parsed);
    }
  }

  Future<void> _saveVt2(String value) async {
    final parsed = double.tryParse(value);
    if (parsed != null && parsed > 0) {
      await context.read<AppState>().setVt2Ve(parsed);
    }
  }

  Future<void> _connectBreathingSensor() async {
    if (_connectingBreathing) return;

    setState(() => _connectingBreathing = true);

    final bleService = context.read<BleService>();
    final appState = context.read<AppState>();
    final success = await bleService.connectBreathingSensor();

    if (mounted) {
      setState(() => _connectingBreathing = false);

      if (success) {
        appState.setBreathingSensorConnected(
          true,
          battery: bleService.breathingSensorBattery,
        );
      } else {
        _showError(bleService.connectionError ?? 'Connection failed');
      }
    }
  }

  Future<void> _connectHrSensor() async {
    if (_connectingHr) return;

    setState(() => _connectingHr = true);

    final bleService = context.read<BleService>();
    final appState = context.read<AppState>();
    final success = await bleService.connectHrSensor();

    if (mounted) {
      setState(() => _connectingHr = false);

      if (success) {
        appState.setHrSensorConnected(
          true,
          battery: bleService.hrSensorBattery,
        );
      } else {
        _showError(bleService.connectionError ?? 'Connection failed');
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline, color: AppTheme.accentRed),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppTheme.surfaceCard,
      ),
    );
  }

  void _navigateToRunFormat() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const RunFormatScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.05, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOut,
              )),
              child: child,
            ),
          );
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'VT ANALYZER',
                              style: AppTheme.labelLarge.copyWith(
                                color: AppTheme.textMuted,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Setup',
                              style: AppTheme.headlineLarge,
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: AppTheme.cardDecoration,
                          child: Icon(
                            Icons.settings_outlined,
                            color: AppTheme.textMuted,
                            size: 24,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // VT Thresholds Section
                          _buildSectionLabel('THRESHOLDS'),
                          const SizedBox(height: 12),
                          _buildThresholdCard(appState),

                          const SizedBox(height: 32),

                          // Sensors Section
                          _buildSectionLabel('SENSORS'),
                          const SizedBox(height: 12),
                          _buildSensorCard(
                            name: 'Breathing',
                            icon: Icons.air,
                            connected: appState.breathingSensorConnected,
                            battery: appState.breathingSensorBattery,
                            isConnecting: _connectingBreathing,
                            onConnect: _connectBreathingSensor,
                          ),
                          const SizedBox(height: 12),
                          _buildSensorCard(
                            name: 'Heart Rate',
                            icon: Icons.favorite_outline,
                            connected: appState.hrSensorConnected,
                            battery: appState.hrSensorBattery,
                            isConnecting: _connectingHr,
                            onConnect: _connectHrSensor,
                          ),

                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),

                  // Bottom Button
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        _buildContinueButton(appState),
                        if (!appState.sensorsReady) ...[
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _navigateToRunFormat,
                            child: Text(
                              'Skip (Dev Mode)',
                              style: AppTheme.bodyMedium.copyWith(
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: AppTheme.labelLarge.copyWith(
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildThresholdCard(AppState appState) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration,
      child: Row(
        children: [
          Expanded(
            child: _buildCompactThresholdInput(
              label: 'VT1',
              controller: _vt1Controller,
              onChanged: _saveVt1,
              color: AppTheme.accentBlue,
            ),
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 60, color: AppTheme.borderSubtle),
          const SizedBox(width: 12),
          Expanded(
            child: _buildCompactThresholdInput(
              label: 'VT2',
              controller: _vt2Controller,
              onChanged: _saveVt2,
              color: AppTheme.accentOrange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactThresholdInput({
    required String label,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    required Color color,
  }) {
    return Column(
      children: [
        // Label
        Text(
          label,
          style: AppTheme.labelLarge.copyWith(color: color),
        ),
        const SizedBox(height: 8),
        // Value row with +/- buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildSmallCircleButton(
              icon: Icons.remove,
              onTap: () {
                final current = double.tryParse(controller.text) ?? 0;
                if (current > 1) {
                  final newVal = (current - 1).toStringAsFixed(1);
                  controller.text = newVal;
                  onChanged(newVal);
                }
              },
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _showValueEditor(controller, onChanged, label),
              child: Text(
                controller.text,
                style: AppTheme.headlineMedium.copyWith(
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _buildSmallCircleButton(
              icon: Icons.add,
              onTap: () {
                final current = double.tryParse(controller.text) ?? 0;
                if (current < 200) {
                  final newVal = (current + 1).toStringAsFixed(1);
                  controller.text = newVal;
                  onChanged(newVal);
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSmallCircleButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppTheme.surfaceCardLight,
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.borderSubtle),
        ),
        child: Icon(
          icon,
          color: AppTheme.textSecondary,
          size: 18,
        ),
      ),
    );
  }

  void _showValueEditor(
    TextEditingController controller,
    ValueChanged<String> onChanged,
    String label,
  ) {
    final editController = TextEditingController(text: controller.text);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        ),
        title: Text(
          'Enter $label Threshold',
          style: AppTheme.titleLarge,
        ),
        content: TextField(
          controller: editController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
          ],
          style: AppTheme.headlineMedium,
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            suffixText: 'L/min',
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
              final parsed = double.tryParse(editController.text);
              if (parsed != null && parsed > 0) {
                controller.text = parsed.toStringAsFixed(1);
                onChanged(controller.text);
              }
              Navigator.pop(ctx);
            },
            child: Text(
              'Save',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.accentBlue),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSensorCard({
    required String name,
    required IconData icon,
    required bool connected,
    required int battery,
    required bool isConnecting,
    required VoidCallback onConnect,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(
          color: connected ? AppTheme.accentGreen.withOpacity(0.5) : AppTheme.borderSubtle,
        ),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: connected
                  ? AppTheme.accentGreen.withOpacity(0.15)
                  : AppTheme.surfaceCardLight,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            ),
            child: Icon(
              icon,
              color: connected ? AppTheme.accentGreen : AppTheme.textMuted,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                if (connected)
                  Row(
                    children: [
                      Icon(
                        Icons.battery_full,
                        size: 14,
                        color: battery > 20 ? AppTheme.accentGreen : AppTheme.accentRed,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$battery%',
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  )
                else if (isConnecting)
                  Text(
                    'Scanning...',
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.accentBlue,
                    ),
                  )
                else
                  Text(
                    'Not connected',
                    style: AppTheme.labelSmall,
                  ),
              ],
            ),
          ),

          // Action
          if (isConnecting)
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.accentBlue,
              ),
            )
          else if (connected)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.accentGreen.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check,
                color: AppTheme.accentGreen,
                size: 20,
              ),
            )
          else
            GestureDetector(
              onTap: onConnect,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.accentBlue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(AppTheme.radiusCircular),
                  border: Border.all(color: AppTheme.accentBlue.withOpacity(0.3)),
                ),
                child: Text(
                  'Connect',
                  style: AppTheme.labelLarge.copyWith(
                    color: AppTheme.accentBlue,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContinueButton(AppState appState) {
    final ready = appState.sensorsReady;

    return GestureDetector(
      onTap: ready ? _navigateToRunFormat : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          gradient: ready ? AppTheme.accentGradient : null,
          color: ready ? null : AppTheme.surfaceCard,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(
            color: ready ? Colors.transparent : AppTheme.borderSubtle,
          ),
          boxShadow: ready
              ? [
                  BoxShadow(
                    color: AppTheme.accentBlue.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            ready ? 'Continue' : 'Connect Sensors to Continue',
            style: AppTheme.titleMedium.copyWith(
              color: ready ? AppTheme.textPrimary : AppTheme.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
