import 'dart:convert';
import 'package:appflowy_editor/appflowy_editor.dart';

void main() {
  final text = '''
```dart
print("hello world");
```
  ''';
  final doc = markdownToDocument(text);
  print(jsonEncode(doc.toJson()));
}
