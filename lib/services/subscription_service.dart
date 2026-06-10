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

      // No row yet (webhook still pending after a fresh payment) — DON'T clear
      // the cached entitlement; just wait for the next refresh/poll.
      if (row == null) return;

      final status = row['status'] as String?;
      final endStr = row['current_period_end'] as String?;
      final end = endStr == null ? null : DateTime.tryParse(endStr);

      if (status == 'active' && end != null) {
        // Active with a real period end — cache it.
        await settings.setServerSub(end);
      } else if (status == 'cancelled' || status == 'expired') {
        // Only revoke on an explicit terminal status — never on a transient
        // gap or a missing period end (avoids locking out a paid customer).
        await settings.clearServerSub();
      }
      // Any other case (active-without-end, unknown/transient): keep last cache.
    } catch (_) {
      // Keep the last cached state when offline.
    }
  }
}
