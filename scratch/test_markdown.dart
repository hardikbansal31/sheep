import 'package:appflowy_editor/appflowy_editor.dart';

void main() {
  final doc = Document.blank();
  final md = documentToMarkdown(doc);
  print(md);
}
