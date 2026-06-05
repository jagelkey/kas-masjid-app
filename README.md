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

```bash
flutter pub get
flutter run
```

Tanpa konfigurasi Supabase, app tetap berjalan dalam mode lokal/offline.

Untuk mengaktifkan sync online:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://your-project-url.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

Jangan memasukkan `SUPABASE_SERVICE_ROLE_KEY` ke Flutter client. Operasi admin user berjalan melalui Supabase Edge Function `admin-users`.

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

Remote integration test dilewati secara default. Untuk menjalankannya:

```bash
flutter test test/full_integration_test.dart \
  --dart-define=TEST_SUPABASE_URL=https://your-project-url.supabase.co \
  --dart-define=TEST_SUPABASE_ANON_KEY=your-anon-key \
  --dart-define=TEST_SUPABASE_EMAIL=test-user@example.com \
  --dart-define=TEST_SUPABASE_PASSWORD=test-password
```
