import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_analyzer_app/core/config/app_environment.dart';
import 'package:food_analyzer_app/core/services/supabase_service.dart';
import 'package:food_analyzer_app/core/router/app_router.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/core/widgets/fresh_cached_product_image.dart';

const _appEnvFile = '.env.client';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureFreshScanImageCache();

  try {
    // Load client-safe environment variables from the bundled asset file.
    await dotenv.load(fileName: _appEnvFile);
    validateReleaseEnvironment();
    await SupabaseService.initialize();
  } catch (e, stackTrace) {
    _debugStartupLog('Startup failed: $e');
    if (kDebugMode) {
      _debugStartupLog('$stackTrace');
    }
    runApp(_ErrorApp(message: _startupErrorMessageForUser(e), details: '$e'));
    return;
  }

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Etiketly',
      theme: AppTheme.lightTheme(),
      routerConfig: AppRouter.router,
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Error app displayed if Supabase initialization fails.
class _ErrorApp extends StatelessWidget {
  final String message;
  final String? details;

  const _ErrorApp({required this.message, this.details});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Initialization Error')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Supabase initialization failed:',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 16),
              Text(message, style: const TextStyle(fontSize: 16)),
              if (kDebugMode && details != null) ...[
                const SizedBox(height: 16),
                Text(
                  details!,
                  style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
                ),
              ],
              const SizedBox(height: 32),
              const Text(
                'Steps to fix:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text('1. Copy .env.client.example to $_appEnvFile if needed'),
              const Text('2. Fill only client-safe Supabase values'),
              const Text('3. Use an HTTPS OCR_BACKEND_URL for release builds'),
              const Text('4. Save the file and restart the app'),
            ],
          ),
        ),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

void _debugStartupLog(String message) {
  if (!kDebugMode) return;
  debugPrint('[startup] $message');
}

String _startupErrorMessageForUser(Object error) {
  if (error is AppEnvironmentValidationException) {
    return error.message;
  }

  if (kReleaseMode) {
    return 'Uygulama yapılandırması tamamlanamadı. Lütfen beta yapılandırmasını kontrol edip tekrar deneyin.';
  }

  return error.toString();
}
