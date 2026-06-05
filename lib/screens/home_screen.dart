import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/loan.dart';
import '../services/reminder_service.dart';
import 'contact_picker_screen.dart';
import 'edit_loan_screen.dart';
import 'loan_detail_screen.dart';
import 'reminder_log_screen.dart';

/// Lightweight bundle of the two reminder counts shown on the home screen.
class _ReminderStats {
  final int sent;
  final int dueNow;
  const _ReminderStats(this.sent, this.dueNow);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _db = DatabaseHelper.instance;
  late Future<List<Loan>> _loansFuture;
  late Future<_ReminderStats> _statsFuture;

  final _money = NumberFormat.currency(symbol: 'Rs ', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _loansFuture = _db.getAllLoans();
      _statsFuture = _loadStats();
    });
  }

  Future<_ReminderStats> _loadStats() async {
    final sent = await _db.countSentReminders();
    final due = await countDueReminders();
    return _ReminderStats(sent, due);
  }

  Future<void> _openHistory() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ReminderLogScreen()),
    );
  }

  /// GPay-style add flow: pick/type a contact first, then enter the amount.
  Future<void> _addQardan() async {
    final picked = await Navigator.of(context).push<PickedContact>(
      MaterialPageRoute(builder: (_) => const ContactPickerScreen()),
    );
    if (picked == null || !mounted) return;

    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditLoanScreen(
          initialName: picked.name,
          initialPhone: picked.phone,
        ),
      ),
    );
    if (changed == true) _reload();
  }

  Future<void> _openDetail(Loan loan) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => LoanDetailScreen(loanId: loan.id!)),
    );
    if (changed == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Qardan Tracker'),
        actions: [
          IconButton(
            tooltip: 'Run reminder check now',
            icon: const Icon(Icons.send_to_mobile),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await runReminderSweep();
              if (!mounted) return;
              messenger.showSnackBar(
                const SnackBar(content: Text('Reminder check finished')),
              );
              _reload();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addQardan,
        icon: const Icon(Icons.add),
        label: const Text('Add Qardan'),
      ),
      body: FutureBuilder<List<Loan>>(
        future: _loansFuture,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final loans = snap.data!;
          if (loans.isEmpty) {
            return const _EmptyState();
          }
          final outstanding = loans
              .where((l) => l.isActive)
              .fold<double>(0, (s, l) => s + l.outstanding);
          return Column(
            children: [
              _SummaryCard(total: _money.format(outstanding), count: loans.where((l) => l.isActive && !l.isSettled).length),
              _ReminderStatsRow(future: _statsFuture, onTap: _openHistory),
              Expanded(
                child: ListView.separated(
                  itemCount: loans.length,
                  separatorBuilder: (_, index) => const Divider(height: 1),
                  itemBuilder: (_, i) => _LoanTile(
                    loan: loans[i],
                    money: _money,
                    onTap: () => _openDetail(loans[i]),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.total, required this.count});
  final String total;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Total Outstanding',
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
          const SizedBox(height: 6),
          Text(total,
              style: theme.textTheme.headlineMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('$count pending qardan',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
        ],
      ),
    );
  }
}

class _ReminderStatsRow extends StatelessWidget {
  const _ReminderStatsRow({required this.future, required this.onTap});
  final Future<_ReminderStats> future;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ReminderStats>(
      future: future,
      builder: (context, snap) {
        final stats = snap.data ?? const _ReminderStats(0, 0);
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: _StatChip(
                  icon: Icons.mark_chat_read,
                  label: 'Reminders sent',
                  value: '${stats.sent}',
                  color: Colors.teal,
                  onTap: onTap,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatChip(
                  icon: Icons.schedule_send,
                  label: 'Pending now',
                  value: '${stats.dueNow}',
                  color: Colors.orange,
                  onTap: onTap,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoanTile extends StatelessWidget {
  const _LoanTile(
      {required this.loan, required this.money, required this.onTap});
  final Loan loan;
  final NumberFormat money;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final settled = loan.isSettled || !loan.isActive;
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: settled ? Colors.green.shade100 : null,
        child: Icon(settled ? Icons.check : Icons.person),
      ),
      title: Text(loan.debtorName,
          style: TextStyle(
              decoration: settled ? TextDecoration.lineThrough : null)),
      subtitle: Text(loan.phoneNumber),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(money.format(loan.outstanding),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          if (!settled && loan.reminderIntervalDays > 0)
            Text('every ${loan.reminderIntervalDays}d',
                style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.account_balance_wallet_outlined,
              size: 72, color: Theme.of(context).disabledColor),
          const SizedBox(height: 16),
          const Text('No qardan recorded yet.'),
          const Text('Tap “Add Qardan” to start.'),
        ],
      ),
    );
  }
}
