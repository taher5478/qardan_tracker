import 'package:another_telephony/telephony.dart';

import '../constants.dart';
import '../models/loan.dart';

/// Sends SMS directly (silently) via the device's SMS subsystem.
///
/// Requires the SEND_SMS runtime permission. Works only on Android; on a
/// non-supported platform [sendReminder] returns false.
class SmsService {
  final Telephony _telephony = Telephony.instance;

  /// Builds the reminder message body for a loan. Casual, friendly tone, with
  /// a footer noting it was sent automatically by the app.
  static String buildMessage(Loan loan, {String currency = kCurrencySymbol}) {
    final amount = loan.outstanding.toStringAsFixed(0);
    final firstName = loan.debtorName.trim().split(' ').first;
    return 'Assalamu Alaikum $firstName! 😊\n'
        'Just a little reminder — $currency$amount qardan is still pending. '
        'Whenever it’s easy for you, no rush at all. JazakAllah Khair! 🤝\n\n'
        '— sent automatically by $kAppName';
  }

  /// Returns true if the SMS was handed to the telephony stack.
  Future<bool> sendReminder(Loan loan, {String currency = kCurrencySymbol}) async {
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
