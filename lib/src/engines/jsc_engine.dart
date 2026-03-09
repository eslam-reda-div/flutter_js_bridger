/// JavaScriptCore engine — iOS and macOS via dart:ffi.
///
/// Uses the system JavaScriptCore framework (always available on
/// Apple platforms, no extra libraries needed).
///
/// This engine evaluates JavaScript synchronously through FFI,
/// making it faster than subprocess-based engines for simple operations.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import '../embedded_worker_source.dart';
import 'in_process_engine.dart';

// ═══════════════════════════════════════════════════════
//  JavaScriptCore FFI Type Definitions
// ═══════════════════════════════════════════════════════

/// Opaque JSC context pointer.
typedef JSContextRef = Pointer<Void>;

/// Opaque JSC value pointer.
typedef JSValueRef = Pointer<Void>;

/// Opaque JSC string pointer.
typedef JSStringRef = Pointer<Void>;

// Native function signatures (use Pointer<Uint8> for C strings)
typedef _JSGlobalContextCreateNative = JSContextRef Function(
    Pointer<Void> globalObjectClass);
typedef _JSGlobalContextCreateDart = JSContextRef Function(
    Pointer<Void> globalObjectClass);

typedef _JSGlobalContextReleaseNative = Void Function(JSContextRef ctx);
typedef _JSGlobalContextReleaseDart = void Function(JSContextRef ctx);

typedef _JSStringCreateNative = JSStringRef Function(Pointer<Uint8> string);
typedef _JSStringCreateDart = JSStringRef Function(Pointer<Uint8> string);

typedef _JSStringReleaseNative = Void Function(JSStringRef string);
typedef _JSStringReleaseDart = void Function(JSStringRef string);

typedef _JSEvaluateScriptNative = JSValueRef Function(
  JSContextRef ctx,
  JSStringRef script,
  JSValueRef thisObject,
  JSStringRef sourceURL,
  Int32 startingLineNumber,
  Pointer<JSValueRef> exception,
);
typedef _JSEvaluateScriptDart = JSValueRef Function(
  JSContextRef ctx,
  JSStringRef script,
  JSValueRef thisObject,
  JSStringRef sourceURL,
  int startingLineNumber,
  Pointer<JSValueRef> exception,
);

typedef _JSValueToStringCopyNative = JSStringRef Function(
  JSContextRef ctx,
  JSValueRef value,
  Pointer<JSValueRef> exception,
);
typedef _JSValueToStringCopyDart = JSStringRef Function(
  JSContextRef ctx,
  JSValueRef value,
  Pointer<JSValueRef> exception,
);

typedef _JSStringGetMaxUTF8Native = Size Function(JSStringRef string);
typedef _JSStringGetMaxUTF8Dart = int Function(JSStringRef string);

typedef _JSStringGetUTF8Native = Size Function(
    JSStringRef string, Pointer<Uint8> buffer, Size bufferSize);
typedef _JSStringGetUTF8Dart = int Function(
    JSStringRef string, Pointer<Uint8> buffer, int bufferSize);

typedef _JSValueIsUndefinedNative = Bool Function(
    JSContextRef ctx, JSValueRef value);
typedef _JSValueIsUndefinedDart = bool Function(
    JSContextRef ctx, JSValueRef value);

/// FFI bindings to JavaScriptCore framework.
class _JscBindings {
  late final _JSGlobalContextCreateDart createContext;
  late final _JSGlobalContextReleaseDart releaseContext;
  late final _JSStringCreateDart createString;
  late final _JSStringReleaseDart releaseString;
  late final _JSEvaluateScriptDart evaluateScript;
  late final _JSValueToStringCopyDart valueToStringCopy;
  late final _JSStringGetMaxUTF8Dart getMaxUTF8Size;
  late final _JSStringGetUTF8Dart getUTF8CString;
  late final _JSValueIsUndefinedDart isUndefined;

  _JscBindings(DynamicLibrary lib) {
    createContext = lib.lookupFunction<_JSGlobalContextCreateNative,
        _JSGlobalContextCreateDart>('JSGlobalContextCreate');
    releaseContext = lib.lookupFunction<_JSGlobalContextReleaseNative,
        _JSGlobalContextReleaseDart>('JSGlobalContextRelease');
    createString =
        lib.lookupFunction<_JSStringCreateNative, _JSStringCreateDart>(
            'JSStringCreateWithUTF8CString');
    releaseString =
        lib.lookupFunction<_JSStringReleaseNative, _JSStringReleaseDart>(
            'JSStringRelease');
    evaluateScript =
        lib.lookupFunction<_JSEvaluateScriptNative, _JSEvaluateScriptDart>(
            'JSEvaluateScript');
    valueToStringCopy = lib.lookupFunction<_JSValueToStringCopyNative,
        _JSValueToStringCopyDart>('JSValueToStringCopy');
    getMaxUTF8Size =
        lib.lookupFunction<_JSStringGetMaxUTF8Native, _JSStringGetMaxUTF8Dart>(
            'JSStringGetMaximumUTF8CStringSize');
    getUTF8CString =
        lib.lookupFunction<_JSStringGetUTF8Native, _JSStringGetUTF8Dart>(
            'JSStringGetUTF8CString');
    isUndefined =
        lib.lookupFunction<_JSValueIsUndefinedNative, _JSValueIsUndefinedDart>(
            'JSValueIsUndefined');
  }
}

/// JavaScriptCore engine for iOS and macOS.
///
/// Uses the system framework — no extra libraries needed.
class JscEngine extends InProcessEngine {
  _JscBindings? _bindings;
  JSContextRef? _ctx;

  JscEngine(super.config);

  /// Check if JavaScriptCore is available on this platform.
  static bool get isAvailable {
    if (!Platform.isIOS && !Platform.isMacOS) return false;
    try {
      DynamicLibrary.open(
        '/System/Library/Frameworks/JavaScriptCore.framework/JavaScriptCore',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void initRuntime() {
    final lib = DynamicLibrary.open(
      '/System/Library/Frameworks/JavaScriptCore.framework/JavaScriptCore',
    );
    _bindings = _JscBindings(lib);
    _ctx = _bindings!.createContext(nullptr);

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
      _bindings!.releaseContext(_ctx!);
      _ctx = null;
    }
    _bindings = null;
  }

  @override
  String evalJs(String code) {
    final b = _bindings!;
    final ctx = _ctx!;

    // Create JS string from Dart string
    final codePtr = _toNative(code);
    final jsStr = b.createString(codePtr);
    _freePtr(codePtr);

    // Evaluate
    final exception = _allocPointer();
    final result = b.evaluateScript(
      ctx,
      jsStr,
      nullptr, // thisObject
      nullptr, // sourceURL
      1, // startingLineNumber
      exception,
    );
    b.releaseString(jsStr);

    // Check for exception
    final exc = exception.value;
    _freePtr(exception);
    if (exc != nullptr) {
      final errStr = _jsValueToString(ctx, exc);
      throw Exception('JSC error: $errStr');
    }

    // Convert result to string
    if (result == nullptr || b.isUndefined(ctx, result)) {
      return 'null';
    }
    return _jsValueToString(ctx, result);
  }

  String _jsValueToString(JSContextRef ctx, JSValueRef value) {
    final b = _bindings!;
    final exception = _allocPointer();
    final jsStr = b.valueToStringCopy(ctx, value, exception);
    _freePtr(exception);

    final maxSize = b.getMaxUTF8Size(jsStr);
    final buffer = _allocBuffer(maxSize);
    b.getUTF8CString(jsStr, buffer, maxSize);
    b.releaseString(jsStr);

    final result = _fromNative(buffer);
    _freePtr(buffer);
    return result;
  }
}

// ═══════════════════════════════════════════════════════
//  Native memory helpers (no package:ffi dependency)
// ═══════════════════════════════════════════════════════

final DynamicLibrary _stdlib = Platform.isMacOS || Platform.isIOS
    ? DynamicLibrary.process()
    : DynamicLibrary.open('libc.so.6');

typedef _MallocNative = Pointer<Void> Function(Size size);
typedef _MallocDart = Pointer<Void> Function(int size);
typedef _FreeNative = Void Function(Pointer<Void> ptr);
typedef _FreeDart = void Function(Pointer<Void> ptr);

final _MallocDart _malloc =
    _stdlib.lookupFunction<_MallocNative, _MallocDart>('malloc');
final _FreeDart _free = _stdlib.lookupFunction<_FreeNative, _FreeDart>('free');

/// Encode a Dart String to a null-terminated UTF-8 byte array in native memory.
Pointer<Uint8> _toNative(String s) {
  final units = utf8.encode(s);
  final ptr = _malloc(units.length + 1).cast<Uint8>();
  final byteList = ptr.asTypedList(units.length + 1);
  byteList.setAll(0, units);
  byteList[units.length] = 0; // null terminator
  return ptr;
}

/// Allocate a native buffer of the given size.
Pointer<Uint8> _allocBuffer(int size) {
  return _malloc(size).cast<Uint8>();
}

/// Allocate space for a single pointer.
Pointer<Pointer<Void>> _allocPointer() {
  return _malloc(sizeOf<Pointer>()).cast<Pointer<Void>>();
}

/// Free a native pointer.
void _freePtr(Pointer ptr) {
  _free(ptr.cast<Void>());
}

/// Decode a null-terminated UTF-8 C string to a Dart String.
String _fromNative(Pointer<Uint8> ptr) {
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
