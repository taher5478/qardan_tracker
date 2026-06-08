import 'package:flutter/material.dart';

import '../constants.dart';
import 'package:intl/intl.dart';

import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../services/drive_backup_service.dart';
import '../services/foreground_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
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

  Future<void> _connectDrive() async {
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
    setState(() => _busy = true);
    final ok = await _drive.backupNow();
    if (!mounted) return;
    _snack(ok ? 'Backed up to Google Drive' : 'Drive backup failed — reconnect?');
    setState(() => _busy = false);
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
            _actionTile(Icons.table_view_outlined, 'Export ledger (CSV)',
                'Share a spreadsheet of all accounts',
                () => _runBackup(_backup.exportLedgerCsv, 'Ledger exported')),
            _actionTile(Icons.backup_outlined, 'Full backup (JSON)',
                'Save a complete copy you can restore later',
                () => _runBackup(_backup.backupToJson, 'Backup created')),
            _actionTile(Icons.restore_outlined, 'Restore from backup',
                'Replace all data with a backup file', _restore),

            const SizedBox(height: 20),
            _section('Google Drive'),
            if (!_settings.driveBackupEnabled)
              _actionTile(
                Icons.cloud_outlined,
                'Daily backup to Google Drive',
                'Connect your account to auto-backup once a day',
                _connectDrive,
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
