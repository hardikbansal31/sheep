import 'dart:convert';

class MarkdownExporter {
  static String export(String contentJson) {
    try {
      final doc = jsonDecode(contentJson) as Map<String, dynamic>;
      final document = doc['document'] as Map<String, dynamic>?;
      if (document == null) return '';

      final buffer = StringBuffer();
      final children = document['children'] as List?;
      if (children != null) {
        for (final child in children) {
          if (child is Map<String, dynamic>) {
            _walkNode(child, buffer, 0);
          }
        }
      }
      return buffer.toString().trim();
    } catch (_) {
      return '';
    }
  }

  static void _walkNode(Map<String, dynamic> node, StringBuffer buffer, int indentLevel) {
    final type = node['type'] as String?;
    final delta = (node['data'] as Map<String, dynamic>?)?['delta'] as List?;
    
    final indent = '  ' * indentLevel;

    if (delta != null) {
      switch (type) {
        case 'title':
        case 'heading1':
          buffer.write('$indent# ');
          break;
        case 'heading2':
          buffer.write('$indent## ');
          break;
        case 'heading3':
        case 'subheading':
          buffer.write('$indent### ');
          break;
        case 'bulleted_list':
          buffer.write('$indent- ');
          break;
        case 'numbered_list':
          buffer.write('${indent}1. ');
          break;
        case 'todo_list':
          // We can check attributes for 'checked' if available
          final checked = (node['data'] as Map<String, dynamic>?)?['checked'] == true;
          buffer.write(checked ? '$indent[x] ' : '$indent[ ] ');
          break;
        case 'quote':
          buffer.write('$indent> ');
          break;
        case 'code':
          buffer.write('$indent```\n');
          break;
        case 'paragraph':
        default:
          buffer.write(indent);
          break;
      }

      for (final op in delta) {
        if (op is Map && op['insert'] is String) {
          final text = op['insert'] as String;
          final attrs = op['attributes'] as Map<String, dynamic>?;
          
          String formattedText = text;
          if (attrs != null) {
            if (attrs['bold'] == true) formattedText = '**$formattedText**';
            if (attrs['italic'] == true) formattedText = '*$formattedText*';
            if (attrs['strikethrough'] == true) formattedText = '~~$formattedText~~';
            if (attrs['code'] == true) formattedText = '`$formattedText`';
            if (attrs['href'] != null) formattedText = '[$formattedText](${attrs['href']})';
          }
          buffer.write(formattedText);
        }
      }

      if (type == 'code') {
        buffer.write('\n$indent```\n\n');
      } else {
        buffer.write('\n\n');
      }
    }

    final children = node['children'] as List?;
    if (children != null) {
      for (final child in children) {
        if (child is Map<String, dynamic>) {
          // Increase indent if it's a list item
          final newIndent = (type == 'bulleted_list' || type == 'numbered_list' || type == 'todo_list') 
              ? indentLevel + 1 
              : indentLevel;
          _walkNode(child, buffer, newIndent);
        }
      }
    }
  }
}
