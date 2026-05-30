class Env {
  // Ganti dengan URL dan Anon Key dari Project Supabase Anda
  // Bisa didapatkan di: Supabase Dashboard -> Project Settings -> API

  // Opsi 1: Hardcode di sini (Mudah tapi kurang aman jika code dishare)
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://your-project-url.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'your-supabase-jwt',
  );

  static bool get hasValidConfig =>
      supabaseUrl != 'https://your-project-url.supabase.co' &&
      supabaseAnonKey != 'your-anon-key';

  static const String supabaseServiceRoleKey = String.fromEnvironment(
    'SUPABASE_SERVICE_ROLE_KEY',
    defaultValue:
        'your-supabase-jwt',
  );
}
