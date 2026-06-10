import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';

const _uuid = Uuid();

// Removed _emptyDocument as content is dynamically generated now

/// Lightweight page model for list views — excludes content_json.
class PageListEntry {
  const PageListEntry({
    required this.id,
    required this.sectionId,
    required this.title,
    required this.updatedAt,
  });
  final String id;
  final String sectionId;
  final String title;
  final DateTime updatedAt;
}

class SheepRepository {
  SheepRepository(this._db);
  final SheepDatabase _db;

  // ── Sections ─────────────────────────────────────────────

  Stream<List<Section>> watchSections() {
    return (_db.select(_db.sections)
          ..where((s) => s.isDeleted.equals(false))
          ..orderBy([(s) => OrderingTerm.asc(s.orderIndex)]))
        .watch();
  }

  Future<Section?> getSection(String id) {
    return (_db.select(_db.sections)..where((s) => s.id.equals(id)))
        .getSingleOrNull();
  }

  Future<Section> createSection(String title) async {
    final count = await _db.sections.count().getSingle();
    final section = SectionsCompanion.insert(
      id: _uuid.v4(),
      title: title,
      orderIndex: count,
    );
    await _db.into(_db.sections).insert(section);
    return (await getSection(section.id.value))!;
  }

  Future<void> updateSectionTitle(String id, String title) {
    return (_db.update(_db.sections)..where((s) => s.id.equals(id)))
        .write(SectionsCompanion(title: Value(title)));
  }

  Future<void> deleteSection(String id) async {
    await (_db.delete(_db.sections)..where((s) => s.id.equals(id))).go();
    // FTS cleanup for all pages that were in this section is handled by CASCADE
    await _db.customStatement(
      'DELETE FROM pages_search WHERE page_id NOT IN (SELECT id FROM pages)',
    );
    await _ensureNotEmpty();
  }

  Future<void> softDeleteSection(String id) async {
    await (_db.update(_db.sections)..where((s) => s.id.equals(id)))
        .write(const SectionsCompanion(isDeleted: Value(true)));
        
    // Also soft delete all pages in this section
    await (_db.update(_db.pages)..where((p) => p.sectionId.equals(id)))
        .write(const PagesCompanion(isDeleted: Value(true)));
        
    // Remove from FTS to prevent search hits for deleted pages
    await _db.customStatement(
      'DELETE FROM pages_search WHERE page_id IN (SELECT id FROM pages WHERE section_id = ?)',
      [id],
    );
  }

  Future<void> reorderSections(List<String> orderedIds) {
    return _db.batch((batch) {
      for (var i = 0; i < orderedIds.length; i++) {
        batch.update(
          _db.sections,
          SectionsCompanion(orderIndex: Value(i)),
          where: ($SectionsTable s) => s.id.equals(orderedIds[i]),
        );
      }
    });
  }

  // ── Pages ────────────────────────────────────────────────

  /// List query — excludes content_json for performance.
  Stream<List<PageListEntry>> watchPages(String sectionId) {
    final query = _db.selectOnly(_db.pages)
      ..addColumns([
        _db.pages.id,
        _db.pages.sectionId,
        _db.pages.title,
        _db.pages.updatedAt,
      ])
      ..where(_db.pages.sectionId.equals(sectionId) & _db.pages.isDeleted.equals(false))
      ..orderBy([OrderingTerm.desc(_db.pages.updatedAt)]);

    return query.watch().map((rows) => rows
        .map((row) => PageListEntry(
              id: row.read(_db.pages.id)!,
              sectionId: row.read(_db.pages.sectionId)!,
              title: row.read(_db.pages.title)!,
              updatedAt: row.read(_db.pages.updatedAt)!,
            ))
        .toList());
  }

  Future<Page?> getPage(String id) {
    return (_db.select(_db.pages)..where((p) => p.id.equals(id)))
        .getSingleOrNull();
  }

  Future<Page> createPage(String sectionId, String title) async {
    final id = _uuid.v4();
    final safeTitle = title.replaceAll('"', '\\"').replaceAll('\n', ' ');
    final contentJson = '{"document":{"type":"page","children":['
        '{"type":"title","data":{"delta":[{"insert":"$safeTitle"}]}},'
        '{"type":"paragraph","data":{"delta":[{"insert":""}]}}'
        ']}}';
    final companion = PagesCompanion.insert(
      id: id,
      sectionId: sectionId,
      title: title,
      contentJson: contentJson,
    );
    await _db.into(_db.pages).insert(companion);
    await _syncFts(id, title, '');
    return (await getPage(id))!;
  }

  Future<void> updatePageTitle(String id, String title) async {
    await (_db.update(_db.pages)..where((p) => p.id.equals(id)))
        .write(PagesCompanion(title: Value(title)));
    final page = await getPage(id);
    if (page != null) {
      await _syncFts(id, title, _extractPlainText(page.contentJson));
    }
  }

  Future<void> updatePage(String id, String title, String contentJson) async {
    await (_db.update(_db.pages)..where((p) => p.id.equals(id))).write(
      PagesCompanion(
        title: Value(title),
        contentJson: Value(contentJson),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _syncFts(id, title, _extractPlainText(contentJson));
  }

  Future<void> updatePageContent(String id, String contentJson) async {
    await (_db.update(_db.pages)..where((p) => p.id.equals(id))).write(
      PagesCompanion(
        contentJson: Value(contentJson),
        updatedAt: Value(DateTime.now()),
      ),
    );
    final page = await getPage(id);
    if (page != null) {
      await _syncFts(id, page.title, _extractPlainText(contentJson));
    }
  }

  Future<void> deletePage(String id) async {
    await (_db.delete(_db.pages)..where((p) => p.id.equals(id))).go();
    await _db.customStatement(
      'DELETE FROM pages_search WHERE page_id = ?',
      [id],
    );
  }

  Future<void> softDeletePage(String id) async {
    await (_db.update(_db.pages)..where((p) => p.id.equals(id)))
        .write(const PagesCompanion(isDeleted: Value(true)));
        
    await _db.customStatement(
      'DELETE FROM pages_search WHERE page_id = ?',
      [id],
    );
  }

  // ── Preferences ──────────────────────────────────────────

  Future<String?> getPreference(String key) async {
    final row = await (_db.select(_db.userPreferences)
          ..where((p) => p.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> setPreference(String key, String value) {
    return _db
        .into(_db.userPreferences)
        .insertOnConflictUpdate(UserPreferencesCompanion.insert(
          key: key,
          value: value,
        ));
  }

  // ── Dictionary ───────────────────────────────────────────

  Future<List<String>> getWords() async {
    final rows = await _db.select(_db.customDictionary).get();
    return rows.map((r) => r.word).toList();
  }

  Future<void> addWord(String word) {
    return _db
        .into(_db.customDictionary)
        .insertOnConflictUpdate(CustomDictionaryCompanion.insert(word: word));
  }

  Future<void> removeWord(String word) {
    return (_db.delete(_db.customDictionary)..where((d) => d.word.equals(word)))
        .go();
  }

  // ── Search ───────────────────────────────────────────────

  Future<List<({String pageId, String title, String snippet})>> searchPages(
    String query,
  ) async {
    final results = await _db.customSelect(
      'SELECT page_id, title, snippet(pages_search, 2, \'<b>\', \'</b>\', \'...\', 32) '
      'as snip FROM pages_search WHERE pages_search MATCH ? ORDER BY rank',
      variables: [Variable.withString(query)],
    ).get();

    return results
        .map((row) => (
              pageId: row.read<String>('page_id'),
              title: row.read<String>('title'),
              snippet: row.read<String>('snip'),
            ))
        .toList();
  }

  // ── Empty state ──────────────────────────────────────────

  Future<void> ensureInitialState() async {
    final count = await _db.sections.count().getSingle();
    if (count == 0) {
      final section = await createSection('Section 1');
      await createPage(section.id, 'Page 1');
    }
  }

  Future<void> _ensureNotEmpty() async {
    final count = await _db.sections.count().getSingle();
    if (count == 0) {
      final section = await createSection('Section 1');
      await createPage(section.id, 'Page 1');
    }
  }

  // ── FTS sync ─────────────────────────────────────────────

  Future<void> _syncFts(String pageId, String title, String bodyText) async {
    await _db.customStatement(
      'DELETE FROM pages_search WHERE page_id = ?',
      [pageId],
    );
    await _db.customStatement(
      'INSERT INTO pages_search (page_id, title, body_text) VALUES (?, ?, ?)',
      [pageId, title, bodyText],
    );
  }

  // ── Plain text extraction from AppFlowy JSON ─────────────

  static String _extractPlainText(String contentJson) {
    try {
      final doc = jsonDecode(contentJson) as Map<String, dynamic>;
      final document = doc['document'] as Map<String, dynamic>?;
      if (document == null) return '';
      final buffer = StringBuffer();
      _walkNode(document, buffer);
      return buffer.toString().trim();
    } catch (_) {
      return '';
    }
  }

  static void _walkNode(Map<String, dynamic> node, StringBuffer buffer) {
    final delta = (node['data'] as Map<String, dynamic>?)?['delta'] as List?;
    if (delta != null) {
      for (final op in delta) {
        if (op is Map && op['insert'] is String) {
          buffer.write(op['insert']);
        }
      }
      buffer.write('\n');
    }
    final children = node['children'] as List?;
    if (children != null) {
      for (final child in children) {
        if (child is Map<String, dynamic>) {
          _walkNode(child, buffer);
        }
      }
    }
  }
}
