import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/loan.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../services/foreground_service.dart';
import '../services/settings_service.dart';
import '../services/sms_service.dart';
import '../theme/app_theme.dart';

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

  late final TextEditingController _business =
      TextEditingController(text: _settings.businessName);
  late final TextEditingController _currency =
      TextEditingController(text: _settings.currencySymbol);
  late final TextEditingController _template =
      TextEditingController(text: _settings.smsTemplate);

  bool _busy = false;

  @override
  void dispose() {
    _business.dispose();
    _currency.dispose();
    _template.dispose();
    super.dispose();
  }

  // Sample used for the live SMS preview.
  Loan get _sampleLoan => Loan(
        customerId: 0,
        customerName: 'Ali Khan',
        customerPhone: '+920000000000',
        reference: 'INV-102',
        principal: 5000,
        amountPaid: 2000,
        dateGiven: DateTime.now().subtract(const Duration(days: 40)),
        dueDate: DateTime.now().subtract(const Duration(days: 5)),
      );

  Future<void> _saveBusiness() async {
    await _settings.setBusinessName(_business.text);
    await _settings.setCurrencySymbol(_currency.text);
    await _settings.setSmsTemplate(_template.text);
    _currency.text = _settings.currencySymbol;
    _snack('Saved');
    setState(() {});
  }

  Future<void> _runBackup(Future<void> Function() action, String done) async {
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

  Future<void> _restore() async {
    final confirmed = await _confirm('Restore backup?',
        'This REPLACES all current data with the contents of the backup file.');
    if (!confirmed) return;
    setState(() => _busy = true);
    final msg = await _backup.restoreFromJson();
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(msg);
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
    _snack('PIN set');
    return true;
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

  Future<bool> _confirm(String title, String body) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continue')),
        ],
      ),
    );
    return r ?? false;
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final preview = SmsService.render(
      _sampleLoan,
      template: _template.text,
      businessName: _business.text,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
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
            const SizedBox(height: 22),

            _section('Reminder message'),
            _label('Template'),
            TextField(
              controller: _template,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  hintText: 'Use placeholders like {amount}, {name}…'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Placeholders: {name} {fullname} {amount} {business} {reference} '
              '{due} {daysoverdue}',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            _previewCard(preview),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _saveBusiness,
              icon: const Icon(Icons.check),
              label: const Text('Save settings'),
            ),
            const SizedBox(height: 26),

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
            _actionTile(Icons.table_view_outlined, 'Export ledger (CSV)',
                'Share a spreadsheet of all accounts',
                () => _runBackup(_backup.exportLedgerCsv, 'Ledger exported')),
            _actionTile(Icons.backup_outlined, 'Full backup (JSON)',
                'Save a complete copy you can restore later',
                () => _runBackup(_backup.backupToJson, 'Backup created')),
            _actionTile(Icons.restore_outlined, 'Restore from backup',
                'Replace all data with a backup file', _restore),
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

  Widget _previewCard(String preview) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.sage.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Preview',
                style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(preview, style: const TextStyle(height: 1.4)),
          ],
        ),
      );

  Widget _actionTile(
          IconData icon, String title, String subtitle, VoidCallback onTap) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
            backgroundColor: AppColors.sage,
            child: Icon(icon, color: AppColors.pine)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        onTap: onTap,
      );
}
