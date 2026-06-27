import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service to initialize and provide access to Supabase client.
///
/// This is a simple wrapper that handles initialization and throws
/// helpful errors if environment variables are missing.
class SupabaseService {
  SupabaseService._();

  static Supabase? _instance;

  /// Get the initialized Supabase instance.
  ///
  /// Call [initialize] first before accessing this.
  static Supabase get instance {
    if (_instance == null) {
      throw StateError(
        'SupabaseService not initialized. Call SupabaseService.initialize() in main() first.',
      );
    }
    return _instance!;
  }

  /// Get the Supabase client directly.
  static SupabaseClient get client => instance.client;

  /// Initialize Supabase with environment variables.
  ///
  /// Throws [Exception] if SUPABASE_URL or SUPABASE_ANON_KEY are missing.
  static Future<void> initialize() async {
    try {
      final url = dotenv.env['SUPABASE_URL'];
      final anonKey = dotenv.env['SUPABASE_ANON_KEY'];

      if (url == null || url.isEmpty) {
        throw Exception(
          'SUPABASE_URL not found in environment variables. '
          'Create a .env file in the project root with:\n'
          'SUPABASE_URL=https://your-project.supabase.co',
        );
      }

      if (anonKey == null || anonKey.isEmpty) {
        throw Exception(
          'SUPABASE_ANON_KEY not found in environment variables. '
          'Create a .env file in the project root with:\n'
          'SUPABASE_ANON_KEY=your-anon-key-here',
        );
      }

      await Supabase.initialize(url: url, anonKey: anonKey);

      _instance = Supabase.instance;
    } on Exception catch (e) {
      // Re-throw with better error message for developers
      throw Exception('Supabase initialization failed: $e');
    }
  }
}
