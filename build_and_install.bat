@echo off
REM Build and Install Script for Windows
REM This script builds the Flutter app and installs it on connected Android device

echo ========================================
echo Build and Install - Masjid App
echo ========================================
echo.

REM Check if Flutter is installed
where flutter >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Flutter is not installed or not in PATH
    echo Please install Flutter from https://flutter.dev
    pause
    exit /b 1
)

REM Load SUPABASE_URL / SUPABASE_ANON_KEY from .env unless already set in the
REM shell. Only these two values are passed to the build: the service role key
REM and the database password must NEVER be compiled into a client APK.
REM Without them Env.hasValidConfig is false, Supabase is never initialised, and
REM the installed app silently runs 100%% offline with no backend at all.
if exist ".env" (
    for /f "usebackq eol=# tokens=1,* delims==" %%A in (".env") do (
        if /i "%%A"=="SUPABASE_URL" if not defined SUPABASE_URL set "SUPABASE_URL=%%~B"
        if /i "%%A"=="SUPABASE_ANON_KEY" if not defined SUPABASE_ANON_KEY set "SUPABASE_ANON_KEY=%%~B"
    )
)

if not defined SUPABASE_URL goto :missing_config
if not defined SUPABASE_ANON_KEY goto :missing_config
goto :config_ok

:missing_config
echo [ERROR] SUPABASE_URL / SUPABASE_ANON_KEY not found.
echo Create a .env file (see .env.example) or set them as environment variables.
echo Building without them produces an APK that never connects to the backend.
pause
exit /b 1

:config_ok
echo [OK] Supabase config loaded (%SUPABASE_URL%)
echo.

echo [1/6] Checking Flutter version...
flutter --version
echo.

echo [2/6] Checking connected devices...
flutter devices
echo.

REM Ask user to confirm device
set /p CONFIRM="Is your Infinix device listed above? (Y/N): "
if /i not "%CONFIRM%"=="Y" (
    echo.
    echo Please connect your Infinix device and enable USB debugging:
    echo 1. Go to Settings ^> About Phone
    echo 2. Tap "Build Number" 7 times to enable Developer Options
    echo 3. Go to Settings ^> Developer Options
    echo 4. Enable "USB Debugging"
    echo 5. Connect device via USB cable
    echo 6. Accept USB debugging prompt on device
    echo.
    pause
    exit /b 1
)

echo.
echo [3/6] Cleaning previous build...
flutter clean
echo.

echo [4/6] Getting dependencies...
flutter pub get
echo.

echo [5/6] Building APK (Release mode - Split per ABI)...
echo This may take a few minutes...
echo Building optimized APK for Infinix (arm64-v8a)...
flutter build apk --split-per-abi --release ^
    --dart-define=SUPABASE_URL=%SUPABASE_URL% ^
    --dart-define=SUPABASE_ANON_KEY=%SUPABASE_ANON_KEY%
echo.

if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Build failed!
    pause
    exit /b 1
)

echo [SUCCESS] APK built successfully!
echo.
echo Available APKs:
echo - Universal: build\app\outputs\flutter-apk\app-release.apk
echo - ARM64 (Recommended for Infinix): build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
echo - ARM32: build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk
echo.

echo [6/6] Installing ARM64 version on device (recommended for Infinix)...
adb install -r build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
echo.

if %ERRORLEVEL% EQU 0 (
    echo ========================================
    echo [SUCCESS] App installed successfully!
    echo ========================================
    echo.
    echo You can now open the app on your Infinix device.
    echo App name: Masjid App
    echo.
) else (
    echo [ERROR] Installation failed!
    echo.
    echo Troubleshooting:
    echo 1. Make sure USB debugging is enabled
    echo 2. Check if device is authorized (check device screen)
    echo 3. Try: adb devices
    echo 4. Try: adb install -r build\app\outputs\flutter-apk\app-release.apk
    echo.
)

pause
