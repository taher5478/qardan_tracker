import 'dart:ui';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';

import 'reminder_service.dart';

/// Third reliability layer: an AlarmManager alarm that fires every 15 minutes,
/// runs the reminder sweep, and revives the foreground service if an OEM
/// killed it.
///
/// Why three layers? Aggressive OEMs (Xiaomi, Oppo, Vivo, Samsung A-series)
/// kill both WorkManager jobs and foreground services. AlarmManager broadcasts
/// are delivered by the SYSTEM process and wake the app even after it has been
/// killed, making them the most kill-resistant trigger available:
///   1. Foreground service  — continuous, runs the sweep every 15 min.
///   2. WorkManager        — hourly fallback sweep.
///   3. AlarmManager        — wakes the app even when 1 and 2 were killed.
/// The per-loan atomic claim in the DB guarantees no duplicate SMS no matter
/// how many layers fire at once.
class AlarmReminderService {
  static const _alarmId = 7001;
  static const _interval = Duration(minutes: 15);

  static Future<void> init() async {
    await AndroidAlarmManager.initialize();
  }

  /// (Re)register the periodic alarm. Uses an exact, doze-piercing alarm when
  /// the user has granted SCHEDULE_EXACT_ALARM (Android 14+ denies it by
  /// default); otherwise an inexact repeating alarm, which still wakes the app
  /// but may be batched by the OS.
  static Future<void> schedule() async {
    final exact = await Permission.scheduleExactAlarm.isGranted;
    await AndroidAlarmManager.periodic(
      _interval,
      _alarmId,
      alarmSweepCallback,
      exact: exact,
      wakeup: true,
      allowWhileIdle: exact,
      rescheduleOnReboot: true,
    );
  }

  /// Ask for the exact-alarm permission (no-op below Android 12, where it is
  /// granted implicitly), then reschedule so the alarm upgrades to exact.
  static Future<void> requestExactAndReschedule() async {
    if (!await Permission.scheduleExactAlarm.isGranted) {
      await Permission.scheduleExactAlarm.request();
    }
    await schedule();
  }
}

/// Runs in a fresh background isolate started by an AlarmManager broadcast,
/// possibly after the app process was killed. Must be top-level + entry-point,
/// and must register plugins before touching prefs/DB/SMS.
@pragma('vm:entry-point')
Future<void> alarmSweepCallback() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await runReminderSweep();
}
