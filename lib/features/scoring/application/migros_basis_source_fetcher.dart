import 'dart:convert';
import 'dart:io';

import 'package:food_analyzer_app/features/product/models/nutrition_data.dart';
import 'package:food_analyzer_app/features/scoring/application/basis_source_fetcher.dart';

/// [BasisSourceFetcher] implementation for `web_scraper:migros` sources.
/// Bridges to scripts/product_import/basis_revalidation_bridge.py — a thin
/// wrapper that reuses the SAME, already-tested Migros extraction pipeline
/// (web_scraper.runner.scrape_product_page /
/// web_scraper.nutrition_parser.detect_basis) every ordinary scrape run
/// uses, rather than a second, divergent HTML/nutrition parser
/// reimplemented in Dart. Section F explicitly requires this reuse.
///
/// Performs exactly one live, read-only HTTP GET per [fetch] call (via the
/// Python bridge subprocess) — never a write, never a batch/bulk request.
/// A future A101-like or BIM-like adapter would implement this SAME
/// interface with its own bridge script; nothing about
/// [HistoricalBasisRevalidationService] or the CLI tool that drives it is
/// Migros-specific.
class MigrosBasisSourceFetcher implements BasisSourceFetcher {
  const MigrosBasisSourceFetcher({
    this.bridgeScriptPath =
        'scripts/product_import/basis_revalidation_bridge.py',
    this.pythonExecutable = 'python3',
    this.timeout = const Duration(seconds: 30),
  });

  final String bridgeScriptPath;
  final String pythonExecutable;
  final Duration timeout;

  @override
  Future<BasisSourceFetchResult?> fetch({
    required String source,
    required String sourceUrl,
  }) async {
    final sourceId = source.startsWith('web_scraper:')
        ? source.substring('web_scraper:'.length)
        : source;
    final process = await Process.run(
      pythonExecutable,
      [bridgeScriptPath, sourceUrl, '--source-id', sourceId],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    ).timeout(timeout);

    final stdout = process.stdout is String
        ? process.stdout as String
        : process.stdout.toString();
    final decoded = _tryDecode(stdout);
    if (decoded == null) return null;
    if (decoded['ok'] != true) return null;

    final adapterVersion = decoded['adapter_version'] as String?;
    final fetchedAtRaw = decoded['fetched_at'] as String?;
    final fetchedAt = fetchedAtRaw == null
        ? null
        : DateTime.tryParse(fetchedAtRaw);
    final normalizedBasis = decoded['normalized_basis'] as String?;
    if (adapterVersion == null || fetchedAt == null || normalizedBasis == null) {
      return null;
    }

    final nutritionJson = decoded['nutrition'];
    final nutrition = nutritionJson is Map
        ? NutritionData.fromMap(Map<String, dynamic>.from(nutritionJson))
        : null;

    return BasisSourceFetchResult(
      adapterVersion: adapterVersion,
      fetchedAt: fetchedAt,
      barcode: decoded['barcode'] as String?,
      canonicalUrlIdentifier: decoded['canonical_url_identifier'] as String?,
      rawBasisText: decoded['raw_basis_text'] as String?,
      normalizedBasis: normalizedBasis,
      nutrition: nutrition,
    );
  }

  Map<String, dynamic>? _tryDecode(String stdout) {
    final trimmed = stdout.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// Extracts the same canonical Migros URL product identifier
  /// (`"...-p-XXXXXX"`) the bridge script itself extracts — exposed here so
  /// [HistoricalBasisRevalidationService.extractCanonicalIdentifier] can be
  /// wired to it directly for the identity gate's second tier.
  static String? extractCanonicalIdentifier(String sourceUrl) {
    final match = RegExp(
      r'-p-([a-z0-9]+)',
      caseSensitive: false,
    ).firstMatch(sourceUrl);
    return match?.group(1)?.toLowerCase();
  }
}
