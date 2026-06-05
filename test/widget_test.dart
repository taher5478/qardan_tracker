import 'package:flutter_test/flutter_test.dart';

import 'package:qardan_tracker/models/loan.dart';

void main() {
  test('outstanding is principal minus paid, clamped at zero', () {
    final loan = Loan(
      debtorName: 'Test',
      phoneNumber: '+10000000000',
      principal: 1000,
      amountPaid: 400,
      dateGiven: DateTime(2026, 1, 1),
    );
    expect(loan.outstanding, 600);
    expect(loan.isSettled, false);

    final paid = loan.copyWith(amountPaid: 1200);
    expect(paid.outstanding, 0);
    expect(paid.isSettled, true);
  });
}
