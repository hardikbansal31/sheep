import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../pages/providers.dart';
import 'providers.dart';

class SearchModal extends ConsumerStatefulWidget {
  const SearchModal({super.key});

  @override
  ConsumerState<SearchModal> createState() => _SearchModalState();
}

class _SearchModalState extends ConsumerState<SearchModal> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    // We should clear the search query when the modal closes
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final resultsAsync = ref.watch(searchResultsProvider);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      alignment: Alignment.topCenter,
      child: Container(
        width: 600,
        margin: const EdgeInsets.only(top: 48),
        decoration: BoxDecoration(
          color: colors.surfacePanel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: TextField(
                controller: _controller,
                autofocus: true,
                style: TextStyle(color: colors.inkPrimary, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Search pages...',
                  hintStyle: TextStyle(color: colors.inkMuted),
                  border: InputBorder.none,
                  icon: Icon(Icons.search, color: colors.inkMuted),
                ),
                onChanged: (val) {
                  ref.read(searchQueryProvider.notifier).update(val);
                },
              ),
            ),
            if (ref.watch(searchQueryProvider).isNotEmpty) ...[
              Divider(height: 1, color: colors.border),
              Flexible(
                child: resultsAsync.when(
                  data: (results) {
                    if (results.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No results found',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.inkMuted),
                        ),
                      );
                    }
                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: results.length,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemBuilder: (context, index) {
                        final result = results[index];
                        return ListTile(
                          onTap: () {
                            ref.read(activePageProvider.notifier).select(result.pageId);
                            // Clear query state so it's fresh next time
                            ref.read(searchQueryProvider.notifier).clear();
                            Navigator.of(context).pop();
                          },
                          title: Row(
                            children: [
                              Icon(Icons.description_outlined, size: 16, color: colors.inkSecondary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  result.title.isEmpty ? 'Untitled' : result.title,
                                  style: TextStyle(
                                    color: colors.inkPrimary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: colors.surfaceBase,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: colors.border),
                                ),
                                child: Text(
                                  result.sectionName,
                                  style: TextStyle(
                                    color: colors.inkSecondary,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4, left: 24),
                            child: RichText(
                              text: _parseSnippet(result.snippet, colors),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        );
                      },
                    );
                  },
                  loading: () => Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, color: colors.accent),
                      ),
                    ),
                  ),
                  error: (err, stack) => Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Error: $err',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  TextSpan _parseSnippet(String snippet, AppColors colors) {
    final spans = <TextSpan>[];
    final parts = snippet.split('<b>');
    
    // First part is always unbolded
    if (parts.isNotEmpty) {
      spans.add(TextSpan(
        text: parts[0],
        style: TextStyle(color: colors.inkMuted, fontSize: 13),
      ));
      
      for (var i = 1; i < parts.length; i++) {
        final subparts = parts[i].split('</b>');
        if (subparts.isNotEmpty) {
          // Inside <b>...</b>
          spans.add(TextSpan(
            text: subparts[0],
            style: TextStyle(color: colors.inkPrimary, fontWeight: FontWeight.bold, fontSize: 13),
          ));
          // After </b>
          if (subparts.length > 1) {
            spans.add(TextSpan(
              text: subparts[1],
              style: TextStyle(color: colors.inkMuted, fontSize: 13),
            ));
          }
        }
      }
    }
    
    return TextSpan(children: spans);
  }
}
