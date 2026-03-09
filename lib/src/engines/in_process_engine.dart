/// Base class for in-process JS engines (web, mobile).
///
/// Unlike [NodeEngine] which communicates over stdin/stdout with a subprocess,
/// in-process engines run JavaScript directly (via FFI or js_interop) and
/// call the handler function synchronously.
///
/// ## Timeout Limitation
///
/// Because `evalJs()` is a **synchronous FFI call** (or synchronous
/// `js_interop` call on web), it blocks the Dart isolate until JavaScript
/// execution completes. There is no way to abort or timeout a running
/// FFI call from the same isolate.
///
/// The `EngineConfig.requestTimeout` setting has **no effect** for
/// in-process engines. If a JavaScript operation runs an infinite loop,
/// the Dart isolate will be blocked indefinitely.
///
/// **Workarounds**:
/// - Avoid running untrusted/long-running JS code on mobile/web.
/// - For desktop, use [NodeEngine] which runs JS in a separate process
///   and supports true request timeouts.
/// - Future versions may add isolate-based execution for timeout support.
library;

import 'dart:async';
import 'dart:convert';

import '../errors.dart';
import 'engine_interface.dart';

/// Base class for engines that run JS in the same process.
///
/// Subclasses implement [evalJs] and [initRuntime]/[destroyRuntime].
/// Message handling, GC batching, callback polling, and protocol parsing
/// are provided.
abstract class InProcessEngine implements JsEngine {
  final EngineConfig config;

  bool _ready = false;
  int _nextId = 0;
  late final GcBatcher _gcBatcher;
  final StreamController<EngineEvent> _eventController =
      StreamController<EngineEvent>.broadcast();

  /// Handler for JS→Dart callback invocations.
  ///
  /// Set this from [JsBridge] to receive callbacks from the JS side.
  void Function(int callbackId, List<dynamic> args)? onCallback;

  InProcessEngine(this.config) {
    _gcBatcher = GcBatcher(sendFireAndForget);
  }

  /// Evaluate a JavaScript string and return the result as a string.
  ///
  /// This is the only method subclasses MUST implement.
  /// It should evaluate the code in the JS runtime and return the
  /// result (or throw on error).
  String evalJs(String code);

  /// Initialize the JS runtime (called by [start]).
  ///
  /// Subclasses should create the JS context/runtime here.
  void initRuntime();

  /// Destroy the JS runtime (called by [shutdown]).
  void destroyRuntime();

  @override
  bool get isReady => _ready;

  @override
  Stream<EngineEvent> get events => _eventController.stream;

  @override
  Future<void> start() async {
    if (_ready) return;
    initRuntime();
    _ready = true;
    _eventController.add(EngineReadyEvent());
  }

  @override
  Future<dynamic> send(Map<String, dynamic> message) async {
    if (!_ready) {
      throw const JsRuntimeException(
        JsErrorCode.workerNotReady,
        'Engine not ready. Call initialize() first.',
      );
    }

    final id = ++_nextId;
    final fullMsg = {...message, 'id': id};
    final msgJson = jsonEncode(fullMsg);

    // Escape single quotes in the JSON for JS string embedding
    final escaped = msgJson.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

    // Note: evalJs is synchronous (FFI/js_interop). A true timeout requires
    // isolate-based execution. For now, we wrap in try/catch for error recovery.
    String resultJson;
    try {
      resultJson = evalJs("__bridgerHandle('$escaped')");
    } on Exception catch (e) {
      throw JsBridgeException(
        JsErrorCode.protocolError,
        'JS eval failed: $e',
      );
    } on Error catch (e) {
      throw JsBridgeException(
        JsErrorCode.protocolError,
        'JS eval crashed: $e',
      );
    }

    // Drain callback queue after each operation
    _drainCallbackQueue();

    Map<String, dynamic> resultMap;
    try {
      resultMap = jsonDecode(resultJson) as Map<String, dynamic>;
    } catch (e) {
      throw JsBridgeException(
        JsErrorCode.protocolError,
        'Invalid JSON response from JS engine: $e',
      );
    }

    if (resultMap.containsKey('error')) {
      throw JsBridgeException.fromWorker(
          resultMap['error'] as Map<String, dynamic>);
    }

    return resultMap['result'];
  }

  @override
  void sendFireAndForget(Map<String, dynamic> message) {
    if (!_ready) return;
    try {
      final id = ++_nextId;
      final fullMsg = {...message, 'id': id};
      final msgJson = jsonEncode(fullMsg);
      final escaped = msgJson.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
      evalJs("__bridgerHandle('$escaped')");
    } catch (_) {
      // best-effort
    }
  }

  @override
  Future<List<dynamic>> sendBatch(List<Map<String, dynamic>> messages) async {
    if (messages.isEmpty) return [];
    if (messages.length == 1) return [await send(messages.first)];

    final result = await send({
      'action': 'batch',
      'requests': messages,
    });

    if (result is! List) {
      throw const JsBridgeException(
        JsErrorCode.protocolError,
        'Batch response was not a list',
      );
    }

    return result.map((item) {
      if (item is Map && item.containsKey('error')) {
        throw JsBridgeException.fromWorker(
            item['error'] as Map<String, dynamic>);
      }
      return item is Map ? item['result'] : item;
    }).toList();
  }

  @override
  void scheduleGc(int refId) => _gcBatcher.schedule(refId);

  @override
  void flushGc() => _gcBatcher.flush();

  @override
  Future<void> shutdown() async {
    _gcBatcher.flush();
    _gcBatcher.dispose();
    _ready = false;
    destroyRuntime();
    await _eventController.close();
  }

  /// Poll the JS callback queue and dispatch to the Dart handler.
  void _drainCallbackQueue() {
    if (onCallback == null) return;
    try {
      final json = evalJs('__bridgerDrainCallbacks()');
      final queue = jsonDecode(json) as List;
      for (final entry in queue) {
        final map = entry as Map<String, dynamic>;
        final callbackId = map['callbackId'] as int;
        final argsJson = map['args'] as String;
        final args = jsonDecode(argsJson) as List;
        onCallback!(callbackId, args);
      }
    } catch (_) {
      // best-effort — callback queue may not exist yet
    }
  }
}
