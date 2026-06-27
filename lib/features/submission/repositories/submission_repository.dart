import 'dart:typed_data';
import 'package:food_analyzer_app/core/services/supabase_service.dart';
import 'package:food_analyzer_app/core/services/storage_service.dart';

class SubmissionRepository {
  const SubmissionRepository();

  /// Submit a user submission. Images are optional; if bytes provided,
  /// attempts to upload to Supabase Storage under 'submissions' bucket.
  Future<void> submit({
    required String productName,
    String? barcode,
    Uint8List? frontImageBytes,
    String? frontImageName,
    Uint8List? ingredientsImageBytes,
    String? ingredientsImageName,
    String? ocrText,
  }) async {
    final client = SupabaseService.client;

    String? frontUrl;
    String? ingredientsUrl;

    // Attempt uploads if bytes present
    if (frontImageBytes != null && frontImageName != null) {
      frontUrl = await StorageService.uploadFileBytes(
        'submissions',
        frontImageName,
        frontImageBytes,
      );
    }

    if (ingredientsImageBytes != null && ingredientsImageName != null) {
      ingredientsUrl = await StorageService.uploadFileBytes(
        'submissions',
        ingredientsImageName,
        ingredientsImageBytes,
      );
    }

    final payload = {
      'barcode': barcode,
      'product_name': productName,
      'front_image_url': frontUrl,
      'ingredients_image_url': ingredientsUrl,
      'ocr_text': ocrText,
      'status': 'pending',
    };

    final resp = await client
        .from('user_submissions')
        .insert(payload)
        .select()
        .maybeSingle();
    if (resp == null) {
      // insertion may return null in some setups; treat as success
      return;
    }
  }
}
