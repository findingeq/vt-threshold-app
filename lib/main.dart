import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'models/app_state.dart';
import 'screens/start_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialize Hive (pure Dart, no native iOS code)
    await Hive.initFlutter();
    final box = await Hive.openBox('settings');

    runApp(
      ChangeNotifierProvider(
        create: (_) => AppState(box),
        child: const VTThresholdApp(),
      ),
    );
  } catch (e) {
    // If Hive fails, show error app
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Failed to initialize app: $e'),
          ),
        ),
      ),
    );
  }
}

class VTThresholdApp extends StatelessWidget {
  const VTThresholdApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VT Threshold Analyzer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const StartScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
