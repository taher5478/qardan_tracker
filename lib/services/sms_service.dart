import 'package:another_telephony/telephony.dart';

import '../models/loan.dart';

/// Sends SMS directly (silently) via the device's SMS subsystem.
///
/// Requires the SEND_SMS runtime permission. Works only on Android; on a
/// non-supported platform [sendReminder] returns false.
class SmsService {
  final Telephony _telephony = Telephony.instance;

  /// Builds the reminder message body for a loan.
  static String buildMessage(Loan loan, {String currency = 'Rs'}) {
    final amount = loan.outstanding.toStringAsFixed(0);
    return 'Assalamu Alaikum ${loan.debtorName}, this is a friendly reminder '
        'that $currency$amount of qardan is still pending. '
        'Please repay when convenient. JazakAllah Khair.';
  }

  /// Returns true if the SMS was handed to the telephony stack.
  Future<bool> sendReminder(Loan loan, {String currency = 'Rs'}) async {
    final granted = await _telephony.requestSmsPermissions ?? false;
    if (!granted) return false;

    try {
      await _telephony.sendSms(
        to: loan.phoneNumber,
        message: buildMessage(loan, currency: currency),
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
