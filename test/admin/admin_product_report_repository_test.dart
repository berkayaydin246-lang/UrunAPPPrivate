import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:food_analyzer_app/features/admin/models/admin_product_report_cursor.dart';
import 'package:food_analyzer_app/features/admin/models/admin_product_report_detail.dart';
import 'package:food_analyzer_app/features/admin/models/admin_product_report_page.dart';
import 'package:food_analyzer_app/features/admin/models/admin_product_report_summary.dart';
import 'package:food_analyzer_app/features/admin/models/current_product_snapshot.dart';
import 'package:food_analyzer_app/features/admin/repositories/admin_product_report_repository.dart';
import 'package:food_analyzer_app/features/product_reports/models/product_report_status.dart';
import 'package:food_analyzer_app/features/product_reports/models/product_report_type.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _kReportId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _kProductId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _kUserId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

Map<String, dynamic> _summaryJson({
  String id = _kReportId,
  String status = 'pending',
  String reportType = 'wrong_image',
  String? reviewedAt,
  String? currentProductName,
}) {
  return {
    'id': id,
    'product_id': _kProductId,
    'product_name_snapshot': 'Test Ürünü',
    'product_brand_snapshot': 'Test Marka',
    'product_image_snapshot': null,
    'report_type': reportType,
    'details': null,
    'evidence_image_count': 0,
    'status': status,
    'created_at': '2026-06-26T10:00:00.000Z',
    'reviewed_at': reviewedAt,
    'current_product_name': currentProductName,
    'current_product_brand': null,
    'current_product_image_url': null,
  };
}

Map<String, dynamic> _detailJson({
  String id = _kReportId,
  String status = 'pending',
  String? adminNote,
  String? reviewedBy,
  String? reviewedAt,
  List<String> evidenceImageUrls = const [],
  String? currentProductBarcode,
}) {
  return {
    ..._summaryJson(id: id, status: status),
    'evidence_image_urls': evidenceImageUrls,
    'admin_note': adminNote,
    'reviewed_by': reviewedBy,
    'reviewed_at': reviewedAt,
    'current_product_barcode': currentProductBarcode,
  };
}

// ── Fake RPC invoker ──────────────────────────────────────────────────────────

class _FakeInvoker {
  _FakeInvoker({
    required Future<dynamic> Function(Map<String, dynamic>) handler,
  }) : _handler = handler;

  final Future<dynamic> Function(Map<String, dynamic>) _handler;
  String? lastFunctionName;
  Map<String, dynamic>? lastParams;
  var callCount = 0;

  factory _FakeInvoker.returningList(List<Map<String, dynamic>> rows) =>
      _FakeInvoker(handler: (_) async => rows);

  factory _FakeInvoker.returningDetail(Map<String, dynamic> json) =>
      _FakeInvoker(handler: (_) async => json);

  factory _FakeInvoker.throwingPostgrest(String message, {String? code}) =>
      _FakeInvoker(
        handler: (_) async => throw PostgrestException(
          message: message,
          code: code,
          details: '',
          hint: '',
        ),
      );

  factory _FakeInvoker.throwingSocket() => _FakeInvoker(
    handler: (_) async => throw const SocketException('no route'),
  );

  Future<dynamic> call(String name, Map<String, dynamic> params) {
    callCount++;
    lastFunctionName = name;
    lastParams = params;
    return _handler(params);
  }
}

/// Builds a repo that skips the real Supabase session check.
SupabaseAdminProductReportRepository _repoSkipAuth(_FakeInvoker invoker) =>
    SupabaseAdminProductReportRepository(
      rpcInvoker: invoker.call,
      sessionChecker: () => true,
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── 1. Status enum — mappings and Turkish labels ───────────────────────────

  group('ProductReportStatus', () {
    test('has 4 values: pending, reviewing, resolved, rejected', () {
      expect(ProductReportStatus.values, hasLength(4));
    });

    test('databaseValue is stable snake_case', () {
      expect(ProductReportStatus.pending.databaseValue, 'pending');
      expect(ProductReportStatus.reviewing.databaseValue, 'reviewing');
      expect(ProductReportStatus.resolved.databaseValue, 'resolved');
      expect(ProductReportStatus.rejected.databaseValue, 'rejected');
    });

    test('labelTr values match the centralized Turkish spec', () {
      expect(ProductReportStatus.pending.labelTr, 'Bekliyor');
      expect(ProductReportStatus.reviewing.labelTr, 'İnceleniyor');
      expect(ProductReportStatus.resolved.labelTr, 'Çözüldü');
      expect(ProductReportStatus.rejected.labelTr, 'Reddedildi');
    });

    test('fromDatabase round-trips all values', () {
      for (final s in ProductReportStatus.values) {
        expect(ProductReportStatus.fromDatabase(s.databaseValue), s);
      }
    });

    test('tryFromDatabase returns null for unknown value', () {
      expect(ProductReportStatus.tryFromDatabase('unknown_status'), isNull);
    });

    test('tryFromDatabase returns null for empty string', () {
      expect(ProductReportStatus.tryFromDatabase(''), isNull);
    });

    test('fromDatabase throws for unknown value', () {
      expect(
        () => ProductReportStatus.fromDatabase('bogus'),
        throwsArgumentError,
      );
    });

    test('isReviewed is true for resolved and rejected only', () {
      expect(ProductReportStatus.resolved.isReviewed, isTrue);
      expect(ProductReportStatus.rejected.isReviewed, isTrue);
      expect(ProductReportStatus.pending.isReviewed, isFalse);
      expect(ProductReportStatus.reviewing.isReviewed, isFalse);
    });

    test('isOpen is true for pending and reviewing only', () {
      expect(ProductReportStatus.pending.isOpen, isTrue);
      expect(ProductReportStatus.reviewing.isOpen, isTrue);
      expect(ProductReportStatus.resolved.isOpen, isFalse);
      expect(ProductReportStatus.rejected.isOpen, isFalse);
    });
  });

  // ── 2. Summary model mapping ──────────────────────────────────────────────

  group('AdminProductReportSummary.fromJson', () {
    test('maps all summary fields from JSON', () {
      final s = AdminProductReportSummary.fromJson(_summaryJson());
      expect(s.id, _kReportId);
      expect(s.productId, _kProductId);
      expect(s.productNameSnapshot, 'Test Ürünü');
      expect(s.productBrandSnapshot, 'Test Marka');
      expect(s.type, ProductReportType.wrongImage);
      expect(s.evidenceImageCount, 0);
      expect(s.status, ProductReportStatus.pending);
      expect(s.createdAt, DateTime.utc(2026, 6, 26, 10));
      expect(s.reviewedAt, isNull);
    });

    test('nullable fields are safe when absent', () {
      final json = _summaryJson()
        ..['product_brand_snapshot'] = null
        ..['product_image_snapshot'] = null
        ..['details'] = null
        ..['reviewed_at'] = null;
      final s = AdminProductReportSummary.fromJson(json);
      expect(s.productBrandSnapshot, isNull);
      expect(s.productImageSnapshot, isNull);
      expect(s.details, isNull);
      expect(s.reviewedAt, isNull);
    });

    test('currentProduct is non-null when current_product_name is present', () {
      final s = AdminProductReportSummary.fromJson(
        _summaryJson(currentProductName: 'Gerçek Adı'),
      );
      expect(s.currentProduct, isNotNull);
      expect(s.currentProduct!.name, 'Gerçek Adı');
    });

    test(
      'currentProduct is null when all current-product fields are absent',
      () {
        final s = AdminProductReportSummary.fromJson(_summaryJson());
        expect(s.currentProduct, isNull);
      },
    );
  });

  // ── 3. Detail model mapping ───────────────────────────────────────────────

  group('AdminProductReportDetail.fromJson', () {
    test('maps all detail fields from JSON', () {
      final d = AdminProductReportDetail.fromJson(
        _detailJson(
          status: 'reviewing',
          adminNote: 'Kontrol edildi',
          reviewedBy: _kUserId,
          reviewedAt: '2026-06-26T12:00:00.000Z',
          evidenceImageUrls: ['https://img.example.test/a.jpg'],
          currentProductBarcode: '1234567890123',
        ),
      );
      expect(d.status, ProductReportStatus.reviewing);
      expect(d.adminNote, 'Kontrol edildi');
      expect(d.reviewedBy, _kUserId);
      expect(d.reviewedAt, DateTime.utc(2026, 6, 26, 12));
      expect(d.evidenceImageUrls, ['https://img.example.test/a.jpg']);
      expect(d.currentProduct?.barcode, '1234567890123');
    });

    test('optional detail fields are safe when absent', () {
      final d = AdminProductReportDetail.fromJson(_detailJson());
      expect(d.adminNote, isNull);
      expect(d.reviewedBy, isNull);
      expect(d.reviewedAt, isNull);
      expect(d.evidenceImageUrls, isEmpty);
      expect(d.currentProduct, isNull);
    });

    test('evidenceImageUrls filters empty strings from the DB array', () {
      final json = _detailJson(
        evidenceImageUrls: ['https://ok.test/a.jpg', ''],
      );
      final d = AdminProductReportDetail.fromJson(json);
      expect(d.evidenceImageUrls, ['https://ok.test/a.jpg']);
    });

    test('unknown report_type raises FormatException', () {
      final json = _detailJson()..['report_type'] = 'unknown_type';
      expect(
        () => AdminProductReportDetail.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('unknown status raises FormatException', () {
      final json = _detailJson()..['status'] = 'unknown_status';
      expect(
        () => AdminProductReportDetail.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });
  });

  // ── 4. Cursor mapping ─────────────────────────────────────────────────────

  group('AdminProductReportCursor', () {
    test('fromSummary copies createdAt and id from the summary', () {
      final s = AdminProductReportSummary.fromJson(_summaryJson());
      final cursor = AdminProductReportCursor.fromSummary(s);
      expect(cursor.id, s.id);
      expect(cursor.createdAt, s.createdAt);
    });

    test('createdAtIso returns UTC ISO-8601 string', () {
      final cursor = AdminProductReportCursor(
        createdAt: DateTime.utc(2026, 6, 26, 10),
        id: _kReportId,
      );
      expect(cursor.createdAtIso, '2026-06-26T10:00:00.000Z');
    });

    test('equality is value-based', () {
      final a = AdminProductReportCursor(
        createdAt: DateTime.utc(2026, 6, 26, 10),
        id: _kReportId,
      );
      final b = AdminProductReportCursor(
        createdAt: DateTime.utc(2026, 6, 26, 10),
        id: _kReportId,
      );
      expect(a, equals(b));
    });
  });

  // ── 5. Page model and cursor computation ──────────────────────────────────

  group('AdminProductReportPage', () {
    test('nextCursor is non-null when reports.length == requestedLimit', () {
      final rows = [_summaryJson(id: 'id-a'), _summaryJson(id: 'id-b')];
      final page = AdminProductReportPage.fromJsonArray(
        rows,
        requestedLimit: 2,
      );
      expect(page.nextCursor, isNotNull);
      expect(page.nextCursor!.id, 'id-b');
    });

    test('nextCursor is null when fewer reports than limit (last page)', () {
      final rows = [_summaryJson()];
      final page = AdminProductReportPage.fromJsonArray(
        rows,
        requestedLimit: 30,
      );
      expect(page.nextCursor, isNull);
    });

    test('nextCursor is null for empty result', () {
      final page = AdminProductReportPage.fromJsonArray([], requestedLimit: 30);
      expect(page.nextCursor, isNull);
      expect(page.isEmpty, isTrue);
    });

    test('hasNextPage reflects cursor presence', () {
      final withNext = AdminProductReportPage.fromJsonArray([
        _summaryJson(),
      ], requestedLimit: 1);
      final withoutNext = AdminProductReportPage.fromJsonArray([
        _summaryJson(),
      ], requestedLimit: 30);
      expect(withNext.hasNextPage, isTrue);
      expect(withoutNext.hasNextPage, isFalse);
    });
  });

  // ── 6. Repository — correct RPC names and parameters ──────────────────────

  group('SupabaseAdminProductReportRepository — listReports', () {
    test('calls admin_list_product_reports RPC', () async {
      final invoker = _FakeInvoker.returningList([]);
      await _repoSkipAuth(invoker).listReports();
      expect(invoker.lastFunctionName, 'admin_list_product_reports');
    });

    test('passes null p_status when no filter', () async {
      final invoker = _FakeInvoker.returningList([]);
      await _repoSkipAuth(invoker).listReports();
      expect(invoker.lastParams!['p_status'], isNull);
    });

    test('passes correct p_status for status filter', () async {
      final invoker = _FakeInvoker.returningList([]);
      await _repoSkipAuth(
        invoker,
      ).listReports(status: ProductReportStatus.reviewing);
      expect(invoker.lastParams!['p_status'], 'reviewing');
    });

    test('passes cursor p_before_created_at and p_before_id', () async {
      final invoker = _FakeInvoker.returningList([]);
      final cursor = AdminProductReportCursor(
        createdAt: DateTime.utc(2026, 6, 26, 10),
        id: _kReportId,
      );
      await _repoSkipAuth(invoker).listReports(cursor: cursor);
      expect(invoker.lastParams!['p_before_created_at'], cursor.createdAtIso);
      expect(invoker.lastParams!['p_before_id'], cursor.id);
    });

    test('clamps limit to maximum 100', () async {
      final invoker = _FakeInvoker.returningList([]);
      await _repoSkipAuth(invoker).listReports(limit: 999);
      expect(invoker.lastParams!['p_limit'], 100);
    });

    test('clamps limit to minimum 1', () async {
      final invoker = _FakeInvoker.returningList([]);
      await _repoSkipAuth(invoker).listReports(limit: 0);
      expect(invoker.lastParams!['p_limit'], 1);
    });
  });

  group('SupabaseAdminProductReportRepository — getReport', () {
    test('calls admin_get_product_report RPC with the report ID', () async {
      final invoker = _FakeInvoker.returningDetail(_detailJson());
      await _repoSkipAuth(invoker).getReport(_kReportId);
      expect(invoker.lastFunctionName, 'admin_get_product_report');
      expect(invoker.lastParams!['p_report_id'], _kReportId);
    });

    test('returns a populated AdminProductReportDetail', () async {
      final invoker = _FakeInvoker.returningDetail(
        _detailJson(status: 'reviewing'),
      );
      final detail = await _repoSkipAuth(invoker).getReport(_kReportId);
      expect(detail.id, _kReportId);
      expect(detail.status, ProductReportStatus.reviewing);
    });
  });

  group('SupabaseAdminProductReportRepository — updateReport', () {
    test('calls admin_update_product_report RPC with correct params', () async {
      final invoker = _FakeInvoker.returningDetail(
        _detailJson(status: 'reviewing'),
      );
      await _repoSkipAuth(invoker).updateReport(
        reportId: _kReportId,
        status: ProductReportStatus.reviewing,
        adminNote: 'İnceleniyor',
      );
      expect(invoker.lastFunctionName, 'admin_update_product_report');
      expect(invoker.lastParams!['p_report_id'], _kReportId);
      expect(invoker.lastParams!['p_status'], 'reviewing');
      expect(invoker.lastParams!['p_admin_note'], 'İnceleniyor');
    });

    test('trims admin note before sending', () async {
      final invoker = _FakeInvoker.returningDetail(_detailJson());
      await _repoSkipAuth(invoker).updateReport(
        reportId: _kReportId,
        status: ProductReportStatus.pending,
        adminNote: '  notu ile  ',
      );
      expect(invoker.lastParams!['p_admin_note'], 'notu ile');
    });

    test('sends null p_admin_note when note is blank', () async {
      final invoker = _FakeInvoker.returningDetail(_detailJson());
      await _repoSkipAuth(invoker).updateReport(
        reportId: _kReportId,
        status: ProductReportStatus.pending,
        adminNote: '   ',
      );
      expect(invoker.lastParams!['p_admin_note'], isNull);
    });

    test('rejects admin notes over 2000 characters before RPC', () async {
      final invoker = _FakeInvoker.returningDetail(_detailJson());
      expect(
        () => _repoSkipAuth(invoker).updateReport(
          reportId: _kReportId,
          status: ProductReportStatus.pending,
          adminNote: 'a' * 2001,
        ),
        throwsA(
          isA<AdminProductReportException>().having(
            (e) => e.type,
            'type',
            AdminReportFailureType.invalidRequest,
          ),
        ),
      );
      // RPC must not have been called
      expect(invoker.callCount, 0);
    });

    test('accepts admin notes of exactly 2000 characters', () async {
      final invoker = _FakeInvoker.returningDetail(_detailJson());
      await _repoSkipAuth(invoker).updateReport(
        reportId: _kReportId,
        status: ProductReportStatus.pending,
        adminNote: 'a' * 2000,
      );
      expect(invoker.callCount, 1);
    });
  });

  // ── 7. Only RPCs are used — no direct table queries ───────────────────────

  group('repository uses only RPCs', () {
    test('listReports sends exactly one RPC call', () async {
      final invoker = _FakeInvoker.returningList([]);
      await _repoSkipAuth(invoker).listReports();
      expect(invoker.callCount, 1);
    });

    test('getReport sends exactly one RPC call', () async {
      final invoker = _FakeInvoker.returningDetail(_detailJson());
      await _repoSkipAuth(invoker).getReport(_kReportId);
      expect(invoker.callCount, 1);
    });

    test('updateReport sends exactly one RPC call', () async {
      final invoker = _FakeInvoker.returningDetail(_detailJson());
      await _repoSkipAuth(invoker).updateReport(
        reportId: _kReportId,
        status: ProductReportStatus.resolved,
      );
      expect(invoker.callCount, 1);
    });
  });

  // ── 8. Error mapping — safe messages, no raw backend text ─────────────────

  group('error mapping', () {
    test(
      'not_authorized maps to notAuthorized with safe Turkish message',
      () async {
        final invoker = _FakeInvoker.throwingPostgrest('not_authorized');
        expect(
          () => _repoSkipAuth(invoker).getReport(_kReportId),
          throwsA(
            isA<AdminProductReportException>()
                .having(
                  (e) => e.type,
                  'type',
                  AdminReportFailureType.notAuthorized,
                )
                .having(
                  (e) => e.userMessage,
                  'userMessage',
                  isNot(contains('not_authorized')),
                ),
          ),
        );
      },
    );

    test('SQLSTATE 42501 maps to notAuthorized', () async {
      final invoker = _FakeInvoker.throwingPostgrest('', code: '42501');
      expect(
        () => _repoSkipAuth(invoker).getReport(_kReportId),
        throwsA(
          isA<AdminProductReportException>().having(
            (e) => e.type,
            'type',
            AdminReportFailureType.notAuthorized,
          ),
        ),
      );
    });

    test('report_not_found maps to reportNotFound with safe message', () async {
      final invoker = _FakeInvoker.throwingPostgrest('report_not_found');
      expect(
        () => _repoSkipAuth(invoker).getReport(_kReportId),
        throwsA(
          isA<AdminProductReportException>()
              .having(
                (e) => e.type,
                'type',
                AdminReportFailureType.reportNotFound,
              )
              .having(
                (e) => e.userMessage,
                'userMessage',
                isNot(contains('report_not_found')),
              ),
        ),
      );
    });

    test('invalid_status_transition maps to invalidTransition', () async {
      final invoker = _FakeInvoker.throwingPostgrest(
        'invalid_status_transition',
      );
      expect(
        () => _repoSkipAuth(invoker).updateReport(
          reportId: _kReportId,
          status: ProductReportStatus.rejected,
        ),
        throwsA(
          isA<AdminProductReportException>().having(
            (e) => e.type,
            'type',
            AdminReportFailureType.invalidTransition,
          ),
        ),
      );
    });

    test('SocketException maps to networkFailure with safe message', () async {
      final invoker = _FakeInvoker.throwingSocket();
      expect(
        () => _repoSkipAuth(invoker).listReports(),
        throwsA(
          isA<AdminProductReportException>()
              .having(
                (e) => e.type,
                'type',
                AdminReportFailureType.networkFailure,
              )
              .having(
                (e) => e.userMessage,
                'userMessage',
                isNot(contains('SocketException')),
              ),
        ),
      );
    });

    test('unknown error maps to unknown with safe message', () async {
      final invoker = _FakeInvoker(
        handler: (_) async => throw Exception('raw error'),
      );
      expect(
        () => _repoSkipAuth(invoker).getReport(_kReportId),
        throwsA(
          isA<AdminProductReportException>()
              .having((e) => e.type, 'type', AdminReportFailureType.unknown)
              .having(
                (e) => e.userMessage,
                'userMessage',
                isNot(contains('raw error')),
              ),
        ),
      );
    });

    test('raw backend text never appears in userMessage', () async {
      final invoker = _FakeInvoker.throwingPostgrest(
        'internal postgres error: constraint violation on product_reports',
      );
      try {
        await _repoSkipAuth(invoker).getReport(_kReportId);
        fail('Expected exception');
      } on AdminProductReportException catch (e) {
        expect(e.userMessage, isNot(contains('postgres')));
        expect(e.userMessage, isNot(contains('constraint')));
        expect(e.userMessage, isNot(contains('product_reports')));
      }
    });
  });

  // ── 9. CurrentProductSnapshot optional safety ─────────────────────────────

  group('CurrentProductSnapshot', () {
    test('tryFromJson returns null when all current fields are null', () {
      final json = {
        'current_product_name': null,
        'current_product_brand': null,
        'current_product_image_url': null,
        'current_product_barcode': null,
      };
      expect(CurrentProductSnapshot.tryFromJson(json), isNull);
    });

    test('tryFromJson returns snapshot when at least one field is present', () {
      final json = {
        'current_product_name': 'Coca Cola',
        'current_product_brand': null,
        'current_product_image_url': null,
        'current_product_barcode': null,
      };
      final snapshot = CurrentProductSnapshot.tryFromJson(json);
      expect(snapshot, isNotNull);
      expect(snapshot!.name, 'Coca Cola');
      expect(snapshot.brand, isNull);
    });
  });
}
