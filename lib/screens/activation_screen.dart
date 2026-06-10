import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher.dart';

import '../constants.dart';
import '../services/account_service.dart';
import '../services/entitlement.dart';
import '../services/license_service.dart';
import '../services/settings_service.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';

/// Ensures the user can use a paid feature (trial OR licensed). Otherwise opens
/// the activation screen and returns the state afterwards.
Future<bool> requireActive(BuildContext context) async {
  if (Entitlement.isActive) return true;
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const ActivationScreen()),
  );
  return Entitlement.isActive;
}

/// Ensures a paid activation key (NOT just the trial) — used for backup/restore
/// so trial users can't export, reinstall to reset the trial, and restore.
Future<bool> requireLicensed(BuildContext context) async {
  if (Entitlement.isLicensed) return true;
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const ActivationScreen()),
  );
  return Entitlement.isLicensed;
}

/// Enter an activation key (provided manually after registration).
class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen>
    with WidgetsBindingObserver {
  final _keyCtrl = TextEditingController();
  bool _busy = false;
  bool _checking = false;
  bool _awaitingPayment = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keyCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // User returned from the payment browser — confirm the subscription.
    if (state == AppLifecycleState.resumed && _awaitingPayment) {
      _awaitingPayment = false;
      _pollStatus();
    }
  }

  /// Poll the server a few times (the webhook lands a few seconds after
  /// payment), updating the UI as soon as the subscription is active.
  Future<void> _pollStatus() async {
    if (_checking) return;
    setState(() => _checking = true);
    for (var i = 0; i < 6 && mounted; i++) {
      await SubscriptionService.instance.refresh();
      if (Entitlement.isLicensed) break;
      await Future.delayed(const Duration(seconds: 2));
    }
    if (!mounted) return;
    setState(() => _checking = false);
    if (Entitlement.isLicensed) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Subscription active — thank you!')));
    }
  }

  Future<void> _activate() async {
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) return;
    setState(() => _busy = true);
    final result = await LicenseService.instance.activate(key);
    if (!mounted) return;
    setState(() => _busy = false);

    final msg = switch (result.outcome) {
      ActivationOutcome.activated ||
      ActivationOutcome.alreadyActive =>
        'Activated — valid until ${_fmt(result.validUntil!)}',
      ActivationOutcome.usedElsewhere =>
        'This key is already activated on another device.',
      ActivationOutcome.invalid => 'Invalid key. Please check and try again.',
      ActivationOutcome.offline =>
        'Couldn’t reach the server. Check your internet and try again.',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

    final ok = result.outcome == ActivationOutcome.activated ||
        result.outcome == ActivationOutcome.alreadyActive;
    if (ok) Navigator.of(context).maybePop();
  }

  String _fmt(DateTime d) =>
      '${d.day}/${d.month}/${d.year}';

  Future<void> _subscribe() async {
    final messenger = ScaffoldMessenger.of(context);
    // Subscriptions attach to an account, so sign in first.
    if (!AccountService.instance.isSignedIn) {
      final ok = await AccountService.instance.signInWithGoogle();
      if (!ok) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Please sign in with Google to subscribe')));
        return;
      }
    }
    setState(() => _busy = true);
    final link = await SubscriptionService.instance.createCheckoutLink();
    if (!mounted) return;
    setState(() => _busy = false);
    if (link == null) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Couldn’t start checkout. Try again.')));
      return;
    }
    // Mark that we're awaiting payment; the lifecycle resume handler will poll
    // the status when the user returns from the browser.
    _awaitingPayment = true;
    await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final licensed = Entitlement.isLicensed;
    final inTrial = Entitlement.inTrial;
    final daysLeft = Entitlement.trialDaysLeft;

    return Scaffold(
      appBar: AppBar(title: const Text('Activate OweMe')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _statusCard(licensed, inTrial, daysLeft),
          const SizedBox(height: 24),

          if (_checking)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.sage.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: const Row(children: [
                SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.pine)),
                SizedBox(width: 12),
                Expanded(
                    child: Text('Confirming your payment…',
                        style: TextStyle(
                            color: AppColors.pineDark,
                            fontWeight: FontWeight.w600))),
              ]),
            ),

          if (!licensed) ...[
            // Primary path: self-serve subscription via Dodo.
            FilledButton.icon(
              onPressed: (_busy || _checking) ? null : _subscribe,
              icon: const Icon(Icons.workspace_premium_outlined),
              label: Text(_busy ? 'Please wait…' : 'Subscribe · $kPriceLabel'),
            ),
            const SizedBox(height: 6),
            const Text(
              'Secure payment via Dodo Payments. Cancel anytime.',
              style: TextStyle(color: AppColors.muted, fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            Center(
              child: TextButton(
                onPressed: _checking ? null : _pollStatus,
                child: const Text('Already paid? Check status'),
              ),
            ),
            const SizedBox(height: 14),
            Row(children: const [
              Expanded(child: Divider(color: AppColors.hairline)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('or', style: TextStyle(color: AppColors.muted)),
              ),
              Expanded(child: Divider(color: AppColors.hairline)),
            ]),
            const SizedBox(height: 16),
            const Text('Have an activation key?',
                style: TextStyle(
                    color: AppColors.muted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _keyCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: 'XXXX-XXXX-XXXX'),
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: _busy ? null : _activate,
              child: Text(_busy ? 'Activating…' : 'Activate key'),
            ),
            const SizedBox(height: 12),
            Text(kActivationContact,
                style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          ] else
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.check),
              label: const Text('Your key is active'),
            ),

          const SizedBox(height: 24),
          _disclaimers(),
        ],
      ),
    );
  }

  Widget _statusCard(bool licensed, bool inTrial, int daysLeft) {
    final String title;
    final String subtitle;
    final Color color;
    if (licensed) {
      title = 'Active';
      final until = AppSettings.instance.licenseValidUntil ??
          AppSettings.instance.serverSubUntil;
      subtitle = until == null
          ? 'Your subscription is active. Thank you!'
          : 'Active until ${_fmt(until)}. Thank you!';
      color = AppColors.success;
    } else if (inTrial) {
      title = 'Free trial';
      subtitle = '$daysLeft day${daysLeft == 1 ? '' : 's'} left. '
          'Enter an activation key any time to keep using OweMe.';
      color = AppColors.brass;
    } else {
      title = 'Trial ended';
      subtitle = 'Enter an activation key to add credit, record payments and '
          'send reminders again. Your data is safe and viewable.';
      color = AppColors.danger;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.money(size: 22, color: color)),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(height: 1.4)),
        ],
      ),
    );
  }

  Widget _disclaimers() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: AppColors.hairline),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DisclaimerLine(
            'One activation key works on a single device only. Once used it '
            'cannot be activated on another phone.',
          ),
          _DisclaimerLine(
            'Reminders are sent as SMS from your phone’s own SIM. Standard '
            'carrier SMS charges apply.',
          ),
          _DisclaimerLine(
            'Delivery is not guaranteed: Android may close the app in the '
            'background to save battery, so some reminders can be delayed or '
            'not sent. Enable “Keep running in background” and allow battery '
            'exemption to improve reliability.',
          ),
        ],
      ),
    );
  }
}

class _DisclaimerLine extends StatelessWidget {
  const _DisclaimerLine(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6, right: 8),
            child: Icon(Icons.circle, size: 5, color: AppColors.muted),
          ),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: AppColors.muted, fontSize: 12.5, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
