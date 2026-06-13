import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PdfExporter {
  static Future<Uint8List> export(String contentJson) async {
    final pdf = pw.Document();

    try {
      final doc = jsonDecode(contentJson) as Map<String, dynamic>;
      final document = doc['document'] as Map<String, dynamic>?;
      if (document == null) return pdf.save();

      final children = document['children'] as List?;
      if (children != null) {
        final widgets = <pw.Widget>[];
        for (final child in children) {
          if (child is Map<String, dynamic>) {
            _walkNode(child, widgets, 0);
          }
        }
        
        pdf.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(32),
            build: (context) => widgets,
          ),
        );
      }
    } catch (e) {
      // Return empty or error PDF
      pdf.addPage(pw.Page(build: (context) => pw.Text('Error generating PDF: $e')));
    }

    try {
      return await pdf.save();
    } catch (e) {
      final errPdf = pw.Document();
      errPdf.addPage(pw.Page(build: (context) => pw.Text('Error generating PDF: $e')));
      return await errPdf.save();
    }
  }

  static void _walkNode(Map<String, dynamic> node, List<pw.Widget> widgets, int indentLevel) {
    final type = node['type'] as String?;
    final delta = (node['data'] as Map<String, dynamic>?)?['delta'] as List?;
    
    if (delta != null) {
      final textSpans = <pw.TextSpan>[];
      
      for (final op in delta) {
        if (op is Map && op['insert'] is String) {
          final text = _sanitizeText(op['insert'] as String);
          final attrs = op['attributes'] as Map<String, dynamic>?;
          
          pw.Font font = pw.Font.helvetica();
          pw.FontWeight weight = pw.FontWeight.normal;
          pw.FontStyle style = pw.FontStyle.normal;
          
          if (attrs != null) {
            if (attrs['bold'] == true) weight = pw.FontWeight.bold;
            if (attrs['italic'] == true) style = pw.FontStyle.italic;
            if (attrs['code'] == true) font = pw.Font.courier();
          }

          // In standard fonts, bold+italic requires specific fonts
          if (weight == pw.FontWeight.bold && style == pw.FontStyle.italic) {
            if (font == pw.Font.courier()) {
              font = pw.Font.courierBoldOblique();
            } else {
              font = pw.Font.helveticaBoldOblique();
            }
          } else if (weight == pw.FontWeight.bold) {
            if (font == pw.Font.courier()) {
              font = pw.Font.courierBold();
            } else {
              font = pw.Font.helveticaBold();
            }
          } else if (style == pw.FontStyle.italic) {
            if (font == pw.Font.courier()) {
              font = pw.Font.courierOblique();
            } else {
              font = pw.Font.helveticaOblique();
            }
          }

          textSpans.add(pw.TextSpan(
            text: text,
            style: pw.TextStyle(
              font: font,
              fontWeight: weight,
              fontStyle: style,
            ),
          ));
        }
      }

      final richText = pw.RichText(text: pw.TextSpan(children: textSpans));
      pw.Widget blockWidget;

      switch (type) {
        case 'title':
        case 'heading1':
          blockWidget = pw.Padding(
            padding: const pw.EdgeInsets.only(top: 16, bottom: 8),
            child: pw.RichText(text: pw.TextSpan(children: textSpans, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, font: pw.Font.timesBold()))),
          );
          break;
        case 'heading2':
          blockWidget = pw.Padding(
            padding: const pw.EdgeInsets.only(top: 12, bottom: 6),
            child: pw.RichText(text: pw.TextSpan(children: textSpans, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, font: pw.Font.timesBold()))),
          );
          break;
        case 'heading3':
        case 'subheading':
          blockWidget = pw.Padding(
            padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
            child: pw.RichText(text: pw.TextSpan(children: textSpans, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, font: pw.Font.timesBold()))),
          );
          break;
        case 'bulleted_list':
          blockWidget = pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(width: 16, padding: const pw.EdgeInsets.only(top: 6), child: pw.Bullet()),
                pw.Expanded(child: richText),
              ],
            ),
          );
          break;
        case 'numbered_list':
          blockWidget = pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(width: 20, child: pw.Text('-')),
                pw.Expanded(child: richText),
              ],
            ),
          );
          break;
        case 'todo_list':
          final checked = (node['data'] as Map<String, dynamic>?)?['checked'] == true;
          blockWidget = pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(width: 20, child: pw.Text(checked ? '[x]' : '[ ]')),
                pw.Expanded(child: richText),
              ],
            ),
          );
          break;
        case 'quote':
          blockWidget = pw.Padding(
            padding: const pw.EdgeInsets.only(left: 12, top: 4, bottom: 4),
            child: pw.Container(
              decoration: const pw.BoxDecoration(border: pw.Border(left: pw.BorderSide(width: 2, color: PdfColors.grey))),
              padding: const pw.EdgeInsets.only(left: 8),
              child: richText,
            ),
          );
          break;
        case 'code':
          blockWidget = pw.Container(
            padding: const pw.EdgeInsets.all(8),
            margin: const pw.EdgeInsets.only(top: 4, bottom: 4),
            decoration: pw.BoxDecoration(color: PdfColors.grey200, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))),
            child: pw.RichText(text: pw.TextSpan(children: textSpans, style: pw.TextStyle(font: pw.Font.courier()))),
          );
          break;
        case 'paragraph':
        default:
          blockWidget = pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: richText,
          );
          break;
      }

      if (indentLevel > 0) {
        widgets.add(pw.Padding(
          padding: pw.EdgeInsets.only(left: indentLevel * 16.0),
          child: blockWidget,
        ));
      } else {
        widgets.add(blockWidget);
      }
    }

    final children = node['children'] as List?;
    if (children != null) {
      for (final child in children) {
        if (child is Map<String, dynamic>) {
          final newIndent = (type == 'bulleted_list' || type == 'numbered_list' || type == 'todo_list') 
              ? indentLevel + 1 
              : indentLevel;
          _walkNode(child, widgets, newIndent);
        }
      }
    }
  }

  static String _sanitizeText(String text) {
    return text
        .replaceAll(RegExp(r'[\u201C\u201D\u0093\u0094]'), '"')
        .replaceAll(RegExp(r'[\u2018\u2019\u0091\u0092\u00B4`]'), "'")
        .replaceAll(RegExp(r'[\u2013\u2014\u0096\u0097\u2212]'), '-')
        .replaceAll(RegExp(r'[\u2026\u0085]'), '...')
        .replaceAll('→', '->')
        .replaceAll('←', '<-')
        // Strictly allow only standard printable ASCII, tab, newline, and carriage return.
        // This guarantees no 'missing glyph' boxes can be drawn by the PDF engine.
        .replaceAll(RegExp(r'[^\x20-\x7E\n\r\t]'), '');
  }
}
