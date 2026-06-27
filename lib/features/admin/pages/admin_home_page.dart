import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/features/admin/widgets/admin_authorization_gate.dart';

class AdminHomePage extends StatelessWidget {
  const AdminHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Yönetim'),
        actions: const [AdminSignOutButton()],
      ),
      body: AdminAuthorizationGate(
        authorizedBuilder: (context, ref) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              const _AdminHero(),
              const SizedBox(height: 22),
              _AdminMenuCard(
                icon: Icons.report_outlined,
                title: 'Ürün Bildirimleri',
                subtitle:
                    'Kullanıcıların ürün bilgileri için gönderdiği bildirimleri incele.',
                color: AppColors.accent,
                onTap: () => context.pushNamed('admin_product_reports'),
              ),
              const SizedBox(height: 14),
              // TODO(pre-release): Legacy staging/submission admin screens still
              // need separate hardening before production. Keep new product
              // reports review flows RPC-only and do not reuse those older data
              // access patterns as a security template.
              _AdminMenuCard(
                icon: Icons.inventory_2_outlined,
                title: 'Staging Ürünleri',
                subtitle: 'İçe aktarılan staging kayıtlarını gözden geçir.',
                color: AppColors.primary,
                onTap: () => context.pushNamed('product_staging_review'),
              ),
              const SizedBox(height: 12),
              _AdminMenuCard(
                icon: Icons.fact_check_outlined,
                title: 'Ürün Gönderileri',
                subtitle: 'Eksik ürün başvurularını incele ve değerlendir.',
                color: AppColors.info,
                onTap: () => context.pushNamed('product_submission_review'),
              ),
              const SizedBox(height: 12),
              _AdminMenuCard(
                icon: Icons.speed_outlined,
                title: 'OCR Benchmark',
                subtitle: 'OCR kalite ve hız ölçümlerini kontrol et.',
                color: AppColors.warning,
                onTap: () => context.pushNamed('ocr_benchmark'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AdminHero extends StatelessWidget {
  const _AdminHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.textPrimary, AppColors.primary],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: AppShadows.soft(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.admin_panel_settings_outlined,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Etiketly yönetim alanı',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Bildirimleri incele, kayıtları takip et ve yönetim akışlarını güvenli şekilde yürüt.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.84),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminMenuCard extends StatelessWidget {
  const _AdminMenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

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
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadows.soft(color),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
