import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';

class SearchQuery extends Notifier<String> {
  @override
  String build() => '';
  
  void update(String val) => state = val;
  void clear() => state = '';
}

final searchQueryProvider = NotifierProvider<SearchQuery, String>(
  SearchQuery.new,
);

final searchResultsProvider = FutureProvider<List<({String pageId, String title, String sectionName, String snippet})>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.trim().isEmpty) return [];

  // Add a small debounce
  await Future.delayed(const Duration(milliseconds: 300));
  
  // If the query was cleared or changed during the delay, the future will be
  // cancelled automatically by Riverpod (well, the result will be discarded).
  final repository = ref.read(repositoryProvider);
  
  // AppFlowy FTS5 matcher format for partial matching: add a * if it doesn't have one
  String ftsQuery = query;
  if (!ftsQuery.contains('*')) {
    final terms = ftsQuery.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (terms.isNotEmpty) {
      // e.g., "hello world" -> "hello* AND world*"
      ftsQuery = terms.map((t) => '$t*').join(' AND ');
    }
  }

  List<({String pageId, String title, String snippet})> rawResults;
  try {
    rawResults = await repository.searchPages(ftsQuery);
  } catch (e) {
    // If syntax error in FTS5 query, fallback to normal query or return empty
    try {
      rawResults = await repository.searchPages('"$query"*');
    } catch (_) {
      return [];
    }
  }

  // Hydrate each result with live data from SyncRepository (PowerSync)
  final syncRepo = ref.read(syncRepoProvider);
  final hydrated = <({String pageId, String title, String sectionName, String snippet})>[];

  // Cache section lookups to avoid repeated queries
  final sectionCache = <String, String?>{};

  for (final raw in rawResults) {
    final page = await syncRepo.getPage(raw.pageId);
    // Skip deleted, missing, or locked pages
    if (page == null || page.isDeleted || page.isLocked) continue;

    // Resolve section name (with cache)
    if (!sectionCache.containsKey(page.sectionId)) {
      final section = await syncRepo.getSection(page.sectionId);
      sectionCache[page.sectionId] =
          (section != null && !section.isDeleted && !section.isLocked) ? section.title : null;
    }

    final sectionName = sectionCache[page.sectionId];
    // Skip if section is deleted or missing
    if (sectionName == null) continue;

    hydrated.add((
      pageId: raw.pageId,
      title: page.title,
      sectionName: sectionName,
      snippet: raw.snippet,
    ));
  }

  return hydrated;
});
