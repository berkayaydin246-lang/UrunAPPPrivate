import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OCR Edge Function proxies both supported endpoints securely', () {
    final source = File('supabase/functions/ocr/index.ts').readAsStringSync();

    expect(source, contains("endsWith('/ocr/product-label')"));
    expect(source, contains("endsWith('/ocr/ingredients')"));
    expect(source, contains(r'`${backendUrl}${endpoint}`'));
    expect(source, contains("Deno.env.get('OCR_BACKEND_API_KEY')"));
    expect(source, contains(r"'Authorization': `Bearer ${backendApiKey}`"));
  });
}
