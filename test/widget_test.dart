import 'package:flutter_test/flutter_test.dart';
import 'package:sheep/app.dart';

void main() {
  testWidgets('Sheep app renders blank scaffold', (WidgetTester tester) async {
    await tester.pumpWidget(const SheepApp());
    expect(find.text('sheep'), findsOneWidget);
  });
}
