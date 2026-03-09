/// Node.js subprocess engine — desktop platforms (Windows, macOS, Linux).
///
/// Spawns a Node.js child process running an embedded worker script.
/// Communicates via newline-delimited JSON over stdin/stdout.
///
/// Includes:
/// - Batch GC (queued reference cleanup)
/// - Auto-reconnect on crash
/// - Batch request API
/// - Callback support (JS → Dart)
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../errors.dart';
import '../worker_source.dart';
import 'engine_interface.dart';

/// Node.js subprocess engine for desktop platforms.
///
/// Each request gets a unique ID, and responses are matched back
/// via stdin/stdout JSON-RPC protocol.
class NodeEngine implements JsEngine {
  final EngineConfig _config;

  Process? _process;
  final Map<int, Completer<dynamic>> _pending = {};
  int _nextId = 0;
  bool _ready = false;
  int _restartCount = 0;
  Completer<void>? _readyCompleter;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  final StringBuffer _stderrBuffer = StringBuffer();
  late final GcBatcher _gcBatcher;
  final StreamController<EngineEvent> _eventController =
      StreamController<EngineEvent>.broadcast();

  /// Handler for JS→Dart callback invocations.
  void Function(int callbackId, List<dynamic> args, int? invokeId)? onCallback;

  NodeEngine(this._config) {
    _gcBatcher = GcBatcher(sendFireAndForget);
  }

  @override
  bool get isReady => _ready;

  @override
  Stream<EngineEvent> get events => _eventController.stream;

  @override
  Future<void> start() async {
    if (_ready) return;

    final dir = Directory(_config.workingDirectory);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    // Write embedded worker.js
    final workerFile =
        File('${_config.workingDirectory}${Platform.pathSeparator}.worker.js');
    await workerFile.writeAsString(workerJsSource);

    // Spawn Node.js
    _readyCompleter = Completer<void>();
    try {
      _process = await Process.start(
        _config.nodeBinary,
        [workerFile.path],
        workingDirectory: _config.workingDirectory,
      );
    } catch (e) {
      throw JsRuntimeException(
        JsErrorCode.nodeNotFound,
        'Failed to start Node.js ("${_config.nodeBinary}"): $e\n'
        'Make sure Node.js is installed and available in PATH.',
      );
    }

    // Listen for JSON responses on stdout
    _stdoutSub = _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onStdoutLine);

    // Capture stderr for debugging
    _stderrSub = _process!.stderr.transform(utf8.decoder).listen((data) {
      _stderrBuffer.write(data);
      if (_stderrBuffer.length > 10000) {
        final s = _stderrBuffer.toString();
        _stderrBuffer.clear();
        _stderrBuffer.write(s.substring(s.length - 5000));
      }
    });

    // Handle process exit — auto-reconnect if enabled
    _process!.exitCode.then(_onProcessExit);

    // Wait for ready signal
    try {
      await _readyCompleter!.future.timeout(
        Duration(milliseconds: _config.readyTimeout),
        onTimeout: () {
          _process?.kill();
          throw JsRuntimeException(
            JsErrorCode.workerStartFailed,
            'Worker did not send ready signal within '
            '${_config.readyTimeout}ms',
          );
        },
      );
    } catch (e) {
      await _cleanup(rejectPending: true);
      rethrow;
    }

    _eventController.add(EngineReadyEvent());
  }

  @override
  Future<dynamic> send(Map<String, dynamic> message) {
    if (!_ready || _process == null) {
      throw const JsRuntimeException(
        JsErrorCode.workerNotReady,
        'Worker not ready. Call initialize() first.',
      );
    }

    final id = ++_nextId;
    final completer = Completer<dynamic>();
    _pending[id] = completer;

    final fullMsg = {...message, 'id': id};

    try {
      _process!.stdin.writeln(jsonEncode(fullMsg));
    } catch (e) {
      _pending.remove(id);
      throw JsBridgeException(
        JsErrorCode.protocolError,
        'Failed to write to worker stdin: $e',
      );
    }

    return completer.future.timeout(
      Duration(milliseconds: _config.requestTimeout),
      onTimeout: () {
        _pending.remove(id);
        throw JsTimeoutException(
          'Request timed out after ${_config.requestTimeout}ms '
          '(action: ${message['action']})',
        );
      },
    );
  }

  @override
  void sendFireAndForget(Map<String, dynamic> message) {
    if (!_ready || _process == null) return;
    try {
      final fullMsg = {...message, 'id': 0};
      _process!.stdin.writeln(jsonEncode(fullMsg));
    } catch (_) {
      // Best-effort — ignore errors
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

  /// Send a callback response back to the JS worker.
  void sendCallbackResponse(
    int callbackId, {
    int? invokeId,
    dynamic result,
    String? error,
  }) {
    if (!_ready || _process == null) return;
    try {
      final msg = <String, dynamic>{
        'type': 'callback_response',
        'callbackId': callbackId,
      };
      if (invokeId != null) msg['invokeId'] = invokeId;
      if (error != null) {
        msg['error'] = {'message': error};
      } else {
        msg['result'] = result;
      }
      _process!.stdin.writeln(jsonEncode(msg));
    } catch (_) {
      // best-effort
    }
  }

  @override
  Future<void> shutdown() async {
    _gcBatcher.flush();
    if (!_ready || _process == null) {
      _gcBatcher.dispose();
      return;
    }
    // Disable auto-reconnect for intentional shutdown
    _restartCount = _config.maxRestarts;
    try {
      await send({'action': 'shutdown'}).timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );
    } catch (_) {
      // Ignore — we'll force kill
    }
    _gcBatcher.dispose();
    await _cleanup(rejectPending: true);
    await _eventController.close();
  }

  // ─── Private ───────────────────────────────────────

  void _onStdoutLine(String line) {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    // Ready handshake
    if (msg['type'] == 'ready') {
      _ready = true;
      _restartCount = 0; // Reset on successful start
      if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
        _readyCompleter!.complete();
      }
      return;
    }

    // JS → Dart callback
    if (msg['type'] == 'callback') {
      final callbackId = msg['callbackId'] as int;
      final invokeId = msg['invokeId'] as int?;
      final args = msg['args'] as List? ?? [];
      onCallback?.call(callbackId, args, invokeId);
      return;
    }

    // Response matching
    final id = msg['id'];
    if (id == null || id == 0) return;
    final completer = _pending.remove(id);
    if (completer == null) return;

    if (msg.containsKey('error')) {
      final error = msg['error'] as Map<String, dynamic>;
      completer.completeError(JsBridgeException.fromWorker(error));
    } else {
      completer.complete(msg['result']);
    }
  }

  void _onProcessExit(int code) {
    _ready = false;
    final stderr = _stderrBuffer.toString().trim();
    final errorMsg = stderr.isNotEmpty
        ? 'Worker exited with code $code: $stderr'
        : 'Worker exited with code $code';
    _stderrBuffer.clear();
    _eventController.add(EngineCrashEvent(code, errorMsg));

    // Auto-reconnect if within limit
    if (_restartCount < _config.maxRestarts) {
      _restartCount++;
      _eventController.add(EngineRestartEvent(_restartCount));
      _rejectAllPending(
        'Worker crashed (code $code), restarting (attempt $_restartCount)...',
        JsErrorCode.workerCrash,
      );
      // Restart asynchronously
      _cleanup(rejectPending: false).then((_) => start());
    } else {
      _rejectAllPending(
        'Worker process exited with code $code',
        JsErrorCode.workerCrash,
      );
    }
  }

  void _rejectAllPending(String message, JsErrorCode code) {
    final error = JsBridgeException(code, message);
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
    _pending.clear();
  }

  Future<void> _cleanup({required bool rejectPending}) async {
    _ready = false;
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    if (rejectPending) {
      _rejectAllPending('Worker shutting down', JsErrorCode.workerCrash);
    }
    final proc = _process;
    _process = null;
    if (proc != null) {
      proc.kill();
      await proc.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () => -1,
      );
    }
  }
}
