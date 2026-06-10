import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/repository.dart';
import '../../core/providers.dart';

final pagesProvider = StreamProvider.family<List<PageListEntry>, String>((ref, sectionId) {
  final repository = ref.watch(repositoryProvider);
  return repository.watchPages(sectionId);
});

class ActivePage extends Notifier<String?> {
  @override
  String? build() => null;
  void select(String? id) => state = id;
}

final activePageProvider = NotifierProvider<ActivePage, String?>(
  ActivePage.new,
);
