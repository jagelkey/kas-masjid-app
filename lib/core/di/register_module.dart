import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@module
abstract class RegisterModule {
  @lazySingleton
  SupabaseClient get supabaseClient {
    try {
      return Supabase.instance.client;
    } catch (_) {
      // Return a placeholder or throw.
      // SyncService handles the case where supabaseClient is null or not configured in Env.
      // But we must return a non-null instance here for GetIt lazySingleton<T> where T is Object.
      // If we throw, the app might crash on startup.
      // However, SupabaseClient constructor requires url and key.
      // We can return a "dummy" client if needed, or better, rely on SyncService to handle injection failure?
      // No, SyncService depends on SupabaseClient.

      // If Env is not valid, we can't create a real client.
      // Let's assume Env is checked before accessing this.
      // Or we can modify SyncService to accept nullable SupabaseClient?
      // Yes, SyncService accepts nullable in constructor, but GetIt expects non-nullable here.

      // Hack: Return Supabase.instance.client anyway, let it throw if not initialized?
      // No, that's what we are catching.

      throw Exception(
        'Supabase not initialized. Call Supabase.initialize() first.',
      );
    }
  }
}
