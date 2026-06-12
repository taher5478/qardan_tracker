import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/drive_backup_service.dart';
import '../services/foreground_service.dart';
import '../services/oem_battery_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import 'activation_screen.dart';

/// First-launch setup that drives the user through the permissions and options
/// the reminder system depends on — and pushes Google Drive backup.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver {
  bool _sms = false;
  bool _notif = false;
  bool _battery = false;
  bool _oemHandled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final sms = await Permission.sms.isGranted;
    final notif = await Permission.notification.isGranted;
    final battery = await Permission.ignoreBatteryOptimizations.isGranted;
    final oemHandled = await OemBatteryService.isHandled();
    if (!mounted) return;
    setState(() {
      _sms = sms;
      _notif = notif;
      _battery = battery;
      _oemHandled = oemHandled;
    });
  }

  Future<void> _request(Permission p) async {
    final status = await p.request();
    if (status.isPermanentlyDenied) await openAppSettings();
    await _refresh();
  }

  Future<void> _enableBackground() async {
    await ForegroundReminderService.start();
    await AppSettings.instance.setForegroundEnabled(true);
    if (mounted) setState(() {});
  }

  Future<void> _setupDrive() async {
    // Backup is premium — guide to activation first if needed.
    if (!await requireLicensed(context)) return;
    final email = await DriveBackupService().connect();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(email != null
            ? 'Google Drive backup connected'
            : 'Drive connection cancelled')));
    setState(() {});
  }

  void _finish() {
    AppSettings.instance.setOnboardingComplete();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final driveOn = AppSettings.instance.driveBackupEnabled;
    final bgOn = AppSettings.instance.foregroundEnabled;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                children: [
                  Text('Welcome to OweMe',
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 6),
                  const Text(
                    'A quick setup so your reminders actually reach customers, '
                    'and your ledger is never lost.',
                    style: TextStyle(color: AppColors.muted, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  _step(
                    icon: Icons.sms_outlined,
                    title: 'Send reminders (SMS)',
                    body: 'Required — reminders are sent as SMS from your SIM.',
                    done: _sms,
                    action: 'Allow',
                    onAction: () => _request(Permission.sms),
                  ),
                  _step(
                    icon: Icons.notifications_outlined,
                    title: 'Notifications',
                    body: 'So you’re told when reminders are sent or need you.',
                    done: _notif,
                    action: 'Allow',
                    onAction: () => _request(Permission.notification),
                  ),
                  _step(
                    icon: Icons.battery_charging_full_outlined,
                    title: 'Ignore battery optimization',
                    body: 'Critical on Xiaomi, Oppo, Vivo, Samsung — lets the '
                        'app run reminders in the background.',
                    done: _battery,
                    action: 'Allow',
                    onAction: () =>
                        _request(Permission.ignoreBatteryOptimizations),
                  ),
                  if (!_oemHandled)
                    _step(
                      icon: Icons.settings_suggest_outlined,
                      title: 'Allow auto-start',
                      body: 'Your phone has extra settings that kill apps. '
                          'Follow the steps so reminders are never stopped.',
                      done: _oemHandled,
                      action: 'Open',
                      onAction: () async {
                        await OemBatteryService.openSettings();
                        await _refresh();
                      },
                    ),
                  _step(
                    icon: Icons.shield_outlined,
                    title: 'Keep running in background',
                    body: 'Most reliable on aggressive phones (adds a permanent '
                        'notification).',
                    done: bgOn,
                    action: 'Enable',
                    onAction: _enableBackground,
                  ),
                  _step(
                    icon: Icons.cloud_outlined,
                    title: 'Back up to Google Drive',
                    body: 'Never lose your ledger if your phone is lost or '
                        'damaged. (Premium)',
                    done: driveOn,
                    action: 'Set up',
                    onAction: _setupDrive,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _finish,
                  child: Text(_sms ? 'Get started' : 'Skip for now'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _step({
    required IconData icon,
    required String title,
    required String body,
    required bool done,
    required String action,
    required VoidCallback onAction,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
            color: done ? AppColors.success.withValues(alpha: 0.5) : AppColors.hairline),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.sage,
            child: Icon(icon, color: AppColors.pine),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(body,
                    style: const TextStyle(
                        color: AppColors.muted, fontSize: 12.5, height: 1.3)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          done
              ? const Icon(Icons.check_circle, color: AppColors.success)
              : OutlinedButton(onPressed: onAction, child: Text(action)),
        ],
      ),
    );
  }
}
