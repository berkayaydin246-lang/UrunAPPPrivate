import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> openLegalLink(BuildContext context, Uri uri) async {
  try {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      _showFailSnackBar(context);
    }
  } catch (_) {
    if (context.mounted) {
      _showFailSnackBar(context);
    }
  }
}

void _showFailSnackBar(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Bağlantı açılamadı. Lütfen daha sonra tekrar deneyin.'),
    ),
  );
}
