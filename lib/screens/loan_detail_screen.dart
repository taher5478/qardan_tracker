import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/loan.dart';
import '../models/reminder_log.dart';
import '../services/sms_service.dart';
import '../theme/app_theme.dart';
import '../ui/common.dart';
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
          decoration:
              const InputDecoration(labelText: 'Amount received', prefixText: 'Rs  '),
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
    if (mounted && updated.isSettled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Qardan fully repaid — masha’Allah')),
      );
    }
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
        content: Text(ok
            ? 'Reminder SMS sent'
            : 'Could not send SMS (check permission)')));
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
        content: const Text('This permanently removes the record.'),
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
    if (confirm != true) return;
    await _db.deleteLoan(widget.loanId);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  void _onMenu(String value) {
    switch (value) {
      case 'edit':
        _edit();
      case 'archive':
        _toggleActive();
      case 'delete':
        _delete();
    }
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
          title: const Text('Qardan'),
          actions: [
            if (loan != null)
              PopupMenuButton<String>(
                onSelected: _onMenu,
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
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
      ),
    );
  }

  Widget _body(Loan loan) {
    final progress = loan.principal <= 0
        ? 0.0
        : (loan.amountPaid / loan.principal).clamp(0.0, 1.0);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        // Hero: who + how much is outstanding.
        Column(
          children: [
            InitialAvatar(name: loan.debtorName, radius: 36),
            const SizedBox(height: 12),
            Text(loan.debtorName,
                style: Theme.of(context).textTheme.headlineSmall),
            Text(loan.phoneNumber,
                style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 18),
            Text('Outstanding',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: AppColors.muted)),
            Text(money.format(loan.outstanding),
                style: AppTheme.money(
                    size: 40,
                    color: loan.isSettled ? AppColors.success : AppColors.brass)),
          ],
        ),
        const SizedBox(height: 20),

        // Repayment progress card.
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _miniStat('Given', money.format(loan.principal)),
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
          ),
        ),
        const SizedBox(height: 16),

        // Details card.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Column(
            children: [
              _InfoRow('Date given', _df.format(loan.dateGiven)),
              _InfoRow('Due date',
                  loan.dueDate == null ? '—' : _df.format(loan.dueDate!)),
              _InfoRow(
                  'Reminder',
                  loan.reminderIntervalDays == 0
                      ? 'Off'
                      : 'Every ${loan.reminderIntervalDays} day'
                          '${loan.reminderIntervalDays == 1 ? '' : 's'}'),
              _InfoRow(
                  'Last reminder',
                  loan.lastReminderAt == null
                      ? 'Never'
                      : _df.format(DateTime.fromMillisecondsSinceEpoch(
                          loan.lastReminderAt!))),
              if (loan.note.isNotEmpty) _InfoRow('Note', loan.note, last: true),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Primary action.
        FilledButton.icon(
          onPressed: loan.isSettled ? null : _recordPayment,
          icon: const Icon(Icons.payments_outlined),
          label: const Text('Record repayment'),
        ),
        const SizedBox(height: 10),
        // Secondary action.
        OutlinedButton.icon(
          onPressed: loan.isSettled ? null : _sendNow,
          icon: const Icon(Icons.sms_outlined),
          label: const Text('Send reminder now'),
        ),
      ],
    );
  }

  Widget _miniStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        const SizedBox(height: 2),
        Text(value, style: AppTheme.money(size: 16, weight: FontWeight.w600)),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value, {this.last = false});
  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(
                bottom: BorderSide(color: AppColors.hairline)),
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
}
