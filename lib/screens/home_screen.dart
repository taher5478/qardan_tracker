import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../db/database_helper.dart';
import '../models/customer.dart';
import '../services/entitlement.dart';
import '../services/reminder_service.dart';
import '../services/remote_config_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../ui/common.dart';
import 'contact_picker_screen.dart';
import 'customer_detail_screen.dart';
import 'edit_loan_screen.dart';
import 'activation_screen.dart';
import 'reminder_log_screen.dart';
import 'settings_screen.dart';

class _HomeData {
  final List<CustomerSummary> customers;
  final int remindersSent;
  final int dueNow;
  final bool smsGranted;
  final bool batteryExempt;
  final bool backgroundStale;
  const _HomeData(this.customers, this.remindersSent, this.dueNow,
      this.smsGranted, this.batteryExempt, this.backgroundStale);

  double get totalOutstanding =>
      customers.fold<double>(0, (s, c) => s + c.totalOutstanding);

  int get openCustomers => customers.where((c) => !c.isSettled).length;

  bool get hasWarnings => !smsGranted || !batteryExempt || backgroundStale;
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkRemoteConfig());
  }

  /// On open: show a one-time broadcast message and/or an update prompt
  /// (download the new APK from the website).
  Future<void> _checkRemoteConfig() async {
    final cfg = await RemoteConfigService.fetch();
    if (cfg == null || !mounted) return;

    // Broadcast message — shown once per alert id.
    if (cfg.alertMessage.trim().isNotEmpty &&
        cfg.alertId != AppSettings.instance.lastSeenAlertId) {
      await AppSettings.instance.setLastSeenAlertId(cfg.alertId);
      if (!mounted) return;
      await _showAlert(cfg.alertTitle, cfg.alertMessage);
    }

    // Update prompt — when the installed build is older than the latest.
    final info = await PackageInfo.fromPlatform();
    final current = int.tryParse(info.buildNumber) ?? 0;
    if (current < cfg.latestVersionCode && mounted) {
      await _showUpdate(cfg);
    }
  }

  Future<void> _showAlert(String title, String message) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title.trim().isEmpty ? 'Message' : title),
        content: Text(message),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _showUpdate(RemoteConfig cfg) {
    return showDialog<void>(
      context: context,
      barrierDismissible: !cfg.forceUpdate,
      builder: (ctx) => PopScope(
        canPop: !cfg.forceUpdate,
        child: AlertDialog(
          title: const Text('Update available'),
          content: Text(cfg.updateMessage),
          actions: [
            if (!cfg.forceUpdate)
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Later')),
            FilledButton.icon(
              onPressed: () => launchUrl(Uri.parse(cfg.apkUrl),
                  mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.download),
              label: const Text('Download'),
            ),
          ],
        ),
      ),
    );
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<_HomeData> _load() async {
    await AppSettings.instance.reload(); // pick up background-isolate writes
    final customers = await _db.getCustomerSummaries();
    final sent = await _db.countSentReminders();
    final due = await countDueReminders();
    final smsGranted = await Permission.sms.isGranted;
    final batteryExempt = await Permission.ignoreBatteryOptimizations.isGranted;

    // "Background dead" = there are active reminders, a sweep has run before,
    // but not in the last 24h. (Null = never run yet -> don't false-alarm.)
    final hasReminderAccounts =
        customers.any((c) => !c.isSettled && c.openAccounts > 0);
    final last = AppSettings.instance.lastBackgroundSweep;
    final stale = hasReminderAccounts &&
        last != null &&
        DateTime.now().difference(last) > const Duration(hours: 24);

    return _HomeData(customers, sent, due, smsGranted, batteryExempt, stale);
  }

  Future<void> _fixSms() async {
    final status = await Permission.sms.request();
    if (status.isPermanentlyDenied) await openAppSettings();
    _reload();
  }

  Future<void> _fixBattery() async {
    final status = await Permission.ignoreBatteryOptimizations.request();
    if (status.isPermanentlyDenied) await openAppSettings();
    _reload();
  }

  Future<void> _addCredit() async {
    if (!await requireActive(context)) return;
    if (!mounted) return;
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

  Future<void> _openCustomer(int customerId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => CustomerDetailScreen(customerId: customerId)),
    );
    _reload(); // refresh balances after any change inside
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ReminderLogScreen()),
    );
  }

  Future<void> _openSubscription() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ActivationScreen()),
    );
    _reload();
  }

  /// Catch-up: send reminders the (possibly killed) background task missed.
  /// Sending paces messages several seconds apart, so this shows live progress
  /// rather than freezing the UI with no feedback.
  Future<void> _sendDueNow() async {
    if (!await requireActive(context)) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final progress = ValueNotifier<String>('Preparing…');

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      // canPop: false also blocks the system back button — if the dialog were
      // dismissed mid-send, the pop below would pop the home screen instead.
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5)),
              const SizedBox(width: 18),
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: progress,
                  builder: (_, text, child) => Text(text),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final res = await sendDueReminders(
      onProgress: (done, total) {
        // `done` counts completed customers; show the one being sent now.
        final current = done < total ? done + 1 : total;
        progress.value =
            total == 0 ? 'No reminders due' : 'Sending $current of $total…';
      },
    );

    if (mounted) Navigator.of(context, rootNavigator: true).pop(); // close dialog
    progress.dispose();
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(res.total == 0
          ? 'Nothing sent — check SMS permission'
          : '${res.sent} sent from your SIM'
              '${res.failed > 0 ? ', ${res.failed} failed' : ''}'),
    ));
    _reload();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    _reload(); // currency / template changes may affect figures
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCredit,
        backgroundColor: AppColors.pine,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add credit',
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
    final open = data.customers.where((c) => !c.isSettled).toList();
    final settled = data.customers.where((c) => c.isSettled).toList();

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
            child: _Header(onHistory: _openHistory, onSettings: _openSettings)),
        if (Entitlement.isLocked || (Entitlement.inTrial && Entitlement.trialDaysLeft <= 7))
          SliverToBoxAdapter(
            child: _SubscriptionBanner(
              locked: Entitlement.isLocked,
              daysLeft: Entitlement.trialDaysLeft,
              onTap: _openSubscription,
            ),
          ),
        if (data.dueNow > 0 && Entitlement.isActive)
          SliverToBoxAdapter(
            child: _CatchUpBanner(count: data.dueNow, onSend: _sendDueNow),
          ),
        if (data.hasWarnings)
          SliverToBoxAdapter(
            child: _HealthBanners(
              smsGranted: data.smsGranted,
              batteryExempt: data.batteryExempt,
              backgroundStale: data.backgroundStale,
              onFixSms: _fixSms,
              onFixBattery: _fixBattery,
              onFixBackground: _openSettings,
            ),
          ),
        SliverToBoxAdapter(
          child: _BalanceCard(
            amount: data.totalOutstanding,
            customerCount: data.openCustomers,
          ).animate().fadeIn(duration: 450.ms).slideY(begin: 0.08, end: 0),
        ),
        SliverToBoxAdapter(
          child: _StatsRow(
            sent: data.remindersSent,
            dueNow: data.dueNow,
            onTap: _openHistory,
          ).animate(delay: 120.ms).fadeIn(duration: 400.ms),
        ),
        if (data.customers.isEmpty)
          const SliverFillRemaining(hasScrollBody: false, child: _EmptyState())
        else ...[
          _sectionHeader('Owing', open.length),
          _customerSliver(open, muted: false),
          if (settled.isNotEmpty) _sectionHeader('Cleared', settled.length),
          _customerSliver(settled, muted: true),
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

  Widget _customerSliver(List<CustomerSummary> list, {required bool muted}) {
    return SliverList.builder(
      itemCount: list.length,
      itemBuilder: (context, i) {
        final tile = _CustomerTile(
          summary: list[i],
          muted: muted,
          onTap: () => _openCustomer(list[i].customer.id!),
        );
        return tile
            .animate(delay: (40 * i).ms)
            .fadeIn(duration: 300.ms)
            .slideX(begin: 0.04, end: 0);
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onHistory, required this.onSettings});
  final VoidCallback onHistory;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Accounts receivable',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppColors.muted)),
                Text('Your Ledger',
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
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Settings',
            onPressed: onSettings,
            style: IconButton.styleFrom(
                backgroundColor: AppColors.sage,
                foregroundColor: AppColors.pineDark),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
    );
  }
}

/// Catch-up banner: due reminders the background task may have missed.
class _CatchUpBanner extends StatelessWidget {
  const _CatchUpBanner({required this.count, required this.onSend});
  final int count;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: AppColors.pine,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: InkWell(
          onTap: onSend,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.schedule_send, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$count reminder${count == 1 ? '' : 's'} due to send',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                      const Text('Tap to send them now from your SIM.',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 12.5)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: onSend,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.pine,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    textStyle: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  child: const Text('Send now'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Trial-countdown / paywall banner.
class _SubscriptionBanner extends StatelessWidget {
  const _SubscriptionBanner(
      {required this.locked, required this.daysLeft, required this.onTap});
  final bool locked;
  final int daysLeft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = locked ? AppColors.danger : AppColors.brass;
    final title = locked
        ? 'Free trial ended'
        : 'Trial ends in $daysLeft day${daysLeft == 1 ? '' : 's'}';
    final body = locked
        ? 'Subscribe to add credit, record payments and send reminders.'
        : 'Subscribe any time to keep OweMe after your trial.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.chip),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(locked ? Icons.lock_outline : Icons.workspace_premium_outlined,
                    color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, color: AppColors.ink)),
                      const SizedBox(height: 2),
                      Text(body,
                          style: const TextStyle(
                              color: AppColors.muted, fontSize: 12.5)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: onTap,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.pine,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    textStyle: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  child: const Text('Subscribe'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Persistent, actionable warnings shown whenever the reminder system is at
/// risk: SMS permission revoked, or the app not exempt from battery killing.
class _HealthBanners extends StatelessWidget {
  const _HealthBanners({
    required this.smsGranted,
    required this.batteryExempt,
    required this.backgroundStale,
    required this.onFixSms,
    required this.onFixBattery,
    required this.onFixBackground,
  });
  final bool smsGranted;
  final bool batteryExempt;
  final bool backgroundStale;
  final VoidCallback onFixSms;
  final VoidCallback onFixBattery;
  final VoidCallback onFixBackground;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          if (!smsGranted)
            _banner(
              icon: Icons.sms_failed_outlined,
              title: 'Reminders can’t be sent',
              body:
                  'SMS permission is off, so automatic reminders won’t go out.',
              action: 'Enable SMS',
              onTap: onFixSms,
            ),
          if (backgroundStale)
            _banner(
              icon: Icons.running_with_errors_outlined,
              title: 'Background reminders stopped',
              body:
                  'No reminders have run in over 24h — your phone likely killed '
                  'the app. Enable background mode & battery exemption.',
              action: 'Fix',
              onTap: onFixBackground,
            ),
          if (!batteryExempt)
            _banner(
              icon: Icons.battery_alert_outlined,
              title: 'Background reminders may stop',
              body:
                  'Allow the app to ignore battery optimization so it can run reliably.',
              action: 'Allow',
              onTap: onFixBattery,
            ),
        ],
      ),
    );
  }

  Widget _banner({
    required IconData icon,
    required String title,
    required String body,
    required String action,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFBE7DC),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: AppColors.brass.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.danger),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: AppColors.ink)),
                const SizedBox(height: 2),
                Text(body,
                    style:
                        const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.pine,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              textStyle:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            child: Text(action),
          ),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.amount, required this.customerCount});
  final double amount;
  final int customerCount;

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
                    const Icon(Icons.account_balance_wallet_outlined,
                        color: Colors.white70, size: 18),
                    const SizedBox(width: 8),
                    Text('Total receivable',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: Colors.white70, letterSpacing: 0.4)),
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
                  customerCount == 0
                      ? 'All accounts cleared'
                      : 'Owed by $customerCount '
                          '${customerCount == 1 ? 'customer' : 'customers'}',
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
                        style:
                            AppTheme.money(size: 22, weight: FontWeight.w600)),
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

class _CustomerTile extends StatelessWidget {
  const _CustomerTile(
      {required this.summary, required this.muted, required this.onTap});
  final CustomerSummary summary;
  final bool muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = summary.customer;
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
              child: Row(
                children: [
                  InitialAvatar(name: c.name),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          muted
                              ? 'Cleared'
                              : '${summary.openAccounts} '
                                  'open account${summary.openAccounts == 1 ? '' : 's'}',
                          style: const TextStyle(
                              color: AppColors.muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(money.format(summary.totalOutstanding),
                          style: AppTheme.money(
                              size: 19,
                              color: muted ? AppColors.muted : AppColors.brass,
                              weight: FontWeight.w600)),
                      if (!muted && summary.dueNow > 0)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.brass.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('${summary.dueNow} due',
                              style: const TextStyle(
                                  color: AppColors.brass,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
            child: const Icon(Icons.receipt_long_outlined,
                size: 48, color: AppColors.pine),
          ),
          const SizedBox(height: 24),
          Text('No credit recorded',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text(
            'Add credit you’ve extended to a customer and\nthe app will remind them automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, height: 1.5),
          ),
        ],
      ),
    );
  }
}
