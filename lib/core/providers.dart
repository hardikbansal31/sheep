import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database/database.dart';
import 'database/repository.dart';

final databaseProvider = Provider<SheepDatabase>((ref) {
  final db = SheepDatabase();
  ref.onDispose(db.close);
  return db;
});

final repositoryProvider = Provider<SheepRepository>((ref) {
  return SheepRepository(ref.watch(databaseProvider));
});
