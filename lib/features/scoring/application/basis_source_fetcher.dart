import 'package:food_analyzer_app/features/product/models/nutrition_data.dart';

/// Source-neutral contract for fetching a product's CURRENT live source
/// page state, for basis revalidation only (Section F/G of the basis
/// remediation pass). Any trusted retailer adapter — Migros, a future
/// A101-like or BIM-like adapter — implements this the same way; nothing
/// in [HistoricalBasisRevalidationService] is retailer-specific.
///
/// IMPORTANT (Section F): a live fetch is NEW current evidence about the
/// page as it exists right now — it is NEVER proof of what the page said
/// at the time the historical row was originally scraped. Implementations
/// must not claim otherwise; callers must always route the result through
/// the identity and nutrition-consistency gates before trusting it for
/// anything.
abstract interface class BasisSourceFetcher {
  /// Returns null when the source could not be fetched at all (network
  /// failure, 404, page removed) — the caller reports
  /// [BasisRevalidationOutcome.sourceUnavailable] for a null result, never
  /// throws for an ordinary "page not found" condition.
  Future<BasisSourceFetchResult?> fetch({
    required String source,
    required String sourceUrl,
  });
}

/// One fetch attempt's raw, unverified result — deliberately named
/// "unverified": nothing here has passed the identity or nutrition
/// consistency gates yet. [adapterVersion] must be stamped by every real
/// implementation so a future re-run can tell which parser logic produced
/// this evidence.
class BasisSourceFetchResult {
  const BasisSourceFetchResult({
    required this.adapterVersion,
    required this.fetchedAt,
    this.barcode,
    this.canonicalUrlIdentifier,
    this.rawBasisText,
    required this.normalizedBasis,
    this.nutrition,
  });

  final String adapterVersion;
  final DateTime fetchedAt;

  /// Exact barcode as currently displayed on the live page, if the source
  /// exposes one. Strongest identity tier — see Section G.
  final String? barcode;

  /// Exact canonical retailer product identifier extracted from the
  /// fetched page/URL (e.g. Migros's "-p-XXXXXX" URL suffix). Second
  /// identity tier, used only when barcode is unavailable on either side.
  final String? canonicalUrlIdentifier;

  /// The exact raw text the basis classifier matched against — retained
  /// for audit, never re-interpreted differently later without a new fetch.
  final String? rawBasisText;

  /// One of 'per_100g' / 'per_100ml' / 'per_100_generic' / 'per_100' /
  /// 'per_serving' / 'unknown' — the SAME vocabulary
  /// scripts/product_import/web_scraper/nutrition_parser.py's
  /// detect_basis() produces, kept source-neutral so any adapter's output
  /// is interchangeable here.
  final String normalizedBasis;

  /// Freshly fetched nutrition values, for the Section H consistency gate.
  /// Null when the source has no nutrition table right now at all.
  final NutritionData? nutrition;
}
