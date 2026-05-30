# Panduan Migrasi & Setup Database Supabase

Jika Anda meng-clone proyek ini dan ingin menghubungkannya ke project Supabase baru:

1.  **Buat Project Supabase Baru** di [database.new](https://database.new).
2.  **Buka SQL Editor** di dashboard Supabase Anda.
3.  **Jalankan Script Migrasi**:
    - Buka file `supabase_migration.sql` yang ada di root folder proyek ini.
    - Copy semua isinya.
    - Paste ke SQL Editor Supabase dan klik **RUN**.
4.  **Update Environment Variables**:
    - Buat file `.env` baru dari `.env.example`.
    - Masukkan URL dan Anon Key dari project Supabase baru Anda.
    - Masukkan Service Role Key (jika diperlukan untuk fitur admin).

Script `supabase_migration.sql` akan otomatis membuat:

- Semua tabel (`profiles`, `transactions`, `activities`, `mosque_profiles`, `audit_logs`).
- Trigger otomatis untuk user baru dan `updated_at`.
- Row Level Security (RLS) policies.
- Storage Buckets (`proofs`, `logos`) dan policies-nya.
