/// Workflow status for a submitted product report.
///
/// Values are stable across versions — never rename or remove them without
/// a coordinated database migration.
enum ProductReportStatus {
  pending,
  reviewing,
  resolved,
  rejected;

  /// The snake_case value stored in the `product_reports.status` column.
  String get databaseValue => name;

  /// Turkish display label for admin and consumer-facing surfaces.
  String get labelTr => switch (this) {
    ProductReportStatus.pending => 'Bekliyor',
    ProductReportStatus.reviewing => 'İnceleniyor',
    ProductReportStatus.resolved => 'Çözüldü',
    ProductReportStatus.rejected => 'Reddedildi',
  };

  /// Maps a raw database string to the enum, or returns null for unknown values.
  static ProductReportStatus? tryFromDatabase(String? rawValue) {
    final normalized = rawValue?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    for (final status in ProductReportStatus.values) {
      if (status.databaseValue == normalized) return status;
    }
    return null;
  }

  /// Like [tryFromDatabase] but throws [ArgumentError] for unknown values.
  static ProductReportStatus fromDatabase(String rawValue) {
    final result = tryFromDatabase(rawValue);
    if (result == null) {
      throw ArgumentError.value(
        rawValue,
        'rawValue',
        'Unknown ProductReportStatus database value',
      );
    }
    return result;
  }
}

extension ProductReportStatusX on ProductReportStatus {
  /// Whether this status represents a terminal reviewed state.
  bool get isReviewed =>
      this == ProductReportStatus.resolved ||
      this == ProductReportStatus.rejected;

  /// Whether the report is awaiting initial admin attention.
  bool get isOpen =>
      this == ProductReportStatus.pending ||
      this == ProductReportStatus.reviewing;

  /// Valid next states for admin status actions.
  List<ProductReportStatus> get validAdminTransitions => switch (this) {
    ProductReportStatus.pending => const [
      ProductReportStatus.reviewing,
      ProductReportStatus.resolved,
      ProductReportStatus.rejected,
    ],
    ProductReportStatus.reviewing => const [
      ProductReportStatus.pending,
      ProductReportStatus.resolved,
      ProductReportStatus.rejected,
    ],
    ProductReportStatus.resolved => const [ProductReportStatus.reviewing],
    ProductReportStatus.rejected => const [ProductReportStatus.reviewing],
  };

  bool canAdminTransitionTo(ProductReportStatus target) {
    return validAdminTransitions.contains(target);
  }

  String adminActionLabelFor(ProductReportStatus target) {
    return switch ((this, target)) {
      (ProductReportStatus.pending, ProductReportStatus.reviewing) =>
        'İncelemeye al',
      (ProductReportStatus.pending, ProductReportStatus.resolved) =>
        'Çözüldü olarak işaretle',
      (ProductReportStatus.pending, ProductReportStatus.rejected) => 'Reddet',
      (ProductReportStatus.reviewing, ProductReportStatus.pending) =>
        'Beklemeye al',
      (ProductReportStatus.reviewing, ProductReportStatus.resolved) =>
        'Çözüldü olarak işaretle',
      (ProductReportStatus.reviewing, ProductReportStatus.rejected) => 'Reddet',
      (ProductReportStatus.resolved, ProductReportStatus.reviewing) =>
        'Yeniden incelemeye al',
      (ProductReportStatus.rejected, ProductReportStatus.reviewing) =>
        'Yeniden incelemeye al',
      _ => throw ArgumentError(
        'Invalid admin transition from $this to $target',
      ),
    };
  }
}
