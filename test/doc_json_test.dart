import 'package:flutter_test/flutter_test.dart';
import 'package:sheep/features/export/markdown_exporter.dart';
import 'package:sheep/features/export/pdf_exporter.dart';

void main() {
  test('test exporters', () async {
    final jsonStr = '''{"document":{"type":"page","children":[{"type":"paragraph","data":{"delta":[{"insert":"Hello World"}]}}]}}''';
    
    final md = MarkdownExporter.export(jsonStr);
    expect(md, isNotNull);
    
    final pdfBytes = await PdfExporter.export(jsonStr);
    expect(pdfBytes, isNotEmpty);
  });
}
