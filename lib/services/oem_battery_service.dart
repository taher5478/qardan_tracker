import 'package:disable_battery_optimization/disable_battery_optimization.dart';

/// Vendor "app killer" settings — Xiaomi/Oppo/Vivo/Huawei auto-start toggles
/// and manufacturer battery managers (see dontkillmyapp.com).
///
/// These are separate from (and not covered by) the standard Android
/// battery-optimization exemption the app already requests, and they are the
/// usual reason background reminders silently die on those phones. The plugin
/// walks the user to the right vendor screen with step-by-step dialogs, and
/// no-ops on stock Android.
class OemBatteryService {
  /// Whether the vendor settings have been handled (or don't exist on this
  /// device). Android has no API to read the real toggle state — the plugin
  /// records that the user completed the guided steps, so treat this as a
  /// best-effort hint, not a guarantee.
  static Future<bool> isHandled() async {
    final autoStart = await DisableBatteryOptimization.isAutoStartEnabled;
    final manufacturer = await DisableBatteryOptimization
        .isManufacturerBatteryOptimizationDisabled;
    return (autoStart ?? true) && (manufacturer ?? true);
  }

  /// Guide the user through enabling auto-start and whitelisting the app in
  /// the manufacturer battery manager. Shows nothing on phones without them.
  static Future<void> openSettings() async {
    await DisableBatteryOptimization.showEnableAutoStartSettings(
      'Allow auto-start',
      'This phone blocks apps from waking in the background. Enable '
          'auto-start for OweMe so reminders keep working after a restart '
          'or when the app is closed.',
    );
    await DisableBatteryOptimization
        .showDisableManufacturerBatteryOptimizationSettings(
      'Protect OweMe from the battery manager',
      'This phone has extra battery settings that silently stop apps. '
          'Set OweMe to "No restrictions" (or mark it protected) so '
          'reminders are never killed.',
    );
  }
}
