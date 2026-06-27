import 'dart:async';

import 'package:food_analyzer_app/features/admin/models/admin_product_report_cursor.dart';
import 'package:food_analyzer_app/features/admin/models/admin_product_report_detail.dart';
import 'package:food_analyzer_app/features/admin/models/admin_product_report_page.dart';
import 'package:food_analyzer_app/features/admin/models/admin_product_report_summary.dart';
import 'package:food_analyzer_app/features/admin/models/current_product_snapshot.dart';
import 'package:food_analyzer_app/features/admin/repositories/admin_auth_repository.dart';
import 'package:food_analyzer_app/features/admin/repositories/admin_product_report_repository.dart';
import 'package:food_analyzer_app/features/product_reports/models/product_report_status.dart';
import 'package:food_analyzer_app/features/product_reports/models/product_report_type.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Session fakeSession({
  String userId = 'admin-user-id',
  String email = 'admin@freshscan.test',
  Map<String, dynamic> appMetadata = const {'role': 'admin'},
}) {
  return Session.fromJson({
    'access_token': 'test-access-token',
    'token_type': 'bearer',
    'refresh_token': 'test-refresh-token',
    'user': {
      'id': userId,
      'aud': 'authenticated',
      'email': email,
      'created_at': '2026-06-26T00:00:00.000Z',
      'app_metadata': appMetadata,
      'user_metadata': const <String, dynamic>{},
    },
  })!;
}

class FakeAdminAuthRepository implements AdminAuthRepository {
  FakeAdminAuthRepository({
    Session? currentSession,
    this.verifyResult = true,
    this.signInError,
    this.verifyError,
    this.emitSessionChangeOnSignIn = true,
  }) : _currentSession = currentSession;

  final _controller = StreamController<Session?>.broadcast();

  Session? _currentSession;
  bool verifyResult;
  Object? signInError;
  Object? verifyError;
  bool emitSessionChangeOnSignIn;

  var signInCallCount = 0;
  var signOutCallCount = 0;
  var verifyCallCount = 0;
  String? lastEmail;
  String? lastPassword;

  @override
  Session? get currentSession => _currentSession;

  @override
  Stream<Session?> get authStateChanges => _controller.stream;

  @override
  Future<void> signIn({required String email, required String password}) async {
    signInCallCount++;
    lastEmail = email;
    lastPassword = password;

    if (signInError != null) {
      throw signInError!;
    }

    _currentSession = fakeSession(email: email);
    if (emitSessionChangeOnSignIn) {
      _controller.add(_currentSession);
    }
  }

  @override
  Future<void> signOut() async {
    signOutCallCount++;
    _currentSession = null;
    _controller.add(null);
  }

  @override
  Future<bool> verifyAdminAuthorization() async {
    verifyCallCount++;
    if (verifyError != null) {
      throw verifyError!;
    }

    return verifyResult;
  }

  Future<void> emitSession(Session? session) async {
    _currentSession = session;
    _controller.add(session);
  }

  void dispose() {
    unawaited(_controller.close());
  }
}

typedef FakeListReportsHandler =
    Future<AdminProductReportPage> Function({
      ProductReportStatus? status,
      int limit,
      AdminProductReportCursor? cursor,
    });

typedef FakeGetReportHandler =
    Future<AdminProductReportDetail> Function(String reportId);

typedef FakeUpdateReportHandler =
    Future<AdminProductReportDetail> Function({
      required String reportId,
      required ProductReportStatus status,
      String? adminNote,
    });

class ListReportsCall {
  const ListReportsCall({
    required this.status,
    required this.limit,
    required this.cursor,
  });

  final ProductReportStatus? status;
  final int limit;
  final AdminProductReportCursor? cursor;
}

class UpdateReportCall {
  const UpdateReportCall({
    required this.reportId,
    required this.status,
    required this.adminNote,
  });

  final String reportId;
  final ProductReportStatus status;
  final String? adminNote;
}

class FakeAdminProductReportRepository implements AdminProductReportRepository {
  FakeAdminProductReportRepository({
    FakeListReportsHandler? listHandler,
    FakeGetReportHandler? getHandler,
    FakeUpdateReportHandler? updateHandler,
  }) : _listHandler = listHandler,
       _getHandler = getHandler,
       _updateHandler = updateHandler;

  final FakeListReportsHandler? _listHandler;
  final FakeGetReportHandler? _getHandler;
  final FakeUpdateReportHandler? _updateHandler;

  final listCalls = <ListReportsCall>[];
  final getCalls = <String>[];
  final updateCalls = <UpdateReportCall>[];

  @override
  Future<AdminProductReportPage> listReports({
    ProductReportStatus? status,
    int limit = 30,
    AdminProductReportCursor? cursor,
  }) async {
    listCalls.add(
      ListReportsCall(status: status, limit: limit, cursor: cursor),
    );
    final handler = _listHandler;
    if (handler == null) {
      throw UnimplementedError('Fake listReports handler not provided.');
    }

    return handler(status: status, limit: limit, cursor: cursor);
  }

  @override
  Future<AdminProductReportDetail> getReport(String reportId) async {
    getCalls.add(reportId);
    final handler = _getHandler;
    if (handler == null) {
      throw UnimplementedError('Fake getReport handler not provided.');
    }

    return handler(reportId);
  }

  @override
  Future<AdminProductReportDetail> updateReport({
    required String reportId,
    required ProductReportStatus status,
    String? adminNote,
  }) async {
    updateCalls.add(
      UpdateReportCall(
        reportId: reportId,
        status: status,
        adminNote: adminNote,
      ),
    );
    final handler = _updateHandler;
    if (handler == null) {
      throw UnimplementedError('Fake updateReport handler not provided.');
    }

    return handler(reportId: reportId, status: status, adminNote: adminNote);
  }
}

AdminProductReportSummary makeReportSummary({
  String id = 'report-1',
  String? productId = 'product-1',
  String productNameSnapshot = 'Test Ürünü',
  String? productBrandSnapshot = 'Test Marka',
  String? productImageSnapshot = 'https://img.example.test/report-1.png',
  ProductReportType type = ProductReportType.wrongImage,
  String? details = 'Kullanıcı açıklaması',
  int evidenceImageCount = 0,
  ProductReportStatus status = ProductReportStatus.pending,
  DateTime? createdAt,
  DateTime? reviewedAt,
  CurrentProductSnapshot? currentProduct,
}) {
  return AdminProductReportSummary(
    id: id,
    productId: productId,
    productNameSnapshot: productNameSnapshot,
    productBrandSnapshot: productBrandSnapshot,
    productImageSnapshot: productImageSnapshot,
    type: type,
    details: details,
    evidenceImageCount: evidenceImageCount,
    status: status,
    createdAt: createdAt ?? DateTime.utc(2026, 6, 26, 10),
    reviewedAt: reviewedAt,
    currentProduct: currentProduct,
  );
}

AdminProductReportDetail makeReportDetail({
  String id = 'report-1',
  String? productId = 'product-1',
  String productNameSnapshot = 'Test Ürünü',
  String? productBrandSnapshot = 'Test Marka',
  String? productImageSnapshot = 'https://img.example.test/report-1.png',
  ProductReportType type = ProductReportType.wrongImage,
  String? details = 'Kullanıcı açıklaması',
  List<String> evidenceImageUrls = const <String>[],
  int? evidenceImageCount,
  ProductReportStatus status = ProductReportStatus.pending,
  String? adminNote,
  DateTime? createdAt,
  DateTime? reviewedAt,
  String? reviewedBy,
  CurrentProductSnapshot? currentProduct = const CurrentProductSnapshot(
    name: 'Katalog Ürünü',
    brand: 'Katalog Marka',
    imageUrl: 'https://img.example.test/current.png',
    barcode: '1234567890123',
  ),
}) {
  return AdminProductReportDetail(
    id: id,
    productId: productId,
    productNameSnapshot: productNameSnapshot,
    productBrandSnapshot: productBrandSnapshot,
    productImageSnapshot: productImageSnapshot,
    type: type,
    details: details,
    evidenceImageUrls: evidenceImageUrls,
    evidenceImageCount: evidenceImageCount ?? evidenceImageUrls.length,
    status: status,
    adminNote: adminNote,
    createdAt: createdAt ?? DateTime.utc(2026, 6, 26, 10),
    reviewedAt: reviewedAt,
    reviewedBy: reviewedBy,
    currentProduct: currentProduct,
  );
}

Future<void> flushMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
