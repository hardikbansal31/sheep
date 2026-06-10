import 'package:flutter_riverpod/flutter_riverpod.dart';

// --- Sections pane visibility ---

class SectionsPaneVisibility extends Notifier<bool> {
  @override
  bool build() => true;
  void toggle() => state = !state;
}

final sectionsPaneVisibleProvider =
    NotifierProvider<SectionsPaneVisibility, bool>(
  SectionsPaneVisibility.new,
);

// --- Pages pane visibility ---

class PagesPaneVisibility extends Notifier<bool> {
  @override
  bool build() => true;
  void toggle() => state = !state;
}

final pagesPaneVisibleProvider =
    NotifierProvider<PagesPaneVisibility, bool>(
  PagesPaneVisibility.new,
);

// --- Mobile nav index (0=sections, 1=pages, 2=editor) ---

class MobileNavIndex extends Notifier<int> {
  @override
  int build() => 0;
  void go(int index) => state = index;
  void back() {
    if (state > 0) state = state - 1;
  }
}

final mobileNavIndexProvider =
    NotifierProvider<MobileNavIndex, int>(
  MobileNavIndex.new,
);
