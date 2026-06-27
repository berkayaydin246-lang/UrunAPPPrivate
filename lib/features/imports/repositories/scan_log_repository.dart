import 'package:food_analyzer_app/core/services/supabase_service.dart';

class ScanLogRepository {
  const ScanLogRepository();

  /// Log a barcode scan event. Failures are silently ignored — logging is
  /// non-fatal and must never block the main scan flow.
  Future<void> logBarcodeScan({
    required String barcode,
    String? productId,
    required String resultStatus,
    required String sourceUsed,
    bool importedFromOff = false,
  }) async {
    try {
      await SupabaseService.client.from('scan_logs').insert({
        'input_type': 'barcode',
        'barcode': barcode,
        'product_id': ?productId,
        'result_status': resultStatus,
        'source_used': sourceUsed,
        'imported_from_off': importedFromOff,
      });
    } catch (_) {
      // Non-fatal — do not rethrow.
    }
  }
}
