import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:food_analyzer_app/core/legal/legal_link_launcher.dart';
import 'package:food_analyzer_app/core/legal/legal_links.dart';
import 'package:food_analyzer_app/core/legal/public_legal_copy.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';

/// About / settings page.
///
/// Provides a visible entry point for branding info and legal text.
/// Contains a hidden developer shortcut: tapping the version string 7 times
/// navigates to the admin authorization route. No visible hint is shown.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _versionTapCount = 0;

  void _onVersionTap() {
    _versionTapCount++;
    if (_versionTapCount >= 7) {
      _versionTapCount = 0;
      context.push('/internal/admin');
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Hakkında')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          children: [
            // ── Brand block ────────────────────────────────────────────────
            Center(
              child: Image.asset(
                'assets/branding/etiketly_logo_mark.png',
                width: 72,
                height: 72,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Etiketly',
              textAlign: TextAlign.center,
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Etiketi tara, içeriği anla.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),

            // Version — hidden admin tap target (7 taps)
            GestureDetector(
              onTap: _onVersionTap,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'Sürüm 1.0.0',
                  textAlign: TextAlign.center,
                  style: textTheme.labelSmall?.copyWith(
                    color: AppColors.neutral,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 40),

            // ── Disclaimer ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.warningSoft,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Bilgilendirme Amacıyla',
                        style: textTheme.labelMedium?.copyWith(
                          color: AppColors.warningText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    PublicLegalCopy.healthDisclaimer,
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.warningText,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // ── Legal links ────────────────────────────────────────────────
            _LegalRow(
              label: 'Gizlilik Politikası',
              icon: Icons.shield_outlined,
              onTap: () => openLegalLink(context, LegalLinks.privacy),
            ),
            const Divider(color: AppColors.border, height: 1),
            _LegalRow(
              label: 'Kullanım Şartları',
              icon: Icons.description_outlined,
              onTap: () => openLegalLink(context, LegalLinks.terms),
            ),
            const Divider(color: AppColors.border, height: 1),
            _LegalRow(
              label: 'İletişim / Veri Silme Talebi',
              icon: Icons.mail_outline_rounded,
              onTap: () => openLegalLink(context, LegalLinks.contact),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegalRow extends StatelessWidget {
  const _LegalRow({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const Icon(
              Icons.open_in_new_rounded,
              size: 16,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
