import 'dart:io';
import 'dart:ui' show Locale;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SpellCheckService {
  SpellCheckService();

  final _macosChannel = const MethodChannel('sheep/spellcheck');
  final _flutterSpellCheck = DefaultSpellCheckService();

  /// Checks spelling of the given [text] and returns ranges of misspelled words.
  Future<List<TextRange>> checkSpelling(String text) async {
    if (text.isEmpty) return [];

    final List<TextRange> misspelled = [];

    if (!kIsWeb) {
      if (Platform.isMacOS) {
        try {
          final List<dynamic>? results = await _macosChannel.invokeMethod('checkSpelling', text);
          if (results != null) {
            for (final res in results) {
              final loc = res['location'] as int;
              final len = res['length'] as int;
              misspelled.add(TextRange(start: loc, end: loc + len));
            }
          }
        } catch (e) {
          debugPrint('macOS spellcheck error: $e');
        }
      } else if (Platform.isAndroid || Platform.isIOS) {
        try {
          final spans = await _flutterSpellCheck.fetchSpellCheckSuggestions(
            const Locale('en', 'US'),
            text,
          );
          if (spans != null) {
            for (final span in spans) {
              misspelled.add(span.range);
            }
          }
        } catch (e) {
          debugPrint('Mobile spellcheck error: $e');
        }
      }
    }

    return misspelled;
  }
}

final spellCheckServiceProvider = Provider((ref) => SpellCheckService());
