# Laporan Analisis Mendalam (Deep Dive Analysis Report)
**Proyek:** App-Masjid
**Tanggal Analisis:** 2026-04-30

Laporan ini berisi temuan hasil analisis mendalam terhadap basis kode, mencakup analisis statis, keamanan, logika BLoC, serta mekanisme data dan sinkronisasi.

---

## 1. Hasil Analisis Statis (`flutter analyze`)
Ditemukan **93 isu** yang terbagi dalam beberapa kategori:
- **Error (73 Temuan):** Mayoritas berada di direktori `test/`. 
  - Dependensi `bloc_test` dan `mockito` belum terdaftar di `pubspec.yaml`.
  - File mock (`.mocks.dart`) belum di-generate (menghasilkan error `undefined_class` dan `undefined_function`).
  - Konflik *import* `AuthState` di `auth_bloc_update_profile_test.dart`.
- **Warning (7 Temuan):**
  - *Unnecessary Non-null Assertion* (`!`) berlebihan di `sync_service.dart`.
  - *Dead Code* (kode yang tidak tereksekusi) di `auth_bloc.dart`.
- **Info (13 Temuan):**
  - *Unnecessary import* `dart:typed_data` di `pdf_service.dart`.
  - Penggunaan `print()` di file testing yang sebaiknya dihindari.

---

## 2. Keamanan & Logika Autentikasi (Auth & User Management)
- **Celah Keamanan Kritis:**
  - `supabaseServiceRoleKey` disimpan secara statis di `env.dart` dan digunakan di *client*. Sangat berbahaya jika terekspos karena bisa membypass RLS (Row Level Security).
  - *Password* untuk mode *offline* di-hash dengan SHA-256 biasa (tanpa *salt*).
  - Metadata sensitif tidak terhapus sempurna dari SQLite saat *logout*.
- **Error Logika & Potensi Bug:**
  - Pembuatan *user* offline dengan email yang ternyata sudah ada di Supabase dapat memicu *sync conflict* permanen.
  - Penghapusan *user* di `UserRepositoryImpl` tidak mengecek relasi (*foreign key constraint*). Jika user tersebut terhubung ke log transaksi atau aktivitas, aplikasi berpotensi mogok (crash).
  - Logika *auto-migration* login dapat *crash* jika email sudah dimiliki pengguna lain.
- **Fitur Belum Selesai:**
  - Fitur "Ganti Password" untuk akun lokal/offline belum didukung.
  - Fitur "Lupa Password" belum diimplementasikan.

---

## 3. State Management & Logika Fitur Utama (BLoC)
- **ActivityBloc & TransactionBloc:**
  - **Memory Leak & Multiple Subscriptions:** Pemanggilan event *Load* berulang kali (mis. *pull-to-refresh*) tanpa transformer `restartable` dari `bloc_concurrency` memicu tumpukan *stream subscription*.
  - **State Loss:** Jika proses *Add/Update/Delete* gagal, BLoC meng-emit `ErrorState` yang langsung menimpa `LoadedState`, menyebabkan daftar aktivitas/transaksi di layar hilang.
  - **Race Condition:** Pada `TransactionBloc._onLoadTransactions`, terdapat eksekusi *async* yang berjalan bersamaan untuk menarik *balance*, *income*, dan *expense*. Respons yang *out-of-order* berpotensi menampilkan *stale data*.
  - **Dead Code:** Event `ActivitiesUpdated` di `ActivityBloc` tidak pernah dipanggil.
- **ProfileBloc:**
  - **UX Bug:** Event `SaveProfile` langsung meng-emit `ProfileLoading()`, menghilangkan form pengisian dari layar. 

---

## 4. Lapisan Data & Sinkronisasi (Offline-First)
- **Kegagalan Data (Data Failures):**
  - *Swallow Error* pada `StringListConverter` di SQLite. Jika gagal memparsing JSON gambar, ia diam-diam mengembalikan *list* kosong.
  - Kegagalan upload logo masjid akan membatalkan seluruh sinkronisasi `Profile` secara permanen.
- **Race Condition Sinkronisasi:**
  - Fungsi `syncData()` dapat dieksekusi secara paralel jika ditekan berulang dengan cepat, memicu duplikasi pengiriman data (double insert) ke Supabase.
  - Saat menarik data (`_pullTransactions`), strategi yang digunakan adalah *Client Wins* murni tanpa mekanisme penggabungan (*merge*), sehingga berpotensi menimpa pembaruan dari perangkat lain secara buta.
- **Bug Sinkronisasi:**
  - **Infinite Loop Partial Upload:** Jika sebagian gambar bukti transaksi gagal terunggah, status tetap menjadi `pendingUpdate`. Saat sinkronisasi berikutnya, ia mengulangi *upload* dari awal.
- **Fitur Belum Optimal / N+1 Issue:**
  - Sinkronisasi menarik dan mengirim data satu per satu di dalam *loop* tanpa *batching* API (sangat membebani performa jaringan).
  - Tidak ada *cursor-based pagination* (seperti berdasarkan `updated_at`); aplikasi menarik semua baris tabel yang ada secara *brute-force* (Overfetching).
  - Limitasi keras (*hardcode*) `limit(100)` pada penarikan Audit Logs, membuat aktivitas di atas 100 log terhapus jika terlewat saat offline.
  - Belum ada *Garbage Collection* di *database* lokal (SQLite akan membengkak).

---

## Kesimpulan & Rekomendasi
Aplikasi telah memiliki dasar fitur yang cukup baik, namun **membutuhkan refactoring ekstensif** sebelum dapat dikatakan siap *production*. Rekomendasi prioritas perbaikan:
1. **Keamanan:** Segera pindahkan operasi *admin user* ke Supabase Edge Functions dan amankan proses penyimpanan sandi lokal.
2. **BLoC Refactor:** Gunakan `restartable` pada *stream*, dan satukan status eksekusi (Loading/Error) ke dalam state `Loaded` agar UI tidak hilang.
3. **Optimasi Sinkronisasi:** Terapkan *batch processing*, sinkronisasi berbasis *timestamp*, serta kunci `_isSyncing` untuk mencegah eksekusi paralel.
4. **Perbaikan Error Test:** Perbaiki konfigurasi *testing* dan *mock files* agar CI/CD bisa berjalan lancar.
