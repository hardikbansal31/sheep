import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/providers.dart';

final sectionsProvider = StreamProvider<List<Section>>((ref) {
  final repository = ref.watch(repositoryProvider);
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
