import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:food_analyzer_app/features/barcode/controllers/barcode_controller.dart';
import 'package:food_analyzer_app/features/submission/repositories/product_submission_repository.dart';

class MissingProductSubmissionPage extends ConsumerStatefulWidget {
  final String barcode;

  const MissingProductSubmissionPage({super.key, required this.barcode});

  @override
  ConsumerState<MissingProductSubmissionPage> createState() =>
      _MissingProductSubmissionPageState();
}

class _MissingProductSubmissionPageState
    extends ConsumerState<MissingProductSubmissionPage> {
  final _formKey = GlobalKey<FormState>();
  final _productNameController = TextEditingController();
  final _brandController = TextEditingController();
  final _notesController = TextEditingController();

  final _repository = const ProductSubmissionRepository();
  final _picker = ImagePicker();

  Uint8List? _frontImageBytes;
  String? _frontImageName;
  Uint8List? _labelImageBytes;
  String? _labelImageName;

  bool _isSubmitting = false;
  bool _submitted = false;
  String _successMessage = 'Ürün inceleme için gönderildi.';

  @override
  void dispose() {
    _productNameController.dispose();
    _brandController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickImage({required bool isFront}) async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 2000,
        maxHeight: 2000,
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      if (!mounted) return;

      setState(() {
        if (isFront) {
          _frontImageBytes = bytes;
          _frontImageName = file.name;
        } else {
          _labelImageBytes = bytes;
          _labelImageName = file.name;
        }
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      final denied =
          (e.code.toLowerCase().contains('camera') ||
              e.code.toLowerCase().contains('permission')) &&
          e.code.toLowerCase().contains('denied');
      final message = denied
          ? 'Kamera izni gerekli. Lütfen ayarlardan kamera iznini etkinleştirin.'
          : 'Fotoğraf alınamadı. Lütfen tekrar deneyin.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fotoğraf alınamadı. Lütfen tekrar deneyin.'),
        ),
      );
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_frontImageBytes == null || _labelImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ürünü ekleyebilmemiz için ön yüz ve içerik/besin etiketi fotoğrafları gereklidir.',
          ),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final response = await _repository.submitMissingProduct(
      barcode: widget.barcode,
      frontImageBytes: _frontImageBytes!,
      labelImageBytes: _labelImageBytes!,
      frontImageName: _frontImageName ?? 'front.jpg',
      labelImageName: _labelImageName ?? 'label.jpg',
      productName: _productNameController.text.trim().isEmpty
          ? null
          : _productNameController.text.trim(),
      brand: _brandController.text.trim().isEmpty
          ? null
          : _brandController.text.trim(),
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );

    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
      if (response.isSuccess) {
        _submitted = true;
        _successMessage = response.message;
      }
    });

    if (!response.isSuccess) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(response.message)));
    }
  }

  void _goToBarcodeScan() {
    ref.read(barcodeScanProvider.notifier).reset();
    context.go('/barcode');
  }

  void _goHome() {
    ref.read(barcodeScanProvider.notifier).reset();
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ürün Bilgisi Gönder')),
      body: SafeArea(
        child: _submitted ? _buildSuccessState(context) : _buildForm(context),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              initialValue: widget.barcode,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Barkod',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Barkod gerekli';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _productNameController,
              decoration: const InputDecoration(
                labelText: 'Ürün Adı (isteğe bağlı)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _brandController,
              decoration: const InputDecoration(
                labelText: 'Marka (isteğe bağlı)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            _PhotoPickerTile(
              title: 'Ön yüz fotoğrafı',
              subtitle: 'Zorunlu',
              picked: _frontImageBytes != null,
              buttonText: 'Ön yüz fotoğrafı çek',
              onTap: () => _pickImage(isFront: true),
            ),
            const SizedBox(height: 10),
            _PhotoPickerTile(
              title: 'İçindekiler/Besin Değeri fotoğrafı',
              subtitle: 'Zorunlu',
              picked: _labelImageBytes != null,
              buttonText: 'İçindekiler/Besin Değeri fotoğrafı çek',
              onTap: () => _pickImage(isFront: false),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Notlar (isteğe bağlı)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            if (_frontImageBytes == null || _labelImageBytes == null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: const Text(
                  'Ürünü ekleyebilmemiz için ön yüz ve içerik/besin etiketi fotoğrafları gereklidir.',
                ),
              ),
            const SizedBox(height: 16),
            _isSubmitting
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
                    onPressed: _submit,
                    child: const Text('İncelemeye Gönder'),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ürün inceleme için gönderildi.',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Bilgiler kontrol edildikten sonra ürün veritabanına eklenebilir.',
                ),
                const SizedBox(height: 8),
                Text(_successMessage),
              ],
            ),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: _goToBarcodeScan,
            child: const Text('Yeni Barkod Tara'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _goHome,
            child: const Text('Ana Sayfaya Dön'),
          ),
        ],
      ),
    );
  }
}

class _PhotoPickerTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool picked;
  final String buttonText;
  final VoidCallback onTap;

  const _PhotoPickerTile({
    required this.title,
    required this.subtitle,
    required this.picked,
    required this.buttonText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (picked)
                const Icon(Icons.check_circle, color: Colors.green)
              else
                Text(
                  subtitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(buttonText),
            ),
          ),
        ],
      ),
    );
  }
}
