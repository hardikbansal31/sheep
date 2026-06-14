import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/sync/sync_repository.dart';

final fullPageProvider = FutureProvider.autoDispose.family<SyncPage?, String>((ref, id) {
  final repository = ref.watch(syncRepoProvider);
  return repository.getPage(id);
});
