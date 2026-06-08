import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants.dart';
import '../services/auth_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';

/// Full-screen gate shown when the app lock is enabled. Tries biometrics first
/// (if available + enabled), with a PIN pad as the always-available fallback.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.onUnlocked});
  final VoidCallback onUnlocked;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _auth = AuthService();
  final _settings = AppSettings.instance;

  String _entered = '';
  String? _error;
  bool _tryingBiometric = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
  }

  Future<void> _tryBiometric() async {
    if (!_settings.biometricEnabled) return;
    if (!await _auth.isBiometricAvailable()) return;
    setState(() => _tryingBiometric = true);
    final ok = await _auth.authenticate();
    if (!mounted) return;
    setState(() => _tryingBiometric = false);
    if (ok) widget.onUnlocked();
  }

  void _onDigit(String d) {
    if (_entered.length >= 6) return;
    setState(() {
      _entered += d;
      _error = null;
    });
    if (_entered.length >= 4) _maybeSubmit();
  }

  void _onBackspace() {
    if (_entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  void _maybeSubmit() {
    // Allow 4-6 digit PINs: verify on each keypress once at least 4 entered.
    if (_settings.verifyPin(_entered)) {
      HapticFeedback.lightImpact();
      widget.onUnlocked();
    } else if (_entered.length >= 6) {
      HapticFeedback.heavyImpact();
      setState(() {
        _error = 'Incorrect PIN';
        _entered = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.parchment,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            const Icon(Icons.lock_outline, size: 48, color: AppColors.pine),
            const SizedBox(height: 16),
            Text(kAppName, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(_error ?? 'Enter your PIN to continue',
                style: TextStyle(
                    color: _error == null ? AppColors.muted : AppColors.danger)),
            const SizedBox(height: 28),
            _dots(),
            const SizedBox(height: 28),
            if (_settings.biometricEnabled)
              TextButton.icon(
                onPressed: _tryingBiometric ? null : _tryBiometric,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Use biometrics'),
              ),
            const Spacer(),
            _keypad(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _dots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (i) {
        final filled = i < _entered.length;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? AppColors.pine : Colors.transparent,
            border: Border.all(color: AppColors.pine, width: 1.5),
          ),
        );
      }),
    );
  }

  Widget _keypad() {
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '⌫'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.6,
        children: keys.map((k) {
          if (k.isEmpty) return const SizedBox.shrink();
          final isBackspace = k == '⌫';
          return InkResponse(
            onTap: () => isBackspace ? _onBackspace() : _onDigit(k),
            radius: 36,
            child: Center(
              child: isBackspace
                  ? const Icon(Icons.backspace_outlined, color: AppColors.ink)
                  : Text(k, style: AppTheme.money(size: 28, color: AppColors.ink)),
            ),
          );
        }).toList(),
      ),
    );
  }
}
