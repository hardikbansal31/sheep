import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database/database.dart';
import 'database/repository.dart';
import 'sync/sync_providers.dart';
import 'sync/sync_repository.dart';

/// The local Drift database — used ONLY for local-only tables:
/// UserPreferences, CustomDictionary, PagesSearch (FTS5).
final databaseProvider = Provider<SheepDatabase>((ref) {
  final db = SheepDatabase();
  ref.onDispose(db.close);
  return db;
});

/// The local-only repository — preferences, dictionary, search.
/// Sections/Pages CRUD is now on [syncRepoProvider].
final repositoryProvider = Provider<SheepRepository>((ref) {
  return SheepRepository(ref.watch(databaseProvider));
});

/// Provides the [SyncRepository] backed by PowerSync + Drift (for FTS).
/// Use this for all Sections and Pages operations.
final syncRepoProvider = Provider<SyncRepository>((ref) {
  final powerSync = ref.watch(powerSyncProvider);
  final driftDb = ref.watch(databaseProvider);
  return SyncRepository(powerSync, driftDb);
});
