import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../constants.dart';
import 'reminder_service.dart';

/// Optional persistent foreground service for maximum background reliability.
///
/// When enabled it shows a permanent (low-priority) notification and runs the
/// reminder sweep on a fixed interval — far less likely to be killed by the OS
/// than WorkManager. WorkManager stays registered as a fallback; the per-loan
/// [Loan.isReminderDue] gating guarantees no message is ever sent twice.

const _channelId = 'qarzan_foreground';
const int _serviceId = 333;

/// Background-isolate entry point for the service. Must be top-level + pragma.
@pragma('vm:entry-point')
void startForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(_ReminderTaskHandler());
}

class _ReminderTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await runReminderSweep();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    runReminderSweep();
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}

class ForegroundReminderService {
  /// Configure notification + task options. Call once at startup.
  static void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: '$kAppName background service',
        channelDescription: 'Keeps reminder checks running reliably',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(60 * 60 * 1000), // hourly
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  static Future<bool> isRunning() => FlutterForegroundTask.isRunningService;

  static Future<bool> start() async {
    if (await FlutterForegroundTask.isRunningService) return true;
    final result = await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      notificationTitle: '$kAppName is active',
      notificationText: 'Monitoring your accounts for reminders',
      callback: startForegroundCallback,
    );
    return result is ServiceRequestSuccess;
  }

  static Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}
