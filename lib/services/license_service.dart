import 'package:android_id/android_id.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'settings_service.dart';

enum ActivationOutcome {
  activated, // key claimed for this device
  alreadyActive, // same device re-validated
  usedElsewhere, // key already bound to another device
  invalid, // key not found
  offline, // couldn't reach Supabase
}

class ActivationResult {
  final ActivationOutcome outcome;
  final DateTime? validUntil;
  const ActivationResult(this.outcome, [this.validUntil]);
}

/// Validates manual activation keys against Supabase. One key binds to one
/// device (stable Android ID); re-activation on the same device is allowed.
class LicenseService {
  LicenseService._();
  static final LicenseService instance = LicenseService._();

  static const _androidId = AndroidId();

  Future<String> _deviceId() async {
    // Settings.Secure.ANDROID_ID — stable per device + signing key, survives
    // reinstalls. Falls back to a stored id if unavailable.
    final id = await _androidId.getId();
    if (id != null && id.isNotEmpty) return id;
    final s = AppSettings.instance;
    final existing = s.activationKey; // reuse any prior marker if present
    return existing ?? 'unknown-device';
  }

  /// Activate (or re-validate) a key. Persists the expiry locally on success.
  Future<ActivationResult> activate(String key) async {
    final device = await _deviceId();
    try {
      final res = await Supabase.instance.client.rpc(
        'activate_key',
        params: {'p_key': key.trim(), 'p_device': device},
      );
      final map = res as Map<String, dynamic>;
      switch (map['status']) {
        case 'activated':
        case 'active':
          final until = DateTime.parse(map['valid_until'] as String);
          await AppSettings.instance.setLicense(until, key.trim());
          return ActivationResult(
            map['status'] == 'activated'
                ? ActivationOutcome.activated
                : ActivationOutcome.alreadyActive,
            until,
          );
        case 'used':
          return const ActivationResult(ActivationOutcome.usedElsewhere);
        default:
          return const ActivationResult(ActivationOutcome.invalid);
      }
    } catch (_) {
      return const ActivationResult(ActivationOutcome.offline);
    }
  }

  /// Re-check the stored key online (refreshes expiry / catches revocation).
  /// Best-effort: silent on failure so offline use still works.
  Future<void> revalidate() async {
    final key = AppSettings.instance.activationKey;
    if (key == null) return;
    await activate(key);
  }
}
