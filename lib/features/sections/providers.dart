import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/sync/sync_repository.dart';

final sectionsProvider = StreamProvider<List<SyncSection>>((ref) {
  final repository = ref.watch(syncRepoProvider);
  return repository.watchSections();
});

class ActiveSection extends Notifier<String?> {
  @override
  String? build() => null;
  void select(String? id) => state = id;
}

final activeSectionProvider = NotifierProvider<ActiveSection, String?>(
  ActiveSection.new,
);
