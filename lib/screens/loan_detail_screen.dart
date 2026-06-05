import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/loan.dart';
import '../models/reminder_log.dart';
import '../services/sms_service.dart';
import 'edit_loan_screen.dart';

/// View a single qardan: record repayments, send a reminder now, edit/delete.
class LoanDetailScreen extends StatefulWidget {
  const LoanDetailScreen({super.key, required this.loanId});
  final int loanId;

  @override
  State<LoanDetailScreen> createState() => _LoanDetailScreenState();
}

class _LoanDetailScreenState extends State<LoanDetailScreen> {
  final _db = DatabaseHelper.instance;
  final _sms = SmsService();
  final _money = NumberFormat.currency(symbol: 'Rs ', decimalDigits: 0);
  final _df = DateFormat.yMMMd();

  Loan? _loan;
  bool _dirty = false; // whether to tell the list to refresh

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final loan = await _db.getLoan(widget.loanId);
    setState(() => _loan = loan);
  }

  Future<void> _recordPayment() async {
    final controller = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record repayment'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount received'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(controller.text.trim())),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (amount == null || amount <= 0) return;

    final loan = _loan!;
    final updated = loan.copyWith(
      amountPaid: (loan.amountPaid + amount).clamp(0, loan.principal),
    );
    await _db.updateLoan(updated);
    _dirty = true;
    await _load();
  }

  Future<void> _toggleActive() async {
    final loan = _loan!;
    await _db.updateLoan(loan.copyWith(isActive: !loan.isActive));
    _dirty = true;
    await _load();
  }

  Future<void> _sendNow() async {
    final loan = _loan!;
    final now = DateTime.now().millisecondsSinceEpoch;
    final ok = await _sms.sendReminder(loan);

    await _db.insertReminderLog(ReminderLog(
      loanId: loan.id!,
      debtorName: loan.debtorName,
      phoneNumber: loan.phoneNumber,
      amount: loan.outstanding,
      sentAt: DateTime.fromMillisecondsSinceEpoch(now),
      success: ok,
    ));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'Reminder SMS sent' : 'Could not send SMS (check permission)')));
    if (ok) {
      await _db.markReminderSent(loan.id!, now);
      _dirty = true;
      await _load();
    }
  }

  Future<void> _edit() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditLoanScreen(loan: _loan)),
    );
    if (changed == true) {
      _dirty = true;
      await _load();
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete qardan?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    await _db.deleteLoan(widget.loanId);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final loan = _loan;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_dirty);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(loan?.debtorName ?? 'Qardan'),
          actions: [
            IconButton(icon: const Icon(Icons.edit), onPressed: loan == null ? null : _edit),
            IconButton(icon: const Icon(Icons.delete), onPressed: loan == null ? null : _delete),
          ],
        ),
        body: loan == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _AmountRow(label: 'Principal', value: _money.format(loan.principal)),
                  _AmountRow(label: 'Paid', value: _money.format(loan.amountPaid)),
                  const Divider(),
                  _AmountRow(
                    label: 'Outstanding',
                    value: _money.format(loan.outstanding),
                    emphasize: true,
                  ),
                  const SizedBox(height: 16),
                  _InfoRow('Phone', loan.phoneNumber),
                  _InfoRow('Date given', _df.format(loan.dateGiven)),
                  _InfoRow('Due date',
                      loan.dueDate == null ? '—' : _df.format(loan.dueDate!)),
                  _InfoRow(
                      'Reminder',
                      loan.reminderIntervalDays == 0
                          ? 'Off'
                          : 'Every ${loan.reminderIntervalDays} day(s)'),
                  _InfoRow(
                      'Last reminder',
                      loan.lastReminderAt == null
                          ? 'Never'
                          : _df.format(DateTime.fromMillisecondsSinceEpoch(
                              loan.lastReminderAt!))),
                  if (loan.note.isNotEmpty) _InfoRow('Note', loan.note),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: loan.isSettled ? null : _recordPayment,
                    icon: const Icon(Icons.payments),
                    label: const Text('Record repayment'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: loan.isSettled ? null : _sendNow,
                    icon: const Icon(Icons.sms),
                    label: const Text('Send reminder now'),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _toggleActive,
                    icon: Icon(loan.isActive ? Icons.archive : Icons.unarchive),
                    label: Text(loan.isActive
                        ? 'Archive (stop reminders)'
                        : 'Reactivate'),
                  ),
                ],
              ),
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow(
      {required this.label, required this.value, this.emphasize = false});
  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = emphasize
        ? Theme.of(context).textTheme.titleLarge
        : Theme.of(context).textTheme.titleMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 120,
              child: Text(label,
                  style: TextStyle(color: Theme.of(context).hintColor))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
