import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/core/widgets/fresh_cached_product_image.dart';
import 'package:food_analyzer_app/features/product/controllers/product_detail_controller.dart';
import 'package:food_analyzer_app/features/search/widgets/product_card.dart';
import 'package:food_analyzer_app/features/user_library/controllers/user_product_library_controller.dart';
import 'package:food_analyzer_app/features/user_library/models/favorite_product_entry.dart';
import 'package:food_analyzer_app/features/user_library/models/local_product_snapshot.dart';
import 'package:food_analyzer_app/features/user_library/models/product_activity_entry.dart';
import 'package:food_analyzer_app/features/user_library/services/user_library_time_formatter.dart';

class UserLibraryPage extends ConsumerStatefulWidget {
  const UserLibraryPage({super.key});

  @override
  ConsumerState<UserLibraryPage> createState() => _UserLibraryPageState();
}

class _UserLibraryPageState extends ConsumerState<UserLibraryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  String? _openingProductId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Kitaplığım')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surfaceSoft,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: TabBar(
                controller: _tabController,
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                padding: const EdgeInsets.all(4),
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                labelStyle: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                unselectedLabelStyle: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                indicator: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: AppShadows.soft(AppColors.primary),
                ),
                tabs: const [
                  Tab(text: 'Favoriler'),
                  Tab(text: 'Görüntülenenler'),
                  Tab(text: 'Tarananlar'),
                ],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _FavoritesTab(
                  onOpenSnapshot: _openSnapshot,
                  onShowMessage: _showMessage,
                ),
                _HistoryTab(
                  type: ProductActivityType.viewed,
                  onOpenSnapshot: _openSnapshot,
                  onClearRequested: () =>
                      _confirmClearHistory(ProductActivityType.viewed),
                ),
                _HistoryTab(
                  type: ProductActivityType.scanned,
                  onOpenSnapshot: _openSnapshot,
                  onClearRequested: () =>
                      _confirmClearHistory(ProductActivityType.scanned),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSnapshot(LocalProductSnapshot snapshot) async {
    if (_openingProductId == snapshot.productId) {
      return;
    }

    setState(() {
      _openingProductId = snapshot.productId;
    });

    try {
      final product = await ref
          .read(productRepositoryProvider)
          .getProductById(snapshot.productId);

      if (!mounted) return;

      if (product == null) {
        _showMessage('Bu ürün artık veritabanında bulunamıyor.');
        return;
      }

      context.push('/product/${snapshot.productId}');
    } catch (_) {
      if (!mounted) return;
      _showMessage('Ürün açılamadı. Tekrar deneyin.');
    } finally {
      if (mounted) {
        setState(() {
          _openingProductId = null;
        });
      }
    }
  }

  Future<void> _confirmClearHistory(ProductActivityType type) async {
    final isViewed = type == ProductActivityType.viewed;
    final entries = isViewed
        ? ref.read(viewedProductActivityEntriesProvider)
        : ref.read(scannedProductActivityEntriesProvider);

    if (entries.isEmpty) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            isViewed
                ? 'Görüntüleme geçmişi temizlensin mi?'
                : 'Tarama geçmişi temizlensin mi?',
          ),
          content: Text(
            isViewed
                ? 'Bu işlem favorilerini ve tarama geçmişini etkilemez.'
                : 'Bu işlem favorilerini ve görüntüleme geçmişini etkilemez.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Temizle'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await ref
          .read(recentProductActivityProvider.notifier)
          .clearRecentActivity(type: type);
    } catch (_) {
      if (!mounted) return;
      _showMessage('Değişiklik kaydedilemedi. Tekrar deneyin.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

class _FavoritesTab extends ConsumerWidget {
  final ValueChanged<LocalProductSnapshot> onOpenSnapshot;
  final ValueChanged<String> onShowMessage;

  const _FavoritesTab({
    required this.onOpenSnapshot,
    required this.onShowMessage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoriteEntriesProvider);

    if (favorites.isEmpty) {
      return _LibraryEmptyState(
        key: const ValueKey('favorites-empty-state'),
        icon: Icons.favorite_border_rounded,
        title: 'Henüz favori ürünün yok',
        message:
            'Beğendiğin ürünleri kalp simgesine dokunarak burada saklayabilirsin.',
        actionLabel: 'Ürünleri keşfet',
        onAction: () => context.goNamed('search'),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth < 320 ? 2 : 3;
        const horizontalPadding = 16.0;
        const crossAxisSpacing = 12.0;
        const mainAxisSpacing = 16.0;
        final usableWidth =
            constraints.maxWidth -
            (horizontalPadding * 2) -
            (crossAxisSpacing * (crossAxisCount - 1));
        final itemWidth = usableWidth / crossAxisCount;
        final itemHeight = compactProductTileHeight(itemWidth) + 6;

        return GridView.builder(
          key: const ValueKey('user-library-favorites-grid'),
          padding: const EdgeInsets.fromLTRB(
            horizontalPadding,
            2,
            horizontalPadding,
            24,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: crossAxisSpacing,
            mainAxisSpacing: mainAxisSpacing,
            mainAxisExtent: itemHeight,
          ),
          itemCount: favorites.length,
          itemBuilder: (context, index) {
            final entry = favorites[index];
            return _FavoriteGridTile(
              entry: entry,
              onTap: () => onOpenSnapshot(entry.product),
              onRemove: () async {
                try {
                  await ref
                      .read(favoriteProductsProvider.notifier)
                      .removeFavorite(entry.product.productId);
                } catch (_) {
                  onShowMessage('Değişiklik kaydedilemedi. Tekrar deneyin.');
                }
              },
            );
          },
        );
      },
    );
  }
}

class _HistoryTab extends ConsumerWidget {
  final ProductActivityType type;
  final ValueChanged<LocalProductSnapshot> onOpenSnapshot;
  final VoidCallback onClearRequested;

  const _HistoryTab({
    required this.type,
    required this.onOpenSnapshot,
    required this.onClearRequested,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = type == ProductActivityType.viewed
        ? ref.watch(viewedProductActivityEntriesProvider)
        : ref.watch(scannedProductActivityEntriesProvider);
    final isViewed = type == ProductActivityType.viewed;

    if (entries.isEmpty) {
      return _LibraryEmptyState(
        key: ValueKey(isViewed ? 'viewed-empty-state' : 'scanned-empty-state'),
        icon: isViewed ? Icons.visibility_outlined : Icons.qr_code_rounded,
        title: isViewed
            ? 'Henüz görüntüleme geçmişin yok'
            : 'Henüz tarama geçmişin yok',
        message: isViewed
            ? 'İncelediğin ürünler burada görünecek.'
            : 'Barkodunu taradığın ürünler burada görünecek.',
        actionLabel: isViewed ? null : 'Barkod tara',
        onAction: isViewed ? null : () => context.goNamed('barcode'),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
          child: Row(
            children: [
              Text(
                '${entries.length} ürün',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              TextButton(
                key: ValueKey(
                  isViewed
                      ? 'clear-viewed-history-button'
                      : 'clear-scanned-history-button',
                ),
                onPressed: onClearRequested,
                child: const Text('Geçmişi temizle'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            key: ValueKey(
              isViewed ? 'viewed-history-list' : 'scanned-history-list',
            ),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return _HistoryListItem(
                entry: entry,
                onTap: () => onOpenSnapshot(entry.product),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FavoriteGridTile extends StatelessWidget {
  final FavoriteProductEntry entry;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _FavoriteGridTile({
    required this.entry,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final product = entry.product;
    final brand = product.brand?.trim();

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: ValueKey('favorite-tile-${product.productId}'),
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                _GridProductImage(snapshot: product),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Semantics(
                    label: 'Favorilerden çıkar',
                    button: true,
                    child: Material(
                      color: AppColors.surface,
                      shape: const CircleBorder(),
                      child: InkWell(
                        key: ValueKey('favorite-remove-${product.productId}'),
                        customBorder: const CircleBorder(),
                        onTap: onRemove,
                        child: const SizedBox(
                          width: 34,
                          height: 34,
                          child: Icon(
                            Icons.favorite_rounded,
                            size: 18,
                            color: AppColors.danger,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: kCompactProductImageTextGap),
            SizedBox(
              height: kCompactProductBrandAreaHeight,
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  (brand == null || brand.isEmpty) ? ' ' : brand,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.25,
                  ),
                ),
              ),
            ),
            const SizedBox(height: kCompactProductBrandNameGap),
            Padding(
              padding: const EdgeInsets.only(
                bottom: kCompactProductNameBottomPadding,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: kCompactProductNameMinHeight,
                ),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                    textHeightBehavior: const TextHeightBehavior(
                      applyHeightToFirstAscent: true,
                      applyHeightToLastDescent: true,
                      leadingDistribution: TextLeadingDistribution.even,
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 12.8,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      height: 1.28,
                      leadingDistribution: TextLeadingDistribution.even,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryListItem extends StatelessWidget {
  final ProductActivityEntry entry;
  final VoidCallback onTap;

  const _HistoryListItem({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final product = entry.product;
    final brand = product.brand?.trim();

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        key: ValueKey(
          '${entry.type.storageValue}-history-item-${product.productId}',
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadows.soft(),
          ),
          child: Row(
            children: [
              _RowProductImage(snapshot: product),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (brand != null && brand.isNotEmpty)
                      Text(
                        brand,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.22,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      formatUserLibraryActivityTime(entry.occurredAt),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.chevron_right_rounded, color: AppColors.neutral),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridProductImage extends StatelessWidget {
  final LocalProductSnapshot snapshot;

  const _GridProductImage({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final imageSurface = Color.lerp(Colors.white, AppColors.primary, 0.025)!;

    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: imageSurface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.10)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.028),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ProductThumbnail(
            productId: snapshot.productId,
            imageUrl: snapshot.imageUrl,
            accentColor: AppColors.primary,
            iconSize: 30,
          ),
        ),
      ),
    );
  }
}

class _RowProductImage extends StatelessWidget {
  final LocalProductSnapshot snapshot;

  const _RowProductImage({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 68,
      height: 68,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.surfaceSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ProductThumbnail(
            productId: snapshot.productId,
            imageUrl: snapshot.imageUrl,
            accentColor: AppColors.primary,
            iconSize: 24,
          ),
        ),
      ),
    );
  }
}

class _LibraryEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _LibraryEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: AppColors.surfaceSoft,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: AppColors.primary, size: 28),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 18),
                OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
