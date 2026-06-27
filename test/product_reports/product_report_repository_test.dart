import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/core/services/app_installation_id_service.dart';
import 'package:food_analyzer_app/features/product_reports/models/product_report_submission.dart';
import 'package:food_analyzer_app/features/product_reports/models/product_report_type.dart';
import 'package:food_analyzer_app/features/product_reports/repositories/product_report_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('SupabaseProductReportRepository', () {
    test('submits normalized params and returns the parsed receipt', () async {
      String? capturedFunctionName;
      Map<String, dynamic>? capturedParams;
      var submissionIdCallCount = 0;

      final repository = _buildRepository(
        rpcInvoker: (functionName, params) async {
          capturedFunctionName = functionName;
          capturedParams = params;
          return {
            'report_id': _reportId,
            'submitted_at': '2026-06-26T12:30:00Z',
          };
        },
        submissionIdGenerator: () {
          submissionIdCallCount += 1;
          return _submissionId;
        },
      );

      final receipt = await repository.submitReport(
        ProductReportSubmission(
          productId: '  $_productId  ',
          type: ProductReportType.wrongImage,
          details: '  Ön foto yanlış görünüyor.  ',
          evidenceImageUrls: const [
            '  https://cdn.example.com/front.jpg  ',
            '  ',
            'https://cdn.example.com/back.jpg',
          ],
        ),
      );

      expect(capturedFunctionName, 'submit_product_report');
      expect(capturedParams, {
        'p_product_id': _productId,
        'p_report_type': 'wrong_image',
        'p_details': 'Ön foto yanlış görünüyor.',
        'p_client_install_id': _installationId,
        'p_client_submission_id': _submissionId,
        'p_evidence_image_urls': [
          'https://cdn.example.com/front.jpg',
          'https://cdn.example.com/back.jpg',
        ],
      });
      expect(submissionIdCallCount, 1);
      expect(receipt.reportId, _reportId);
      expect(receipt.submittedAt, DateTime.parse('2026-06-26T12:30:00Z'));
    });

    test('accepts empty evidence URLs and list-shaped RPC responses', () async {
      Map<String, dynamic>? capturedParams;

      final repository = _buildRepository(
        rpcInvoker: (functionName, params) async {
          capturedParams = params;
          return [
            {'report_id': _reportId, 'submitted_at': '2026-06-26T13:00:00Z'},
          ];
        },
      );

      final receipt = await repository.submitReport(
        ProductReportSubmission(
          productId: _productId,
          type: ProductReportType.other,
        ),
      );

      expect(capturedParams?['p_details'], isNull);
      expect(capturedParams?['p_evidence_image_urls'], isEmpty);
      expect(receipt.reportId, _reportId);
      expect(receipt.submittedAt, DateTime.parse('2026-06-26T13:00:00Z'));
    });

    test('rejects details longer than 1000 characters before RPC', () async {
      var rpcCalled = false;
      final repository = _buildRepository(
        rpcInvoker: (functionName, params) async {
          rpcCalled = true;
          return {};
        },
      );

      await expectLater(
        repository.submitReport(
          ProductReportSubmission(
            productId: _productId,
            type: ProductReportType.other,
            details: 'a' * 1001,
          ),
        ),
        throwsA(
          isA<ProductReportSubmissionException>()
              .having(
                (error) => error.type,
                'type',
                ProductReportSubmissionFailureType.invalidSubmission,
              )
              .having(
                (error) => error.userMessage,
                'userMessage',
                isNot(contains('details_too_long')),
              ),
        ),
      );

      expect(rpcCalled, isFalse);
    });

    test('rejects more than three evidence URLs before RPC', () async {
      var rpcCalled = false;
      final repository = _buildRepository(
        rpcInvoker: (functionName, params) async {
          rpcCalled = true;
          return {};
        },
      );

      await expectLater(
        repository.submitReport(
          ProductReportSubmission(
            productId: _productId,
            type: ProductReportType.wrongImage,
            evidenceImageUrls: const [
              'https://cdn.example.com/1.jpg',
              'https://cdn.example.com/2.jpg',
              'https://cdn.example.com/3.jpg',
              'https://cdn.example.com/4.jpg',
            ],
          ),
        ),
        throwsA(
          isA<ProductReportSubmissionException>().having(
            (error) => error.type,
            'type',
            ProductReportSubmissionFailureType.invalidSubmission,
          ),
        ),
      );

      expect(rpcCalled, isFalse);
    });

    test('maps duplicate-recent backend responses to a safe failure', () async {
      final repository = _buildRepository(
        rpcInvoker: (functionName, params) async {
          throw const PostgrestException(message: 'duplicate_recent_report');
        },
      );

      await expectLater(
        repository.submitReport(
          ProductReportSubmission(
            productId: _productId,
            type: ProductReportType.wrongImage,
          ),
        ),
        throwsA(
          isA<ProductReportSubmissionException>()
              .having(
                (error) => error.type,
                'type',
                ProductReportSubmissionFailureType.duplicateRecentReport,
              )
              .having(
                (error) => error.userMessage,
                'userMessage',
                isNot(contains('duplicate_recent_report')),
              ),
        ),
      );
    });

    test('maps rate-limit backend responses to a safe failure', () async {
      final repository = _buildRepository(
        rpcInvoker: (functionName, params) async {
          throw const PostgrestException(message: 'report_rate_limited');
        },
      );

      await expectLater(
        repository.submitReport(
          ProductReportSubmission(
            productId: _productId,
            type: ProductReportType.other,
          ),
        ),
        throwsA(
          isA<ProductReportSubmissionException>().having(
            (error) => error.type,
            'type',
            ProductReportSubmissionFailureType.rateLimited,
          ),
        ),
      );
    });

    test(
      'maps product-not-found backend responses to a safe failure',
      () async {
        final repository = _buildRepository(
          rpcInvoker: (functionName, params) async {
            throw const PostgrestException(message: 'product_not_found');
          },
        );

        await expectLater(
          repository.submitReport(
            ProductReportSubmission(
              productId: _productId,
              type: ProductReportType.wrongCategory,
            ),
          ),
          throwsA(
            isA<ProductReportSubmissionException>().having(
              (error) => error.type,
              'type',
              ProductReportSubmissionFailureType.productNotFound,
            ),
          ),
        );
      },
    );

    test('maps invalid backend responses to invalidSubmission', () async {
      final repository = _buildRepository(
        rpcInvoker: (functionName, params) async {
          throw const PostgrestException(message: 'invalid_report_type');
        },
      );

      await expectLater(
        repository.submitReport(
          ProductReportSubmission(
            productId: _productId,
            type: ProductReportType.wrongBarcode,
          ),
        ),
        throwsA(
          isA<ProductReportSubmissionException>().having(
            (error) => error.type,
            'type',
            ProductReportSubmissionFailureType.invalidSubmission,
          ),
        ),
      );
    });

    test('maps network exceptions to networkFailure', () async {
      final repository = _buildRepository(
        rpcInvoker: (functionName, params) async {
          throw const SocketException('connection reset');
        },
      );

      await expectLater(
        repository.submitReport(
          ProductReportSubmission(
            productId: _productId,
            type: ProductReportType.outdatedIngredients,
          ),
        ),
        throwsA(
          isA<ProductReportSubmissionException>().having(
            (error) => error.type,
            'type',
            ProductReportSubmissionFailureType.networkFailure,
          ),
        ),
      );
    });

    test(
      'maps unexpected backend responses to unknown without leaking raw text',
      () async {
        final repository = _buildRepository(
          rpcInvoker: (functionName, params) async {
            throw const PostgrestException(message: 'internal_backend_trace');
          },
        );

        await expectLater(
          repository.submitReport(
            ProductReportSubmission(
              productId: _productId,
              type: ProductReportType.wrongNutrition,
            ),
          ),
          throwsA(
            isA<ProductReportSubmissionException>()
                .having(
                  (error) => error.type,
                  'type',
                  ProductReportSubmissionFailureType.unknown,
                )
                .having(
                  (error) => error.userMessage,
                  'userMessage',
                  isNot(contains('internal_backend_trace')),
                ),
          ),
        );
      },
    );
  });
}

SupabaseProductReportRepository _buildRepository({
  required ProductReportRpcInvoker rpcInvoker,
  String installationId = _installationId,
  String Function()? submissionIdGenerator,
}) {
  final storage = _InMemoryAppInstallationIdStorage(
    initialValues: {kAppInstallationIdStorageKey: installationId},
  );

  return SupabaseProductReportRepository(
    installationIdService: AppInstallationIdService(storage: storage),
    rpcInvoker: rpcInvoker,
    submissionIdGenerator: submissionIdGenerator ?? () => _submissionId,
  );
}

class _InMemoryAppInstallationIdStorage implements AppInstallationIdStorage {
  _InMemoryAppInstallationIdStorage({Map<String, String>? initialValues})
    : _values = <String, String>{...?initialValues};

  final Map<String, String> _values;

  @override
  Future<String?> readString(String key) async => _values[key];

  @override
  Future<void> writeString(String key, String value) async {
    _values[key] = value;
  }
}

const _productId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _installationId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _submissionId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _reportId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
