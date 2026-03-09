/// Web engine — runs JavaScript via dart:js_interop.
///
/// On web platforms, there's no subprocess. JavaScript runs in the
/// browser's main context. The embedded worker logic is loaded via
/// eval and called directly through JS interop.
///
/// npm packages must be pre-bundled at dev time:
///   dart run flutter_js_bridger bundle
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import '../errors.dart';
import '../embedded_worker_source.dart';
import 'engine_interface.dart';

@JS('eval')
external JSAny? _jsEval(JSString code);

@JS('JSON.stringify')
external JSString _jsonStringify(JSAny? value);

/// Web engine — evaluates JS in the browser context via dart:js_interop.
class WebEngine implements JsEngine {
  final EngineConfig _config;

  bool _ready = false;
  int _nextId = 0;
  late final GcBatcher _gcBatcher;
  final StreamController<EngineEvent> _eventController =
      StreamController<EngineEvent>.broadcast();

  WebEngine(this._config) {
    _gcBatcher = GcBatcher(sendFireAndForget);
  }

  @override
  bool get isReady => _ready;

  @override
  Stream<EngineEvent> get events => _eventController.stream;

  @override
  Future<void> start() async {
    if (_ready) return;

    // Load the embedded worker script into the global scope
    _jsEval(embeddedWorkerSource.toJS);

    // Load bundle if configured
    if (_config.bundlePath != null && _config.bundlePath!.isNotEmpty) {
      // On web, bundlePath points to a JS file that should be loaded
      // via a <script> tag. The bundle registers modules in __bundledModules.
      // For runtime loading, we fetch and eval it.
      try {
        final fetchResult = _jsEval(
          '''
          (async function() {
            const resp = await fetch('${_config.bundlePath}');
            const code = await resp.text();
            (0, eval)(code);
            return 'ok';
          })()
          '''
              .toJS,
        );
        if (fetchResult != null) {
          // Wait for the fetch promise
          await (fetchResult as JSPromise).toDart;
        }
      } catch (_) {
        // Bundle loading is best-effort on web
      }
    }

    _ready = true;
    _eventController.add(EngineReadyEvent());
  }

  String _evalJs(String code) {
    final result = _jsEval(code.toJS);
    if (result == null) return 'null';
    // Convert JSAny to string
    try {
      return (result as JSString).toDart;
    } catch (_) {
      return _jsonStringify(result).toDart;
    }
  }

  @override
  Future<dynamic> send(Map<String, dynamic> message) async {
    if (!_ready) {
      throw const JsRuntimeException(
        JsErrorCode.workerNotReady,
        'Web engine not ready. Call initialize() first.',
      );
    }

    final id = ++_nextId;
    final fullMsg = {...message, 'id': id};
    final msgJson = jsonEncode(fullMsg);
    final escaped = msgJson.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

    String resultJson;
    try {
      resultJson = _evalJs("__bridgerHandle('$escaped')");
    } catch (e) {
      throw JsBridgeException(
        JsErrorCode.protocolError,
        'JS eval failed: $e',
      );
    }

    final resultMap = jsonDecode(resultJson) as Map<String, dynamic>;

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
      _evalJs("__bridgerHandle('$escaped')");
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
    // Eval cleanup
    try {
      _jsEval("refs && refs.clear && refs.clear()".toJS);
    } catch (_) {}
    await _eventController.close();
  }
}
