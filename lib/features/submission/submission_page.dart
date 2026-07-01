import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:food_analyzer_app/core/errors/user_message.dart';
import 'package:food_analyzer_app/features/submission/repositories/submission_repository.dart';

class SubmissionPage extends StatefulWidget {
  final String? prefillName;
  final String? prefillBarcode;

  const SubmissionPage({super.key, this.prefillName, this.prefillBarcode});

  @override
  State<SubmissionPage> createState() => _SubmissionPageState();
}

class _SubmissionPageState extends State<SubmissionPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtr = TextEditingController();
  final _barcodeCtr = TextEditingController();
  final _ocrCtr = TextEditingController();
  Uint8List? _frontBytes;
  String? _frontName;
  Uint8List? _ingredientsBytes;
  String? _ingredientsName;
  bool _isSubmitting = false;

  final _repo = SubmissionRepository();

  @override
  void initState() {
    super.initState();

    if (widget.prefillName != null) {
      _nameCtr.text = widget.prefillName!;
    }

    if (widget.prefillBarcode != null) {
      _barcodeCtr.text = widget.prefillBarcode!;
    }
  }

  @override
  void dispose() {
    _nameCtr.dispose();
    _barcodeCtr.dispose();
    _ocrCtr.dispose();
    super.dispose();
  }

  Future<void> _pickImage(bool isFront) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 2000,
      maxHeight: 2000,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      if (isFront) {
        _frontBytes = bytes;
        _frontName = 'front_${DateTime.now().millisecondsSinceEpoch}.jpg';
      } else {
        _ingredientsBytes = bytes;
        _ingredientsName =
            'ingredients_${DateTime.now().millisecondsSinceEpoch}.jpg';
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      await _repo.submit(
        productName: _nameCtr.text.trim(),
        barcode: _barcodeCtr.text.trim().isEmpty
            ? null
            : _barcodeCtr.text.trim(),
        frontImageBytes: _frontBytes,
        frontImageName: _frontName,
        ingredientsImageBytes: _ingredientsBytes,
        ingredientsImageName: _ingredientsName,
        ocrText: _ocrCtr.text.trim().isEmpty ? null : _ocrCtr.text.trim(),
      );

      if (!mounted) return;
      // Show success and pop
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Teşekkürler'),
          content: const Text('Ürün inceleme için gönderildi.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              },
              child: const Text('Tamam'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(UserMessage.forGeneric(e))));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ürün Gönder')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameCtr,
                  decoration: const InputDecoration(labelText: 'Ürün Adı'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Ürün adı gerekli' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _barcodeCtr,
                  decoration: const InputDecoration(
                    labelText: 'Barkod (isteğe bağlı)',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Ön Görsel (isteğe bağlı)'),
                        onPressed: () => _pickImage(true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_frontBytes != null)
                      const Icon(Icons.check_circle, color: Colors.green),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.image),
                        label: const Text(
                          'İçindekiler Fotoğrafı (isteğe bağlı)',
                        ),
                        onPressed: () => _pickImage(false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_ingredientsBytes != null)
                      const Icon(Icons.check_circle, color: Colors.green),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _ocrCtr,
                  decoration: const InputDecoration(
                    labelText: 'OCR metni (isteğe bağlı)',
                  ),
                  maxLines: 4,
                ),
                const SizedBox(height: 20),
                _isSubmitting
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        onPressed: _submit,
                        child: const Text('Gönder'),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
