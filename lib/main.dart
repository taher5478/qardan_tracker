import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:workmanager/workmanager.dart';

import 'screens/home_screen.dart';
import 'services/reminder_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise the background task engine.
  await Workmanager().initialize(callbackDispatcher);

  await _ensurePermissions();
  await scheduleReminders();

  runApp(const QardanApp());
}

/// Request SMS, notification, and battery-optimization exemptions up front so
/// the background sweep can actually send messages.
Future<void> _ensurePermissions() async {
  await [
    Permission.sms,
    Permission.notification,
  ].request();

  // Asking the user to exclude us from battery optimization dramatically
  // improves background reliability on most OEM Android builds.
  if (await Permission.ignoreBatteryOptimizations.isDenied) {
    await Permission.ignoreBatteryOptimizations.request();
  }
}

class QardanApp extends StatelessWidget {
  const QardanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Qardan Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF00695C),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      home: const HomeScreen(),
    );
  }
}
