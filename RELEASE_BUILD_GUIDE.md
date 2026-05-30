# Release Build Guide - Production Deployment

## 🚀 Building for Production

### Pre-Build Checklist

- [x] All code changes committed
- [x] All tests passing
- [x] Documentation complete
- [x] Security audit passed
- [ ] Version number updated
- [ ] Build configuration verified

---

## 📱 Building APK for Android (Infinix)

### Step 1: Update Version Number

Edit `pubspec.yaml`:

```yaml
version: 1.0.0+1 # Update this (format: major.minor.patch+buildNumber)
```

### Step 2: Clean Build

```bash
flutter clean
flutter pub get
```

### Step 3: Build Release APK

```bash
# Build APK (recommended for direct installation)
flutter build apk --release

# Or build App Bundle (for Play Store)
flutter build appbundle --release
```

### Step 4: Locate APK

APK will be located at:

```
build/app/outputs/flutter-apk/app-release.apk
```

### Step 5: Install on Infinix

**Method 1: USB Cable**

```bash
# Connect phone via USB
# Enable USB debugging on phone
adb install build/app/outputs/flutter-apk/app-release.apk
```

**Method 2: File Transfer**

1. Copy `app-release.apk` to phone
2. Open file manager on phone
3. Tap APK file
4. Allow installation from unknown sources if prompted
5. Install

---

## 🔧 Build Configuration

### Release Signing (Optional but Recommended)

Create `android/key.properties`:

```properties
storePassword=<your-store-password>
keyPassword=<your-key-password>
keyAlias=<your-key-alias>
storeFile=<path-to-keystore-file>
```

Update `android/app/build.gradle`:

```gradle
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
    ...
    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
        }
    }
    buildTypes {
        release {
            signingConfig signingConfigs.release
        }
    }
}
```

---

## 📊 Build Verification

### Check APK Size

```bash
ls -lh build/app/outputs/flutter-apk/app-release.apk
```

Target: < 50MB

### Verify APK Contents

```bash
# Extract APK info
aapt dump badging build/app/outputs/flutter-apk/app-release.apk
```

### Test Installation

```bash
# Install on connected device
adb install -r build/app/outputs/flutter-apk/app-release.apk

# Check if installed
adb shell pm list packages | grep masjid
```

---

## 🔍 Troubleshooting

### Issue 1: Build Fails

```bash
flutter clean
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
flutter build apk --release
```

### Issue 2: APK Too Large

```bash
# Build split APKs
flutter build apk --split-per-abi --release
```

### Issue 3: Installation Blocked

- Enable "Install from Unknown Sources" in phone settings
- Check if phone has enough storage
- Uninstall old version first

---

## 📱 Device Requirements

### Minimum Requirements

- Android 5.0 (API level 21) or higher
- 100MB free storage
- Internet connection (for online features)

### Recommended

- Android 8.0 or higher
- 200MB free storage
- Stable internet connection

---

## 🎯 Post-Installation

### Verify Installation

1. Open app
2. Check version number in settings
3. Test login
4. Test profile update feature
5. Test offline mode

### Monitor

- Check for crashes
- Monitor performance
- Collect user feedback

---

## 📝 Release Notes

### Version 1.0.0

**New Features:**

- ✅ User profile management
- ✅ Update username, email, password
- ✅ Offline support with auto-sync
- ✅ Enhanced validation
- ✅ Improved security

**Bug Fixes:**

- ✅ Fixed memory leaks
- ✅ Fixed credential cleanup
- ✅ Fixed validation issues

**Improvements:**

- ✅ Better error messages
- ✅ Improved UX
- ✅ Enhanced security

---

## 🔐 Security Notes

- APK is signed with release key
- ProGuard/R8 enabled for code obfuscation
- No debug symbols included
- Secure storage for credentials

---

**Build Date:** 2024-02-24  
**Version:** 1.0.0  
**Build Number:** 1
