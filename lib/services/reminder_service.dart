import 'dart:math';

import 'package:workmanager/workmanager.dart';

import '../constants.dart';
import '../db/database_helper.dart';
import '../models/loan.dart';
import '../models/reminder_log.dart';
import 'drive_backup_service.dart';
import 'entitlement.dart';
import 'foreground_service.dart';
import 'notification_service.dart';
import 'settings_service.dart';
import 'sms_service.dart';

/// Result of a send pass.
class SweepResult {
  final int sent;
  final int failed;
  const SweepResult(this.sent, this.failed);
  int get total => sent + failed;
}

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

  // Heartbeat: record that background execution is alive (home shows a warning
  // if this goes stale for >24h).
  await AppSettings.instance.markBackgroundSweep();

  // Best-effort daily Drive backup (may be a no-op in a headless isolate; the
  // on-open path is the dependable one).
  await DriveBackupService().maybeDailyBackup();

  // Watchdog: if the persistent service was killed by the OEM, try to revive it
  // (best-effort; Android 12+ may block a background FGS start).
  await _reviveForegroundIfNeeded();

  // Paid feature: stop sending once the trial ends without a subscription.
  if (Entitlement.isLocked) {
    await NotificationService.show(
      'Reminders paused',
      'Your $kAppName free trial has ended. Subscribe to keep sending '
          'automatic reminders.',
    );
    return;
  }

  final result = await sendDueReminders();
  if (result.total > 0) {
    final body = result.failed == 0
        ? '${result.sent} reminder${result.sent == 1 ? '' : 's'} sent from your SIM.'
        : '${result.sent} sent, ${result.failed} failed. Tap to review in history.';
    await NotificationService.show('Reminder update', body);
  }
}

/// Sends an SMS to every account whose reminder is due right now. Shared by the
/// background sweep and the on-launch catch-up. Returns counts; does not show a
/// notification (callers decide how to report).
Future<SweepResult> sendDueReminders() async {
  final db = DatabaseHelper.instance;
  final sms = SmsService();
  final now = DateTime.now();

  if (Entitlement.isLocked) return const SweepResult(0, 0);
  if (!await sms.hasPermission()) return const SweepResult(0, 0);

  final due = (await db.getLoansNeedingReminders())
      .where((l) => l.isReminderDue(now) && l.id != null)
      .toList();

  final rng = Random();
  var sent = 0;
  var failed = 0;
  for (var i = 0; i < due.length; i++) {
    final loan = due[i];
    final ok = await sms.sendReminder(loan);
    await db.insertReminderLog(ReminderLog(
      loanId: loan.id!,
      debtorName: loan.debtorName,
      phoneNumber: loan.phoneNumber,
      amount: loan.outstanding,
      sentAt: DateTime.now(),
      success: ok,
    ));
    if (ok) {
      sent++;
      await db.markReminderSent(loan.id!, DateTime.now().millisecondsSinceEpoch);
    } else {
      failed++;
    }

    // Pace messages so carriers don't flag a spam burst. No delay after the
    // last one. Each message is also marked sent immediately, so if the
    // process is killed mid-batch the rest are simply picked up next sweep.
    if (i < due.length - 1) {
      final gap = kSmsGapBaseSeconds + rng.nextInt(kSmsGapJitterSeconds + 1);
      await Future.delayed(Duration(seconds: gap));
    }
  }
  return SweepResult(sent, failed);
}

/// Loans currently due for a reminder (for the catch-up prompt on the home
/// screen). Distinct from the silent background sweep.
Future<List<Loan>> dueReminders() async {
  final db = DatabaseHelper.instance;
  final now = DateTime.now();
  return (await db.getLoansNeedingReminders())
      .where((l) => l.isReminderDue(now))
      .toList();
}

Future<void> _reviveForegroundIfNeeded() async {
  try {
    if (AppSettings.instance.foregroundEnabled &&
        !await ForegroundReminderService.isRunning()) {
      await ForegroundReminderService.start();
    }
  } catch (_) {
    // Background FGS launch can be blocked on Android 12+; on-launch restart
    // (in main.dart) covers that case.
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
