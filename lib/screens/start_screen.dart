import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';
import 'run_format_screen.dart';

class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  late TextEditingController _vt1Controller;
  late TextEditingController _vt2Controller;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _vt1Controller = TextEditingController(text: appState.vt1Ve.toString());
    _vt2Controller = TextEditingController(text: appState.vt2Ve.toString());
  }

  @override
  void dispose() {
    _vt1Controller.dispose();
    _vt2Controller.dispose();
    super.dispose();
  }

  void _saveVt1(String value) {
    final parsed = double.tryParse(value);
    if (parsed != null && parsed > 0) {
      context.read<AppState>().setVt1Ve(parsed);
    }
  }

  void _saveVt2(String value) {
    final parsed = double.tryParse(value);
    if (parsed != null && parsed > 0) {
      context.read<AppState>().setVt2Ve(parsed);
    }
  }

  void _connectBreathingSensor() {
    // TODO: Implement Bluetooth connection with flutter_blue_plus
    // For now, simulate connection
    context.read<AppState>().setBreathingSensorConnected(true, battery: 85);
  }

  void _connectHrSensor() {
    // TODO: Implement Bluetooth connection with flutter_blue_plus
    // For now, simulate connection
    context.read<AppState>().setHrSensorConnected(true, battery: 92);
  }

  void _navigateToRunFormat() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RunFormatScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VT Threshold Analyzer'),
        centerTitle: true,
      ),
      body: Consumer<AppState>(
        builder: (context, appState, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // VT Thresholds Section
                _buildSectionHeader('VT Thresholds'),
                const SizedBox(height: 16),
                _buildThresholdInput(
                  label: 'VT1 VE',
                  controller: _vt1Controller,
                  onChanged: _saveVt1,
                  hint: 'L/min at VT1',
                ),
                const SizedBox(height: 16),
                _buildThresholdInput(
                  label: 'VT2 VE',
                  controller: _vt2Controller,
                  onChanged: _saveVt2,
                  hint: 'L/min at VT2',
                ),
                const SizedBox(height: 8),
                Text(
                  'Values from prior ramp test. Auto-saved.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                ),

                const SizedBox(height: 40),

                // Sensor Connection Section
                _buildSectionHeader('Sensor Connection'),
                const SizedBox(height: 16),
                _buildSensorRow(
                  name: 'Breathing Sensor',
                  connected: appState.breathingSensorConnected,
                  battery: appState.breathingSensorBattery,
                  onConnect: _connectBreathingSensor,
                ),
                const SizedBox(height: 12),
                _buildSensorRow(
                  name: 'Heart Rate Sensor',
                  connected: appState.hrSensorConnected,
                  battery: appState.hrSensorBattery,
                  onConnect: _connectHrSensor,
                ),

                const SizedBox(height: 48),

                // Continue Button
                ElevatedButton(
                  onPressed: appState.sensorsReady ? _navigateToRunFormat : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[300],
                  ),
                  child: Text(
                    appState.sensorsReady ? 'Continue' : 'Connect Sensors to Continue',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),

                // Dev mode: Skip sensor check
                if (!appState.sensorsReady) ...[
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _navigateToRunFormat,
                    child: const Text(
                      'Skip (Dev Mode)',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ],
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

  Widget _buildThresholdInput({
    required String label,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    required String hint,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
            ],
            decoration: InputDecoration(
              hintText: hint,
              suffixText: 'L/min',
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildSensorRow({
    required String name,
    required bool connected,
    required int battery,
    required VoidCallback onConnect,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: connected ? Colors.green[50] : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: connected ? Colors.green : Colors.grey[300]!,
        ),
      ),
      child: Row(
        children: [
          Icon(
            connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
            color: connected ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                if (connected)
                  Text(
                    'Battery: $battery%',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
              ],
            ),
          ),
          if (!connected)
            ElevatedButton(
              onPressed: onConnect,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Connect'),
            )
          else
            const Icon(Icons.check_circle, color: Colors.green),
        ],
      ),
    );
  }
}
