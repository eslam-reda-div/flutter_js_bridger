# Android QuickJS Native Library Setup

## Overview

`flutter_js_bridger` uses [QuickJS](https://bellard.org/quickjs/) on Android to run JavaScript natively via FFI without needing Node.js. This requires a compiled `libquickjs.so` shared library for each Android ABI.

## Quick Setup

### Option 1: Pre-built Libraries (Recommended)

Download pre-built `.so` files from the [releases page](https://github.com/nicbarker/nicbarker-quickjs/releases) or build them yourself:

### Option 2: Build From Source

#### Prerequisites

- Android NDK (install via Android Studio → SDK Manager → SDK Tools → NDK)
- CMake 3.10+ (install via Android Studio or system package manager)
- Git

#### Steps

```bash
# 1. Navigate to the native build directory
cd native/quickjs

# 2. Download QuickJS source
git clone https://github.com/nicbarker/nicbarker-quickjs quickjs-src

# 3. Build for all Android ABIs
chmod +x build_android.sh
./build_android.sh

# 4. Copy to your Flutter project
# The script will print the copy commands at the end
```

## Installing in Your Flutter Project

Copy the compiled `.so` files into your Flutter project's JNI libs directory:

```
your_flutter_app/
  android/
    app/
      src/
        main/
          jniLibs/
            armeabi-v7a/
              libquickjs.so
            arm64-v8a/
              libquickjs.so
            x86/
              libquickjs.so        (emulator only)
            x86_64/
              libquickjs.so        (emulator only)
```

The minimum required ABIs for production are `armeabi-v7a` and `arm64-v8a`. The x86 variants are only needed for Android emulators.

## How It Works

1. `flutter_js_bridger` detects Android at runtime
2. Opens `libquickjs.so` via `dart:ffi` (`DynamicLibrary.open`)
3. Creates a QuickJS runtime and context
4. Evaluates JavaScript through the `qjs_eval_to_string()` shim function
5. The embedded worker script handles the JSON-RPC message protocol

## The C Shim

The `quickjs_bridger_shim.c` file provides two functions:

```c
// Evaluate JS and return result as string (or "ERROR:..." on failure)
const char* qjs_eval_to_string(JSContext* ctx, const char* code);

// Free the returned string
void qjs_free_cstring(JSContext* ctx, const char* ptr);
```

These are the only two functions called from Dart via FFI. All other QuickJS symbols are internal.

## Bundling npm Packages for Android

Since Android doesn't have npm at runtime, packages must be pre-bundled:

```bash
# In your project root:
dart run flutter_js_bridger init
dart run flutter_js_bridger add lodash
dart run flutter_js_bridger bundle --output assets/js_bundle.js
```

Then in your Dart code:

```dart
final js = JsBridge(JsBridgeConfig(
  bundlePath: 'assets/js_bundle.js',
));
await js.initialize();
dynamic _ = await js.require('lodash');
```

## Troubleshooting

### `Failed to load libquickjs.so`

- Ensure the `.so` files are in the correct `jniLibs` directories
- Verify the ABI matches (use `adb shell getprop ro.product.cpu.abi`)
- Check that `libquickjs.so` exports `qjs_eval_to_string` and `qjs_free_cstring`

### `Symbol not found: qjs_eval_to_string`

- The QuickJS library was compiled without the shim. Rebuild using the CMakeLists.txt in this directory which includes `quickjs_bridger_shim.c`.

### Build errors on Windows

- Use WSL2 or a Linux Docker container to cross-compile for Android
- Windows native builds use `quickjs.dll` and the NodeEngine, not QuickJsEngine
