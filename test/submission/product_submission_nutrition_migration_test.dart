import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('nutrition image migration is additive and nullable', () {
    final sql = File(
      'supabase/migrations/20260808000000_product_submissions_add_nutrition_image.sql',
    ).readAsStringSync();
    final normalized = sql.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

    expect(
      normalized,
      contains(
        'alter table product_submissions add column if not exists nutrition_image_url text',
      ),
    );
    expect(normalized, isNot(contains('nutrition_image_url text not null')));
    expect(normalized, isNot(contains('drop column')));
  });
}
