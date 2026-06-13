import 'dart:io' show Platform, File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

class ExportService {
  static Future<void> exportString(String content, String fileName) async {
    if (kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Markdown File',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['md'],
      );

      if (outputFile != null) {
        final file = File(outputFile);
        await file.writeAsString(content);
      }
    } else {
      final dir = await getApplicationDocumentsDirectory();
      final tempFile = File('${dir.path}/$fileName');
      await tempFile.writeAsString(content);
      await Share.shareXFiles([XFile(tempFile.path)], subject: 'Exported Note');
    }
  }

  static Future<void> exportBytes(List<int> bytes, String fileName) async {
    if (kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save PDF File',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (outputFile != null) {
        final file = File(outputFile);
        await file.writeAsBytes(bytes);
      }
    } else {
      final dir = await getApplicationDocumentsDirectory();
      final tempFile = File('${dir.path}/$fileName');
      await tempFile.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(tempFile.path)], subject: 'Exported Note');
    }
  }
}
