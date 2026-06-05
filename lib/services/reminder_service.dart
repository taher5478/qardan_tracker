import 'package:workmanager/workmanager.dart';

import '../db/database_helper.dart';
import '../models/loan.dart';
import '../models/reminder_log.dart';
import 'sms_service.dart';

/// Name of the periodic task registered with WorkManager.
const kReminderTaskName = 'qardan_reminder_check';
const kReminderTaskUniqueName = 'qardan_reminder_periodic';

/// Entry point that runs in a *separate background isolate*.
///
/// Must be a top-level (or static) function annotated with @pragma so it is
/// not tree-shaken away in release builds.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != kReminderTaskName) return true;
    await runReminderSweep();
    return true; // returning true marks the task successful
  });
}

/// Checks every loan and sends an SMS to any debtor whose reminder is due.
///
/// Safe to call both from the background isolate and (for a manual test)
/// from the UI isolate.
Future<void> runReminderSweep() async {
  final db = DatabaseHelper.instance;
  final sms = SmsService();
  final now = DateTime.now().millisecondsSinceEpoch;

  final loans = await db.getLoansNeedingReminders();
  for (final loan in loans) {
    if (!_isReminderDue(loan, now)) continue;

    final sent = await sms.sendReminder(loan);
    if (loan.id != null) {
      await db.insertReminderLog(ReminderLog(
        loanId: loan.id!,
        debtorName: loan.debtorName,
        phoneNumber: loan.phoneNumber,
        amount: loan.outstanding,
        sentAt: DateTime.fromMillisecondsSinceEpoch(now),
        success: sent,
      ));
      if (sent) await db.markReminderSent(loan.id!, now);
    }
  }
}

/// True when [loan]'s reminder interval has elapsed since the last one.
bool _isReminderDue(Loan loan, int nowMillis) {
  if (loan.reminderIntervalDays <= 0) return false;
  final intervalMillis = loan.reminderIntervalDays * 24 * 60 * 60 * 1000;
  final last = loan.lastReminderAt ?? 0;
  return nowMillis - last >= intervalMillis;
}

/// How many active qardans are due for a reminder SMS right now.
Future<int> countDueReminders() async {
  final db = DatabaseHelper.instance;
  final now = DateTime.now().millisecondsSinceEpoch;
  final loans = await db.getLoansNeedingReminders();
  return loans.where((l) => _isReminderDue(l, now)).length;
}

/// Registers the recurring background check. Android enforces a 15-minute
/// minimum period; we poll hourly and the per-loan interval gating above
/// decides whether an SMS actually goes out.
Future<void> scheduleReminders() async {
  await Workmanager().registerPeriodicTask(
    kReminderTaskUniqueName,
    kReminderTaskName,
    frequency: const Duration(hours: 1),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    constraints: Constraints(networkType: NetworkType.notRequired),
  );
}
