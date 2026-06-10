import 'package:supabase_flutter/supabase_flutter.dart';

import 'settings_service.dart';

/// Dodo subscription via Supabase Edge Functions (no secret in the app):
///  - create-checkout: returns a per-user payment link.
///  - subscriptions table: the server (webhook) source of truth, read here.
class SubscriptionService {
  SubscriptionService._();
  static final SubscriptionService instance = SubscriptionService._();

  SupabaseClient get _sb => Supabase.instance.client;

  /// Ask the edge function for a Dodo checkout link for the signed-in user.
  /// Returns the payment URL, or null if not signed in / on error.
  Future<String?> createCheckoutLink() async {
    if (_sb.auth.currentUser == null) return null;
    try {
      final res = await _sb.functions.invoke('create-checkout');
      if (res.status != 200) return null;
      final data = res.data;
      if (data is Map && data['payment_link'] is String) {
        return data['payment_link'] as String;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Pull the latest subscription state from the server into the local cache,
  /// which [Entitlement] reads. Safe no-op when signed out / offline.
  Future<void> refresh() async {
    final user = _sb.auth.currentUser;
    if (user == null) return;
    try {
      final row = await _sb
          .from('subscriptions')
          .select('status,current_period_end')
          .eq('user_id', user.id)
          .maybeSingle();

      final settings = AppSettings.instance;
      final status = row?['status'] as String?;
      final endStr = row?['current_period_end'] as String?;
      final end = endStr == null ? null : DateTime.tryParse(endStr);

      if (status == 'active') {
        // Active: cache the period end (or a year out if the server omitted it).
        await settings
            .setServerSub(end ?? DateTime.now().add(const Duration(days: 366)));
      } else {
        await settings.clearServerSub();
      }
    } catch (_) {
      // Keep the last cached state when offline.
    }
  }
}
