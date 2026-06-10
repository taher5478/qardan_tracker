import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import 'constants.dart';
import 'screens/home_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/drive_backup_service.dart';
import 'services/foreground_service.dart';
import 'services/license_service.dart';
import 'services/notification_service.dart';
import 'services/reminder_service.dart';
import 'services/settings_service.dart';
import 'services/subscription_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppSettings.instance.ensureLoaded();
  await AppSettings.instance.ensureTrialStarted(); // start the free-trial clock
  await NotificationService.init();
  ForegroundReminderService.init();

  await Supabase.initialize(
      url: kSupabaseUrl, publishableKey: kSupabasePublishableKey);
  // Re-check the stored activation key + Dodo subscription online (non-blocking).
  LicenseService.instance.revalidate();
  SubscriptionService.instance.refresh();

  await Workmanager().initialize(callbackDispatcher);

  // Permissions are requested in onboarding (with context), not cold at launch.
  await scheduleReminders();

  // Re-start the persistent service if the owner had opted in.
  if (AppSettings.instance.foregroundEnabled) {
    await ForegroundReminderService.start();
  }

  // Daily Google Drive backup (once per 24h) — fire-and-forget so it never
  // blocks startup.
  DriveBackupService().maybeDailyBackup();

  runApp(const QardanApp());
}

class QardanApp extends StatelessWidget {
  const QardanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const AuthGate(),
    );
  }
}

/// Shows the lock screen when the app lock is enabled, and re-locks whenever the
/// app is resumed from the background.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  late bool _unlocked;

  bool get _lockActive =>
      AppSettings.instance.lockEnabled && AppSettings.instance.hasPin;

  @override
  void initState() {
    super.initState();
    _unlocked = !_lockActive;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _lockActive) {
      setState(() => _unlocked = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_lockActive && !_unlocked) {
      return LockScreen(onUnlocked: () => setState(() => _unlocked = true));
    }
    if (!AppSettings.instance.onboardingComplete) {
      return OnboardingScreen(onDone: () => setState(() {}));
    }
    return const HomeScreen();
  }
}
