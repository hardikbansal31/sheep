import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sheep/app.dart';

void main() {
  testWidgets('Sheep app renders blank scaffold', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const ProviderScope(child: SheepApp()));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(Scaffold), findsAtLeast(1));
  });
}
