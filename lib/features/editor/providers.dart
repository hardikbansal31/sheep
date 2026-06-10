import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/providers.dart';

final fullPageProvider = FutureProvider.autoDispose.family<Page?, String>((ref, id) {
  final repository = ref.watch(repositoryProvider);
  return repository.getPage(id);
});
