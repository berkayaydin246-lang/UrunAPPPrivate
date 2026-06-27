import 'package:flutter/material.dart';

/// Widget for editing OCR-extracted text
class OcrTextEditor extends StatefulWidget {
  final String initialText;
  final Function(String) onSave;
  final VoidCallback? onCancel;

  const OcrTextEditor({
    super.key,
    required this.initialText,
    required this.onSave,
    this.onCancel,
  });

  @override
  State<OcrTextEditor> createState() => _OcrTextEditorState();
}

class _OcrTextEditorState extends State<OcrTextEditor> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Metni elle düzenle',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Text(
            'Metni kontrol edip gerekli düzeltmeleri yapabilirsin',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          // Editable text field
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: TextField(
              controller: _controller,
              maxLines: 8,
              expands: false,
              decoration: InputDecoration(
                hintText: 'İçindekiler...',
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(12.0),
                hintStyle: TextStyle(color: Colors.grey[400]),
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 24),
          // Action buttons
          Row(
            children: [
              if (widget.onCancel != null)
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onCancel,
                    child: const Text('İptal'),
                  ),
                ),
              if (widget.onCancel != null) const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('Kaydet'),
                  onPressed: () {
                    widget.onSave(_controller.text);
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
