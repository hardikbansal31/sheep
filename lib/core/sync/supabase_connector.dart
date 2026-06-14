import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_config.dart';

/// Connects PowerSync to Supabase for authentication and data upload.
///
/// - [fetchCredentials] returns a JWT from the current Supabase session.
/// - [uploadData] translates PowerSync CRUD operations into Supabase
///   REST calls, including injecting the current user's `user_id`.
class SupabaseConnector extends PowerSyncBackendConnector {
  SupabaseConnector(this._supabase);

  final SupabaseClient _supabase;

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    // Refresh the session if needed — returns null if no session exists.
    final session = _supabase.auth.currentSession;
    if (session == null) return null;

    // If the token is about to expire (< 30s), refresh it.
    final expiresAt = session.expiresAt;
    if (expiresAt != null &&
        DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000)
            .difference(DateTime.now())
            .inSeconds <
            30) {
      try {
        await _supabase.auth.refreshSession();
      } catch (_) {
        // If refresh fails, return the existing token — PowerSync will
        // retry later.
      }
    }

    final refreshedSession = _supabase.auth.currentSession;
    if (refreshedSession == null) return null;

    return PowerSyncCredentials(
      endpoint: SyncConfig.powerSyncUrl,
      token: refreshedSession.accessToken,
      expiresAt: refreshedSession.expiresAt != null
          ? DateTime.fromMillisecondsSinceEpoch(
              refreshedSession.expiresAt! * 1000)
          : null,
    );
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final transaction = await database.getNextCrudTransaction();
    if (transaction == null) return;

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      // Not authenticated — cannot upload. PowerSync will retry.
      throw Exception('Not authenticated — cannot upload sync data.');
    }

    try {
      for (final op in transaction.crud) {
        final table = op.table;
        final data = Map<String, dynamic>.from(op.opData ?? {});

        switch (op.op) {
          case UpdateType.put:
            // INSERT — include id and user_id.
            data['id'] = op.id;
            data['user_id'] = userId;
            await _supabase.from(table).upsert(data);
            break;

          case UpdateType.patch:
            // UPDATE — include user_id for RLS.
            data['user_id'] = userId;
            await _supabase.from(table).update(data).eq('id', op.id);
            break;

          case UpdateType.delete:
            await _supabase.from(table).delete().eq('id', op.id);
            break;
        }
      }
      await transaction.complete();
    } catch (e) {
      // If any op fails, the entire transaction is retried later.
      rethrow;
    }
  }
}
