# 🚀 Quick Install ke HP Infinix

## Langkah Cepat (5 Menit)

### 1️⃣ Persiapan HP Infinix

```
Settings → About Phone → Tap "Build Number" 7x
Settings → Developer Options → USB Debugging ON
Hubungkan HP ke komputer via USB
```

### 2️⃣ Install Otomatis

**Windows:**

```
Double-click: build_and_install.bat
```

**Linux/Mac:**

```bash
chmod +x build_and_install.sh
./build_and_install.sh
```

### 3️⃣ Selesai! ✅

Aplikasi akan otomatis terinstall di HP Infinix Anda.

---

## 📱 Jika Ada Masalah

### HP Tidak Terdeteksi?

```bash
# Cek device
adb devices

# Jika "unauthorized", cek HP dan tap "Allow"
# Jika tidak muncul, coba:
adb kill-server
adb start-server
adb devices
```

### Build Gagal?

```bash
flutter clean
flutter pub get
flutter build apk --split-per-abi --release
```

### Install Gagal?

```bash
# Install manual
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

---

## 📖 Panduan Lengkap

Lihat: `INSTALLATION_GUIDE_INFINIX.md`

---

## ✅ Checklist

- [ ] USB Debugging aktif
- [ ] HP terhubung ke komputer
- [ ] `adb devices` menampilkan device
- [ ] Run `build_and_install.bat` atau `.sh`
- [ ] Aplikasi terinstall di HP

---

**Butuh bantuan?** Baca `INSTALLATION_GUIDE_INFINIX.md` untuk troubleshooting lengkap.
