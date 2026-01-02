import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'models/app_state.dart';
import 'screens/start_screen.dart';
import 'services/ble_service.dart';
import 'services/workout_data_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system UI overlay style for dark theme
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppTheme.background,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  final appState = AppState();
  // Load persisted VT thresholds before starting the app
  await appState.loadPersistedValues();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider(create: (_) => BleService()),
        ChangeNotifierProvider(create: (_) => WorkoutDataService()),
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
      theme: AppTheme.darkTheme,
      home: const StartScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
