import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scoring evidence migration is additive and nullable', () {
    final sql = File(
      'supabase/migrations/20260808010000_add_scoring_evidence.sql',
    ).readAsStringSync();
    final normalized = sql.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

    for (final table in [
      'products',
      'product_staging',
      'product_submissions',
    ]) {
      expect(
        normalized,
        contains(
          'alter table $table add column if not exists scoring_evidence jsonb',
        ),
      );
    }
    expect(normalized, isNot(contains('scoring_evidence jsonb not null')));
    expect(normalized, isNot(contains('default')));
    expect(normalized, isNot(contains('drop column')));
  });
}
