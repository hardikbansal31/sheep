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

  try {
    return await repository.searchPages(ftsQuery);
  } catch (e) {
    // If syntax error in FTS5 query, fallback to normal query or return empty
    try {
      return await repository.searchPages('"$query"*');
    } catch (_) {
      return [];
    }
  }
});
