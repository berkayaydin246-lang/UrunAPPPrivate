import 'dart:typed_data';
import 'package:food_analyzer_app/core/services/supabase_service.dart';

/// Simple storage abstraction for uploading files to Supabase Storage.
class StorageService {
  StorageService._();

  /// Upload bytes to the given bucket/path. Returns public URL or null on failure.
  static Future<String?> uploadFileBytes(
    String bucket,
    String path,
    Uint8List bytes,
  ) async {
    try {
      final client = SupabaseService.client;
      // Try upload; API may vary, so wrap in try/catch
      await client.storage.from(bucket).uploadBinary(path, bytes);
      // Try to make public URL
      final url = client.storage.from(bucket).getPublicUrl(path);
      return url; // may be null if storage not configured
    } catch (_) {
      // Storage not available or upload failed; return null
      return null;
    }
  }

  /// Best-effort cleanup for temporary files.
  static Future<bool> deleteFile(String bucket, String path) async {
    try {
      final client = SupabaseService.client;
      await client.storage.from(bucket).remove([path]);
      return true;
    } catch (_) {
      return false;
    }
  }
}
