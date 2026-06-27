import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:food_analyzer_app/features/barcode/controllers/barcode_controller.dart';
import 'package:food_analyzer_app/features/imports/models/off_product.dart';
import 'package:food_analyzer_app/features/submission/missing_product_submission_page.dart';

class BarcodeScreen extends ConsumerStatefulWidget {
  const BarcodeScreen({super.key});

  @override
  ConsumerState<BarcodeScreen> createState() => _BarcodeScreenState();
}

class _BarcodeScreenState extends ConsumerState<BarcodeScreen> {
  late MobileScannerController _scannerController;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController();
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  /// Handle barcode detection
  Future<void> _handleBarcode(BarcodeCapture capture) async {
    if (capture.barcodes.isEmpty) return;

    final barcode = capture.barcodes.first.rawValue;
    if (barcode == null) return;

    // Process the barcode scan
    final notifier = ref.read(barcodeScanProvider.notifier);
    final processed = await notifier.handleBarcodeScanned(barcode);

    if (!processed) {
      return; // Duplicate scan, ignore
    }

    // Stop scanning to prevent repeated detections
    await _scannerController.stop();

    // Check the result
    final state = ref.read(barcodeScanProvider);

    if (state.hasProduct) {
      // Product found, navigate to detail
      if (mounted) {
        context.push('/product/${state.product!.id}');
      }
    } else if (state.notFound) {
      // Not in local catalog. _buildNotFoundUI handles both cases:
      // with externalPreview (shows OFF card) or without (generic empty state).
    } else if (state.hasError) {
      // Error occurred, show error message
      // User can retry
    }
  }

  @override
  Widget build(BuildContext context) {
    final scanState = ref.watch(barcodeScanProvider);

    if (scanState.isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Barkod Tara'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text(
                  scanState.loadingMessage ?? 'Ürün verisi getiriliyor...',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // If product was found and we're still on this screen, show not found UI
    if (scanState.notFound && !scanState.hasProduct) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Barkod Tara'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: _buildNotFoundUI(context),
      );
    }

    // If there's an error, show error UI
    if (scanState.hasError) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Barkod Tara'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: _buildErrorUI(context, scanState.error!),
      );
    }

    // Show camera scanner
    return Scaffold(
      appBar: AppBar(
        title: const Text('Barkod Tara'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: _handleBarcode,
          ),
          // Overlay with scan frame and instructions
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Scan frame
                  Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.green, width: 3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.barcode_reader,
                            size: 64,
                            color: Colors.green,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Barkodu tarayın',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: Colors.green),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Instruction text
                  Text(
                    'Ürünün barkodunu kamera karesi içine yerleştirin',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build the "Product not found" UI.
  ///
  /// When the barcode was found on Open Food Facts (but not in our local
  /// catalog), an unverified external preview card is shown above the CTA
  /// buttons.  The OFF data is never inserted into the products table here.
  Widget _buildNotFoundUI(BuildContext context) {
    final scanState = ref.read(barcodeScanProvider);
    final barcode = scanState.scannedBarcode;
    final preview = scanState.externalPreview;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 24),
          Icon(Icons.inventory_2, size: 56, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Ürün veritabanımızda yok',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Bu ürün veritabanımızda yok. Etiket fotoğrafını yükleyerek '
            'eklenmesine yardımcı olabilirsiniz.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          if (barcode != null) ...[
            const SizedBox(height: 6),
            Text(
              'Barkod: $barcode',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
            ),
          ],

          // External OFF preview — shown only when OFF has data
          if (preview != null) ...[
            const SizedBox(height: 20),
            _ExternalPreviewCard(preview: preview),
          ],

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Etiket Fotoğrafı Yükle'),
              onPressed: barcode == null
                  ? null
                  : () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              MissingProductSubmissionPage(barcode: barcode),
                        ),
                      );
                    },
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Tekrar Tara'),
              onPressed: () {
                ref.read(barcodeScanProvider.notifier).reset();
                _scannerController.start();
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Build the error UI
  Widget _buildErrorUI(BuildContext context, String error) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
            const SizedBox(height: 24),
            Text(
              'Hata oluştu',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                error,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Yeniden Dene'),
              onPressed: () {
                ref.read(barcodeScanProvider.notifier).reset();
                _scannerController.start();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── External OFF preview card ─────────────────────────────────────────────────

/// Shows unverified Open Food Facts data as a read-only preview card.
/// Makes it clear that this product has not been approved into our catalog.
class _ExternalPreviewCard extends StatelessWidget {
  final OffProduct preview;

  const _ExternalPreviewCard({required this.preview});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.orange.shade300),
        borderRadius: BorderRadius.circular(12),
        color: Colors.orange.shade50,
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.public, size: 16, color: Colors.orange.shade800),
              const SizedBox(width: 6),
              Text(
                'Open Food Facts (doğrulanmamış)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.orange.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (preview.imageUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    preview.imageUrl!,
                    width: 64,
                    height: 64,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const SizedBox(width: 64),
                  ),
                ),
              if (preview.imageUrl != null) const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (preview.brand != null)
                      Text(
                        preview.brand!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    Text(
                      preview.name ?? preview.barcode,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Bu ürün henüz onaylı veritabanımızda yer almıyor. '
            'Fotoğraf yükleyerek eklenmesine yardımcı olabilirsiniz.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.orange.shade900,
            ),
          ),
        ],
      ),
    );
  }
}
