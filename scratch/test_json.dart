import 'dart:convert';
import 'package:appflowy_editor/appflowy_editor.dart';

void main() {
  final doc = Document.blank(withInitialText: true);
  print(jsonEncode(doc.toJson()));
}
