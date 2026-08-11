#!/bin/bash
set -e

# Build Flutter Android APK
# Usage: ENV_FILE=.env ./build-utils/build-android.sh
#
# Optional environment variables for signing:
#   KEYSTORE_PASSWORD, KEY_PASSWORD, KEY_ALIAS, KEYSTORE_PATH

echo "Building Flutter Android APK..."

# Verify Flutter
if ! command -v flutter &> /dev/null; then
    echo "Error: Flutter not found."
    exit 1
fi

# Project root
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Environment file
ENV_FILE="${ENV_FILE:-.env}"
ENV_ARG=""
if [ -f "$ENV_FILE" ]; then
    echo "Loading environment from $ENV_FILE..."
    ENV_ARG="--dart-define-from-file=$ENV_FILE"
else
    echo "Env file not found: $ENV_FILE"
fi

# Build release APK
echo "Building Android release..."

# Create keystore properties from environment variables
if [ -n "$KEYSTORE_PASSWORD" ] && [ -n "$KEY_PASSWORD" ] && [ -n "$KEY_ALIAS" ] && [ -n "$KEYSTORE_PATH" ]; then
  echo "Creating android/key.properties from environment variables..."
  cat > android/key.properties << EOF
storePassword=$KEYSTORE_PASSWORD
keyPassword=$KEY_PASSWORD
keyAlias=$KEY_ALIAS
storeFile=$KEYSTORE_PATH
EOF
else
  echo "Warning: Keystore environment variables not set. Release build may use debug signing."
fi

# One APK instead of a universal one: every device NeoStation targets is arm64,
# but plain `flutter build apk` packs armeabi-v7a and x86_64 in as well. Both
# flags are needed: --target-platform only drops the engine and AOT libs, while
# --split-per-abi sets abiFilters, which is what drops the plugin natives
# Gradle packages for every ABI.
flutter build apk --release --split-per-abi --target-platform android-arm64 $ENV_ARG

# Get version from pubspec.yaml
VERSION=$(grep 'version:' pubspec.yaml | head -1 | awk '{print $2}' | tr -d '\r')

# Create output directory
mkdir -p "$PROJECT_ROOT/release"

# Copy and rename APK. --split-per-abi renames the output to carry the ABI.
APK_DIR="$PROJECT_ROOT/build/app/outputs/flutter-apk"
SOURCE_APK="$APK_DIR/app-arm64-v8a-release.apk"
DEST_APK="$PROJECT_ROOT/release/neostation-android-arm64-v8a-$VERSION.apk"

if [ -f "$SOURCE_APK" ]; then
    cp "$SOURCE_APK" "$DEST_APK"
    echo ""
    echo "Build completed!"
    echo "Result in: release/"
    ls -lh "$DEST_APK"
else
    echo "APK not found at: $SOURCE_APK"
    exit 1
fi
