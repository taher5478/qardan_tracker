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
  // Throttle the upsell notification to at most once per day (it used to fire
  // hourly from both the WorkManager and foreground sweeps).
  if (Entitlement.isLocked) {
    if (AppSettings.instance.shouldShowPausedNotice()) {
      await AppSettings.instance.markPausedNotice();
      await NotificationService.show(
        'Reminders paused',
        'Your $kAppName free trial has ended. Subscribe to keep sending '
            'automatic reminders.',
      );
    }
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
Future<SweepResult> sendDueReminders({
  void Function(int done, int total)? onProgress,
}) async {
  final db = DatabaseHelper.instance;
  final sms = SmsService();
  final now = DateTime.now();

  if (Entitlement.isLocked) return const SweepResult(0, 0);
  if (!await sms.hasPermission()) return const SweepResult(0, 0);

  final due = (await db.getLoansNeedingReminders())
      .where((l) => l.isReminderDue(now) && l.id != null)
      .toList();

  // Consolidate per customer: one SMS covering all of that customer's due
  // accounts, instead of a separate message per invoice.
  final byCustomer = <int, List<Loan>>{};
  for (final l in due) {
    byCustomer.putIfAbsent(l.customerId, () => []).add(l);
  }
  final groups = byCustomer.values.toList();
  onProgress?.call(0, groups.length);

  final rng = Random();
  var sent = 0;
  var failed = 0;
  for (var g = 0; g < groups.length; g++) {
    onProgress?.call(g, groups.length);
    final loans = groups[g];
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // Atomically claim each due account for this customer. If another sweep
    // already claimed them all, skip — no double-send.
    final claimed = <Loan>[];
    for (final l in loans) {
      final intervalMs = l.reminderIntervalDays * 24 * 60 * 60 * 1000;
      if (await db.claimReminder(l.id!, nowMs, intervalMs)) claimed.add(l);
    }
    if (claimed.isEmpty) continue;

    final rep = claimed.first;
    final totalDue = claimed.fold<double>(0, (s, l) => s + l.outstanding);
    DateTime? earliestDue;
    for (final l in claimed) {
      final d = l.dueDate;
      if (d != null && (earliestDue == null || d.isBefore(earliestDue))) {
        earliestDue = d;
      }
    }

    // Synthetic loan carrying the combined total for the message template.
    final consolidated = Loan(
      id: rep.id,
      customerId: rep.customerId,
      reference: claimed.length == 1 ? rep.reference : '',
      principal: totalDue,
      dateGiven: rep.dateGiven,
      dueDate: earliestDue,
      reminderIntervalDays: rep.reminderIntervalDays,
      customerName: rep.customerName,
      customerPhone: rep.customerPhone,
      templateId: rep.templateId,
    );

    final ok = await sms.sendReminder(consolidated);
    await db.insertReminderLog(ReminderLog(
      loanId: rep.id!,
      debtorName: rep.customerName,
      phoneNumber: rep.customerPhone,
      amount: totalDue,
      sentAt: DateTime.now(),
      success: ok,
    ));
    if (ok) {
      sent++;
    } else {
      // Release every claim so the customer is retried on the next sweep.
      for (final l in claimed) {
        await db.setLastReminder(l.id!, l.lastReminderAt);
      }
      failed++;
    }

    // Pace messages between customers so carriers don't flag a burst.
    if (g < groups.length - 1) {
      final gap = kSmsGapBaseSeconds + rng.nextInt(kSmsGapJitterSeconds + 1);
      await Future.delayed(Duration(seconds: gap));
    }
  }
  onProgress?.call(groups.length, groups.length);
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

/// How many reminder messages are due right now. With per-customer
/// consolidation this is the number of distinct customers due (= messages),
/// not the number of invoices.
Future<int> countDueReminders() async {
  final db = DatabaseHelper.instance;
  final now = DateTime.now();
  final loans = await db.getLoansNeedingReminders();
  final customers = <int>{};
  for (final l in loans) {
    if (l.isReminderDue(now)) customers.add(l.customerId);
  }
  return customers.length;
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
