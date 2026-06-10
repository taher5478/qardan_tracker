import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants.dart';

import '../services/account_service.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../services/drive_backup_service.dart';
import '../services/entitlement.dart';
import '../services/foreground_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import 'activation_screen.dart';
import 'templates_screen.dart';

/// Business configuration, security, and data portability in one place.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = AppSettings.instance;
  final _backup = BackupService();
  final _auth = AuthService();
  final _drive = DriveBackupService();

  late final TextEditingController _business =
      TextEditingController(text: _settings.businessName);
  late final TextEditingController _currency =
      TextEditingController(text: _settings.currencySymbol);

  bool _busy = false;

  @override
  void dispose() {
    _business.dispose();
    _currency.dispose();
    super.dispose();
  }

  Future<void> _saveBusiness() async {
    await _settings.setBusinessName(_business.text);
    await _settings.setCurrencySymbol(_currency.text);
    _currency.text = _settings.currencySymbol;
    _snack('Saved');
    setState(() {});
  }

  Future<void> _runBackup(Future<void> Function() action, String done,
      {bool premium = true}) async {
    if (premium && !await requireLicensed(context)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await action();
      _snack(done);
    } catch (e) {
      _snack('Something went wrong');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connectDrive() async {
    if (!await requireLicensed(context)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    final email = await _drive.connect();
    if (!mounted) return;
    if (email != null) {
      _snack('Connected as $email');
      // Take an immediate first backup so there's something in Drive.
      await _drive.maybeDailyBackup();
    } else {
      _snack('Google sign-in cancelled');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _disconnectDrive() async {
    await _drive.disconnect();
    _snack('Google Drive disconnected');
    setState(() {});
  }

  Future<void> _driveBackupNow() async {
    if (!await requireLicensed(context)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    final ok = await _drive.backupNow();
    if (!mounted) return;
    _snack(ok ? 'Backed up to Google Drive' : 'Drive backup failed — reconnect?');
    setState(() => _busy = false);
  }

  Future<void> _toggleLock(bool enable) async {
    if (enable) {
      final ok = await _setOrChangePin();
      if (!ok) return;
      await _settings.setLockEnabled(true);
    } else {
      await _settings.clearPin();
    }
    setState(() {});
  }

  Future<bool> _setOrChangePin() async {
    final pin = await _promptPin('Set a 4-6 digit PIN');
    if (pin == null) return false;
    final confirm = await _promptPin('Re-enter PIN');
    if (confirm == null) return false;
    if (pin != confirm) {
      _snack('PINs did not match');
      return false;
    }
    await _settings.setPin(pin);
    await _showRecoveryCode();
    return true;
  }

  /// Generate a one-time recovery code, store its hash, and show it so the user
  /// can reset the PIN later without losing data.
  Future<void> _showRecoveryCode() async {
    final rng = Random.secure();
    String block() => List.generate(
        4, (_) => '23456789ABCDEFGHJKLMNPQRSTUVWXYZ'[rng.nextInt(32)]).join();
    final code = '${block()}-${block()}';
    await _settings.setRecoveryCode(code);
    await AccountService.instance.pushProfile(); // mirror to server if signed in
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Save your recovery code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'If you forget your PIN, this code unlocks the app and resets '
                'it — without losing your data. Write it down now; it won’t be '
                'shown again.'),
            const SizedBox(height: 16),
            SelectableText(code,
                style: AppTheme.money(size: 26, color: AppColors.pine)),
          ],
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('I’ve saved it')),
        ],
      ),
    );
  }

  Future<String?> _promptPin(String title) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(counterText: ''),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.length < 4) return;
              Navigator.pop(ctx, v);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _signIn() async {
    setState(() => _busy = true);
    final ok = await AccountService.instance.signInWithGoogle();
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(ok
        ? 'Signed in as ${AccountService.instance.email}'
        : 'Sign-in unavailable or cancelled');
  }

  Future<void> _signOut() async {
    await AccountService.instance.signOut();
    _snack('Signed out');
    setState(() {});
  }

  Future<void> _toggleForeground(bool enable) async {
    if (enable) {
      final ok = await ForegroundReminderService.start();
      if (!ok) {
        _snack('Could not start background service');
        return;
      }
      await _settings.setForegroundEnabled(true);
    } else {
      await ForegroundReminderService.stop();
      await _settings.setForegroundEnabled(false);
    }
    setState(() {});
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            _section('Account'),
            if (AccountService.instance.isSignedIn)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                    backgroundColor: AppColors.sage,
                    child: Icon(Icons.person, color: AppColors.pine)),
                title: Text(AccountService.instance.email ?? 'Signed in',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Synced for backup, subscription & PIN recovery'),
                trailing: TextButton(
                    onPressed: _signOut, child: const Text('Sign out')),
              )
            else
              _actionTile(
                Icons.login,
                'Sign in with Google',
                'Records your account, enables subscription & PIN recovery',
                _signIn,
              ),
            const SizedBox(height: 22),

            _section('Activation'),
            _actionTile(
              Icons.workspace_premium_outlined,
              Entitlement.isLicensed
                  ? 'Activated'
                  : Entitlement.inTrial
                      ? 'Free trial — ${Entitlement.trialDaysLeft} days left'
                      : 'Trial ended — activate',
              'Enter an activation key, view status & disclaimers',
              () async {
                await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ActivationScreen()));
                if (mounted) setState(() {});
              },
            ),
            const SizedBox(height: 22),

            _section('Business'),
            _label('Business name'),
            TextField(
              controller: _business,
              decoration: const InputDecoration(hintText: 'Your shop / company'),
            ),
            const SizedBox(height: 14),
            _label('Currency symbol'),
            TextField(
              controller: _currency,
              decoration: const InputDecoration(hintText: kCurrencySymbol),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _saveBusiness,
              icon: const Icon(Icons.check),
              label: const Text('Save settings'),
            ),
            const SizedBox(height: 26),

            _section('Reminder message'),
            _actionTile(
              Icons.sms_outlined,
              'Manage message templates',
              'Create, edit and choose a default reminder template',
              () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const TemplatesScreen())),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Add app link to reminders'),
              subtitle: Text(Entitlement.isLicensed
                  ? 'Appends “Get OweMe: $kAppDownloadLink” to each message'
                  : 'Premium — subscribe to enable'),
              value: _settings.smsFooterUrlEnabled && Entitlement.isLicensed,
              activeThumbColor: AppColors.pine,
              onChanged: Entitlement.isLicensed
                  ? (v) async {
                      await _settings.setSmsFooterUrlEnabled(v);
                      if (mounted) setState(() {});
                    }
                  : null,
            ),
            const SizedBox(height: 16),

            _section('Security'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('App lock'),
              subtitle: Text(_settings.lockEnabled
                  ? 'PIN required on launch'
                  : 'Off — anyone can open the app'),
              value: _settings.lockEnabled && _settings.hasPin,
              activeThumbColor: AppColors.pine,
              onChanged: _toggleLock,
            ),
            if (_settings.lockEnabled && _settings.hasPin) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.password),
                title: const Text('Change PIN'),
                onTap: _setOrChangePin,
              ),
              FutureBuilder<bool>(
                future: _auth.isBiometricAvailable(),
                builder: (context, snap) {
                  if (snap.data != true) return const SizedBox.shrink();
                  return SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Unlock with biometrics'),
                    subtitle: const Text('Fingerprint / face, PIN as fallback'),
                    value: _settings.biometricEnabled,
                    activeThumbColor: AppColors.pine,
                    onChanged: (v) async {
                      await _settings.setBiometricEnabled(v);
                      setState(() {});
                    },
                  );
                },
              ),
            ],
            const SizedBox(height: 20),

            _section('Background reliability'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Keep running in background'),
              subtitle: Text(_settings.foregroundEnabled
                  ? 'On — shows a permanent notification, most reliable'
                  : 'Off — uses the standard hourly check'),
              value: _settings.foregroundEnabled,
              activeThumbColor: AppColors.pine,
              onChanged: _toggleForeground,
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Recommended if your phone (Xiaomi, Oppo, Samsung, etc.) tends to '
                'stop background apps. Android requires a permanent notification '
                'while this is on.',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),

            _section('Backup & export'),
            // CSV export is free for everyone (read-only — can't be re-imported,
            // so it can't be used to game the trial).
            _actionTile(Icons.table_view_outlined, 'Export ledger (CSV)',
                'Free — share a spreadsheet of all accounts',
                () => _runBackup(_backup.exportLedgerCsv, 'Ledger exported',
                    premium: false)),
            // Full JSON backup stays subscriber-only. Restore/import is removed
            // entirely (no in-app way to re-import data).
            _actionTile(Icons.backup_outlined, 'Full backup (JSON)',
                'Save a complete copy of your data',
                () => _runBackup(_backup.backupToJson, 'Backup created'),
                locked: !Entitlement.isLicensed),

            const SizedBox(height: 20),
            _section(Entitlement.isLicensed
                ? 'Google Drive'
                : 'Google Drive · Premium'),
            if (!_settings.driveBackupEnabled)
              _actionTile(
                Icons.cloud_outlined,
                'Daily backup to Google Drive',
                'Connect your account to auto-backup once a day',
                _connectDrive,
                locked: !Entitlement.isLicensed,
              )
            else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                    backgroundColor: AppColors.sage,
                    child: Icon(Icons.cloud_done, color: AppColors.pine)),
                title: Text(_settings.driveAccountEmail ?? 'Connected',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('Last backup: ${_lastDriveLabel()}'),
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _driveBackupNow,
                      icon: const Icon(Icons.backup_outlined),
                      label: const Text('Back up now'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: _disconnectDrive,
                    child: const Text('Disconnect'),
                  ),
                ],
              ),
            ],

            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  String _lastDriveLabel() {
    final last = _settings.lastDriveBackup;
    if (last == null) return 'never';
    return DateFormat('d MMM yyyy · h:mm a').format(last);
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t,
            style: AppTheme.money(size: 18, weight: FontWeight.w600)),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: const TextStyle(
                color: AppColors.muted, fontWeight: FontWeight.w600)),
      );

  Widget _actionTile(
          IconData icon, String title, String subtitle, VoidCallback onTap,
          {bool locked = false}) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
            backgroundColor: AppColors.sage,
            child: Icon(icon, color: AppColors.pine)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: locked ? const _PremiumBadge() : null,
        onTap: onTap,
      );
}

/// Small "Premium" pill with a lock icon, shown on subscriber-only tiles.
class _PremiumBadge extends StatelessWidget {
  const _PremiumBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.brass.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 13, color: AppColors.brass),
          SizedBox(width: 4),
          Text('Premium',
              style: TextStyle(
                  color: AppColors.brass,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
