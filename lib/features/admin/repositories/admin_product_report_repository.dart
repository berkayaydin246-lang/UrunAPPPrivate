import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:food_analyzer_app/core/services/supabase_service.dart';
import 'package:food_analyzer_app/features/admin/models/admin_product_report_cursor.dart';
import 'package:food_analyzer_app/features/admin/models/admin_product_report_detail.dart';
import 'package:food_analyzer_app/features/admin/models/admin_product_report_page.dart';
import 'package:food_analyzer_app/features/product_reports/models/product_report_status.dart';

// ── Failure types ─────────────────────────────────────────────────────────────

enum AdminReportFailureType {
  notAuthenticated,
  notAuthorized,
  reportNotFound,
  invalidTransition,
  invalidRequest,
  networkFailure,
  unknown,
}

class AdminProductReportException implements Exception {
  final AdminReportFailureType type;
  final String userMessage;

  const AdminProductReportException({
    required this.type,
    required this.userMessage,
  });

  @override
  String toString() => 'AdminProductReportException(type: $type)';
}

// ── Injectables (for tests) ───────────────────────────────────────────────────

typedef AdminReportRpcInvoker =
    Future<dynamic> Function(String functionName, Map<String, dynamic> params);

/// Returns true when a valid auth session is present. Injected in tests to
/// avoid touching the real Supabase client.
typedef AdminSessionChecker = bool Function();

// ── Interface ─────────────────────────────────────────────────────────────────

abstract interface class AdminProductReportRepository {
  /// Returns one page of reports. Pass a [cursor] from a previous page to
  /// continue; omit it to start from the newest report.
  ///
  /// Changing [status] resets pagination — always start with cursor = null
  /// when the filter changes.
  Future<AdminProductReportPage> listReports({
    ProductReportStatus? status,
    int limit = 30,
    AdminProductReportCursor? cursor,
  });

  /// Returns the full detail for a single report.
  Future<AdminProductReportDetail> getReport(String reportId);

  /// Updates status and/or admin note, then returns the updated detail.
  Future<AdminProductReportDetail> updateReport({
    required String reportId,
    required ProductReportStatus status,
    String? adminNote,
  });
}

// ── Provider ──────────────────────────────────────────────────────────────────

final adminProductReportRepositoryProvider =
    Provider<AdminProductReportRepository>((ref) {
      return SupabaseAdminProductReportRepository();
    });

// ── Supabase implementation ───────────────────────────────────────────────────

class SupabaseAdminProductReportRepository
    implements AdminProductReportRepository {
  SupabaseAdminProductReportRepository({
    AdminReportRpcInvoker? rpcInvoker,
    AdminSessionChecker? sessionChecker,
  }) : _rpcInvoker = rpcInvoker ?? _defaultRpcInvoker,
       _sessionChecker = sessionChecker ?? _defaultSessionChecker;

  final AdminReportRpcInvoker _rpcInvoker;
  final AdminSessionChecker _sessionChecker;

  static const _listRpc = 'admin_list_product_reports';
  static const _getRpc = 'admin_get_product_report';
  static const _updateRpc = 'admin_update_product_report';

  static const int _maxAdminNoteLength = 2000;

  @override
  Future<AdminProductReportPage> listReports({
    ProductReportStatus? status,
    int limit = 30,
    AdminProductReportCursor? cursor,
  }) async {
    _requireAuthenticated();

    final clampedLimit = limit.clamp(1, 100);

    try {
      final response = await _rpcInvoker(_listRpc, {
        'p_status': status?.databaseValue,
        'p_limit': clampedLimit,
        'p_before_created_at': cursor?.createdAtIso,
        'p_before_id': cursor?.id,
      });

      final jsonArray = response as List<dynamic>;
      return AdminProductReportPage.fromJsonArray(
        jsonArray,
        requestedLimit: clampedLimit,
      );
    } on AdminProductReportException {
      rethrow;
    } on PostgrestException catch (e) {
      throw _mapPostgrest(e);
    } on SocketException {
      throw _networkFailure();
    } on HttpException {
      throw _networkFailure();
    } on TimeoutException {
      throw _networkFailure();
    } catch (_) {
      throw _unknownFailure();
    }
  }

  @override
  Future<AdminProductReportDetail> getReport(String reportId) async {
    _requireAuthenticated();

    try {
      final response = await _rpcInvoker(_getRpc, {'p_report_id': reportId});

      return AdminProductReportDetail.fromJson(
        response as Map<String, dynamic>,
      );
    } on AdminProductReportException {
      rethrow;
    } on PostgrestException catch (e) {
      throw _mapPostgrest(e);
    } on SocketException {
      throw _networkFailure();
    } on HttpException {
      throw _networkFailure();
    } on TimeoutException {
      throw _networkFailure();
    } catch (_) {
      throw _unknownFailure();
    }
  }

  @override
  Future<AdminProductReportDetail> updateReport({
    required String reportId,
    required ProductReportStatus status,
    String? adminNote,
  }) async {
    _requireAuthenticated();

    final trimmedNote = adminNote?.trim();
    if (trimmedNote != null && trimmedNote.length > _maxAdminNoteLength) {
      throw const AdminProductReportException(
        type: AdminReportFailureType.invalidRequest,
        userMessage: 'Admin notu 2000 karakterden uzun olamaz.',
      );
    }

    try {
      final response = await _rpcInvoker(_updateRpc, {
        'p_report_id': reportId,
        'p_status': status.databaseValue,
        'p_admin_note': trimmedNote?.isEmpty == true ? null : trimmedNote,
      });

      return AdminProductReportDetail.fromJson(
        response as Map<String, dynamic>,
      );
    } on AdminProductReportException {
      rethrow;
    } on PostgrestException catch (e) {
      throw _mapPostgrest(e);
    } on SocketException {
      throw _networkFailure();
    } on HttpException {
      throw _networkFailure();
    } on TimeoutException {
      throw _networkFailure();
    } catch (_) {
      throw _unknownFailure();
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  void _requireAuthenticated() {
    if (!_sessionChecker()) {
      throw const AdminProductReportException(
        type: AdminReportFailureType.notAuthenticated,
        userMessage: 'Bu işlem için oturum açman gerekiyor.',
      );
    }
  }

  static bool _defaultSessionChecker() =>
      SupabaseService.client.auth.currentSession != null;

  AdminProductReportException _mapPostgrest(PostgrestException error) {
    final msg = error.message.trim();
    if (msg == 'not_authorized' || error.code == '42501') {
      return const AdminProductReportException(
        type: AdminReportFailureType.notAuthorized,
        userMessage: 'Bu işlem için yetkin yok.',
      );
    }
    if (msg == 'report_not_found') {
      return const AdminProductReportException(
        type: AdminReportFailureType.reportNotFound,
        userMessage: 'Bildirim bulunamadı.',
      );
    }
    if (msg == 'invalid_status_transition') {
      return const AdminProductReportException(
        type: AdminReportFailureType.invalidTransition,
        userMessage: 'Bu durum değişikliği geçerli değil.',
      );
    }
    if (msg == 'invalid_status' ||
        msg == 'admin_note_too_long' ||
        msg == 'invalid_status_transition') {
      return const AdminProductReportException(
        type: AdminReportFailureType.invalidRequest,
        userMessage: 'İstek geçersiz. Lütfen tekrar dene.',
      );
    }
    return _unknownFailure();
  }

  static AdminProductReportException _networkFailure() {
    return const AdminProductReportException(
      type: AdminReportFailureType.networkFailure,
      userMessage: 'Bağlantı kurulamadı. İnternetini kontrol edip tekrar dene.',
    );
  }

  static AdminProductReportException _unknownFailure() {
    return const AdminProductReportException(
      type: AdminReportFailureType.unknown,
      userMessage: 'Bir hata oluştu. Biraz sonra tekrar dene.',
    );
  }

  static Future<dynamic> _defaultRpcInvoker(
    String functionName,
    Map<String, dynamic> params,
  ) {
    return SupabaseService.client.rpc(functionName, params: params);
  }
}
