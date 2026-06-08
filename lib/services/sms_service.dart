import 'package:another_telephony/telephony.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/loan.dart';
import '../ui/common.dart';
import 'settings_service.dart';

/// Sends reminder SMS directly (silently) via the device's SMS subsystem.
///
/// Requires the SEND_SMS runtime permission. Android-only; returns false on
/// unsupported platforms or any send error.
class SmsService {
  final Telephony _telephony = Telephony.instance;

  /// Render a template against a loan, substituting {placeholders}.
  ///
  /// Supported: {name} {fullname} {amount} {business} {reference} {due}
  /// {daysoverdue}. When [template]/[businessName] are omitted, the owner's
  /// saved settings are used.
  static String render(
    Loan loan, {
    String? template,
    String? businessName,
  }) {
    template ??= AppSettings.instance.smsTemplate;
    businessName ??= AppSettings.instance.businessName;
    final now = DateTime.now();
    final overdue = loan.daysOverdue(now);
    final dueStr =
        loan.dueDate == null ? '' : DateFormat.yMMMd().format(loan.dueDate!);
    final referenceStr =
        loan.reference.trim().isEmpty ? '' : ' (Ref: ${loan.reference.trim()})';
    final businessStr =
        businessName.trim().isEmpty ? '' : '\n— ${businessName.trim()}';

    final values = {
      '{name}': loan.customerName.trim().split(' ').first,
      '{fullname}': loan.customerName.trim(),
      '{amount}': money.format(loan.outstanding),
      '{business}': businessStr,
      '{reference}': referenceStr,
      '{due}': dueStr,
      '{daysoverdue}': '$overdue',
    };

    var out = template;
    values.forEach((key, value) => out = out.replaceAll(key, value));
    return out.trim();
  }

  /// Silent check (no prompt) — true if SEND_SMS is currently granted.
  Future<bool> hasPermission() async => Permission.sms.isGranted;

  /// Request the SMS permission, returning the resulting grant state.
  Future<bool> requestPermission() async =>
      (await Permission.sms.request()).isGranted;

  /// Returns true if the SMS was handed to the telephony stack.
  Future<bool> sendReminder(Loan loan) async {
    final granted = await _telephony.requestSmsPermissions ?? false;
    if (!granted) return false;

    try {
      // Multipart handles any length / Unicode without the platform dropping it.
      await _telephony.sendSms(
        to: loan.phoneNumber,
        message: render(loan),
        isMultipart: true,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
