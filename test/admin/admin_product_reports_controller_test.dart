import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/admin/controllers/admin_product_report_detail_controller.dart';
import 'package:food_analyzer_app/features/admin/controllers/admin_product_reports_list_controller.dart';
import 'package:food_analyzer_app/features/admin/models/admin_product_report_cursor.dart';
import 'package:food_analyzer_app/features/admin/models/admin_product_report_detail.dart';
import 'package:food_analyzer_app/features/admin/models/admin_product_report_page.dart';
import 'package:food_analyzer_app/features/admin/repositories/admin_product_report_repository.dart';
import 'package:food_analyzer_app/features/product_reports/models/product_report_status.dart';

import 'helpers/admin_product_reports_test_helpers.dart';

void main() {
  group('ProductReportStatus admin workflow', () {
    test('exposes valid admin transitions and labels for each status', () {
      expect(ProductReportStatus.pending.validAdminTransitions, const [
        ProductReportStatus.reviewing,
        ProductReportStatus.resolved,
        ProductReportStatus.rejected,
      ]);
      expect(ProductReportStatus.reviewing.validAdminTransitions, const [
        ProductReportStatus.pending,
        ProductReportStatus.resolved,
        ProductReportStatus.rejected,
      ]);
      expect(ProductReportStatus.resolved.validAdminTransitions, const [
        ProductReportStatus.reviewing,
      ]);
      expect(ProductReportStatus.rejected.validAdminTransitions, const [
        ProductReportStatus.reviewing,
      ]);

      expect(
        ProductReportStatus.pending.adminActionLabelFor(
          ProductReportStatus.reviewing,
        ),
        'İncelemeye al',
      );
      expect(
        ProductReportStatus.reviewing.adminActionLabelFor(
          ProductReportStatus.pending,
        ),
        'Beklemeye al',
      );
      expect(
        ProductReportStatus.pending.canAdminTransitionTo(
          ProductReportStatus.pending,
        ),
        isFalse,
      );
    });
  });

  group('AdminProductReportsListController', () {
    test(
      'defaults to pending and loads the first page through repository',
      () async {
        final firstSummary = makeReportSummary(id: 'pending-1');
        final repo = FakeAdminProductReportRepository(
          listHandler: ({status, limit = 30, cursor}) async {
            return AdminProductReportPage(
              reports: [firstSummary],
              nextCursor: null,
            );
          },
        );
        final container = ProviderContainer(
          overrides: [
            adminProductReportRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);
        final subscription = container.listen(
          adminProductReportsListControllerProvider,
          (previous, next) {},
        );
        addTearDown(subscription.close);

        await flushMicrotasks();

        final state = container.read(adminProductReportsListControllerProvider);
        expect(state.selectedStatus, ProductReportStatus.pending);
        expect(state.isInitialLoading, isFalse);
        expect(state.reports, [firstSummary]);
        expect(repo.listCalls, hasLength(1));
        expect(repo.listCalls.single.status, ProductReportStatus.pending);
        expect(repo.listCalls.single.limit, 30);
        expect(repo.listCalls.single.cursor, isNull);
      },
    );

    test(
      'loadMore appends next page, blocks concurrent calls, deduplicates IDs, and stops at the end',
      () async {
        final firstSummary = makeReportSummary(id: 'report-1');
        final secondSummary = makeReportSummary(id: 'report-2');
        final secondPageCompleter = Completer<AdminProductReportPage>();
        final repo = FakeAdminProductReportRepository(
          listHandler: ({status, limit = 30, cursor}) async {
            if (cursor == null) {
              return AdminProductReportPage(
                reports: [firstSummary],
                nextCursor: AdminProductReportCursor.fromSummary(firstSummary),
              );
            }

            return secondPageCompleter.future;
          },
        );
        final container = ProviderContainer(
          overrides: [
            adminProductReportRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);
        final subscription = container.listen(
          adminProductReportsListControllerProvider,
          (previous, next) {},
        );
        addTearDown(subscription.close);

        await flushMicrotasks();

        final notifier = container.read(
          adminProductReportsListControllerProvider.notifier,
        );
        unawaited(notifier.loadMore());
        unawaited(notifier.loadMore());
        await flushMicrotasks();

        expect(repo.listCalls, hasLength(2));
        expect(
          repo.listCalls.where((call) => call.cursor != null),
          hasLength(1),
        );

        secondPageCompleter.complete(
          AdminProductReportPage(
            reports: [firstSummary, secondSummary],
            nextCursor: null,
          ),
        );
        await flushMicrotasks();

        final state = container.read(adminProductReportsListControllerProvider);
        expect(state.reports.map((report) => report.id), [
          'report-1',
          'report-2',
        ]);
        expect(state.nextCursor, isNull);

        await notifier.loadMore();
        expect(repo.listCalls, hasLength(2));
      },
    );

    test(
      'filter changes reset cursor and ignore stale responses from old filter',
      () async {
        final pendingCompleter = Completer<AdminProductReportPage>();
        final resolvedCompleter = Completer<AdminProductReportPage>();
        final repo = FakeAdminProductReportRepository(
          listHandler: ({status, limit = 30, cursor}) async {
            switch (status) {
              case ProductReportStatus.pending:
                return pendingCompleter.future;
              case ProductReportStatus.resolved:
                return resolvedCompleter.future;
              case ProductReportStatus.reviewing:
              case ProductReportStatus.rejected:
              case null:
                throw UnimplementedError('Unexpected status $status');
            }
          },
        );
        final container = ProviderContainer(
          overrides: [
            adminProductReportRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);
        final subscription = container.listen(
          adminProductReportsListControllerProvider,
          (previous, next) {},
        );
        addTearDown(subscription.close);

        await flushMicrotasks();

        final notifier = container.read(
          adminProductReportsListControllerProvider.notifier,
        );
        unawaited(notifier.selectStatus(ProductReportStatus.resolved));
        await flushMicrotasks();

        expect(repo.listCalls, hasLength(2));
        expect(repo.listCalls[0].status, ProductReportStatus.pending);
        expect(repo.listCalls[1].status, ProductReportStatus.resolved);
        expect(repo.listCalls[1].cursor, isNull);

        pendingCompleter.complete(
          AdminProductReportPage(
            reports: [makeReportSummary(id: 'old-pending')],
            nextCursor: null,
          ),
        );
        await flushMicrotasks();

        expect(
          container.read(adminProductReportsListControllerProvider).reports,
          isEmpty,
        );

        final resolvedSummary = makeReportSummary(
          id: 'resolved-1',
          status: ProductReportStatus.resolved,
        );
        resolvedCompleter.complete(
          AdminProductReportPage(reports: [resolvedSummary], nextCursor: null),
        );
        await flushMicrotasks();

        final state = container.read(adminProductReportsListControllerProvider);
        expect(state.selectedStatus, ProductReportStatus.resolved);
        expect(state.reports, [resolvedSummary]);
      },
    );

    test(
      'refresh preserves selected filter and visible rows when refresh fails',
      () async {
        final firstSummary = makeReportSummary(id: 'pending-1');
        var callCount = 0;
        final repo = FakeAdminProductReportRepository(
          listHandler: ({status, limit = 30, cursor}) async {
            callCount++;
            if (callCount == 1) {
              return AdminProductReportPage(
                reports: [firstSummary],
                nextCursor: null,
              );
            }

            throw const AdminProductReportException(
              type: AdminReportFailureType.unknown,
              userMessage: 'postgres product_reports exploded',
            );
          },
        );
        final container = ProviderContainer(
          overrides: [
            adminProductReportRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);
        final subscription = container.listen(
          adminProductReportsListControllerProvider,
          (previous, next) {},
        );
        addTearDown(subscription.close);

        await flushMicrotasks();

        final notifier = container.read(
          adminProductReportsListControllerProvider.notifier,
        );
        await notifier.refresh();

        final state = container.read(adminProductReportsListControllerProvider);
        expect(state.selectedStatus, ProductReportStatus.pending);
        expect(state.reports, [firstSummary]);
        expect(
          state.error,
          'Bildirimler yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin.',
        );
        expect(state.error, isNot(contains('product_reports')));
      },
    );

    test(
      'syncUpdatedReport removes rows that no longer match the active filter',
      () async {
        final initialSummary = makeReportSummary(id: 'pending-1');
        final repo = FakeAdminProductReportRepository(
          listHandler: ({status, limit = 30, cursor}) async {
            return AdminProductReportPage(
              reports: [initialSummary],
              nextCursor: null,
            );
          },
        );
        final container = ProviderContainer(
          overrides: [
            adminProductReportRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);
        final subscription = container.listen(
          adminProductReportsListControllerProvider,
          (previous, next) {},
        );
        addTearDown(subscription.close);

        await flushMicrotasks();

        container
            .read(adminProductReportsListControllerProvider.notifier)
            .syncUpdatedReport(
              makeReportDetail(
                id: 'pending-1',
                status: ProductReportStatus.reviewing,
              ),
            );

        expect(
          container.read(adminProductReportsListControllerProvider).reports,
          isEmpty,
        );
      },
    );
  });

  group('AdminProductReportDetailController', () {
    test('loads report detail through repository', () async {
      final detail = makeReportDetail(id: 'report-1');
      final repo = FakeAdminProductReportRepository(
        getHandler: (reportId) async => detail,
      );
      final container = ProviderContainer(
        overrides: [
          adminProductReportRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        adminProductReportDetailControllerProvider('report-1'),
        (previous, next) {},
      );
      addTearDown(subscription.close);

      await flushMicrotasks();

      final state = container.read(
        adminProductReportDetailControllerProvider('report-1'),
      );
      expect(repo.getCalls, ['report-1']);
      expect(state.isLoading, isFalse);
      expect(state.report, detail);
    });

    test(
      'same-status note save works and updates the visible detail immediately',
      () async {
        final initialDetail = makeReportDetail(
          id: 'report-1',
          adminNote: 'Eski not',
        );
        final updatedDetail = makeReportDetail(
          id: 'report-1',
          adminNote: 'Yeni not',
        );
        final repo = FakeAdminProductReportRepository(
          getHandler: (reportId) async => initialDetail,
          updateHandler:
              ({required reportId, required status, String? adminNote}) async {
                return updatedDetail;
              },
        );
        final container = ProviderContainer(
          overrides: [
            adminProductReportRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);
        final subscription = container.listen(
          adminProductReportDetailControllerProvider('report-1'),
          (previous, next) {},
        );
        addTearDown(subscription.close);

        await flushMicrotasks();

        final controller = container.read(
          adminProductReportDetailControllerProvider('report-1').notifier,
        );
        final success = await controller.updateReport(
          status: ProductReportStatus.pending,
          adminNote: 'Yeni not',
        );

        expect(success, isTrue);
        expect(repo.updateCalls, hasLength(1));
        expect(repo.updateCalls.single.status, ProductReportStatus.pending);
        expect(repo.updateCalls.single.adminNote, 'Yeni not');
        expect(
          container
              .read(adminProductReportDetailControllerProvider('report-1'))
              .report,
          updatedDetail,
        );
      },
    );

    test(
      'blocks repeated update taps while a request is already running',
      () async {
        final initialDetail = makeReportDetail(id: 'report-1');
        final updateCompleter = Completer<AdminProductReportDetail>();
        final repo = FakeAdminProductReportRepository(
          getHandler: (reportId) async => initialDetail,
          updateHandler:
              ({required reportId, required status, String? adminNote}) {
                return updateCompleter.future;
              },
        );
        final container = ProviderContainer(
          overrides: [
            adminProductReportRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);
        final subscription = container.listen(
          adminProductReportDetailControllerProvider('report-1'),
          (previous, next) {},
        );
        addTearDown(subscription.close);

        await flushMicrotasks();

        final controller = container.read(
          adminProductReportDetailControllerProvider('report-1').notifier,
        );
        final firstUpdate = controller.updateReport(
          status: ProductReportStatus.reviewing,
          adminNote: 'İlk not',
        );
        final secondUpdate = await controller.updateReport(
          status: ProductReportStatus.resolved,
          adminNote: 'İkinci not',
        );

        expect(secondUpdate, isFalse);
        expect(repo.updateCalls, hasLength(1));

        updateCompleter.complete(
          makeReportDetail(
            id: 'report-1',
            status: ProductReportStatus.reviewing,
            adminNote: 'İlk not',
          ),
        );

        expect(await firstUpdate, isTrue);
        expect(
          container
              .read(adminProductReportDetailControllerProvider('report-1'))
              .report
              ?.status,
          ProductReportStatus.reviewing,
        );
      },
    );

    test(
      'update failure preserves existing report and hides raw backend errors',
      () async {
        final initialDetail = makeReportDetail(
          id: 'report-1',
          adminNote: 'Korunacak not',
        );
        final repo = FakeAdminProductReportRepository(
          getHandler: (reportId) async => initialDetail,
          updateHandler:
              ({required reportId, required status, String? adminNote}) async {
                throw const AdminProductReportException(
                  type: AdminReportFailureType.unknown,
                  userMessage: 'raw postgres product_reports failure',
                );
              },
        );
        final container = ProviderContainer(
          overrides: [
            adminProductReportRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(container.dispose);
        final subscription = container.listen(
          adminProductReportDetailControllerProvider('report-1'),
          (previous, next) {},
        );
        addTearDown(subscription.close);

        await flushMicrotasks();

        final controller = container.read(
          adminProductReportDetailControllerProvider('report-1').notifier,
        );
        final success = await controller.updateReport(
          status: ProductReportStatus.resolved,
          adminNote: 'Yeni not',
        );

        final state = container.read(
          adminProductReportDetailControllerProvider('report-1'),
        );
        expect(success, isFalse);
        expect(state.report, initialDetail);
        expect(
          state.error,
          'Bildirim yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin.',
        );
        expect(state.error, isNot(contains('product_reports')));
      },
    );
  });
}
