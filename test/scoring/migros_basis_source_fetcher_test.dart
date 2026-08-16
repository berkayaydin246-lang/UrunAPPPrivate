import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/scoring/application/migros_basis_source_fetcher.dart';

/// Exercises the REAL subprocess invocation + stdout JSON parsing path,
/// pointed at a tiny throwaway stub script instead of the real Python
/// bridge — proves the Dart-side contract without ever performing a live
/// HTTP fetch or depending on network access.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('migros_basis_fetcher_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  File writeStub(String pythonSource) {
    final file = File('${tempDir.path}/stub.py');
    file.writeAsStringSync(pythonSource);
    return file;
  }

  test('a successful, complete JSON response is mapped correctly', () async {
    final stub = writeStub('''
import json
print(json.dumps({
  "ok": True,
  "adapter_version": "migros_basis_revalidation_bridge_v1",
  "fetched_at": "2026-08-16T12:00:00+00:00",
  "final_url": "https://www.migros.com.tr/x-p-abc123",
  "barcode": "8690000000123",
  "canonical_url_identifier": "abc123",
  "raw_basis_text": "100 g",
  "normalized_basis": "per_100g",
  "nutrition": {"energy_kcal": 200.0, "sugars": 5.0}
}))
''');
    final fetcher = MigrosBasisSourceFetcher(bridgeScriptPath: stub.path);

    final result = await fetcher.fetch(
      source: 'web_scraper:migros',
      sourceUrl: 'https://www.migros.com.tr/x-p-abc123',
    );

    expect(result, isNotNull);
    expect(result!.adapterVersion, 'migros_basis_revalidation_bridge_v1');
    expect(result.barcode, '8690000000123');
    expect(result.canonicalUrlIdentifier, 'abc123');
    expect(result.normalizedBasis, 'per_100g');
    expect(result.rawBasisText, '100 g');
    expect(result.nutrition?.energyKcal, 200.0);
    expect(result.nutrition?.sugars, 5.0);
    expect(result.fetchedAt, DateTime.utc(2026, 8, 16, 12));
  });

  test('ok: false is reported as null, never a partially-filled result', () async {
    final stub = writeStub('''
import json
print(json.dumps({"ok": False, "error": "http 404"}))
''');
    final fetcher = MigrosBasisSourceFetcher(bridgeScriptPath: stub.path);

    final result = await fetcher.fetch(
      source: 'web_scraper:migros',
      sourceUrl: 'https://www.migros.com.tr/gone-p-zzz',
    );

    expect(result, isNull);
  });

  test('malformed (non-JSON) stdout is reported as null, never throws', () async {
    final stub = writeStub('''
print("this is not json")
''');
    final fetcher = MigrosBasisSourceFetcher(bridgeScriptPath: stub.path);

    final result = await fetcher.fetch(
      source: 'web_scraper:migros',
      sourceUrl: 'https://www.migros.com.tr/x-p-abc123',
    );

    expect(result, isNull);
  });

  test('missing a required field (adapter_version) is reported as null', () async {
    final stub = writeStub('''
import json
print(json.dumps({
  "ok": True,
  "fetched_at": "2026-08-16T12:00:00+00:00",
  "normalized_basis": "per_100g"
}))
''');
    final fetcher = MigrosBasisSourceFetcher(bridgeScriptPath: stub.path);

    final result = await fetcher.fetch(
      source: 'web_scraper:migros',
      sourceUrl: 'https://www.migros.com.tr/x-p-abc123',
    );

    expect(result, isNull);
  });

  test('a null barcode/canonical identifier is preserved as null, never guessed', () async {
    final stub = writeStub('''
import json
print(json.dumps({
  "ok": True,
  "adapter_version": "migros_basis_revalidation_bridge_v1",
  "fetched_at": "2026-08-16T12:00:00+00:00",
  "barcode": None,
  "canonical_url_identifier": None,
  "raw_basis_text": None,
  "normalized_basis": "unknown",
  "nutrition": {}
}))
''');
    final fetcher = MigrosBasisSourceFetcher(bridgeScriptPath: stub.path);

    final result = await fetcher.fetch(
      source: 'web_scraper:migros',
      sourceUrl: 'https://www.migros.com.tr/x-p-abc123',
    );

    expect(result, isNotNull);
    expect(result!.barcode, isNull);
    expect(result.canonicalUrlIdentifier, isNull);
    expect(result.normalizedBasis, 'unknown');
  });

  group('extractCanonicalIdentifier', () {
    test('extracts the Migros -p-XXXXXX suffix', () {
      expect(
        MigrosBasisSourceFetcher.extractCanonicalIdentifier(
          'https://www.migros.com.tr/lente-parmesan-peyniri-200-g-p-9ebe02',
        ),
        '9ebe02',
      );
    });

    test('returns null when no such suffix exists', () {
      expect(
        MigrosBasisSourceFetcher.extractCanonicalIdentifier(
          'https://www.migros.com.tr/no-identifier-here',
        ),
        isNull,
      );
    });
  });
}
