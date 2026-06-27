import 'package:food_analyzer_app/features/product/models/nutrition_data.dart';

/// A standardized product candidate that flows into the `product_staging` table.
///
/// Candidates can originate from Open Food Facts, a manual seed list, user
/// submissions, or future market connectors (Migros/Trendyol). They are NEVER
/// written directly into the `products` catalog — they wait in staging for
/// quality scoring and admin review.
///
/// [nutritionJson] is a map compatible with [NutritionData.toMap] /
/// [NutritionData.fromMap]. Use [nutrition] to read it as a [NutritionData].
class ProductCandidate {
  final String? id;

  // Core
  final String? barcode;
  final String? name;
  final String? brand;
  final String? categorySuggestion;
  final List<String>? categoryTags;
  final List<String>? searchKeywords;

  // Images
  final String? imageFrontUrl;
  final String? imageFrontStoragePath;
  final String? imageIngredientsUrl;
  final String? imageNutritionUrl;

  // Extracted data
  final String? ingredientsText;
  final Map<String, dynamic>? nutritionJson;

  // Source tracking
  final String source;
  final String? sourceUrl;
  final Map<String, dynamic>? rawSourcePayload;

  // Field-level source tracking
  final String? nameSource;
  final String? brandSource;
  final String? imageSource;
  final String? ingredientsSource;
  final String? nutritionSource;
  final String? categorySource;

  // Quality / review
  final int qualityScore;
  final List<String> missingFields;
  final String status;
  final String? adminNotes;

  // Timestamps
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ProductCandidate({
    this.id,
    this.barcode,
    this.name,
    this.brand,
    this.categorySuggestion,
    this.categoryTags,
    this.searchKeywords,
    this.imageFrontUrl,
    this.imageFrontStoragePath,
    this.imageIngredientsUrl,
    this.imageNutritionUrl,
    this.ingredientsText,
    this.nutritionJson,
    required this.source,
    this.sourceUrl,
    this.rawSourcePayload,
    this.nameSource,
    this.brandSource,
    this.imageSource,
    this.ingredientsSource,
    this.nutritionSource,
    this.categorySource,
    this.qualityScore = 0,
    this.missingFields = const [],
    this.status = 'pending',
    this.adminNotes,
    this.createdAt,
    this.updatedAt,
  });

  /// True when the candidate has no usable ingredients text.
  bool get hasMissingIngredients {
    final t = ingredientsText?.trim() ?? '';
    return t.isEmpty;
  }

  /// True when the candidate has no usable nutrition data.
  bool get hasMissingNutrition {
    final json = nutritionJson;
    return json == null || json.isEmpty;
  }

  /// True when BOTH ingredients and nutrition are missing.
  ///
  /// Products in this state have no analyzable data — they cannot support
  /// ingredient analysis or nutrition queries and are auto-rejected during
  /// staging approval or import.
  bool get hasNoAnalysisData => hasMissingIngredients && hasMissingNutrition;

  /// Read [nutritionJson] as a [NutritionData], or null when absent/empty.
  NutritionData? get nutrition {
    final json = nutritionJson;
    if (json == null || json.isEmpty) return null;
    final data = NutritionData.fromMap(json);
    return data.hasAnyData ? data : null;
  }

  factory ProductCandidate.fromJson(Map<String, dynamic> json) {
    return ProductCandidate(
      id: json['id'] as String?,
      barcode: json['barcode'] as String?,
      name: json['name'] as String?,
      brand: json['brand'] as String?,
      categorySuggestion: json['category_suggestion'] as String?,
      categoryTags: _stringList(json['category_tags']),
      searchKeywords: _stringList(json['search_keywords']),
      imageFrontUrl: json['image_front_url'] as String?,
      imageFrontStoragePath: json['image_front_storage_path'] as String?,
      imageIngredientsUrl: json['image_ingredients_url'] as String?,
      imageNutritionUrl: json['image_nutrition_url'] as String?,
      ingredientsText: json['ingredients_text'] as String?,
      nutritionJson: _mapOrNull(json['nutrition_json']),
      source: (json['source'] as String?) ?? 'unknown',
      sourceUrl: json['source_url'] as String?,
      rawSourcePayload: _mapOrNull(json['raw_source_payload']),
      nameSource: json['name_source'] as String?,
      brandSource: json['brand_source'] as String?,
      imageSource: json['image_source'] as String?,
      ingredientsSource: json['ingredients_source'] as String?,
      nutritionSource: json['nutrition_source'] as String?,
      categorySource: json['category_source'] as String?,
      qualityScore: (json['quality_score'] as num?)?.toInt() ?? 0,
      missingFields: _stringList(json['missing_fields']) ?? const [],
      status: (json['status'] as String?) ?? 'pending',
      adminNotes: json['admin_notes'] as String?,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  /// Full JSON representation (includes id/timestamps when present).
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'barcode': barcode,
      'name': name,
      'brand': brand,
      'category_suggestion': categorySuggestion,
      'category_tags': categoryTags,
      'search_keywords': searchKeywords,
      'image_front_url': imageFrontUrl,
      'image_front_storage_path': imageFrontStoragePath,
      'image_ingredients_url': imageIngredientsUrl,
      'image_nutrition_url': imageNutritionUrl,
      'ingredients_text': ingredientsText,
      'nutrition_json': nutritionJson,
      'source': source,
      'source_url': sourceUrl,
      'raw_source_payload': rawSourcePayload,
      'name_source': nameSource,
      'brand_source': brandSource,
      'image_source': imageSource,
      'ingredients_source': ingredientsSource,
      'nutrition_source': nutritionSource,
      'category_source': categorySource,
      'quality_score': qualityScore,
      'missing_fields': missingFields,
      'status': status,
      'admin_notes': adminNotes,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  /// Map suitable for inserting into `product_staging`.
  ///
  /// Excludes id and timestamps (DB-managed) and drops null values so DB
  /// defaults apply. quality_score / missing_fields / status are always
  /// included (the repository computes them before insert).
  Map<String, dynamic> toStagingInsertMap() {
    final map = <String, dynamic>{
      'source': source,
      'quality_score': qualityScore,
      'missing_fields': missingFields,
      'status': status,
    };

    void put(String key, dynamic value) {
      if (value == null) return;
      if (value is String && value.trim().isEmpty) return;
      if (value is List && value.isEmpty) return;
      if (value is Map && value.isEmpty) return;
      map[key] = value;
    }

    put('barcode', barcode);
    put('name', name);
    put('brand', brand);
    put('category_suggestion', categorySuggestion);
    put('category_tags', categoryTags);
    put('search_keywords', searchKeywords);
    put('image_front_url', imageFrontUrl);
    put('image_front_storage_path', imageFrontStoragePath);
    put('image_ingredients_url', imageIngredientsUrl);
    put('image_nutrition_url', imageNutritionUrl);
    put('ingredients_text', ingredientsText);
    put('nutrition_json', nutritionJson);
    put('source_url', sourceUrl);
    put('raw_source_payload', rawSourcePayload);
    put('name_source', nameSource);
    put('brand_source', brandSource);
    put('image_source', imageSource);
    put('ingredients_source', ingredientsSource);
    put('nutrition_source', nutritionSource);
    put('category_source', categorySource);
    put('admin_notes', adminNotes);

    return map;
  }

  ProductCandidate copyWith({
    String? id,
    String? barcode,
    String? name,
    String? brand,
    String? categorySuggestion,
    List<String>? categoryTags,
    List<String>? searchKeywords,
    String? imageFrontUrl,
    String? imageFrontStoragePath,
    String? imageIngredientsUrl,
    String? imageNutritionUrl,
    String? ingredientsText,
    Map<String, dynamic>? nutritionJson,
    String? source,
    String? sourceUrl,
    Map<String, dynamic>? rawSourcePayload,
    String? nameSource,
    String? brandSource,
    String? imageSource,
    String? ingredientsSource,
    String? nutritionSource,
    String? categorySource,
    int? qualityScore,
    List<String>? missingFields,
    String? status,
    String? adminNotes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ProductCandidate(
      id: id ?? this.id,
      barcode: barcode ?? this.barcode,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      categorySuggestion: categorySuggestion ?? this.categorySuggestion,
      categoryTags: categoryTags ?? this.categoryTags,
      searchKeywords: searchKeywords ?? this.searchKeywords,
      imageFrontUrl: imageFrontUrl ?? this.imageFrontUrl,
      imageFrontStoragePath:
          imageFrontStoragePath ?? this.imageFrontStoragePath,
      imageIngredientsUrl: imageIngredientsUrl ?? this.imageIngredientsUrl,
      imageNutritionUrl: imageNutritionUrl ?? this.imageNutritionUrl,
      ingredientsText: ingredientsText ?? this.ingredientsText,
      nutritionJson: nutritionJson ?? this.nutritionJson,
      source: source ?? this.source,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      rawSourcePayload: rawSourcePayload ?? this.rawSourcePayload,
      nameSource: nameSource ?? this.nameSource,
      brandSource: brandSource ?? this.brandSource,
      imageSource: imageSource ?? this.imageSource,
      ingredientsSource: ingredientsSource ?? this.ingredientsSource,
      nutritionSource: nutritionSource ?? this.nutritionSource,
      categorySource: categorySource ?? this.categorySource,
      qualityScore: qualityScore ?? this.qualityScore,
      missingFields: missingFields ?? this.missingFields,
      status: status ?? this.status,
      adminNotes: adminNotes ?? this.adminNotes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static List<String>? _stringList(dynamic value) {
    if (value is! List) return null;
    return value.map((e) => e.toString()).toList();
  }

  static Map<String, dynamic>? _mapOrNull(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}
