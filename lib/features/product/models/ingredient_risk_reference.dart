class IngredientRiskReference {
  IngredientRiskReference({
    required this.authority,
    required this.title,
    required this.url,
    required this.accessedAt,
    this.documentCode,
    this.note,
  });

  final String authority;
  final String title;
  final String url;
  final DateTime accessedAt;
  final String? documentCode;
  final String? note;

  factory IngredientRiskReference.fromJson(Map<String, dynamic> json) {
    return IngredientRiskReference(
      authority: json['authority'] as String,
      title: json['title'] as String,
      url: json['url'] as String,
      accessedAt: DateTime.parse(json['accessed_at'] as String),
      documentCode: json['document_code'] as String?,
      note: json['note'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'authority': authority,
      'title': title,
      'url': url,
      'accessed_at': accessedAt.toIso8601String(),
      'document_code': documentCode,
      'note': note,
    };
  }

  IngredientRiskReference copyWith({
    String? authority,
    String? title,
    String? url,
    DateTime? accessedAt,
    String? documentCode,
    String? note,
  }) {
    return IngredientRiskReference(
      authority: authority ?? this.authority,
      title: title ?? this.title,
      url: url ?? this.url,
      accessedAt: accessedAt ?? this.accessedAt,
      documentCode: documentCode ?? this.documentCode,
      note: note ?? this.note,
    );
  }

  String toDisplayString() {
    final buffer = StringBuffer('$authority — $title');
    final code = documentCode?.trim();
    if (code != null && code.isNotEmpty) {
      buffer.write(' ($code)');
    }
    return buffer.toString();
  }
}
