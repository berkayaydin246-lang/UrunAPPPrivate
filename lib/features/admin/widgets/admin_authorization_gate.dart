import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/features/admin/controllers/admin_authorization_controller.dart';
import 'package:food_analyzer_app/features/admin/utils/admin_auth_debug.dart';

class AdminAuthorizationGate extends ConsumerWidget {
  const AdminAuthorizationGate({super.key, required this.authorizedBuilder});

  final Widget Function(BuildContext context, WidgetRef ref) authorizedBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(adminAuthorizationControllerProvider);
    debugAdminAuth('gate_rendering=${authState.status.name}');

    return switch (authState.status) {
      AdminAuthorizationStatus.checking => const Center(
        child: CircularProgressIndicator(),
      ),
      AdminAuthorizationStatus.signedOut => _AdminLoginView(
        errorMessage: authState.errorMessage,
      ),
      AdminAuthorizationStatus.notAuthorized => _AdminMessageView(
        icon: Icons.lock_outline,
        title: 'Yönetici Yetkisi Gerekiyor',
        message: 'Bu hesabın yönetici yetkisi yok.',
        actionLabel: 'Tekrar Dene',
        onAction: () =>
            ref.read(adminAuthorizationControllerProvider.notifier).retry(),
      ),
      AdminAuthorizationStatus.failure => _AdminMessageView(
        icon: Icons.error_outline,
        title: 'Doğrulama Başarısız',
        message: 'Yönetici yetkisi doğrulanamadı. Tekrar deneyin.',
        actionLabel: 'Tekrar Dene',
        onAction: () =>
            ref.read(adminAuthorizationControllerProvider.notifier).retry(),
      ),
      AdminAuthorizationStatus.authorized => authorizedBuilder(context, ref),
    };
  }
}

class AdminSignOutButton extends ConsumerWidget {
  const AdminSignOutButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(adminAuthorizationControllerProvider);
    if (!authState.canSignOut) {
      return const SizedBox.shrink();
    }

    return IconButton(
      tooltip: 'Çıkış yap',
      onPressed: () =>
          ref.read(adminAuthorizationControllerProvider.notifier).signOut(),
      icon: const Icon(Icons.logout_rounded),
    );
  }
}

class _AdminLoginView extends ConsumerStatefulWidget {
  const _AdminLoginView({this.errorMessage});

  final String? errorMessage;

  @override
  ConsumerState<_AdminLoginView> createState() => _AdminLoginViewState();
}

class _AdminLoginViewState extends ConsumerState<_AdminLoginView> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit =
        _emailController.text.trim().isNotEmpty &&
        _passwordController.text.isNotEmpty;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.border),
              boxShadow: AppShadows.soft(),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Yönetici Girişi',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Yönetici hesabınızla giriş yapın.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (widget.errorMessage != null) ...[
                  const SizedBox(height: 16),
                  _InlineError(message: widget.errorMessage!),
                ],
                const SizedBox(height: 18),
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        key: const ValueKey('admin-login-email'),
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(labelText: 'E-posta'),
                        validator: (value) {
                          if ((value ?? '').trim().isEmpty) {
                            return 'E-posta gereklidir.';
                          }
                          return null;
                        },
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const ValueKey('admin-login-password'),
                        controller: _passwordController,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        decoration: const InputDecoration(labelText: 'Şifre'),
                        validator: (value) {
                          if ((value ?? '').isEmpty) {
                            return 'Şifre gereklidir.';
                          }
                          return null;
                        },
                        onChanged: (_) => setState(() {}),
                        onFieldSubmitted: (_) => canSubmit ? _submit() : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Semantics(
                  label: 'Yönetici girişi yap',
                  button: true,
                  child: ElevatedButton(
                    key: const ValueKey('admin-login-button'),
                    onPressed: canSubmit ? _submit : null,
                    child: const Text('Giriş Yap'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    debugAdminAuth('login_button_tapped');
    final isFormValid = _formKey.currentState?.validate() ?? false;
    debugAdminAuth('form_valid=$isFormValid');
    if (!isFormValid) return;

    debugAdminAuth(
      'credentials email_length=${_emailController.text.trim().length} '
      'password_length=${_passwordController.text.length}',
    );
    FocusScope.of(context).unfocus();
    await ref
        .read(adminAuthorizationControllerProvider.notifier)
        .signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );
  }
}

class _AdminMessageView extends StatelessWidget {
  const _AdminMessageView({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 52, color: AppColors.primary),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.dangerBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 18, color: AppColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.dangerText),
            ),
          ),
        ],
      ),
    );
  }
}
