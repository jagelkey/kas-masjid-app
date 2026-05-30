# Manual Testing Guide - Profile Update Feature

## Pre-requisites

- Flutter app installed on device/emulator
- Test user account created
- Internet connection (for online testing)

## Test Scenarios

### Scenario 1: Update Username Only

**Steps:**

1. Login dengan akun test
2. Buka menu Settings → Edit Profil
3. Ubah username dari "testuser" ke "testuser2"
4. Klik "Simpan Perubahan"
5. Konfirmasi di dialog

**Expected Result:**

- ✅ Dialog konfirmasi muncul
- ✅ Loading indicator tampil
- ✅ Success message: "Profil berhasil diperbarui"
- ✅ Redirect ke halaman sebelumnya
- ✅ Username berubah di UI
- ✅ Bisa login dengan username baru

**Test Data:**

- Old Username: testuser
- New Username: testuser2

---

### Scenario 2: Update Email Only

**Steps:**

1. Login dengan akun test
2. Buka menu Settings → Edit Profil
3. Ubah email dari "test@example.com" ke "test2@example.com"
4. Klik "Simpan Perubahan"
5. Konfirmasi di dialog

**Expected Result:**

- ✅ Dialog konfirmasi muncul
- ✅ Loading indicator tampil
- ✅ Success message: "Profil berhasil diperbarui"
- ✅ Email berubah di UI
- ✅ Bisa login dengan email baru
- ⚠️ Supabase: Perlu konfirmasi email (check inbox)

**Test Data:**

- Old Email: test@example.com
- New Email: test2@example.com

---

### Scenario 3: Update Password Only

**Steps:**

1. Login dengan akun test
2. Buka menu Settings → Edit Profil
3. Isi "Password Baru": "newpass123"
4. Isi "Konfirmasi Password Baru": "newpass123"
5. Klik "Simpan Perubahan"
6. Konfirmasi di dialog
7. Logout
8. Login dengan password baru

**Expected Result:**

- ✅ Dialog konfirmasi muncul dengan warning "⚠️ Password akan diubah"
- ✅ Success message muncul
- ✅ Bisa login dengan password baru
- ❌ Tidak bisa login dengan password lama

**Test Data:**

- Old Password: oldpass123
- New Password: newpass123

---

### Scenario 4: Update All Fields

**Steps:**

1. Login dengan akun test
2. Buka menu Settings → Edit Profil
3. Ubah semua field:
   - Nama Lengkap: "Test User Updated"
   - Username: "testupdated"
   - Email: "testupdated@example.com"
   - Password Baru: "updated123"
   - Konfirmasi Password: "updated123"
4. Klik "Simpan Perubahan"
5. Konfirmasi di dialog

**Expected Result:**

- ✅ Semua field berhasil diupdate
- ✅ Bisa login dengan username/email baru dan password baru

---

### Scenario 5: Validation - Email Already Exists

**Steps:**

1. Buat 2 user: user1@test.com dan user2@test.com
2. Login sebagai user1
3. Coba ubah email ke user2@test.com
4. Klik "Simpan Perubahan"

**Expected Result:**

- ❌ Error message: "Email sudah digunakan user lain"
- ✅ Form tidak ter-submit
- ✅ User tetap di halaman edit profil

---

### Scenario 6: Validation - Username Already Exists

**Steps:**

1. Buat 2 user: username1 dan username2
2. Login sebagai username1
3. Coba ubah username ke username2
4. Klik "Simpan Perubahan"

**Expected Result:**

- ❌ Error message: "Username sudah digunakan user lain"
- ✅ Form tidak ter-submit

---

### Scenario 7: Validation - Invalid Email Format

**Steps:**

1. Login dengan akun test
2. Buka Edit Profil
3. Ubah email ke "invalidemail" (tanpa @)
4. Klik "Simpan Perubahan"

**Expected Result:**

- ❌ Validation error: "Format email tidak valid"
- ✅ Form tidak ter-submit

---

### Scenario 8: Validation - Invalid Username

**Steps:**

1. Login dengan akun test
2. Buka Edit Profil
3. Coba username dengan spasi: "test user"
4. Klik "Simpan Perubahan"

**Expected Result:**

- ❌ Validation error: "Username tidak boleh mengandung spasi"

**Test dengan karakter special:**

- "test@user" → Error: "Username hanya boleh huruf, angka, dan underscore"
- "te" → Error: "Minimal 3 karakter"

---

### Scenario 9: Validation - Password Mismatch

**Steps:**

1. Login dengan akun test
2. Buka Edit Profil
3. Isi Password Baru: "password123"
4. Isi Konfirmasi Password: "password456" (berbeda)
5. Klik "Simpan Perubahan"

**Expected Result:**

- ❌ Error message: "Password baru tidak cocok"
- ✅ Form tidak ter-submit

---

### Scenario 10: Validation - Weak Password

**Steps:**

1. Login dengan akun test
2. Buka Edit Profil
3. Isi Password Baru: "12345" (kurang dari 6 karakter)
4. Klik "Simpan Perubahan"

**Expected Result:**

- ❌ Validation error: "Password minimal 6 karakter"

---

### Scenario 11: No Changes

**Steps:**

1. Login dengan akun test
2. Buka Edit Profil
3. Jangan ubah apapun
4. Klik "Simpan Perubahan"

**Expected Result:**

- ⚠️ Info message: "Tidak ada perubahan untuk disimpan"
- ✅ Tidak ada API call
- ✅ User tetap di halaman edit profil

---

### Scenario 12: Offline Mode

**Steps:**

1. Login dengan akun test (online)
2. Matikan internet/WiFi
3. Buka Edit Profil
4. Ubah username ke "offlineuser"
5. Klik "Simpan Perubahan"
6. Konfirmasi
7. Nyalakan internet kembali
8. Tunggu auto-sync

**Expected Result:**

- ✅ Update berhasil meskipun offline
- ✅ Data tersimpan di local database
- ✅ Sync status = pendingUpdate
- ✅ Auto-sync saat online kembali
- ✅ Sync status = synced setelah sync berhasil

---

### Scenario 13: Cancel Update

**Steps:**

1. Login dengan akun test
2. Buka Edit Profil
3. Ubah beberapa field
4. Klik "Simpan Perubahan"
5. Klik "Batal" di dialog konfirmasi

**Expected Result:**

- ✅ Dialog tertutup
- ✅ Tidak ada perubahan tersimpan
- ✅ User tetap di halaman edit profil

---

### Scenario 14: Back Button

**Steps:**

1. Login dengan akun test
2. Buka Edit Profil
3. Ubah beberapa field (jangan save)
4. Klik tombol back/arrow di AppBar

**Expected Result:**

- ✅ Kembali ke halaman sebelumnya
- ✅ Perubahan tidak tersimpan
- ⚠️ (Optional) Bisa tambahkan konfirmasi "Discard changes?"

---

## Performance Testing

### Test 1: Update Speed (Online)

**Steps:**

1. Login
2. Update profil
3. Catat waktu dari klik "Simpan" sampai success message

**Expected Result:**

- ✅ < 2 detik untuk update berhasil

### Test 2: Update Speed (Offline)

**Steps:**

1. Login (offline mode)
2. Update profil
3. Catat waktu

**Expected Result:**

- ✅ < 500ms untuk update berhasil

---

## Security Testing

### Test 1: Password Not Visible in Logs

**Steps:**

1. Enable debug logging
2. Update password
3. Check logs

**Expected Result:**

- ✅ Password tidak muncul di logs
- ✅ Hanya hash yang tersimpan

### Test 2: SQL Injection

**Steps:**

1. Coba input: `'; DROP TABLE users; --`
2. Di field username atau email

**Expected Result:**

- ✅ Input di-escape dengan benar
- ✅ Tidak ada SQL injection

---

## Edge Cases

### Test 1: Very Long Input

**Steps:**

1. Input username dengan 1000 karakter
2. Coba save

**Expected Result:**

- ✅ Validation error atau truncate

### Test 2: Special Characters

**Steps:**

1. Input nama dengan emoji: "Test 😀 User"
2. Coba save

**Expected Result:**

- ✅ Berhasil tersimpan atau validation error yang jelas

### Test 3: Concurrent Updates

**Steps:**

1. Login di 2 device dengan user yang sama
2. Update profil di device 1
3. Update profil di device 2 (sebelum sync)

**Expected Result:**

- ✅ Last write wins
- ✅ Tidak ada data corruption

---

## Bug Report Template

Jika menemukan bug, gunakan template ini:

```
**Bug Title:** [Deskripsi singkat]

**Severity:** [Critical/High/Medium/Low]

**Steps to Reproduce:**
1.
2.
3.

**Expected Result:**
[Apa yang seharusnya terjadi]

**Actual Result:**
[Apa yang sebenarnya terjadi]

**Screenshots:**
[Attach screenshots jika ada]

**Device Info:**
- OS: [Android/iOS]
- Version: [OS version]
- App Version: [App version]

**Additional Context:**
[Info tambahan yang relevan]
```

---

## Test Results Checklist

### Functional Tests

- [ ] Scenario 1: Update Username Only
- [ ] Scenario 2: Update Email Only
- [ ] Scenario 3: Update Password Only
- [ ] Scenario 4: Update All Fields
- [ ] Scenario 5: Email Already Exists
- [ ] Scenario 6: Username Already Exists
- [ ] Scenario 7: Invalid Email Format
- [ ] Scenario 8: Invalid Username
- [ ] Scenario 9: Password Mismatch
- [ ] Scenario 10: Weak Password
- [ ] Scenario 11: No Changes
- [ ] Scenario 12: Offline Mode
- [ ] Scenario 13: Cancel Update
- [ ] Scenario 14: Back Button

### Performance Tests

- [ ] Update Speed (Online) < 2s
- [ ] Update Speed (Offline) < 500ms

### Security Tests

- [ ] Password Not in Logs
- [ ] SQL Injection Protected

### Edge Cases

- [ ] Very Long Input
- [ ] Special Characters
- [ ] Concurrent Updates

---

**Test Date:** ******\_******
**Tester Name:** ******\_******
**App Version:** ******\_******
**Test Result:** [ ] PASS [ ] FAIL

**Notes:**

---

---

---
