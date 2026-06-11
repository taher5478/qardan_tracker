import 'package:supabase_flutter/supabase_flutter.dart';

/// Remote config pulled from Supabase `app_config` on app open: the latest
/// released version (to nudge updates) and an optional broadcast message.
class RemoteConfig {
  final int latestVersionCode;
  final String latestVersionName;
  final String apkUrl;
  final String updateMessage;
  final bool forceUpdate;
  final int alertId;
  final String alertTitle;
  final String alertMessage;

  const RemoteConfig({
    required this.latestVersionCode,
    required this.latestVersionName,
    required this.apkUrl,
    required this.updateMessage,
    required this.forceUpdate,
    required this.alertId,
    required this.alertTitle,
    required this.alertMessage,
  });

  factory RemoteConfig.fromMap(Map<String, dynamic> m) => RemoteConfig(
        latestVersionCode: (m['latest_version_code'] as num?)?.toInt() ?? 0,
        latestVersionName: (m['latest_version_name'] as String?) ?? '',
        apkUrl: (m['apk_url'] as String?) ?? '',
        updateMessage: (m['update_message'] as String?) ?? '',
        forceUpdate: (m['force_update'] as bool?) ?? false,
        alertId: (m['alert_id'] as num?)?.toInt() ?? 0,
        alertTitle: (m['alert_title'] as String?) ?? '',
        alertMessage: (m['alert_message'] as String?) ?? '',
      );
}

class RemoteConfigService {
  RemoteConfigService._();

  /// Fetch the config row, or null if unavailable/offline.
  static Future<RemoteConfig?> fetch() async {
    try {
      final row = await Supabase.instance.client
          .from('app_config')
          .select()
          .eq('id', 1)
          .maybeSingle();
      return row == null ? null : RemoteConfig.fromMap(row);
    } catch (_) {
      return null;
    }
  }
}
