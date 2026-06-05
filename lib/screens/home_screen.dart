import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../db/database_helper.dart';
import '../models/loan.dart';
import '../services/reminder_service.dart';
import '../theme/app_theme.dart';
import '../ui/common.dart';
import 'contact_picker_screen.dart';
import 'edit_loan_screen.dart';
import 'loan_detail_screen.dart';
import 'reminder_log_screen.dart';

/// Everything the home screen needs, loaded in one pass.
class _HomeData {
  final List<Loan> loans;
  final int remindersSent;
  final int dueNow;
  const _HomeData(this.loans, this.remindersSent, this.dueNow);

  double get totalOutstanding => loans
      .where((l) => l.isActive)
      .fold<double>(0, (sum, l) => sum + l.outstanding);

  int get pendingPeople =>
      loans.where((l) => l.isActive && !l.isSettled).length;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _db = DatabaseHelper.instance;
  late Future<_HomeData> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<_HomeData> _load() async {
    final loans = await _db.getAllLoans();
    final sent = await _db.countSentReminders();
    final due = await countDueReminders();
    return _HomeData(loans, sent, due);
  }

  /// GPay-style add flow: pick/type a contact first, then enter the amount.
  Future<void> _addQardan() async {
    final picked = await Navigator.of(context).push<PickedContact>(
      MaterialPageRoute(builder: (_) => const ContactPickerScreen()),
    );
    if (picked == null || !mounted) return;

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditLoanScreen(
          initialName: picked.name,
          initialPhone: picked.phone,
        ),
      ),
    );
    if (saved == true) _reload();
  }

  Future<void> _openDetail(Loan loan) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => LoanDetailScreen(loanId: loan.id!)),
    );
    if (changed == true) _reload();
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ReminderLogScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addQardan,
        backgroundColor: AppColors.pine,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add qardan',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: FutureBuilder<_HomeData>(
          future: _future,
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return RefreshIndicator(
              color: AppColors.pine,
              onRefresh: () async {
                _reload();
                await _future;
              },
              child: _content(snap.data!),
            );
          },
        ),
      ),
    );
  }

  Widget _content(_HomeData data) {
    final active = data.loans.where((l) => l.isActive && !l.isSettled).toList();
    final settled =
        data.loans.where((l) => !l.isActive || l.isSettled).toList();

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _Header(onHistory: _openHistory)),
        SliverToBoxAdapter(
          child: _BalanceCard(
            amount: data.totalOutstanding,
            peopleCount: data.pendingPeople,
          ).animate().fadeIn(duration: 450.ms).slideY(begin: 0.08, end: 0),
        ),
        SliverToBoxAdapter(
          child: _StatsRow(
            sent: data.remindersSent,
            dueNow: data.dueNow,
            onTap: _openHistory,
          ).animate(delay: 120.ms).fadeIn(duration: 400.ms),
        ),
        if (data.loans.isEmpty)
          const SliverFillRemaining(hasScrollBody: false, child: _EmptyState())
        else ...[
          _sectionHeader('Outstanding', active.length),
          _loanSliver(active, muted: false),
          if (settled.isNotEmpty) _sectionHeader('Settled', settled.length),
          _loanSliver(settled, muted: true),
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ],
    );
  }

  Widget _sectionHeader(String title, int count) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
        child: Row(
          children: [
            Text(title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(width: 8),
            Text('$count',
                style: const TextStyle(
                    color: AppColors.muted, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _loanSliver(List<Loan> loans, {required bool muted}) {
    return SliverList.builder(
      itemCount: loans.length,
      itemBuilder: (context, i) {
        final tile = _LoanTile(
          loan: loans[i],
          muted: muted,
          onTap: () => _openDetail(loans[i]),
        );
        return tile
            .animate(delay: (40 * i).ms)
            .fadeIn(duration: 300.ms)
            .slideX(begin: 0.04, end: 0);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.onHistory});
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Assalamu Alaikum',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppColors.muted)),
                Text('Your Qardan',
                    style: Theme.of(context).textTheme.headlineSmall),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Reminder history',
            onPressed: onHistory,
            style: IconButton.styleFrom(
                backgroundColor: AppColors.sage,
                foregroundColor: AppColors.pineDark),
            icon: const Icon(Icons.history),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero balance card (with subtle geometric motif + count-up)
// ---------------------------------------------------------------------------

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.amount, required this.peopleCount});
  final double amount;
  final int peopleCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.pine, AppColors.pineDark],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.pineDark.withValues(alpha: 0.30),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: CustomPaint(
          painter: _MotifPainter(),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.volunteer_activism,
                        color: Colors.white70, size: 18),
                    const SizedBox(width: 8),
                    Text('Total outstanding',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: Colors.white70,
                            letterSpacing: 0.4)),
                  ],
                ),
                const SizedBox(height: 12),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: amount),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => Text(
                    money.format(value),
                    style: AppTheme.money(
                        size: 40, color: Colors.white, weight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  peopleCount == 0
                      ? 'Everyone has repaid — masha’Allah'
                      : 'Pending with $peopleCount '
                          '${peopleCount == 1 ? 'person' : 'people'}',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Faint concentric arcs in the corner — a quiet geometric nod, not noise.
class _MotifPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.06);
    final center = Offset(size.width - 8, 8);
    for (var r = 28.0; r < 200; r += 22) {
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Sent / pending stat chips
// ---------------------------------------------------------------------------

class _StatsRow extends StatelessWidget {
  const _StatsRow(
      {required this.sent, required this.dueNow, required this.onTap});
  final int sent;
  final int dueNow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: _StatChip(
              icon: Icons.mark_chat_read_outlined,
              value: '$sent',
              label: 'Reminders sent',
              tint: AppColors.pine,
              onTap: onTap,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatChip(
              icon: Icons.schedule_send_outlined,
              value: '$dueNow',
              label: 'Due to send now',
              tint: AppColors.brass,
              onTap: onTap,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.value,
    required this.label,
    required this.tint,
    required this.onTap,
  });
  final IconData icon;
  final String value;
  final String label;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: tint, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value,
                        style: AppTheme.money(size: 22, weight: FontWeight.w600)),
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.muted, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loan list tile (with repayment progress)
// ---------------------------------------------------------------------------

class _LoanTile extends StatelessWidget {
  const _LoanTile(
      {required this.loan, required this.muted, required this.onTap});
  final Loan loan;
  final bool muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = loan.principal <= 0
        ? 0.0
        : (loan.amountPaid / loan.principal).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Opacity(
            opacity: muted ? 0.6 : 1,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      InitialAvatar(name: loan.debtorName),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(loan.debtorName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(
                              muted
                                  ? 'Settled'
                                  : (loan.reminderIntervalDays > 0
                                      ? 'Reminder every ${loan.reminderIntervalDays} day'
                                          '${loan.reminderIntervalDays == 1 ? '' : 's'}'
                                      : 'No reminders'),
                              style: const TextStyle(
                                  color: AppColors.muted, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(money.format(loan.outstanding),
                              style: AppTheme.money(
                                  size: 19,
                                  color: muted
                                      ? AppColors.muted
                                      : AppColors.brass,
                                  weight: FontWeight.w600)),
                          if (!muted && loan.amountPaid > 0)
                            Text('of ${money.format(loan.principal)}',
                                style: const TextStyle(
                                    color: AppColors.muted, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                  if (!muted && loan.amountPaid > 0) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: AppColors.sage,
                        valueColor: const AlwaysStoppedAnimation(AppColors.pine),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
                color: AppColors.sage, shape: BoxShape.circle),
            child: const Icon(Icons.volunteer_activism,
                size: 48, color: AppColors.pine),
          ),
          const SizedBox(height: 24),
          Text('No qardan yet',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text(
            'Record a loan you’ve given and the app will\nremind the person for you, automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, height: 1.5),
          ),
        ],
      ),
    );
  }
}
