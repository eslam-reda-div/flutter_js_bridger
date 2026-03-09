/// QuickJS engine — Android and other platforms via dart:ffi.
///
/// Uses QuickJS (https://bellard.org/quickjs/), a small embeddable
/// JavaScript engine. Requires a pre-compiled `libquickjs` shared
/// library accessible at runtime.
///
/// Setup:
/// - Android: Place compiled `libquickjs.so` in `android/src/main/jniLibs/`
/// - Linux:   Compile QuickJS and ensure `libquickjs.so` is in LD_LIBRARY_PATH
/// - Windows: Compile QuickJS and ensure `quickjs.dll` is in PATH
///
/// This engine evaluates JavaScript synchronously through FFI.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import '../embedded_worker_source.dart';
import 'in_process_engine.dart';

// ═══════════════════════════════════════════════════════
//  QuickJS FFI Type Definitions
// ═══════════════════════════════════════════════════════

/// Opaque QuickJS runtime pointer.
typedef JSRuntimePtr = Pointer<Void>;

/// Opaque QuickJS context pointer.
typedef JSContextPtr = Pointer<Void>;

// JS_NewRuntime() → JSRuntime*
typedef _JSNewRuntimeNative = JSRuntimePtr Function();
typedef _JSNewRuntimeDart = JSRuntimePtr Function();

// JS_FreeRuntime(JSRuntime*)
typedef _JSFreeRuntimeNative = Void Function(JSRuntimePtr rt);
typedef _JSFreeRuntimeDart = void Function(JSRuntimePtr rt);

// JS_NewContext(JSRuntime*) → JSContext*
typedef _JSNewContextNative = JSContextPtr Function(JSRuntimePtr rt);
typedef _JSNewContextDart = JSContextPtr Function(JSRuntimePtr rt);

// JS_FreeContext(JSContext*)
typedef _JSFreeContextNative = Void Function(JSContextPtr ctx);
typedef _JSFreeContextDart = void Function(JSContextPtr ctx);

/// Wrapper that calls JS_Eval, converts result to string, and frees the value.
/// This is a C helper function that must be compiled alongside QuickJS.
///
/// Signature: const char* qjs_eval_to_string(JSContext* ctx, const char* code)
typedef _QjsEvalToStringNative = Pointer<Uint8> Function(
    JSContextPtr ctx, Pointer<Uint8> code);
typedef _QjsEvalToStringDart = Pointer<Uint8> Function(
    JSContextPtr ctx, Pointer<Uint8> code);

/// Free a C string returned by qjs_eval_to_string.
typedef _QjsFreeCStringNative = Void Function(
    JSContextPtr ctx, Pointer<Uint8> ptr);
typedef _QjsFreeCStringDart = void Function(
    JSContextPtr ctx, Pointer<Uint8> ptr);

/// Execute pending jobs (for Promise resolution).
typedef _JSExecutePendingJobNative = Int32 Function(
    JSRuntimePtr rt, Pointer<JSContextPtr> pctx);
typedef _JSExecutePendingJobDart = int Function(
    JSRuntimePtr rt, Pointer<JSContextPtr> pctx);

/// FFI bindings to QuickJS library.
class _QuickJsBindings {
  late final _JSNewRuntimeDart newRuntime;
  late final _JSFreeRuntimeDart freeRuntime;
  late final _JSNewContextDart newContext;
  late final _JSFreeContextDart freeContext;
  late final _QjsEvalToStringDart evalToString;
  late final _QjsFreeCStringDart freeCString;
  late final _JSExecutePendingJobDart executePendingJob;

  _QuickJsBindings(DynamicLibrary lib) {
    newRuntime = lib.lookupFunction<_JSNewRuntimeNative, _JSNewRuntimeDart>(
        'JS_NewRuntime');
    freeRuntime = lib.lookupFunction<_JSFreeRuntimeNative, _JSFreeRuntimeDart>(
        'JS_FreeRuntime');
    newContext = lib.lookupFunction<_JSNewContextNative, _JSNewContextDart>(
        'JS_NewContext');
    freeContext = lib.lookupFunction<_JSFreeContextNative, _JSFreeContextDart>(
        'JS_FreeContext');
    evalToString =
        lib.lookupFunction<_QjsEvalToStringNative, _QjsEvalToStringDart>(
            'qjs_eval_to_string');
    freeCString =
        lib.lookupFunction<_QjsFreeCStringNative, _QjsFreeCStringDart>(
            'qjs_free_cstring');
    executePendingJob = lib.lookupFunction<_JSExecutePendingJobNative,
        _JSExecutePendingJobDart>('JS_ExecutePendingJob');
  }
}

/// QuickJS engine for Android and other platforms.
///
/// Requires a compiled QuickJS shared library with the helper shim:
/// ```c
/// #include "quickjs.h"
/// #include <string.h>
///
/// // Evaluate JS code and return result as C string.
/// // Caller must free with qjs_free_cstring().
/// const char* qjs_eval_to_string(JSContext* ctx, const char* code) {
///     JSValue val = JS_Eval(ctx, code, strlen(code), "<eval>",
///                           JS_EVAL_TYPE_GLOBAL);
///     if (JS_IsException(val)) {
///         JSValue exc = JS_GetException(ctx);
///         const char* msg = JS_ToCString(ctx, exc);
///         JS_FreeValue(ctx, exc);
///         // Prefix with "ERROR:" so Dart can detect errors
///         size_t len = strlen(msg) + 7;
///         char* buf = js_malloc(ctx, len + 1);
///         snprintf(buf, len + 1, "ERROR:%s", msg);
///         JS_FreeCString(ctx, msg);
///         JS_FreeValue(ctx, val);
///         return buf;
///     }
///     const char* str = JS_ToCString(ctx, val);
///     JS_FreeValue(ctx, val);
///     return str;
/// }
///
/// void qjs_free_cstring(JSContext* ctx, const char* ptr) {
///     JS_FreeCString(ctx, ptr);
/// }
/// ```
class QuickJsEngine extends InProcessEngine {
  _QuickJsBindings? _bindings;
  JSRuntimePtr? _runtime;
  JSContextPtr? _ctx;
  DynamicLibrary? _lib;

  QuickJsEngine(super.config);

  /// Check if a QuickJS library is available on this platform.
  static bool get isAvailable {
    try {
      _openQuickJsLib();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Try to open the QuickJS shared library.
  static DynamicLibrary _openQuickJsLib() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libquickjs.so');
    } else if (Platform.isLinux) {
      // Try common locations
      try {
        return DynamicLibrary.open('libquickjs.so');
      } catch (_) {
        return DynamicLibrary.open('/usr/local/lib/libquickjs.so');
      }
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('quickjs.dll');
    } else {
      throw UnsupportedError(
        'QuickJS is not supported on ${Platform.operatingSystem}. '
        'Use JscEngine on iOS/macOS.',
      );
    }
  }

  @override
  void initRuntime() {
    _lib = _openQuickJsLib();
    _bindings = _QuickJsBindings(_lib!);
    _runtime = _bindings!.newRuntime();
    _ctx = _bindings!.newContext(_runtime!);

    // Load the embedded worker script
    evalJs(embeddedWorkerSource);

    // Load bundle if configured
    if (config.bundlePath != null) {
      final bundleFile = File(config.bundlePath!);
      if (bundleFile.existsSync()) {
        evalJs(bundleFile.readAsStringSync());
      }
    }
  }

  @override
  void destroyRuntime() {
    if (_ctx != null && _bindings != null) {
      _bindings!.freeContext(_ctx!);
      _ctx = null;
    }
    if (_runtime != null && _bindings != null) {
      _bindings!.freeRuntime(_runtime!);
      _runtime = null;
    }
    _bindings = null;
    _lib = null;
  }

  @override
  String evalJs(String code) {
    final b = _bindings!;
    final ctx = _ctx!;

    final codePtr = _toNativeUtf8(code);
    final resultPtr = b.evalToString(ctx, codePtr);
    _freeNative(codePtr);

    // Execute pending jobs (resolve Promises)
    _drainJobs();

    final result = _fromNativeUtf8(resultPtr);
    b.freeCString(ctx, resultPtr);

    // Check for error prefix
    if (result.startsWith('ERROR:')) {
      throw Exception('QuickJS error: ${result.substring(6)}');
    }

    return result;
  }

  /// Execute all pending microtasks/promises.
  void _drainJobs() {
    if (_bindings == null || _runtime == null) return;
    final pctx = _allocPtrVoid();
    while (_bindings!.executePendingJob(_runtime!, pctx) > 0) {
      // Keep executing until no more pending jobs
    }
    _freeNative(pctx);
  }
}

// ═══════════════════════════════════════════════════════
//  Native memory helpers
// ═══════════════════════════════════════════════════════

final DynamicLibrary _nativeLib = Platform.isWindows
    ? DynamicLibrary.open('msvcrt.dll')
    : Platform.isAndroid
        ? DynamicLibrary.open('libc.so')
        : DynamicLibrary.process();

typedef _MallocNat = Pointer<Void> Function(Size size);
typedef _MallocDt = Pointer<Void> Function(int size);
typedef _FreeNat = Void Function(Pointer<Void> ptr);
typedef _FreeDt = void Function(Pointer<Void> ptr);

final _MallocDt _nativeMalloc =
    _nativeLib.lookupFunction<_MallocNat, _MallocDt>('malloc');
final _FreeDt _nativeFree =
    _nativeLib.lookupFunction<_FreeNat, _FreeDt>('free');

Pointer<Uint8> _toNativeUtf8(String s) {
  final units = utf8.encode(s);
  final ptr = _nativeMalloc(units.length + 1).cast<Uint8>();
  final byteList = ptr.asTypedList(units.length + 1);
  byteList.setAll(0, units);
  byteList[units.length] = 0;
  return ptr;
}

String _fromNativeUtf8(Pointer<Uint8> ptr) {
  final bytes = <int>[];
  var i = 0;
  while (true) {
    final byte = ptr[i];
    if (byte == 0) break;
    bytes.add(byte);
    i++;
  }
  return utf8.decode(bytes);
}

Pointer<Pointer<Void>> _allocPtrVoid() {
  return _nativeMalloc(sizeOf<Pointer>()).cast<Pointer<Void>>();
}

void _freeNative(Pointer ptr) {
  _nativeFree(ptr.cast<Void>());
}
