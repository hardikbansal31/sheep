import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:powersync/powersync.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Lightweight page model for list views — excludes content_json.
class PageListEntry {
  const PageListEntry({
    required this.id,
    required this.sectionId,
    required this.title,
    required this.updatedAt,
    required this.isLocked,
  });
  final String id;
  final String sectionId;
  final String title;
  final DateTime updatedAt;
  final bool isLocked;
}

/// Simple model for a section row from PowerSync.
class SyncSection {
  const SyncSection({
    required this.id,
    required this.title,
    required this.orderIndex,
    required this.createdAt,
    required this.isDeleted,
    required this.isLocked,
  });
  final String id;
  final String title;
  final int orderIndex;
  final DateTime createdAt;
  final bool isDeleted;
  final bool isLocked;

  factory SyncSection.fromRow(Map<String, dynamic> row) {
    return SyncSection(
      id: row['id'] as String,
      title: row['title'] as String,
      orderIndex: (row['order_index'] as num).toInt(),
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ??
          DateTime.now(),
      isDeleted: (row['is_deleted'] ?? 0) == 1,
      isLocked: (row['is_locked'] ?? 0) == 1,
    );
  }
}

/// Simple model for a page row from PowerSync.
class SyncPage {
  const SyncPage({
    required this.id,
    required this.sectionId,
    required this.title,
    required this.contentJson,
    required this.updatedAt,
    required this.isDeleted,
    required this.isLocked,
  });
  final String id;
  final String sectionId;
  final String title;
  final String contentJson;
  final DateTime updatedAt;
  final bool isDeleted;
  final bool isLocked;

  factory SyncPage.fromRow(Map<String, dynamic> row) {
    return SyncPage(
      id: row['id'] as String,
      sectionId: row['section_id'] as String,
      title: row['title'] as String,
      contentJson: row['content_json'] as String,
      updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? '') ??
          DateTime.now(),
      isDeleted: (row['is_deleted'] ?? 0) == 1,
      isLocked: (row['is_locked'] ?? 0) == 1,
    );
  }
}

/// Repository for synced data (Sections & Pages) backed by PowerSync.
///
/// Provides the same interface as the original SheepRepository for sections
/// and pages, but reads/writes through PowerSync's SQLite database.
/// PowerSync handles queueing writes for upload and syncing remote changes.
///
/// Optionally accepts a [_driftDb] reference to keep the local FTS5 search
/// index in sync with page mutations.
class SyncRepository {
  SyncRepository(this._db, [this._driftDb]);
  final PowerSyncDatabase _db;
  final dynamic _driftDb; // SheepDatabase — dynamic to avoid circular imports

  /// Update the FTS5 index in the Drift database (if available).
  Future<void> _syncFts(String pageId, String title, String bodyText) async {
    if (_driftDb == null) return;
    try {
      await _driftDb.customStatement(
        'DELETE FROM pages_search WHERE page_id = ?',
        [pageId],
      );
      await _driftDb.customStatement(
        'INSERT INTO pages_search (page_id, title, body_text) VALUES (?, ?, ?)',
        [pageId, title, bodyText],
      );
    } catch (_) {
      // FTS sync failure is non-fatal — search may be stale.
    }
  }

  Future<void> _deleteFts(String pageId) async {
    if (_driftDb == null) return;
    try {
      await _driftDb.customStatement(
        'DELETE FROM pages_search WHERE page_id = ?',
        [pageId],
      );
    } catch (_) {}
  }

  // ── Sections ─────────────────────────────────────────────

  Stream<List<SyncSection>> watchSections() {
    return _db
        .watch(
          'SELECT * FROM sections WHERE is_deleted = 0 ORDER BY order_index ASC',
        )
        .map((rows) => rows.map(SyncSection.fromRow).toList());
  }

  Future<SyncSection?> getSection(String id) async {
    final rows = await _db.getAll(
      'SELECT * FROM sections WHERE id = ?',
      [id],
    );
    if (rows.isEmpty) return null;
    return SyncSection.fromRow(rows.first);
  }

  Future<SyncSection> createSection(String title) async {
    final count = await _db.getAll('SELECT COUNT(*) as c FROM sections');
    final orderIndex = (count.first['c'] as num).toInt();
    final sectionId = _uuid.v4();
    final now = DateTime.now().toIso8601String();

    await _db.execute(
      'INSERT INTO sections (id, title, order_index, created_at, is_deleted, is_locked) VALUES (?, ?, ?, ?, 0, 0)',
      [sectionId, title, orderIndex, now],
    );

    // Auto-create initial page.
    await createPage(sectionId, 'Title');

    return (await getSection(sectionId))!;
  }

  Future<void> updateSectionTitle(String id, String title) async {
    await _db.execute(
      'UPDATE sections SET title = ? WHERE id = ?',
      [title, id],
    );
  }

  Future<void> updateSectionLock(String id, bool isLocked) async {
    await _db.execute(
      'UPDATE sections SET is_locked = ? WHERE id = ?',
      [isLocked ? 1 : 0, id],
    );
  }

  Future<void> deleteSection(String id) async {
    // Hard delete — cascade pages manually since PowerSync doesn't support
    // foreign key cascades.
    await _db.execute('DELETE FROM pages WHERE section_id = ?', [id]);
    await _db.execute('DELETE FROM sections WHERE id = ?', [id]);
    await _ensureNotEmpty();
  }

  Future<void> softDeleteSection(String id) async {
    await _db.execute(
      'UPDATE sections SET is_deleted = 1 WHERE id = ?',
      [id],
    );
    // Also soft delete all pages in this section.
    await _db.execute(
      'UPDATE pages SET is_deleted = 1 WHERE section_id = ?',
      [id],
    );
  }

  Future<void> reorderSections(List<String> orderedIds) async {
    await _db.writeTransaction((tx) async {
      for (var i = 0; i < orderedIds.length; i++) {
        await tx.execute(
          'UPDATE sections SET order_index = ? WHERE id = ?',
          [i, orderedIds[i]],
        );
      }
    });
  }

  // ── Pages ────────────────────────────────────────────────

  Stream<List<PageListEntry>> watchPages(String sectionId) {
    return _db
        .watch(
          'SELECT id, section_id, title, updated_at, is_locked FROM pages '
          'WHERE section_id = ? AND is_deleted = 0 '
          'ORDER BY updated_at DESC, id ASC',
          parameters: [sectionId],
        )
        .map((rows) => rows
            .map((row) => PageListEntry(
                  id: row['id'] as String,
                  sectionId: row['section_id'] as String,
                  title: row['title'] as String,
                  updatedAt:
                      DateTime.tryParse(row['updated_at']?.toString() ?? '') ??
                          DateTime.now(),
                  isLocked: (row['is_locked'] ?? 0) == 1,
                ))
            .toList());
  }

  Future<SyncPage?> getPage(String id) async {
    final rows = await _db.getAll(
      'SELECT * FROM pages WHERE id = ?',
      [id],
    );
    if (rows.isEmpty) return null;
    return SyncPage.fromRow(rows.first);
  }

  Future<SyncPage> createPage(String sectionId, String title) async {
    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    final safeTitle = title.replaceAll('"', '\\"').replaceAll('\n', ' ');
    final contentJson = '{"document":{"type":"page","children":['
        '{"type":"title","data":{"delta":[{"insert":"$safeTitle"}]}},'
        '{"type":"paragraph","data":{"delta":[{"insert":""}]}}'
        ']}}';

    await _db.execute(
      'INSERT INTO pages (id, section_id, title, content_json, updated_at, is_deleted, is_locked) '
      'VALUES (?, ?, ?, ?, ?, 0, 0)',
      [id, sectionId, title, contentJson, now],
    );

    await _syncFts(id, title, '');
    return (await getPage(id))!;
  }

  Future<void> updatePageTitle(String id, String title) async {
    await _db.execute(
      'UPDATE pages SET title = ? WHERE id = ?',
      [title, id],
    );
    final page = await getPage(id);
    if (page != null) {
      final bodyText = await compute(extractPlainText, page.contentJson);
      await _syncFts(id, title, bodyText);
    }
  }

  Future<void> updatePage(String id, String title, String contentJson) async {
    final now = DateTime.now().toIso8601String();
    await _db.execute(
      'UPDATE pages SET title = ?, content_json = ?, updated_at = ? WHERE id = ?',
      [title, contentJson, now, id],
    );
    final bodyText = await compute(extractPlainText, contentJson);
    await _syncFts(id, title, bodyText);
  }

  Future<void> updatePageContent(String id, String contentJson) async {
    final now = DateTime.now().toIso8601String();
    await _db.execute(
      'UPDATE pages SET content_json = ?, updated_at = ? WHERE id = ?',
      [contentJson, now, id],
    );
  }

  Future<void> updatePageLock(String id, bool isLocked) async {
    await _db.execute(
      'UPDATE pages SET is_locked = ? WHERE id = ?',
      [isLocked ? 1 : 0, id],
    );
  }

  Future<void> deletePage(String id) async {
    await _db.execute('DELETE FROM pages WHERE id = ?', [id]);
    await _deleteFts(id);
  }

  Future<void> softDeletePage(String id) async {
    await _db.execute(
      'UPDATE pages SET is_deleted = 1 WHERE id = ?',
      [id],
    );
    await _deleteFts(id);
  }

  Future<void> restorePage(String id) async {
    await _db.execute(
      'UPDATE pages SET is_deleted = 0 WHERE id = ?',
      [id],
    );
    final page = await getPage(id);
    if (page != null) {
      final bodyText = await compute(extractPlainText, page.contentJson);
      await _syncFts(id, page.title, bodyText);
    }
  }

  // ── Empty state ──────────────────────────────────────────

  Future<void> ensureInitialState() async {
    final countResult =
        await _db.getAll('SELECT COUNT(*) as c FROM sections');
    final count = (countResult.first['c'] as num).toInt();
    if (count == 0) {
      await createSection('Section 1');
    }
  }

  Future<void> _ensureNotEmpty() async {
    final countResult =
        await _db.getAll('SELECT COUNT(*) as c FROM sections');
    final count = (countResult.first['c'] as num).toInt();
    if (count == 0) {
      await createSection('Section 1');
    }
  }

  // ── Plain text extraction from AppFlowy JSON ─────────────

  static String extractPlainText(String contentJson) {
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
