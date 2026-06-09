import 'package:workmanager/workmanager.dart';

import '../constants.dart';
import '../db/database_helper.dart';
import '../models/reminder_log.dart';
import 'drive_backup_service.dart';
import 'entitlement.dart';
import 'notification_service.dart';
import 'settings_service.dart';
import 'sms_service.dart';

const kReminderTaskName = 'qardan_reminder_check';
const kReminderTaskUniqueName = 'qardan_reminder_periodic';

/// Background isolate entry point. Top-level + @pragma so release tree-shaking
/// keeps it.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != kReminderTaskName) return true;
    await runReminderSweep();
    return true;
  });
}

/// Send an SMS to every account whose reminder is actually due now.
Future<void> runReminderSweep() async {
  // The background isolate has its own memory — load settings/notifications
  // before composing any message.
  await AppSettings.instance.ensureLoaded();
  await NotificationService.init();

  // Best-effort daily Drive backup (may be a no-op in a headless isolate; the
  // on-open path is the dependable one).
  await DriveBackupService().maybeDailyBackup();

  // Paid feature: stop sending once the trial ends without a subscription.
  if (Entitlement.isLocked) {
    await NotificationService.show(
      'Reminders paused',
      'Your $kAppName free trial has ended. Subscribe to keep sending '
          'automatic reminders.',
    );
    return;
  }

  final db = DatabaseHelper.instance;
  final sms = SmsService();
  final now = DateTime.now();
  final nowMs = now.millisecondsSinceEpoch;

  final due = (await db.getLoansNeedingReminders())
      .where((l) => l.isReminderDue(now) && l.id != null)
      .toList();
  if (due.isEmpty) return;

  // If the OS has revoked SMS access, the whole collection system is broken —
  // tell the owner loudly instead of failing silently.
  if (!await sms.hasPermission()) {
    await NotificationService.show(
      'Reminders paused',
      '${due.length} reminder(s) could not be sent because SMS permission is '
          'turned off. Open $kAppName to re-enable it.',
    );
    return;
  }

  var sent = 0;
  var failed = 0;
  for (final loan in due) {
    final ok = await sms.sendReminder(loan);
    await db.insertReminderLog(ReminderLog(
      loanId: loan.id!,
      debtorName: loan.debtorName,
      phoneNumber: loan.phoneNumber,
      amount: loan.outstanding,
      sentAt: now,
      success: ok,
    ));
    if (ok) {
      sent++;
      await db.markReminderSent(loan.id!, nowMs);
    } else {
      failed++;
    }
  }

  if (sent > 0 || failed > 0) {
    final body = failed == 0
        ? '$sent reminder${sent == 1 ? '' : 's'} sent from your SIM.'
        : '$sent sent, $failed failed. Tap to review in reminder history.';
    await NotificationService.show('Reminder update', body);
  }
}

/// How many credit accounts are due for a reminder right now (for the UI badge).
Future<int> countDueReminders() async {
  final db = DatabaseHelper.instance;
  final now = DateTime.now();
  final loans = await db.getLoansNeedingReminders();
  return loans.where((l) => l.isReminderDue(now)).length;
}

/// Hourly background check; per-loan gating decides whether an SMS goes out.
Future<void> scheduleReminders() async {
  await Workmanager().registerPeriodicTask(
    kReminderTaskUniqueName,
    kReminderTaskName,
    frequency: const Duration(hours: 1),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    constraints: Constraints(networkType: NetworkType.notRequired),
  );
}
