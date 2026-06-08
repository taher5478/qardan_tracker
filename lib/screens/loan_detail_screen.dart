import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../constants.dart';
import '../db/database_helper.dart';
import '../models/loan.dart';
import '../models/payment.dart';
import '../models/reminder_log.dart';
import '../services/sms_service.dart';
import '../theme/app_theme.dart';
import '../ui/common.dart';
import 'edit_loan_screen.dart';

/// A single credit account: locked principal, an append-only payments ledger,
/// and the actions to record a payment, send a reminder, edit terms or delete.
class LoanDetailScreen extends StatefulWidget {
  const LoanDetailScreen({super.key, required this.loanId});
  final int loanId;

  @override
  State<LoanDetailScreen> createState() => _LoanDetailScreenState();
}

class _LoanDetailScreenState extends State<LoanDetailScreen> {
  final _db = DatabaseHelper.instance;
  final _sms = SmsService();
  final _df = DateFormat.yMMMd();
  final _dfTime = DateFormat('d MMM yyyy · h:mm a');

  Loan? _loan;
  List<Payment> _payments = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final loan = await _db.getLoan(widget.loanId);
    final payments = await _db.getPaymentsForLoan(widget.loanId);
    if (!mounted) return;
    setState(() {
      _loan = loan;
      _payments = payments;
    });
  }

  Future<void> _recordPayment() async {
    final loan = _loan!;
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Amount received', prefixText: '$kCurrencySymbol  '),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              decoration:
                  const InputDecoration(labelText: 'Note (e.g. cash, bank)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add')),
        ],
      ),
    );
    if (result != true) return;

    final amount = double.tryParse(amountCtrl.text.trim());
    if (amount == null || amount <= 0) return;

    // Append-only: a new ledger row, never overwriting prior balance.
    await _db.insertPayment(Payment(
      loanId: loan.id!,
      amount: amount,
      paidAt: DateTime.now(),
      note: noteCtrl.text.trim(),
    ));
    await _load();
  }

  Future<void> _deletePayment(Payment p) async {
    final confirm = await _confirm(
        'Delete this payment?', 'It will be removed from the ledger.');
    if (!confirm) return;
    await _db.deletePayment(p.id!);
    await _load();
  }

  Future<void> _sendNow() async {
    final loan = _loan!;

    // Recover gracefully if the OS revoked SMS access.
    if (!await _sms.hasPermission()) {
      final granted = await _sms.requestPermission();
      if (!granted) {
        if (mounted) await _showPermissionHelp();
        return;
      }
    }

    final now = DateTime.now();
    final ok = await _sms.sendReminder(loan);

    await _db.insertReminderLog(ReminderLog(
      loanId: loan.id!,
      debtorName: loan.debtorName,
      phoneNumber: loan.phoneNumber,
      amount: loan.outstanding,
      sentAt: now,
      success: ok,
    ));

    if (!mounted) return;
    if (ok) {
      await _db.markReminderSent(loan.id!, now.millisecondsSinceEpoch);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        duration: Duration(seconds: 4),
        content: Text(
            'Sent from your SIM — open your Messages app to see it in the chat.'),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Couldn’t send. Please try again.')));
    }
  }

  Future<void> _showPermissionHelp() async {
    final goSettings = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('SMS permission needed'),
        content: const Text(
            'Qarzan sends reminders straight from your SIM, so it needs SMS '
            'permission. Enable it in app settings to continue.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not now')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Open settings')),
        ],
      ),
    );
    if (goSettings == true) await openAppSettings();
  }

  Future<void> _editTerms() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditLoanScreen(loan: _loan)),
    );
    if (changed == true) _load();
  }

  Future<void> _toggleActive() async {
    final loan = _loan!;
    await _db.updateLoanTerms(loan.copyWith(isActive: !loan.isActive));
    await _load();
  }

  Future<void> _delete() async {
    final confirm = await _confirm('Delete this account?',
        'This permanently removes the credit and its payment history.');
    if (!confirm) return;
    await _db.deleteLoan(widget.loanId);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<bool> _confirm(String title, String body) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    return result ?? false;
  }

  void _onMenu(String value) {
    switch (value) {
      case 'edit':
        _editTerms();
      case 'archive':
        _toggleActive();
      case 'delete':
        _delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final loan = _loan;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Credit account'),
        actions: [
          if (loan != null)
            PopupMenuButton<String>(
              onSelected: _onMenu,
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit terms')),
                PopupMenuItem(
                    value: 'archive',
                    child: Text(loan.isActive
                        ? 'Archive (stop reminders)'
                        : 'Reactivate')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
      ),
      body: loan == null
          ? const Center(child: CircularProgressIndicator())
          : _body(loan),
    );
  }

  Widget _body(Loan loan) {
    final progress = loan.principal <= 0
        ? 0.0
        : (loan.amountPaid / loan.principal).clamp(0.0, 1.0);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Column(
          children: [
            Text(loan.customerName,
                style: Theme.of(context).textTheme.titleLarge),
            if (loan.reference.trim().isNotEmpty)
              Text('Ref: ${loan.reference.trim()}',
                  style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 16),
            Text('Outstanding',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: AppColors.muted)),
            Text(money.format(loan.outstanding),
                style: AppTheme.money(
                    size: 40,
                    color: loan.isSettled
                        ? AppColors.success
                        : AppColors.brass)),
          ],
        ),
        const SizedBox(height: 20),

        _card(Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _miniStat('Given (locked)', money.format(loan.principal)),
                _miniStat('Repaid', money.format(loan.amountPaid)),
                _miniStat('Complete', '${(progress * 100).round()}%'),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: AppColors.sage,
                valueColor: const AlwaysStoppedAnimation(AppColors.pine),
              ),
            ),
          ],
        )),
        const SizedBox(height: 16),

        _card(Column(
          children: [
            _infoRow('Date given', _df.format(loan.dateGiven)),
            _infoRow('Due date',
                loan.dueDate == null ? '—' : _df.format(loan.dueDate!)),
            _infoRow(
                'Reminder',
                loan.reminderIntervalDays == 0
                    ? 'Off'
                    : 'Every ${loan.reminderIntervalDays} day'
                        '${loan.reminderIntervalDays == 1 ? '' : 's'}'),
            _infoRow(
                'Last reminder',
                loan.lastReminderAt == null
                    ? 'Never'
                    : _df.format(DateTime.fromMillisecondsSinceEpoch(
                        loan.lastReminderAt!)),
                last: loan.note.trim().isEmpty),
            if (loan.note.trim().isNotEmpty)
              _infoRow('Note', loan.note.trim(), last: true),
          ],
        )),
        const SizedBox(height: 24),

        FilledButton.icon(
          onPressed: loan.isSettled ? null : _recordPayment,
          icon: const Icon(Icons.payments_outlined),
          label: const Text('Record payment'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: loan.isSettled ? null : _sendNow,
          icon: const Icon(Icons.sms_outlined),
          label: const Text('Send reminder now'),
        ),
        const SizedBox(height: 24),

        // Payments ledger / audit trail.
        Row(
          children: [
            Text('Payment history',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Text('${_payments.length}',
                style: const TextStyle(
                    color: AppColors.muted, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 8),
        if (_payments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('No payments recorded yet.',
                style: TextStyle(color: AppColors.muted)),
          )
        else
          _card(Column(
            children: [
              for (var i = 0; i < _payments.length; i++)
                _paymentRow(_payments[i], last: i == _payments.length - 1),
            ],
          )),
      ],
    );
  }

  Widget _paymentRow(Payment p, {required bool last}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.sage,
            child: Icon(Icons.south_west, size: 18, color: AppColors.pine),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_dfTime.format(p.paidAt),
                    style: const TextStyle(fontSize: 13)),
                if (p.note.trim().isNotEmpty)
                  Text(p.note.trim(),
                      style: const TextStyle(
                          color: AppColors.muted, fontSize: 12)),
              ],
            ),
          ),
          Text('+ ${money.format(p.amount)}',
              style: AppTheme.money(size: 16, color: AppColors.success)),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline,
                size: 18, color: AppColors.muted),
            onPressed: () => _deletePayment(p),
          ),
        ],
      ),
    );
  }

  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.hairline),
        ),
        child: child,
      );

  Widget _miniStat(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 2),
          Text(value, style: AppTheme.money(size: 16, weight: FontWeight.w600)),
        ],
      );

  Widget _infoRow(String label, String value, {bool last = false}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(bottom: BorderSide(color: AppColors.hairline)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 120,
                child: Text(label,
                    style: const TextStyle(color: AppColors.muted))),
            Expanded(
                child: Text(value,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );
}
