import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_repository.dart';

// ── Supabase ────────────────────────────────────────────────

/// Provides the global [SupabaseClient] instance.
/// Supabase.initialize() must be called before this is read.
final supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

// ── PowerSync ───────────────────────────────────────────────

/// Provides the [PowerSyncDatabase] instance.
/// Must be overridden in the root ProviderContainer after initialization.
final powerSyncProvider = Provider<PowerSyncDatabase>((ref) {
  throw UnimplementedError(
    'powerSyncProvider must be overridden with an initialized PowerSyncDatabase',
  );
});

// ── Sync Repository ─────────────────────────────────────────

/// Provides the [SyncRepository] for sections and pages CRUD.
/// Injects both the PowerSync database and the Drift database (for FTS).
final syncRepositoryProvider = Provider<SyncRepository>((ref) {
  // We can't import SheepDatabase directly here without circular deps,
  // so this provider is set up in core/providers.dart which has access to both.
  throw UnimplementedError(
    'syncRepositoryProvider must be overridden. Use syncRepoProvider from core/providers.dart.',
  );
});

// ── Sync Status ─────────────────────────────────────────────

/// The possible sync states the UI cares about.
enum SyncStatus {
  /// Connected and fully synced.
  synced,

  /// Actively syncing data.
  syncing,

  /// No network connection — operating offline.
  offline,

  /// Sync encountered an error.
  error,
}

class ImageUploadCountNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state++;
  void decrement() => state--;
}

/// Tracks the number of active background image uploads.
final imageUploadCountProvider = NotifierProvider<ImageUploadCountNotifier, int>(ImageUploadCountNotifier.new);

/// Watches the PowerSync status stream.
final _powerSyncStatusProvider = StreamProvider((ref) {
  return ref.watch(powerSyncProvider).statusStream;
});

/// Computes the overall [SyncStatus] based on PowerSync and image uploads.
final syncStatusProvider = Provider<SyncStatus>((ref) {
  final dbStatus = ref.watch(_powerSyncStatusProvider).value;
  final imageUploadCount = ref.watch(imageUploadCountProvider);

  if (dbStatus == null) return SyncStatus.offline;
  if (dbStatus.anyError != null) return SyncStatus.error;
  if (!dbStatus.connected) return SyncStatus.offline;
  
  if (dbStatus.downloading || dbStatus.uploading || imageUploadCount > 0) {
    return SyncStatus.syncing;
  }
  return SyncStatus.synced;
});

// ── Auth State ──────────────────────────────────────────────

/// Watches the Supabase auth state change stream.
final authStateProvider =
    StreamProvider<AuthState>((ref) {
  final supabase = ref.watch(supabaseProvider);
  return supabase.auth.onAuthStateChange;
});

/// Convenience provider for the current user (null if not signed in).
final currentUserProvider = Provider<User?>((ref) {
  final supabase = ref.watch(supabaseProvider);
  return supabase.auth.currentUser;
});
