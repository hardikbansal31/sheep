import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Handles image storage: save locally first, then upload to Supabase
/// Storage in the background.
///
/// Usage:
/// 1. Call [saveImageLocally] to persist the image to the app cache.
/// 2. Call [uploadImage] to push it to Supabase Storage.
/// 3. On success, update the editor block's URL to the remote URL.
class ImageService {
  ImageService(this._supabase);

  final SupabaseClient _supabase;

  static const _bucket = 'sheep-images';

  /// Saves [bytes] to the local app cache and returns the local file path.
  Future<String> saveImageLocally(
    Uint8List bytes, {
    String extension = 'png',
  }) async {
    final cacheDir = await getApplicationCacheDirectory();
    final imageDir = Directory('${cacheDir.path}/images');
    if (!await imageDir.exists()) {
      await imageDir.create(recursive: true);
    }
    final fileName = '${_uuid.v4()}.$extension';
    final file = File('${imageDir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// Uploads the image at [localPath] to Supabase Storage.
  ///
  /// Returns the public URL on success, or `null` on failure.
  /// The image is stored under `<userId>/<uuid>.<ext>` in the bucket.
  Future<String?> uploadImage(String localPath) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    try {
      final file = File(localPath);
      if (!await file.exists()) return null;

      final ext = localPath.split('.').last;
      final remotePath = '${user.id}/${_uuid.v4()}.$ext';

      await _supabase.storage.from(_bucket).upload(
            remotePath,
            file,
          );

      final publicUrl =
          _supabase.storage.from(_bucket).getPublicUrl(remotePath);
      return publicUrl;
    } catch (e) {
      debugPrint('Image upload failed: $e');
      return null;
    }
  }
}
