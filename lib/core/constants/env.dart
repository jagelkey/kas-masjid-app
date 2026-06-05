class Env {
  // Ganti dengan URL dan Anon Key dari Project Supabase Anda
  // Bisa didapatkan di: Supabase Dashboard -> Project Settings -> API

  // Konfigurasi produksi wajib diberikan lewat --dart-define.
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static bool get hasValidConfig =>
      supabaseUrl.isNotEmpty &&
      supabaseUrl != 'https://your-project-url.supabase.co' &&
      supabaseAnonKey.isNotEmpty &&
      supabaseAnonKey != 'your-anon-key';

  // Service role key tidak boleh berada di aplikasi client.
  // Operasi admin harus lewat backend/Edge Function.
}
