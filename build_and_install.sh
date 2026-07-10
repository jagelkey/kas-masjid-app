#!/bin/bash

# Build and Install Script for Linux/Mac
# This script builds the Flutter app and installs it on connected Android device

echo "========================================"
echo "Build and Install - Masjid App"
echo "========================================"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if Flutter is installed
if ! command -v flutter &> /dev/null
then
    echo -e "${RED}[ERROR] Flutter is not installed or not in PATH${NC}"
    echo "Please install Flutter from https://flutter.dev"
    exit 1
fi

# Load SUPABASE_URL / SUPABASE_ANON_KEY from .env unless already set in the
# shell. Only these two values are passed to the build: the service role key and
# the database password must NEVER be compiled into a client APK. Without them
# Env.hasValidConfig is false, Supabase is never initialised, and the installed
# app silently runs 100% offline with no backend at all.
if [ -f .env ]; then
    # shellcheck disable=SC1091
    SUPABASE_URL="${SUPABASE_URL:-$(. ./.env >/dev/null 2>&1; printf '%s' "$SUPABASE_URL")}"
    SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-$(. ./.env >/dev/null 2>&1; printf '%s' "$SUPABASE_ANON_KEY")}"
fi

if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_ANON_KEY" ]; then
    echo -e "${RED}[ERROR] SUPABASE_URL / SUPABASE_ANON_KEY not found.${NC}"
    echo "Create a .env file (see .env.example) or export them as environment variables."
    echo "Building without them produces an APK that never connects to the backend."
    exit 1
fi
echo -e "${GREEN}[OK] Supabase config loaded ($SUPABASE_URL)${NC}"
echo ""

echo -e "${YELLOW}[1/6] Checking Flutter version...${NC}"
flutter --version
echo ""

echo -e "${YELLOW}[2/6] Checking connected devices...${NC}"
flutter devices
echo ""

# Ask user to confirm device
read -p "Is your Infinix device listed above? (Y/N): " CONFIRM
if [[ ! $CONFIRM =~ ^[Yy]$ ]]
then
    echo ""
    echo "Please connect your Infinix device and enable USB debugging:"
    echo "1. Go to Settings > About Phone"
    echo "2. Tap 'Build Number' 7 times to enable Developer Options"
    echo "3. Go to Settings > Developer Options"
    echo "4. Enable 'USB Debugging'"
    echo "5. Connect device via USB cable"
    echo "6. Accept USB debugging prompt on device"
    echo ""
    exit 1
fi

echo ""
echo -e "${YELLOW}[3/6] Cleaning previous build...${NC}"
flutter clean
echo ""

echo -e "${YELLOW}[4/6] Getting dependencies...${NC}"
flutter pub get
echo ""

echo -e "${YELLOW}[5/6] Building APK (Release mode)...${NC}"
echo "This may take a few minutes..."
echo -e "${YELLOW}[5/6] Building APK (Release mode - Split per ABI)...${NC}"
echo "This may take a few minutes..."
echo "Building optimized APK for Infinix (arm64-v8a)..."
flutter build apk --split-per-abi --release \
    --dart-define=SUPABASE_URL="$SUPABASE_URL" \
    --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
echo ""

if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR] Build failed!${NC}"
    exit 1
fi

echo -e "${GREEN}[SUCCESS] APK built successfully!${NC}"
echo ""
echo "Available APKs:"
echo "- Universal: build/app/outputs/flutter-apk/app-release.apk"
echo "- ARM64 (Recommended for Infinix): build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
echo "- ARM32: build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk"
echo ""

echo -e "${YELLOW}[6/6] Installing ARM64 version on device (recommended for Infinix)...${NC}"
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
echo ""

if [ $? -eq 0 ]; then
    echo "========================================"
    echo -e "${GREEN}[SUCCESS] App installed successfully!${NC}"
    echo "========================================"
    echo ""
    echo "You can now open the app on your Infinix device."
    echo "App name: Masjid App"
    echo ""
else
    echo -e "${RED}[ERROR] Installation failed!${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "1. Make sure USB debugging is enabled"
    echo "2. Check if device is authorized (check device screen)"
    echo "3. Try: adb devices"
    echo "4. Try: adb install -r build/app/outputs/flutter-apk/app-release.apk"
    echo ""
fi
