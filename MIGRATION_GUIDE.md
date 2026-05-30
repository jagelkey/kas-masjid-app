# Panduan Migrasi & Cloning Project App Masjid

Dokumen ini berisi panduan lengkap untuk memindahkan backend Supabase ke akun baru dan cara menjalankan project ini dari awal (cloning).

## 1. Setup Backend Supabase Baru

Langkah pertama adalah membuat project Supabase baru dan menyiapkan database.

### 1.1 Buat Project Baru

1. Login ke [Supabase Dashboard](https://supabase.com/dashboard).
2. Klik **New Project**.
3. Pilih Organization, beri nama project (misal: `MasjidApp`), set password database, dan pilih region terdekat (misal: `Singapore`).
4. Tunggu hingga proses provisioning selesai.

### 1.2 Migrasi Database (Schema & Policies)

Project ini sudah menyertakan file SQL untuk otomatisasi setup database.

1. Di Supabase Dashboard project baru Anda, buka menu **SQL Editor** (icon `>_` di sidebar kiri).
2. Klik **New Query**.
3. Buka file `supabase_migration.sql` yang ada di root folder project ini.
4. Copy semua isi dari `supabase_migration.sql` dan Paste ke dalam SQL Editor di Supabase.
5. Klik tombol **Run** di pojok kanan bawah.

> **Apa yang dilakukan script ini?**
>
> - Mengaktifkan ekstensi UUID.
> - Membuat Storage Buckets: `proofs` (untuk bukti transaksi) dan `logos` (untuk logo masjid).
> - Membuat Tabel: `profiles`, `mosque_profiles`, `transactions`, `activities`.
> - Mengatur Row Level Security (RLS) Policies agar data aman.
> - Membuat Triggers untuk `updated_at`.

### 1.3 Verifikasi Setup

- Buka menu **Table Editor**. Pastikan tabel-tabel di atas sudah muncul.
- Buka menu **Storage**. Pastikan bucket `proofs` dan `logos` sudah ada.
- Buka menu **Authentication** -> **Policies**. Pastikan policies sudah aktif.

### 1.4 Dapatkan API Credentials

1. Buka **Project Settings** (icon gear).
2. Pilih **API**.
3. Simpan **Project URL** dan **anon public key**. Anda akan membutuhkannya di langkah konfigurasi aplikasi.

---

## 2. Setup & Cloning Project Flutter

Setelah backend siap, saatnya menyiapkan aplikasi Flutter.

### 2.1 Clone Repository (Jika belum)

Jika Anda belum memiliki source code di lokal:

```bash
git clone <repository_url_anda>
cd App-Masjid
```

### 2.2 Install Dependencies

Pastikan Anda sudah menginstall Flutter SDK. Jalankan perintah berikut di terminal root project:

```bash
flutter pub get
```

### 2.3 Konfigurasi Environment (API Keys)

Ada dua cara untuk menghubungkan aplikasi ke Supabase baru Anda:

**Cara A: Edit File `env.dart` (Paling Mudah)**

1. Buka file `lib/core/constants/env.dart`.
2. Ganti nilai `defaultValue` pada `supabaseUrl` dan `supabaseAnonKey` dengan nilai dari project Supabase baru Anda.

```dart
// lib/core/constants/env.dart

static const String supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'MASUKKAN_PROJECT_URL_BARU_DISINI' // Ganti ini
);

static const String supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'MASUKKAN_ANON_KEY_BARU_DISINI' // Ganti ini
);
```

**Cara B: Menggunakan `--dart-define` (Lebih Aman)**
Tanpa mengubah kode, Anda bisa menyuntikkan key saat menjalankan aplikasi:

```bash
flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJxxx
```

### 2.4 Generate Code (Wajib)

Project ini menggunakan `json_serializable`, `freezed` (mungkin), atau `injectable` yang butuh code generation. Jalankan perintah ini:

```bash
dart run build_runner build --delete-conflicting-outputs
```

_Tunggu hingga proses selesai._

---

## 3. Menjalankan Aplikasi

Setelah semua langkah di atas selesai, jalankan aplikasi:

```bash
flutter run
```

### Tips Tambahan:

- **Testing Upload**: Coba login/register, lalu upload bukti transaksi atau logo masjid untuk memastikan Storage Bucket berfungsi.
- **Testing Realtime**: Jika fitur realtime tidak berjalan, pastikan "Realtime" diaktifkan di tabel Supabase (biasanya otomatis, tapi bisa dicek di Table Editor -> pilih tabel -> Realtime on).
