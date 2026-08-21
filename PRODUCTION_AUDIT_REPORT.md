# Audit Kesiapan Produksi — App Masjid

**Tanggal audit:** 2026-07-08
**Lingkup:** Seluruh alur transaksi (kas, Qurban), sinkronisasi offline-first, autentikasi/otorisasi, RLS Supabase, skema database lokal (Drift), dan kualitas test/static analysis.
**Metode:** Pembacaan kode langsung + 5 audit mendalam paralel per domain (transaksi keuangan, modul Qurban, sync engine, auth/RBAC/RLS, skema DB lokal), ditambah eksekusi langsung `flutter analyze`, `flutter test`, dan pengecekan kredensial di seluruh repo. Setiap temuan di bawah sudah diverifikasi dengan membaca kode aktual (file:line), bukan dugaan.

## Verdict

**Per 2026-07-09 (akhir hari): semua yang bisa dan sebaiknya diperbaiki lewat kode, sudah diperbaiki.** Semua 5 isu Critical, semua 5 isu High, 11 dari 12 isu Medium (termasuk M7/M8 performa sync dan bagian test dari M11), dan 3 dari 5 catatan Low **sudah diperbaiki di kode**, lolos `flutter analyze` (0 isu) + `flutter test` (44/44 pass) di SETIAP tahap perbaikan, tanpa regresi sepanjang proses. Sisa migrasi tipe uang (M1) **ditanyakan langsung ke user dan dengan sengaja DITAHAN** atas keputusan bersama — bukan sesuatu yang tertunda karena belum sempat, tapi keputusan sadar bahwa ini proyek terpisah. Yang masih menahan status "siap penuh":
1. Dua tindakan manual di Supabase Dashboard belum dikonfirmasi selesai (rotasi password DB, deploy KEDUA migrasi baru) — lihat "Update 2026-07-08" dan "Update 2026-07-09".
2. **Belum ada pengujian manual/live sama sekali** di browser/emulator/device fisik, di seluruh proses audit ini — semua verifikasi adalah `flutter analyze` + `flutter test` + penelusuran kode, bukan menjalankan aplikasinya secara nyata. Ini termasuk belum menguji jalur upgrade skema database yang sesungguhnya (`schemaVersion` lama →7) di perangkat yang sudah terpasang versi lama — test otomatis yang ada baru memverifikasi skema `onCreate`, bukan `onUpgrade`.
3. Sisa 2 item Low (retry foto tanpa batas, StringListConverter kosmetik) sengaja tidak dikerjakan — risiko mengerjakannya lebih besar dari manfaatnya, lihat alasan di masing-masing.
4. Migrasi tipe uang `double`→integer (sisa M1) — ditahan atas persetujuan bersama, lihat catatan di item M1. Bukan penghalang rilis; jadikan proyek tersendiri kalau/ketika mau dikerjakan.

Banyak isu dari laporan audit sebelumnya (2026-04-30) juga **sudah benar-benar diperbaiki** sebelum audit ini dimulai — lihat bagian "Sudah Diperbaiki" di bawah, tim sudah membuat progres nyata dari awal.

Jangan andalkan dokumen `PRODUCTION_RELEASE_SUMMARY.md`, `IMPLEMENTATION_COMPLETE.md`, `DEPLOYMENT_CHECKLIST.md`, dll di root repo — dokumen-dokumen itu mengklaim "95% confidence / APPROVED FOR PRODUCTION" namun kotak sign-off-nya kosong/placeholder dan tidak mencerminkan temuan Critical di audit ini.

---

## Update 2026-07-08 — Status Perbaikan Critical

Kelima isu Critical (C1–C5) di bawah **sudah diperbaiki di kode** dan diverifikasi ulang dengan `flutter analyze` (0 isu) dan `flutter test` (39/39 pass, tidak ada regresi). Detail perbaikan ada di masing-masing item di bawah dengan tag `[FIXED]`.

**Masih perlu tindakan manual dari Anda (tidak bisa dilakukan lewat tools):**
1. **Rotasi password database Supabase** yang bocor di `scripts/create_admin.js` (C3) — lakukan dari Supabase Dashboard → Settings → Database sekarang juga. Kode sudah diperbaiki agar tidak ada lagi credential hardcoded, tapi password lama yang sudah terekspos tetap harus diganti.
2. **Deploy migrasi baru** `supabase/migrations/20260708_fix_role_escalation_and_admin_claim.sql` ke project Supabase yang sudah berjalan (lihat `README.md` untuk cara menjalankan migrasi). Untuk project baru, `supabase_full_setup.sql` sudah memuat perbaikan ini secara langsung.
3. **Redeploy tidak diperlukan untuk Edge Function** `admin-users` — tidak ada perubahan di situ.
4. Setelah migrasi di atas dijalankan, uji ulang alur "Daftar Masjid Baru" dan "Login" sekali di lingkungan staging sebelum rilis ke client.

## Update 2026-07-09 — Status Perbaikan High

Kelima isu High (H1–H5) di bawah **sudah diperbaiki di kode** dan diverifikasi ulang dengan `flutter analyze` (0 isu) dan `flutter test` (39/39 pass, tidak ada regresi). Detail di masing-masing item dengan tag `[FIXED]`. Item Medium/Low masih belum dikerjakan.

**Catatan penting soal batas perbaikan H4:** yang diperbaiki adalah risiko utamanya (kehilangan data pembayaran secara permanen). Sinkronisasi penghapusan ke mirror lokal device lain (tombstone/propagasi delete) **belum** dibangun — itu perubahan arsitektur sinkronisasi yang lebih besar dan sengaja tidak termasuk di iterasi ini. Lihat catatan di item H4.

---

## 🔴 CRITICAL — Wajib diperbaiki sebelum rilis

### C1. Siapapun bisa mendaftar sebagai admin, kapan saja `[FIXED]`
**File:** `lib/presentation/pages/register_mosque_page.dart`, `lib/core/router/app_router.dart`
Halaman `/register-mosque` selalu mengirim `role: UserRole.admin` untuk akun yang didaftarkan, dan router tidak pernah mengecek apakah mosque/admin sudah pernah dibuat sebelumnya. Siapa pun yang menemukan URL login aplikasi bisa membuka halaman ini kapan saja (bukan cuma saat setup awal) dan langsung mendapat akun admin penuh — akses baca/tulis semua transaksi, data Qurban, dan manajemen user.
**Fix:** Batasi route ini agar hanya bisa diakses saat belum ada admin sama sekali (mis. cek `SELECT count(*) FROM profiles WHERE role='admin'` sebelum render), atau lebih baik: pindahkan pembuatan admin pertama ke proses provisioning manual (Edge Function/SQL saat setup project), bukan halaman publik permanen di dalam app.

**Diterapkan:** Penggantian `role` di metadata signup dihapus dari `auth_bloc.dart` (tidak lagi dipercaya sama sekali, lihat C2). Klaim admin pertama sekarang lewat fungsi DB `claim_first_admin()` yang atomik dan hanya bisa sukses sekali per project (lihat migrasi baru di C2). `register_mosque_page.dart` menambahkan pengecekan `mosque_admin_exists()` di awal — jika sudah ada admin, user langsung diarahkan ke halaman login dengan pesan jelas, bukan diizinkan mengisi form yang ujungnya akan ditolak.

### C2. Eskalasi hak akses sendiri lewat Supabase RLS (`profiles.role`) `[FIXED]`
**File:** `supabase/migrations/20260601000000_init.sql:231-232` (identik di `supabase_full_setup.sql`)
```sql
CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);
```
Policy ini **tidak punya `WITH CHECK`**, sehingga hanya membatasi *baris mana* yang boleh diubah (baris milik sendiri) — bukan *kolom mana*. Ditambah `GRANT ... UPDATE ON TABLE public.profiles TO authenticated` yang mencakup semua kolom termasuk `role`. Akibatnya, user dengan role `viewer` bisa memanggil langsung:
```
supabase.from('profiles').update({'role':'admin'}).eq('id', myId)
```
lewat API (di luar app Flutter sama sekali) dan **berhasil** menaikkan diri jadi admin. Tidak ada trigger yang membandingkan `OLD.role` vs `NEW.role`.

Lebih parah lagi: `handle_new_user()` (`init.sql:163-177`, `SECURITY DEFINER`) mengambil `role` langsung dari metadata yang dikirim client saat sign-up, tanpa validasi — artinya siapa pun bisa `signUp({data:{role:'admin'}})` dan langsung dapat profil admin tanpa perlu exploit apa pun (`scripts/create_admin_api.js` di repo ini secara tidak sengaja adalah contoh kerja nyatanya).

Dampak lanjutan: policy `"Admins and Ketua can update any profile"` juga tanpa `WITH CHECK` dan tidak membatasi baris target dengan benar, jadi user yang sudah self-escalate bisa mengubah profil user LAIN (termasuk menurunkan admin asli). `admin-users` Edge Function juga hanya mengecek `profiles.role` yang sama ini — jadi rantainya sampai ke pengambilalihan penuh (create/delete user Supabase Auth sungguhan).
**Fix:** Tambahkan `WITH CHECK` yang mengunci kolom `role` agar hanya berubah lewat path admin (mis. `WITH CHECK (auth.uid() = id AND role = (SELECT role FROM public.profiles WHERE id = auth.uid()))`), validasi `role` di `handle_new_user()` terhadap allowlist yang aman (default selalu `viewer`, jangan percaya metadata client), dan audit ulang policy "admin can update any profile" agar benar-benar scoped.

**Diterapkan:** Persis seperti rekomendasi di atas — `WITH CHECK` ditambahkan ke kedua policy UPDATE pada `profiles` (self-update dan admin/ketua-update-siapapun), dan `handle_new_user()` sekarang selalu memaksa `role = 'viewer'` untuk akun baru, mengabaikan metadata dari client. Ditambahkan juga fungsi `claim_first_admin()` (satu-satunya jalur legal untuk mendapat role admin pertama kali, atomik & sekali pakai) dan `mosque_admin_exists()` (pengecekan publik read-only untuk UX). Perubahan ada di tiga tempat yang harus tetap sinkron: `supabase/migrations/20260601000000_init.sql`, `supabase_full_setup.sql` (diperbarui in-place, untuk project baru), dan migrasi baru `supabase/migrations/20260708_fix_role_escalation_and_admin_claim.sql` (untuk project yang sudah berjalan — **wajib dijalankan manual di Supabase SQL Editor**, tools ini tidak bisa menjalankannya untuk Anda).

### C3. Password database produksi ter-hardcode di file `[FIXED — kode saja]`
**File:** `scripts/create_admin.js:4`
```js
connectionString: 'postgresql://postgres:<DB_PASSWORD_REDACTED>@db.<project-ref>.supabase.co:5432/postgres'
```
Ini adalah kredensial superuser Postgres asli dalam bentuk plaintext, di file yang belum ter-commit ke git tapi sudah ada di working directory (berisiko ter-`git add -A` tanpa sadar). Karena kredensial ini sudah terekspos ke sesi ini, anggap sudah bocor. (Password asli sengaja di-redaksi dari dokumen ini agar tidak masuk ke git history — lihat `.env` untuk nilai sebenarnya, yang sudah di-`.gitignore`.)
**Fix:** **Rotasi password database ini sekarang juga** dari Supabase Dashboard, hapus file `scripts/create_admin.js` dan `scripts/create_admin_api.js` (atau pindahkan ke `.env`-based config dan pastikan masuk `.gitignore`), jangan pernah hardcode kredensial produksi di script ad-hoc. (Sudah dicek: tidak ada kredensial lain yang bocor di tempat lain pada repo ini.)

**Diterapkan:** Kedua script sekarang membaca kredensial dari environment variable (`DATABASE_URL`, `ADMIN_EMAIL`, `ADMIN_PASSWORD`, dst) alih-alih hardcode, dan diberi komentar bahwa keduanya adalah fallback manual legacy — jalur yang direkomendasikan untuk admin pertama adalah lewat app (`register_mosque_page.dart` + `claim_first_admin()`). **Yang TIDAK bisa saya lakukan lewat tools:** benar-benar merotasi password database (nilai di-redaksi) di Supabase Dashboard — itu wajib Anda lakukan sendiri, sekarang, karena password itu sudah terekspos ke sesi ini.

### C4. Transaksi duplikat masih bisa terjadi (root cause lama belum diperbaiki) `[FIXED]`
**File:** `lib/presentation/pages/transaction_form_page.dart:588-626`, `lib/presentation/blocs/transaction/transaction_bloc.dart:170`
`_submitForm()` tidak punya guard internal (`if (_isSubmitting) return;`) — hanya mengandalkan `onPressed: _isSubmitting ? null : _submitForm`, dan setiap kali dipanggil ia generate `Uuid().v4()` baru, sehingga dua kali tap menghasilkan **dua transaksi berbeda**, bukan retry dari yang sama. `AddTransactionEvent` didaftarkan dengan transformer `concurrent()` default (bukan `droppable()`/`sequential()`), dan tidak ada unique constraint apa pun (lokal maupun remote) yang berbasis konten untuk mencegah duplikat. Ini persis pola yang dibersihkan manual oleh `cleanup_duplicate_transactions.sql` — artinya insiden itu kemungkinan besar akan terulang.
**Fix:** Tambahkan guard eksplisit di awal `_submitForm()`, ganti transformer `AddTransactionEvent` ke `droppable()`, dan idealnya tambahkan constraint anti-duplikat (mis. idempotency key per submit) di level repository/DB.

**Diterapkan:** Guard `if (_isSubmitting) return;` ditambahkan di baris pertama `_submitForm()`. `AddTransactionEvent`, `UpdateTransactionEvent`, dan `DeleteTransactionEvent` semuanya diganti ke transformer `droppable()` di `transaction_bloc.dart`, jadi BLoC sendiri menolak event kedua selama satu operasi masih berjalan — proteksi ini tidak lagi bergantung sepenuhnya pada state UI. Constraint idempotency di level DB belum ditambahkan (di luar scope perbaikan cepat ini, masuk daftar rekomendasi lanjutan).

### C5. Tabel profil masjid bisa punya 2 baris → seluruh halaman profil crash `[FIXED]`
**File:** `lib/data/repositories/mosque_profile_repository_impl.dart:44-90`, `lib/data/datasources/local/app_database.dart:125-135`
Tabel `MosqueProfiles` tidak punya unique/singleton constraint. `saveProfile()` memakai pola read-lalu-insert-atau-update tanpa dibungkus `_db.transaction()`. Dua panggilan `saveProfile()` yang hampir bersamaan (double-tap simpan, atau retry setelah timeout jaringan) bisa sama-sama melihat "belum ada profil" dan sama-sama insert → 2 baris. Setelah itu, **setiap** pemanggilan `getProfile()` memakai `getSingleOrNull()` yang di Drift akan **throw `StateError`** begitu baris > 1 — layar profil (dan apa pun yang butuh data masjid, termasuk halaman login yang menampilkan nama masjid) akan crash terus sampai baris ekstra dihapus manual dari database.
**Fix:** Bungkus read-check-write dalam satu `_db.transaction()`, dan/atau tambahkan constraint agar tabel ini maksimal 1 baris (mis. primary key tetap/fixed id, upsert by that id).

**Diterapkan:** `saveProfile()` di `mosque_profile_repository_impl.dart` sekarang dibungkus `_db.transaction()`, sehingga dua panggilan simpan yang hampir bersamaan akan diserialisasi oleh Drift (panggilan kedua akan melihat baris yang baru dibuat panggilan pertama, bukan sama-sama insert). Sebagai lapisan pertahanan tambahan, `getProfile()` dan pembacaan profil di `sync_service.dart` (`_pullMosqueProfile`) diganti dari `getSingleOrNull()` (yang crash bila >1 baris) menjadi query `order by id, limit 1` — jadi kalaupun sebuah device sudah terlanjur punya baris duplikat dari sebelum perbaikan ini, aplikasi tetap jalan (pakai baris pertama) alih-alih crash terus-menerus.

---

## 🟠 HIGH

- **H1 — Pembatasan role di UI bersifat kosmetik untuk transaksi. `[FIXED]`** `app_router.dart` tidak punya guard role di route `/transactions/add|edit`; hanya tombol yang disembunyikan. User `viewer`/`sekretaris` yang mengakses route langsung tetap bisa submit, mendapat pesan **"berhasil"**, lalu sinkronisasi diam-diam gagal permanen di background (diblok RLS admin/bendahara) tanpa ada indikasi apa pun ke user. Data tersebut nyangkut selamanya sebagai `pendingCreate` yang tidak pernah sinkron.
  **Diterapkan:** `app_router.dart` sekarang punya `_roleRedirect()` yang diterapkan ke SEMUA rute mutasi sensitif (bukan cuma transaksi): `/transactions/add|edit`, `/activities/add|edit`, `/qurban/packages`, `/qurban/participant/add|edit`, `/qurban/payment/add|edit`, `/settings/users`, `/settings/audit-logs`. `GlobalAuthNotifier` diperluas dengan `currentRole`, di-update oleh `AuthBloc` di setiap titik perubahan sesi (login/logout/register/restore), sehingga router (bukan widget, tidak punya akses `BuildContext`/Provider yang mudah) bisa menolak akses tanpa bergantung pada state UI. Ini juga otomatis menutup M6 (tidak ada role-guard di router sama sekali).
- **H2 — Foto bukti transaksi bisa hilang permanen secara diam-diam. `[FIXED]`** `sync_service.dart` (`_uploadFile`) mengembalikan `null` tanpa exception saat file lokal sudah tidak ada (mis. dihapus OS/storage cleanup), tapi kode tidak menandai `hasUploadError` untuk kasus ini — transaksi tetap ditandai `synced` dan `proofPaths` dikosongkan. Tidak ada retry, tidak ada indikator ke user bahwa foto bukti hilang.
  **Diterapkan:** Kedua loop upload di `_pushTransactions` (pendingCreate & pendingUpdate) sekarang menandai `hasUploadError = true` juga saat `_uploadFile` mengembalikan `null`, bukan cuma saat exception. Transaksi tetap `pendingUpdate` dan path yang gagal tetap di-retry tiap sync — sama seperti perilaku untuk kegagalan jaringan yang sudah benar sebelumnya.
- **H3 — Kegagalan upload logo membekukan seluruh sync profil masjid. `[FIXED]`** `sync_service.dart:1083-1090`: jika upload logo gagal, exception dilempar **sebelum** perubahan nama/alamat sempat dikirim, lalu ditangkap dan disimpan sebagai error — seluruh baris profil (termasuk field yang tidak berhubungan dengan logo) tetap stuck di status pending selamanya, retry demi retry gagal dengan cara yang identik.
  **Diterapkan:** `_pushMosqueProfile` sekarang melacak kegagalan logo secara terpisah (`logoUploadFailed`) dan **mengecualikan key `logo_url`** dari payload saat gagal (bukan mengirim `null`), sehingga PostgREST membiarkan `logo_url` remote apa adanya sementara `name`/`address` tetap terkirim. Baris tetap `pendingUpdate` (bukan `synced`) agar logo dicoba lagi di sync berikutnya, dan errornya dilaporkan ke `errors` list.
- **H4 — Race condition multi-device pada penghapusan peserta Qurban. `[FIXED — mitigasi utama]`** `qurban_repository_impl.dart:293-304` memblokir hapus peserta HANYA jika ada pembayaran di database **lokal**. Device A yang belum sempat pull pembayaran dari Device B akan lolos guard ini, menghapus peserta; cascade delete di server (`ON DELETE CASCADE` pada `qurban_payments`) ikut menghapus pembayaran milik Device B yang sudah tersinkron, meninggalkan transaksi income terkait nyangkut permanen di buku kas tanpa jejak peserta/pembayaran. Pull juga bersifat additive-only (penghapusan tidak pernah menyebar ke mirror lokal device lain).
  **Diterapkan:** `_pushQurbanParticipants` di `sync_service.dart` sekarang melakukan pengecekan ULANG ke server (bukan cuma lokal) tepat sebelum mengeksekusi delete: query `qurban_payments` remote untuk `participant_id` tsb. Jika ada, delete DIBATALKAN, peserta dikembalikan ke status `synced` (bukan dibiarkan nyangkut `pendingDelete` selamanya), dan error dicatat supaya user tahu harus tarik data terbaru dulu. **Ini menutup risiko data-loss utamanya** (pembayaran/transaksi milik device lain tidak lagi bisa terhapus tanpa sepengetahuan). **Yang BELUM dikerjakan** (di luar scope perbaikan ini, perubahan arsitektur yang lebih besar): propagasi penghapusan ke mirror lokal device lain (tombstone sync) — device lain masih perlu pull manual untuk sadar peserta sudah dihapus di tempat lain.
- **H5 — Password akun online disimpan plaintext di secure storage lokal. `[FIXED]`** `auth_local_datasource.dart` menyimpan password asli (bukan hash) untuk keperluan auto re-login offline. Jika perangkat/keystore OS diretas, penyerang dapat password asli, bukan sekadar hash lokal.
  **Diterapkan:** `saveOnlinePassword`/`getOnlinePassword`/`deleteOnlinePassword` dan penyimpanannya (`_keyOnlinePassword`) dihapus total dari `auth_local_datasource.dart`, begitu juga `_tryRestoreOnlineSession` di `auth_bloc.dart` yang memakainya untuk re-login diam-diam. Silent-restore untuk sesi online tetap berfungsi lewat mekanisme bawaan `supabase_flutter` (refresh token yang dikelola Supabase sendiri, `auth.currentSession`), yang sudah dicek lebih dulu di `_onCheckAuthStatus` — jika itu tidak valid lagi, app sekarang jatuh ke mode offline (`AuthOffline`) alih-alih diam-diam login ulang pakai password tersimpan. `_keyPendingPassword` (dipakai `sync_service.dart` untuk menyelesaikan pembuatan akun Supabase yang awalnya dibuat offline) **sengaja tidak disentuh** — itu keperluan berbeda (sekali pakai, langsung dihapus setelah dipakai), bukan penyimpanan permanen untuk re-login berulang.

*(Catatan: `qurban_repository_impl.dart` sudah punya proteksi yang baik di sisi lain — layar Transaksi umum secara eksplisit memblokir edit/hapus transaksi yang bersumber dari Qurban dan mengarahkan user ke modul Qurban, `transaction_repository_impl.dart:99-103,145-149`.)*

## 🟡 MEDIUM

**Update 2026-07-09 (putaran 1):** M0, M2, M3, M4, M5, M6, M9, M10, M12 diperbaiki di kode (tag `[FIXED]`).
**Update 2026-07-09 (putaran 2, "lanjutkan semuanya"):** M7 dan M8 juga sudah dikerjakan (scope disesuaikan dengan alasan tercatat di masing-masing item), begitu juga bagian test dari M11. Hanya migrasi tipe uang penuh (bagian M1) yang masih sengaja belum disentuh — lihat catatan di item M1 untuk kenapa itu perlu konfirmasi eksplisit dari Anda dulu sebelum saya kerjakan, beda dengan semua perbaikan lain di audit ini. Semua diverifikasi dengan `flutter analyze` (0 isu) dan `flutter test` (44/44 pass, bertambah 5 dari test schema baru).

- **M0 — Peserta Qurban baru langsung berstatus "Menunggak" (overdue) sejak hari pendaftaran. `[FIXED]`** Diverifikasi langsung: `qurban_repository_impl.dart:531-540` (`_calculateDueAmount`) menghitung `dueMonths = (selisih bulan) + 1`, sehingga di bulan pendaftaran sendiri (`current == start`) `dueMonths` sudah 1 dan `dueAmount = monthlyAmount`, padahal peserta baru saja daftar dan belum sempat membayar apa pun.
  **Diterapkan:** `+ 1` dihapus dari rumus `dueMonths`. Bulan pendaftaran kini jadi grace period (0 due), baru terhitung due setelah bulan itu penuh berlalu — konsisten untuk bulan pertama maupun bulan terakhir cicilan.

- **M1 — Nilai uang sebagai `double` tanpa validasi batas atas.** `[SEBAGIAN — sisanya DITAHAN atas keputusan eksplisit Anda]` Nilai uang disimpan sebagai `double`/`RealColumn` di semua tempat (`transaction.dart`, `app_database.dart`) tanpa validasi batas atas — berisiko floating-point drift saat agregasi besar, dan salah ketik angka besar tidak divalidasi.
  **Diterapkan:** Validasi batas atas ditambahkan di form transaksi (Rp 1 miliar) dan form Qurban (cicilan bulanan Rp 50 juta, pembayaran/paket Rp 1 miliar) sebagai pertahanan terhadap salah ketik.
  **Migrasi tipe data penuh dari `double` ke integer: ditanyakan langsung ke user pada 2026-07-09, dan user memilih "tahan dulu"** (bukan keputusan sepihak saya). Alasan yang disepakati: ini bukan bug dengan dampak nyata hari ini — nilai tetap akurat selama tetap berupa bilangan bulat (kasus normal untuk Rupiah) — dan risikonya (penulisan ulang & konversi data pada kolom uang di seluruh app, rebuild tabel penuh karena SQLite tidak bisa ALTER COLUMN affinity in-place, tanpa bisa diverifikasi di device nyata) lebih besar dari manfaatnya untuk dikerjakan tergesa-gesa. **Rekomendasi:** jadikan proyek tersendiri dengan rencana migrasi data yang matang dan pengujian di device nyata, bukan bagian dari sesi perbaikan cepat seperti ini.
- **M2 — Transaksi bertanggal masa depan memengaruhi saldo "saat ini". `[FIXED]`** `getTotalBalance()` menjumlah semua transaksi tanpa filter tanggal.
  **Diterapkan:** Date picker di form transaksi tidak lagi mengizinkan tanggal masa depan (`lastDate: now`). Sebagai lapis pertahanan tambahan untuk data lama/sudah tersinkron, `getTotalBalance()`, `getIncomeThisMonth()`, dan `getExpenseThisMonth()` di `transaction_repository_impl.dart` sekarang membatasi query sampai "sekarang", bukan sampai tanggal manapun yang tersimpan.
- **M3 — Tidak ada unique constraint pada `remoteId`. `[FIXED]`** Retry push setelah timeout (padahal server sudah sukses), atau bug pull-merge, bisa menghasilkan baris lokal ganda untuk transaksi yang sama → uang terhitung dobel.
  **Diterapkan:** Partial unique index pada `remote_id` (mengabaikan NULL, karena baris yang belum sync memang belum punya) ditambahkan untuk `transactions` dan `qurban_payments` — dua tabel yang berdampak langsung ke uang. `schemaVersion` naik ke 7. Index dibungkus try/catch: jika sebuah device kebetulan sudah ada duplikat dari sebelum perbaikan ini, index gagal dibuat khusus di device itu (butuh pembersihan manual) alih-alih membuat app gagal dibuka.
- **M4 — Penulisan audit log tidak atomic dengan aksinya. `[FIXED]`** Bisa hilang diam-diam jika app crash di antara dua statement, atau aksi sukses malah dilaporkan gagal ke caller jika insert log-nya yang error.
  **Diterapkan:** Semua pasangan write+audit-log yang belum atomic dibungkus `_db.transaction()`: `user_repository_impl.dart` (add/update/delete), `activity_repository_impl.dart` (add/update/delete), `transaction_repository_impl.dart` (add/update/delete), `qurban_repository_impl.dart` (package & participant add/update/delete, plus audit log payment dipindah ke DALAM transaction yang sudah ada). Sekalian menemukan dan memperbaiki bug terpisah di `deletePayment`: audit log "hapus" sebelumnya tetap tercatat walau payment yang dihapus ternyata tidak ada.
- **M5 — Hashing password lokal lemah (HMAC-SHA256 1 putaran). `[FIXED]`** Key = userId (bukan rahasia) + fallback permanen ke SHA-256 polos untuk akun lama. Bukan KDF lambat — cepat di-brute-force jika storage ter-ekstrak.
  **Diterapkan:** PBKDF2-HMAC-SHA256 (100.000 iterasi, salt acak 16-byte per user) diimplementasikan dari primitif `crypto` yang sudah ada (tidak perlu dependency baru). `verifyCredentials` sekarang bertingkat 3: coba skema baru dulu, kalau tidak ada baru coba skema lama (HMAC-keyed-userId, lalu SHA-256 polos) — begitu berhasil lewat skema lama, otomatis di-upgrade ke skema baru dengan salt baru. User lama tidak perlu reset password manual.
- **M6. `[FIXED bersamaan dengan H1]`** ~~Tidak ada role-guard di `app_router.dart` untuk halaman sensitif~~ — sudah tertutup oleh `_roleRedirect()` yang ditambahkan untuk H1.
- **M8 — Tidak ada cursor pagination pada pull. `[FIXED]`** Pull menarik seluruh tabel tiap sync tanpa filter `updated_at`, jadi biaya sync tumbuh terus seiring data bertambah.
  **Diterapkan:** Pola cursor `updated_at` yang sama seperti M9 (audit log) diterapkan ke SEMUA pull lain: `_pullTransactions`, `_pullActivities`, `_pullQurbanPackages`, `_pullQurbanParticipants`, `_pullQurbanPayments`, `_pullUsers` — masing-masing sekarang menarik per 500 baris mulai dari `MAX(updated_at)` yang sudah tersimpan lokal (hanya baris ber-`remoteId`, karena baris lokal yang belum ke-push tidak mencerminkan apa yang sudah ditarik dari server), bukan seluruh tabel setiap kali. Logika merge (skip kalau status lokal bukan `synced`, dst.) tidak berubah sama sekali — murni soal berapa banyak yang diambil, bukan bagaimana data digabung. `_pullMosqueProfile` tidak disentuh (memang cuma 1 baris).
- **M7 — Sync push satu-per-satu (N+1). `[FIXED sebagian — lihat cakupan]`** Push tidak batching, satu request per baris.
  **Diterapkan untuk `_pushActivities` dan bagian upsert `_pushQurbanParticipants`:** diganti jadi chunked batch `upsert()` (50 baris/chunk, insert & update disatukan karena keduanya pakai `remoteId` sebagai conflict key), dengan fallback: kalau satu chunk gagal, chunk itu diproses satu-per-satu seperti sebelumnya (jadi satu baris bermasalah tidak lagi menggagalkan seluruh chunk yang sebenarnya baik-baik saja — isolasi error tidak berkurang, cuma jumlah request yang berkurang di kasus normal).
  **Sengaja TIDAK dibatch:** (1) `_pushTransactions` — upload foto bukti tetap harus per-file terlepas dari batching apa pun, jadi bottleneck sebenarnya bukan di panggilan DB; risiko menyentuh method paling rumit (logika retry foto + hasUploadError + merge path) di file uang paling kritis, tanpa cara memverifikasi langsung di device, tidak sepadan dengan manfaat performa. (2) `_pushQurbanPayments` — tiap baris punya dependency check ke participant & transaction yang harus sudah tersinkron dulu (throw kalau belum), bikin batching jauh lebih rumit untuk isolasi error yang benar. (3) Delete peserta Qurban tetap per-baris — perlu pengecekan server per peserta (fix H4), tidak bisa di-batch tanpa kehilangan proteksi itu. (4) `_pushUsers`, `_pushMosqueProfile` (1 baris), `_pushAuditLogs` — volume rendah, batching tidak memberi manfaat nyata. (5) `_pushQurbanPackages` — biasanya cuma 2-5 baris seumur hidup, tidak sepadan risikonya.
- **M9 — Pull audit log hardcode `.limit(100)`. `[FIXED]`** Device yang jarang sync bisa permanen kehilangan entri log lama.
  **Diterapkan:** Diganti dengan pagination berbasis cursor `created_at` (audit log bersifat append-only, tidak pernah di-update, jadi ini valid) — menarik per 500 baris, lanjut ke halaman berikutnya sampai habis, mulai dari cursor terakhir yang sudah tersimpan lokal. Tidak ada lagi entri yang terlewat berapa pun jumlah backlog-nya.
- **M10 — Guard relasi hapus user diam-diam terlewati untuk user tanpa nama. `[FIXED]`** `picName.equals(user.fullName ?? '')` mencari string kosong yang tidak pernah cocok dengan `picName` NULL.
  **Diterapkan:** Guard sekarang eksplisit skip (bukan diam-diam query kosong) saat `fullName` null/kosong, dengan komentar yang menjelaskan keterbatasan pendekatan cocok-nama ini secara umum (activities mereferensi user lewat nama teks, bukan foreign key sungguhan — di luar scope untuk diperbaiki sekarang).
- **M11 — `onUpgrade` migrasi menelan semua error tanpa jejak, tidak ada test skema. `[FIXED — dengan catatan cakupan]`** Kegagalan nyata bisa membuat kolom baru diam-diam tidak pernah ditambahkan, dan tidak ada test yang menangkap regresi migrasi sebelum rilis.
  **Diterapkan:** Semua `catch (_) {}` kosong di `onUpgrade` diganti `catch (e) { debugPrint(...) }` — kegagalan tak terduga sekarang minimal tercatat di log, tidak lagi hilang total. Ditambahkan `test/schema_test.dart` (5 test) yang memverifikasi: skema `onCreate` menghasilkan `schemaVersion` yang benar, semua kolom/tabel yang pernah ditambahkan lewat migrasi historis benar-benar bisa di-query, dan constraint unique dari M3 benar-benar DIBERLAKUKAN saat runtime (bukan cuma dideklarasikan) — termasuk memverifikasi baris dengan `remote_id` NULL ganda tetap diperbolehkan. **Cakupan yang belum:** test ini memverifikasi jalur `onCreate` (skema baru dari nol), BUKAN jalur `onUpgrade` yang sesungguhnya (device lama versi 1 di-upgrade ke versi 7) — mereplikasi itu secara akurat butuh tooling schema-snapshot resmi dari `drift_dev` yang belum pernah disiapkan di project ini untuk versi-versi lama. Lihat juga catatan "belum pernah diverifikasi" di bagian Status Test.
- **M12 — Tidak ada `CHECK` constraint di DB untuk amount/duration Qurban. `[FIXED]`** Validasi hanya ada di form UI, jadi jalur lain (bulk import, event bloc langsung) bisa menyimpan nilai 0/negatif.
  **Diterapkan:** `CHECK (... > 0) NOT VALID` ditambahkan untuk `qurban_packages.monthly_amount`, `qurban_participants.monthly_amount`/`total_months`, `qurban_payments.amount` — di `init.sql`, `supabase_full_setup.sql`, dan migrasi baru `20260709_add_qurban_amount_check_constraints.sql`. `NOT VALID` dipakai supaya migrasi aman dijalankan di project yang sudah punya data (tidak makasa validasi ulang semua baris lama); jalankan `VALIDATE CONSTRAINT` terpisah setelah memastikan data lama bersih. **Constraint yang sama TIDAK dibuat di skema lokal Drift/SQLite** — SQLite tidak mendukung `ADD CONSTRAINT` pada tabel yang sudah ada tanpa rebuild tabel penuh (lebih berisiko untuk migrasi in-place), dan validasi UI lokal sudah menutup jalur normal aplikasi.

## 🟢 LOW

**Update 2026-07-09:** L1 (stale totals), L3 (MosqueProfile syncStatus), dan L6 (PDF truncation indicator) sudah diperbaiki. L2 dan L4 sengaja tidak disentuh (lihat alasan masing-masing); L5 bukan bug, bukan sesuatu yang "diperbaiki".

- **`[FIXED]`** ~~Kemungkinan totals sempat "stale" sesaat pada `TransactionsUpdated`~~ — transformer diganti ke `restartable()`, konsisten dengan `LoadTransactions`.
- **`[TIDAK DIKERJAKAN]`** File foto bukti yang gagal upload terus-menerus (bukan sekadar hilang) tetap dicoba ulang tiap sync tanpa batas. Sengaja dibiarkan: menambah mekanisme "batas retry lalu menyerah" berarti transaksi bisa akhirnya ditandai `synced` TANPA foto buktinya — menukar kejengkelan UX (retry terus) dengan risiko kehilangan data diam-diam (persis yang baru diperbaiki di H2). Retry-selamanya adalah default yang lebih aman untuk item Low ini.
- **`[FIXED]`** ~~`MosqueProfileRepositoryImpl.saveProfile` selalu set `pendingUpdate` tanpa cek status sebelumnya~~ — sekarang cek `existing.syncStatus` dulu, tetap `pendingCreate` kalau memang belum pernah tersinkron.
- **`[TIDAK DIKERJAKAN]`** `StringListConverter`: string multi-URL yang corrupt sebagian dipulihkan sebagai satu string gabungan yang tidak terpakai, bukan hilang total. Murni kosmetik dan butuh byte-level corruption (SQLite write atomic) untuk terjadi — risiko terlalu rendah untuk masuk prioritas.
- Tidak ada jalur "lupa password" untuk akun lokal/offline-only (keterbatasan desain, bukan bug — tidak ada cara aman memverifikasi identitas offline tanpa jalur out-of-band, itu keputusan produk bukan perbaikan kode).
- **`[FIXED]`** ~~Laporan PDF Qurban diam-diam memotong riwayat pembayaran ke 5 transaksi terbaru per peserta tanpa indikator~~ — sekarang menambahkan baris "+N pembayaran lainnya tidak ditampilkan" per peserta yang terpotong.

---

## ✅ Sudah Diperbaiki (dibandingkan laporan 2026-04-30)

Untuk keadilan — banyak yang sudah benar-benar selesai, bukan cuma diklaim:

- Race condition pengambilan balance/income/expense di `TransactionBloc` → sudah pakai `restartable()`.
- Error saat add/update/delete transaksi tidak lagi menghapus daftar yang sedang tampil di layar.
- `sync_service.dart` sudah punya guard `_isSyncing` yang benar (dicek + di-set sebelum `await` pertama, direset di `finally`).
- Strategi pull "client wins yang membabi buta" **sudah diperbaiki dan diterapkan konsisten di ke-7 entitas** (transaksi, aktivitas, user, profil masjid, paket/peserta/pembayaran Qurban) — lebih baik dari yang disebut laporan lama (yang mengira cuma user yang diperbaiki).
- Kegagalan upload sebagian foto bukti kini hanya mengulang foto yang belum berhasil, tidak mengulang semua dari awal.
- `StringListConverter` tidak lagi diam-diam mengembalikan list kosong saat parsing gagal.
- Modul Qurban (kode terbaru) mengikuti pola `remoteId`/`pendingCreate` yang benar — tidak ada regresi ke bug lama.
- Keterkaitan pembayaran Qurban ↔ transaksi kas (create/edit/delete) sudah atomic dan konsisten.
- Perhitungan progress/overpayment Qurban sudah benar, termasuk kasus pembayaran tidak beraturan.
- Klaim laporan lama soal "hapus user bisa crash karena foreign key" — **tidak terbukti/basi**: skema saat ini tidak punya FK apa pun dari transaksi/aktivitas ke user, dan sudah ada guard manual (meski guard itu sendiri punya bug kecil, lihat M10).
- `env.dart` sudah bersih dari service role key (klaim kritis di laporan lama sudah tidak berlaku); Edge Function `admin-users` sudah benar memvalidasi bearer token + role caller di server.
- Total PDF laporan kas sudah konsisten dengan total yang tampil di layar (dihitung dari data terfilter yang sama).

---

## Status Test & Static Analysis

- `flutter analyze` → **0 isu** di SETIAP tahap perbaikan (Critical, High, Medium+Low+M7/M8/M11) — bersih sebelum dan sesudah setiap batch, tanpa kecuali. Laporan lama (2026-04-30) menyebut 93 isu, sudah lama beres.
- `flutter test` → **44/44 pass** (naik dari 39 setelah menambahkan `test/schema_test.dart`), tidak ada regresi sepanjang SELURUH proses perbaikan hari ini. File: `full_integration_test.dart`, `local_logic_test.dart`, `auth_bloc_update_profile_test.dart`, `edit_profile_page_test.dart`, `widget_test.dart`, `schema_test.dart` (baru).
- ⚠️ **Temuan proses (belum ditelusuri akar masalahnya):** `test/user_role_test.dart` **tidak pernah ikut jalan** saat `flutter test` dipanggil tanpa argumen — dikonfirmasi berulang (termasuk setelah `flutter clean`), padahal valid dan lolos 5/5 saat dijalankan langsung. **Ini spesifik ke file itu, bukan pola umum "file test baru tidak kebaca"** — `schema_test.dart` yang sama-sama baru ditambahkan hari ini justru langsung ikut jalan normal di `flutter test` tanpa argumen (menambah dari 39 ke 44 seperti seharusnya). Jangan percaya hasil hijau `flutter test` begitu saja — jalankan `test/user_role_test.dart` secara eksplisit di CI/checklist rilis sampai penyebabnya ditemukan.
- ⚠️ **Belum pernah diverifikasi:** jalur upgrade `schemaVersion` lama→7 pada database yang benar-benar sudah berisi data versi lama. `test/schema_test.dart` (baru) memverifikasi jalur `onCreate` (skema baru dari nol) sudah benar dan constraint M3 benar-benar berfungsi saat runtime — tapi BUKAN jalur `onUpgrade` yang sesungguhnya dari device lama.

---

## Rekomendasi Urutan Perbaikan

1. ~~**Sebelum rilis ke client mana pun:** C1, C2, C4, C5~~ — **selesai 2026-07-08**, lihat tag `[FIXED]`.
2. **Tindakan manual Anda (masih outstanding):** rotasi password DB (C3), dan jalankan KEDUA migrasi baru di project Supabase yang sudah berjalan — `20260708_fix_role_escalation_and_admin_claim.sql` dan `20260709_add_qurban_amount_check_constraints.sql`.
3. ~~**Sebelum rilis:** H1–H5~~ — **selesai 2026-07-09**, lihat tag `[FIXED]`. H4 hanya menutup risiko data-loss utamanya, bukan seluruh gap arsitektur.
4. ~~**Medium:** M0, M2, M3, M4, M5, M6, M9, M10, M12~~ — **selesai 2026-07-09**.
5. ~~**Setelah "lanjutkan semuanya": M7, M8, bagian test M11, L1, L3, L6**~~ — **selesai 2026-07-09**, dengan cakupan yang didokumentasikan per item (mis. M7 tidak mencakup `_pushTransactions`/`_pushQurbanPayments`, alasannya ada di catatan item itu).
6. **Menunggu keputusan Anda:** migrasi tipe uang `double`→integer penuh (bagian M1 yang tersisa) — lihat catatan di item M1 untuk kenapa saya tahan ini secara khusus.
7. **Sengaja tidak dikerjakan (risiko > manfaat):** retry-foto-tanpa-batas dan `StringListConverter` kosmetik (2 item Low tersisa).
8. Tambahkan regression test untuk skenario yang baru diperbaiki (C4 double-submit, C5 concurrent profile save, H1 route guard per role, H4 server-side re-check saat delete — di luar yang sudah ditutup `schema_test.dart` untuk M3), dan investigasi kenapa `user_role_test.dart` tidak ikut jalan di CI. Belum dikerjakan.
9. **Belum dilakukan sama sekali:** pengujian manual/live di device/emulator nyata, termasuk uji upgrade dari versi lama. Wajib sebelum rilis ke client berapa pun hijaunya `flutter analyze`/`flutter test`.
7. **Belum dilakukan sama sekali di seluruh proses ini:** pengujian manual/live di browser, emulator, atau device fisik — semua verifikasi sejauh ini adalah `flutter analyze` + `flutter test` + penelusuran kode langsung, bukan menjalankan aplikasinya. Sebelum rilis ke client, jalankan smoke test manual untuk alur: daftar masjid baru (termasuk kasus "sudah ada admin"), login sebagai tiap role, submit transaksi sebagai viewer/sekretaris (harus ditolak), hapus peserta Qurban di dua device berbeda, dan upgrade app dari versi lama di device yang sudah terpasang (uji migrasi skema 6→7).

Item Medium yang tersisa (M1 penuh, M7-M8, M11 bagian test) dan semua item Low belum dikerjakan — beri tahu jika Anda ingin saya lanjutkan ke situ, atau berhenti di sini.
