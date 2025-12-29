import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/app_state.dart';
import 'screens/start_screen.dart';
import 'services/ble_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => BleService()),
      ],
      child: const VTThresholdApp(),
    ),
  );
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
