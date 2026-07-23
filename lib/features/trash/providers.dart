import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/sync/sync_repository.dart';

/// Provides a stream of sections that are soft-deleted.
final deletedSectionsProvider = StreamProvider<List<SyncSection>>((ref) {
  return ref.watch(syncRepoProvider).watchDeletedSections();
});

/// Provides a stream of pages that are soft-deleted, but whose parent sections are active.
final deletedPagesProvider = StreamProvider<List<SyncPage>>((ref) {
  return ref.watch(syncRepoProvider).watchDeletedPages();
});
