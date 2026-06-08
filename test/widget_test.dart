import 'package:flutter_test/flutter_test.dart';

import 'package:qardan_tracker/models/loan.dart';

Loan _loan({
  double principal = 1000,
  double amountPaid = 0,
  DateTime? dateGiven,
  DateTime? dueDate,
  int reminderIntervalDays = 7,
  int? lastReminderAt,
  bool isActive = true,
}) {
  return Loan(
    customerId: 1,
    customerName: 'Test',
    customerPhone: '+10000000000',
    principal: principal,
    amountPaid: amountPaid,
    dateGiven: dateGiven ?? DateTime(2026, 1, 1),
    dueDate: dueDate,
    reminderIntervalDays: reminderIntervalDays,
    lastReminderAt: lastReminderAt,
    isActive: isActive,
  );
}

void main() {
  test('outstanding is principal minus paid, clamped at zero', () {
    final loan = _loan(principal: 1000, amountPaid: 400);
    expect(loan.outstanding, 600);
    expect(loan.isSettled, false);

    expect(_loan(principal: 1000, amountPaid: 1200).isSettled, true);
  });

  group('isReminderDue — no harassment, respects schedule', () {
    test('does NOT fire the same day a loan is created (no epoch-0 bug)', () {
      final given = DateTime(2026, 1, 1);
      final loan = _loan(dateGiven: given, reminderIntervalDays: 7);
      // One hour later (like the first background sweep).
      final now = given.add(const Duration(hours: 1));
      expect(loan.isReminderDue(now), false);
    });

    test('fires one interval after dateGiven when no due date', () {
      final given = DateTime(2026, 1, 1);
      final loan = _loan(dateGiven: given, reminderIntervalDays: 7);
      expect(loan.isReminderDue(given.add(const Duration(days: 6))), false);
      expect(loan.isReminderDue(given.add(const Duration(days: 7))), true);
    });

    test('does NOT fire before the due date', () {
      final given = DateTime(2026, 1, 1);
      final due = DateTime(2026, 1, 31); // net-30
      final loan = _loan(
          dateGiven: given, dueDate: due, reminderIntervalDays: 7);
      expect(loan.isReminderDue(due.subtract(const Duration(days: 1))), false);
      expect(loan.isReminderDue(due), true); // fires on the due date
    });

    test('never fires for settled or inactive accounts', () {
      final given = DateTime(2026, 1, 1);
      final later = given.add(const Duration(days: 30));
      expect(_loan(amountPaid: 1000, dateGiven: given).isReminderDue(later),
          false);
      expect(_loan(isActive: false, dateGiven: given).isReminderDue(later),
          false);
    });
  });
}
