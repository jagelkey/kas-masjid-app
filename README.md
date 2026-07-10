# App Masjid

Aplikasi Flutter offline-first untuk manajemen kas dan operasional masjid.

## Fitur Utama

- Dashboard saldo kas, pemasukan, pengeluaran, transaksi terbaru, dan kategori pengeluaran terbesar bulan ini.
- Transaksi kas masuk/keluar dengan bukti foto, filter tanggal/tipe/kategori, dan export PDF.
- Iuran Qurban: paket cicilan 250k/275k/custom, peserta jamaah, cicilan fleksibel 10 bulan, progress, dan laporan PDF.
- Jadwal kegiatan masjid dengan role permission.
- Profil masjid dan logo.
- Manajemen pengguna berbasis role: admin, ketua, bendahara, sekretaris, viewer.
- Audit log lokal dan sinkronisasi.
- Sync Center untuk melihat antrean data offline yang belum terkirim.
- Mode offline dengan credential lokal dan sinkronisasi saat online.

## Menjalankan App

Konfigurasi Supabase **wajib diberikan lewat `--dart-define` saat build/run**.
`Env` membacanya dengan `String.fromEnvironment`, jadi file `.env` **tidak**
dibaca otomatis oleh aplikasi Flutter — `.env` hanya sumber nilai untuk skrip
build di bawah.

```bash
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://your-project-url.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

Untuk APK rilis, pakai skrip yang sudah membaca `.env` untuk Anda:

```bash
./build_and_install.sh      # Linux/macOS
build_and_install.bat       # Windows
```

Skrip itu **berhenti dengan pesan jelas** kalau `SUPABASE_URL` /
`SUPABASE_ANON_KEY` tidak ditemukan. Ini disengaja: build tanpa keduanya
menghasilkan APK dengan `Env.hasValidConfig == false`, sehingga Supabase tidak
pernah diinisialisasi dan aplikasi berjalan 100% offline tanpa backend sama
sekali — sebelumnya ini terjadi diam-diam, tanpa peringatan apa pun.

Tanpa konfigurasi Supabase app memang tetap jalan (mode lokal/offline penuh),
tapi itu mode terpisah, bukan mode rilis.

Hanya `SUPABASE_URL` dan `SUPABASE_ANON_KEY` yang boleh masuk ke build. Jangan
pernah mengompilasi `SUPABASE_SERVICE_ROLE_KEY` atau `SUPABASE_DB_PASSWORD` ke
Flutter client (keduanya ada di `.env` untuk keperluan skrip/CLI saja) — apa pun
yang masuk APK bisa diekstrak kembali. Operasi admin user berjalan lewat Edge
Function `admin-users`, yang memegang service role key di sisi server.

## Backend Supabase

1. Jalankan `supabase_full_setup.sql` di Supabase SQL Editor.
   Untuk backend yang sudah pernah dibuat, jalankan migrasi tambahan
   `supabase/migrations/20260604_add_qurban_module.sql`.
2. Deploy Edge Function:

```bash
supabase secrets set SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
supabase functions deploy admin-users
```

3. Pastikan caller yang mengelola user memiliki role `admin` atau `ketua` di tabel `profiles`.

Jika sync menampilkan pesan function `admin-users` tidak ditemukan (`404 NOT_FOUND`),
artinya Edge Function belum ter-deploy ke project Supabase yang dipakai APK.
Data kas, kegiatan, Qurban, profil, dan audit log tetap bisa sync; perubahan
pengguna akan tetap antre di Sync Center sampai function tersebut tersedia.

## Validasi

```bash
flutter analyze
flutter test
```

Remote integration test dilewati secara default. Untuk menjalankannya, berikan
**kedua** set konfigurasi: pasangan `TEST_*` (yang dipakai test untuk login) dan
pasangan `SUPABASE_URL`/`SUPABASE_ANON_KEY` app-level (karena `SyncService`
menolak jalan kecuali `Env.hasValidConfig` bernilai true — dan `Env` membaca
define non-`TEST_`). Umumnya keduanya menunjuk project yang sama:

```bash
flutter test test/full_integration_test.dart \
  --dart-define=SUPABASE_URL=https://your-project-url.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key \
  --dart-define=TEST_SUPABASE_URL=https://your-project-url.supabase.co \
  --dart-define=TEST_SUPABASE_ANON_KEY=your-anon-key \
  --dart-define=TEST_SUPABASE_EMAIL=test-user@example.com \
  --dart-define=TEST_SUPABASE_PASSWORD=test-password
```

Kalau hanya pasangan `TEST_*` yang diberikan, test akan **dilewati dengan pesan
jelas** (bukan gagal membingungkan di tengah jalan).
