import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'database.g.dart';

/// The single Drift database for Sheep.
///
/// Includes all four typed tables plus a raw FTS5 virtual table
/// for full-text search across page content.
@DriftDatabase(tables: [Sections, Pages, UserPreferences, CustomDictionary])
class SheepDatabase extends _$SheepDatabase {
  SheepDatabase([QueryExecutor? executor]) : super(executor ?? _openDefault());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      // FTS5 virtual table — not expressible via Drift's typed API,
      // so we create it with raw SQL.
      await customStatement('''
            CREATE VIRTUAL TABLE IF NOT EXISTS pages_search USING fts5(
              page_id,
              title,
              body_text
            )
          ''');
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        await m.addColumn(sections, sections.isDeleted);
        await m.addColumn(pages, pages.isDeleted);
      }
    },
  );

  static QueryExecutor _openDefault() {
    return driftDatabase(name: 'sheep');
  }
}
