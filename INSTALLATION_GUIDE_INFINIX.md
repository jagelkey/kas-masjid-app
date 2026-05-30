# Panduan Instalasi Aplikasi di HP Infinix

## 📱 Persiapan HP Infinix

### 1. Aktifkan Developer Options

1. Buka **Settings** (Pengaturan)
2. Scroll ke bawah, pilih **About Phone** (Tentang Ponsel)
3. Cari **Build Number** (Nomor Build)
4. Tap **Build Number** sebanyak **7 kali**
5. Masukkan PIN/Password jika diminta
6. Akan muncul notifikasi "You are now a developer!"

### 2. Aktifkan USB Debugging

1. Kembali ke **Settings**
2. Pilih **System** → **Developer Options**
3. Aktifkan **USB Debugging**
4. Aktifkan juga **Install via USB** (jika ada)

### 3. Hubungkan HP ke Komputer

1. Gunakan kabel USB yang bagus (original lebih baik)
2. Colokkan HP ke komputer
3. Di HP, pilih **File Transfer** atau **MTP** mode
4. Akan muncul popup "Allow USB debugging?" → Tap **OK/Allow**
5. Centang "Always allow from this computer" (opsional)

---

## 🔧 Persiapan Komputer

### 1. Install Flutter (jika belum)

```bash
# Cek apakah Flutter sudah terinstall
flutter --version

# Jika belum, download dari:
# https://docs.flutter.dev/get-started/install/windows
```

### 2. Install Android SDK

```bash
# Flutter akan otomatis download Android SDK
flutter doctor

# Jika ada masalah, jalankan:
flutter doctor --android-licenses
```

### 3. Verifikasi Device Terdeteksi

```bash
# Cek apakah HP terdeteksi
flutter devices

# Atau gunakan ADB
adb devices
```

**Output yang diharapkan:**

```
List of devices attached
ABC123456789    device
```

Jika muncul "unauthorized", cek HP dan tap "Allow" pada popup USB debugging.

---

## 🚀 Cara Install (Otomatis)

### Windows

1. **Double-click file:** `build_and_install.bat`
2. Tunggu proses build selesai (5-10 menit)
3. Aplikasi akan otomatis terinstall di HP

### Linux/Mac

```bash
# 1. Beri permission
chmod +x build_and_install.sh

# 2. Jalankan script
./build_and_install.sh
```

---

## 🛠️ Cara Install (Manual)

### Step 1: Build APK

```bash
# Build release APK
flutter build apk --release

# Atau build APK yang lebih kecil (split per ABI)
flutter build apk --split-per-abi --release
```

**Lokasi APK:**

- `build/app/outputs/flutter-apk/app-release.apk`
- Atau jika split: `app-armeabi-v7a-release.apk`, `app-arm64-v8a-release.apk`

### Step 2: Install ke HP

**Opsi A: Via ADB (Recommended)**

```bash
# Install APK
adb install build/app/outputs/flutter-apk/app-release.apk

# Jika sudah terinstall sebelumnya, gunakan -r untuk replace
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

**Opsi B: Via File Transfer**

1. Copy file APK ke HP (via USB atau Bluetooth)
2. Di HP, buka **File Manager**
3. Cari file APK yang sudah dicopy
4. Tap file APK
5. Tap **Install**
6. Jika muncul "Install blocked", aktifkan "Install from unknown sources"

**Opsi C: Via Android Studio**

1. Buka project di Android Studio
2. Pilih device Infinix di dropdown
3. Klik tombol Run (▶️)

---

## ⚠️ Troubleshooting

### Problem 1: Device Tidak Terdeteksi

**Solusi:**

```bash
# 1. Restart ADB server
adb kill-server
adb start-server

# 2. Cek lagi
adb devices

# 3. Jika masih tidak terdeteksi, coba:
# - Ganti kabel USB
# - Ganti port USB di komputer
# - Restart HP dan komputer
# - Pastikan USB Debugging aktif
```

### Problem 2: "Unauthorized" di ADB

**Solusi:**

1. Di HP, akan muncul popup "Allow USB debugging?"
2. Tap **OK/Allow**
3. Centang "Always allow from this computer"
4. Jalankan `adb devices` lagi

### Problem 3: Build Gagal

**Solusi:**

```bash
# 1. Clean project
flutter clean

# 2. Get dependencies
flutter pub get

# 3. Build lagi
flutter build apk --release
```

### Problem 4: "Install blocked" di HP

**Solusi:**

1. Buka **Settings** → **Security**
2. Aktifkan **Unknown Sources** atau **Install from unknown sources**
3. Atau: **Settings** → **Apps** → **Special app access** → **Install unknown apps**
4. Pilih **File Manager** atau **Chrome** → Allow

### Problem 5: APK Terlalu Besar

**Solusi:**

```bash
# Build APK split per ABI (lebih kecil)
flutter build apk --split-per-abi --release

# Pilih APK yang sesuai dengan HP:
# - arm64-v8a: Untuk HP modern (64-bit) - PILIH INI UNTUK INFINIX
# - armeabi-v7a: Untuk HP lama (32-bit)
# - x86_64: Untuk emulator
```

### Problem 6: Aplikasi Crash Setelah Install

**Solusi:**

```bash
# 1. Cek log error
adb logcat | grep -i flutter

# 2. Build debug version untuk testing
flutter build apk --debug

# 3. Install dan cek error
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

---

## 📊 Cek Spesifikasi HP Infinix

```bash
# Cek ABI (arsitektur processor)
adb shell getprop ro.product.cpu.abi

# Cek Android version
adb shell getprop ro.build.version.release

# Cek model HP
adb shell getprop ro.product.model

# Cek semua info
adb shell getprop | grep -i "model\|version\|cpu"
```

---

## 🎯 Rekomendasi untuk HP Infinix

### Build APK yang Optimal

```bash
# Untuk HP Infinix modern (kebanyakan 64-bit)
flutter build apk --split-per-abi --release

# Install APK arm64-v8a (paling umum untuk Infinix)
adb install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

### Ukuran APK

- **Universal APK:** ~50-80 MB
- **Split APK (arm64-v8a):** ~25-40 MB ✅ Recommended
- **Split APK (armeabi-v7a):** ~25-40 MB

---

## 🔍 Verifikasi Instalasi

### 1. Cek Aplikasi Terinstall

```bash
# Cek apakah aplikasi terinstall
adb shell pm list packages | grep -i masjid

# Atau cek di HP:
# Settings → Apps → Lihat daftar aplikasi
```

### 2. Launch Aplikasi

```bash
# Launch aplikasi via ADB
adb shell monkey -p com.example.masjid_app -c android.intent.category.LAUNCHER 1

# Atau buka manual di HP
```

### 3. Cek Log (jika ada error)

```bash
# Monitor log real-time
adb logcat | grep -i flutter

# Atau save ke file
adb logcat > app_log.txt
```

---

## 📝 Checklist Instalasi

### Pre-Installation

- [ ] Developer Options aktif
- [ ] USB Debugging aktif
- [ ] HP terhubung ke komputer
- [ ] Device terdeteksi (`adb devices`)
- [ ] Flutter terinstall (`flutter --version`)

### Build Process

- [ ] `flutter clean` berhasil
- [ ] `flutter pub get` berhasil
- [ ] `flutter build apk --release` berhasil
- [ ] APK file ada di `build/app/outputs/flutter-apk/`

### Installation

- [ ] `adb install` berhasil
- [ ] Aplikasi muncul di app drawer
- [ ] Aplikasi bisa dibuka
- [ ] Tidak ada crash saat launch

### Post-Installation

- [ ] Login berhasil
- [ ] Fitur utama berfungsi
- [ ] Tidak ada error di log
- [ ] Performance bagus

---

## 🚀 Quick Start (TL;DR)

```bash
# 1. Hubungkan HP Infinix (USB Debugging ON)
adb devices

# 2. Build APK
flutter build apk --split-per-abi --release

# 3. Install ke HP
adb install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk

# 4. Launch aplikasi
# Buka manual di HP atau:
adb shell monkey -p com.example.masjid_app -c android.intent.category.LAUNCHER 1
```

---

## 📞 Support

Jika masih ada masalah:

1. **Cek log error:**

   ```bash
   adb logcat | grep -i "error\|exception\|flutter"
   ```

2. **Screenshot error** dan kirim ke developer

3. **Info HP:**
   - Model: (cek di Settings → About Phone)
   - Android Version: (cek di Settings → About Phone)
   - RAM: (cek di Settings → About Phone)

---

## 🎉 Selesai!

Aplikasi sekarang sudah terinstall di HP Infinix Anda!

**Tips:**

- Untuk update aplikasi, cukup build APK baru dan install dengan flag `-r`
- Untuk uninstall: `adb uninstall com.example.masjid_app`
- Untuk backup data: Export dari aplikasi sebelum uninstall

---

**Last Updated:** 2024-02-24  
**Tested on:** Infinix Hot 10, Infinix Note 11, Infinix Zero X
