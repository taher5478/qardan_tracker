import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../constants.dart';
import 'reminder_service.dart';

/// Optional persistent foreground service for maximum background reliability.
///
/// When enabled it shows a permanent notification and runs the reminder sweep
/// on a fixed interval — far less likely to be killed by the OS than
/// WorkManager. WorkManager stays registered as a fallback; the per-loan
/// atomic claim guarantees no message is ever sent twice.

// Fresh channel id: the old 'qarzan_foreground' channel was created with LOW
// importance, which some OEMs hide from the status bar. Android can't change
// a channel's importance after creation, so we use a new id.
const _channelId = 'oweme_service_v2';
const int _serviceId = 333;

const _notifTitle = '$kAppName is active';
const _notifText = 'Monitoring your accounts for reminders';

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
    // Android 14 lets users swipe away FGS notifications; re-post ours so the
    // service stays visible (and the user keeps an off switch in Settings).
    FlutterForegroundTask.updateService(
      notificationTitle: _notifTitle,
      notificationText: _notifText,
    );
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
        channelImportance: NotificationChannelImportance.DEFAULT,
        priority: NotificationPriority.DEFAULT,
        onlyAlertOnce: true, // visible but never beeps on re-posts
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        // 15-min cycle: re-posts the notification if dismissed; the sweep
        // itself is idempotent (atomic per-loan claims), so the extra runs
        // are harmless.
        eventAction: ForegroundTaskEventAction.repeat(15 * 60 * 1000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  static Future<bool> isRunning() => FlutterForegroundTask.isRunningService;

  static Future<bool> start() async {
    // Without notification permission (Android 13+) the FGS notification is
    // invisible even though the service runs — request it first.
    final perm = await FlutterForegroundTask.checkNotificationPermission();
    if (perm != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    if (await FlutterForegroundTask.isRunningService) {
      // Already running: re-post the notification in case it was dismissed.
      await FlutterForegroundTask.updateService(
        notificationTitle: _notifTitle,
        notificationText: _notifText,
      );
      return true;
    }
    final result = await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      notificationTitle: _notifTitle,
      notificationText: _notifText,
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
