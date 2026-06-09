import '../constants.dart';
import 'settings_service.dart';

/// Pure entitlement logic, derived only from persisted settings (no plugins),
/// so it works identically in the UI and the headless background isolate.
///
/// A user may use paid features if EITHER they are within the app-managed free
/// trial OR they hold an active Play subscription (cached locally).
class Entitlement {
  Entitlement._();

  static DateTime _trialStart() =>
      AppSettings.instance.trialStart ?? DateTime.now();

  static int get trialDaysLeft {
    final elapsed = DateTime.now().difference(_trialStart()).inDays;
    final left = kTrialDays - elapsed;
    return left < 0 ? 0 : left;
  }

  static bool get inTrial => trialDaysLeft > 0;

  /// True when a valid (non-expired) activation key is held on this device.
  static bool get isLicensed {
    final until = AppSettings.instance.licenseValidUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  /// True when the user may use paid features (trial or licensed).
  static bool get isActive => isLicensed || inTrial;

  /// True when paid features must be blocked (trial over, no valid key).
  static bool get isLocked => !isActive;
}
