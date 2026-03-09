#!/bin/bash
# build_android.sh — Build libquickjs.so for all Android ABIs
#
# Prerequisites:
#   - Android NDK installed (set ANDROID_NDK_HOME or NDK is in $ANDROID_HOME/ndk/)
#   - CMake 3.10+ installed
#   - QuickJS source placed in ./quickjs-src/
#
# Usage:
#   cd native/quickjs
#   ./build_android.sh
#
# Output:
#   build/android/<abi>/libquickjs.so for each ABI

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build/android"
QUICKJS_SRC="${SCRIPT_DIR}/quickjs-src"

# Find NDK
if [ -z "$ANDROID_NDK_HOME" ]; then
    if [ -n "$ANDROID_HOME" ]; then
        # Find latest NDK version
        NDK_DIR=$(ls -d "$ANDROID_HOME/ndk/"* 2>/dev/null | sort -V | tail -1)
        if [ -n "$NDK_DIR" ]; then
            ANDROID_NDK_HOME="$NDK_DIR"
        fi
    fi
fi

if [ -z "$ANDROID_NDK_HOME" ] || [ ! -d "$ANDROID_NDK_HOME" ]; then
    echo "ERROR: Android NDK not found."
    echo "Set ANDROID_NDK_HOME or install NDK via Android Studio SDK Manager."
    exit 1
fi

if [ ! -f "$QUICKJS_SRC/quickjs.h" ]; then
    echo "ERROR: QuickJS source not found at $QUICKJS_SRC"
    echo ""
    echo "Download QuickJS source:"
    echo "  git clone https://github.com/nicbarker/nicbarker-quickjs quickjs-src"
    echo "  OR"
    echo "  wget https://bellard.org/quickjs/quickjs-2024-02-14.tar.xz"
    echo "  tar xf quickjs-2024-02-14.tar.xz"
    echo "  mv quickjs-2024-02-14 quickjs-src"
    exit 1
fi

CMAKE_TOOLCHAIN="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake"
if [ ! -f "$CMAKE_TOOLCHAIN" ]; then
    echo "ERROR: CMake toolchain not found at $CMAKE_TOOLCHAIN"
    exit 1
fi

ABIS=("armeabi-v7a" "arm64-v8a" "x86" "x86_64")
API_LEVEL=21

echo "Building libquickjs.so for Android..."
echo "NDK: $ANDROID_NDK_HOME"
echo "QuickJS: $QUICKJS_SRC"
echo ""

for ABI in "${ABIS[@]}"; do
    echo "=== Building for $ABI ==="
    ABI_BUILD_DIR="$BUILD_DIR/$ABI"
    mkdir -p "$ABI_BUILD_DIR"

    cmake -S "$SCRIPT_DIR" -B "$ABI_BUILD_DIR" \
        -DCMAKE_TOOLCHAIN_FILE="$CMAKE_TOOLCHAIN" \
        -DANDROID_ABI="$ABI" \
        -DANDROID_PLATFORM="android-$API_LEVEL" \
        -DQUICKJS_SRC_DIR="$QUICKJS_SRC" \
        -DCMAKE_BUILD_TYPE=Release

    cmake --build "$ABI_BUILD_DIR" --config Release -j$(nproc 2>/dev/null || echo 4)

    echo "  -> $ABI_BUILD_DIR/libquickjs.so"
    echo ""
done

echo "Done! Copy the .so files to your Flutter project:"
echo ""
for ABI in "${ABIS[@]}"; do
    echo "  cp $BUILD_DIR/$ABI/libquickjs.so android/app/src/main/jniLibs/$ABI/"
done
echo ""
echo "Or use the setup script:"
echo "  dart run flutter_js_bridger setup-android --libs-dir $BUILD_DIR"
