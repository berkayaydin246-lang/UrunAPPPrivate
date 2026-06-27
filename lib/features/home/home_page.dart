import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            const _HomeHeader(),
            const SizedBox(height: 22),
            _SearchAction(onTap: () => context.goNamed('search')),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _ActionCard(
                    icon: Icons.qr_code_scanner,
                    title: 'Barkod Tara',
                    subtitle: 'Ürünü hızlıca analiz et.',
                    color: AppColors.primary,
                    onTap: () => context.goNamed('barcode'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionCard(
                    icon: Icons.document_scanner_outlined,
                    title: 'Etiket Tara',
                    subtitle: 'İçindekileri OCR ile oku.',
                    color: AppColors.accent,
                    onTap: () => context.goNamed('ocr'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _ActionCard(
              icon: Icons.bookmarks_outlined,
              title: 'Kitaplığım',
              subtitle: 'Favorilerin ve son baktığın ürünler burada.',
              color: AppColors.info,
              horizontal: true,
              onTap: () => context.goNamed('history'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryLight],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: AppShadows.soft(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.eco_outlined, color: Colors.white),
          ),
          const SizedBox(height: 18),
          Text(
            'Bugün hangi ürünü inceleyelim?',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              height: 1.08,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Barkod okut, ürün ara veya kategori seç.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.86),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchAction extends StatelessWidget {
  final VoidCallback onTap;

  const _SearchAction({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadows.soft(),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.surfaceSoft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.search, color: AppColors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Ürün, marka veya barkod ara',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool horizontal;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.horizontal = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadows.soft(color),
          ),
          child: horizontal
              ? Row(children: _horizontalChildren(context))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _verticalChildren(context),
                ),
        ),
      ),
    );
  }

  List<Widget> _verticalChildren(BuildContext context) {
    return [
      _IconTile(icon: icon, color: color),
      const SizedBox(height: 14),
      _ActionCopy(title: title, subtitle: subtitle),
    ];
  }

  List<Widget> _horizontalChildren(BuildContext context) {
    return [
      _IconTile(icon: icon, color: color),
      const SizedBox(width: 12),
      Expanded(
        child: _ActionCopy(title: title, subtitle: subtitle),
      ),
      Icon(Icons.arrow_forward_rounded, color: color),
    ];
  }
}

class _IconTile extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _IconTile({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: color),
    );
  }
}

class _ActionCopy extends StatelessWidget {
  final String title;
  final String subtitle;

  const _ActionCopy({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}
