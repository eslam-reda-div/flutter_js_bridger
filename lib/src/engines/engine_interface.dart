/// Abstract JS engine interface and shared utilities.
///
/// All platform engines (Node.js, Web, JSC, QuickJS) implement [JsEngine].
/// This provides a uniform API for the bridge regardless of platform.
library;

import 'dart:async';

/// Configuration for creating a JS engine.
class EngineConfig {
  /// Working directory where node_modules and worker files live.
  final String workingDirectory;

  /// Timeout per IPC request in milliseconds.
  final int requestTimeout;

  /// Timeout for the engine to become ready in milliseconds.
  final int readyTimeout;

  /// Path to the Node.js binary (desktop only).
  final String nodeBinary;

  /// Path to pre-bundled JS file (for embedded engines: web/mobile).
  final String? bundlePath;

  /// Maximum number of auto-restart attempts on crash.
  final int maxRestarts;

  const EngineConfig({
    required this.workingDirectory,
    this.requestTimeout = 60000,
    this.readyTimeout = 30000,
    this.nodeBinary = 'node',
    this.bundlePath,
    this.maxRestarts = 3,
  });
}

/// Abstract interface every JS engine must implement.
///
/// Engines handle the low-level communication with a JavaScript runtime.
/// The [JsBridge] class uses this interface and doesn't care whether
/// JS runs in a subprocess, via FFI, or in a web worker.
abstract class JsEngine {
  /// Whether the engine is running and ready for requests.
  bool get isReady;

  /// Start the JS runtime and wait until it's ready.
  Future<void> start();

  /// Send a request and await the response.
  Future<dynamic> send(Map<String, dynamic> message);

  /// Send a message without waiting for a response.
  ///
  /// Used for GC cleanup and fire-and-forget operations.
  void sendFireAndForget(Map<String, dynamic> message);

  /// Send multiple requests in a single round-trip.
  ///
  /// Returns a list of results (or errors) in the same order.
  /// Much more efficient than sending requests individually.
  Future<List<dynamic>> sendBatch(List<Map<String, dynamic>> messages);

  /// Schedule a JS reference for batch garbage collection.
  ///
  /// References are queued and flushed periodically rather than
  /// sending one IPC message per GC'd object.
  void scheduleGc(int refId);

  /// Immediately flush all queued GC references.
  void flushGc();

  /// Gracefully shut down the JS runtime.
  Future<void> shutdown();

  /// Stream of engine lifecycle events (crashes, restarts).
  Stream<EngineEvent> get events;
}

/// Events emitted by the engine for lifecycle monitoring.
sealed class EngineEvent {}

/// Emitted when the engine process crashes.
class EngineCrashEvent extends EngineEvent {
  final int exitCode;
  final String message;
  EngineCrashEvent(this.exitCode, this.message);
}

/// Emitted when the engine successfully restarts after a crash.
class EngineRestartEvent extends EngineEvent {
  final int attempt;
  EngineRestartEvent(this.attempt);
}

/// Emitted when the engine is ready for requests.
class EngineReadyEvent extends EngineEvent {}

/// Helper that batches GC reference deletions.
///
/// Instead of sending one `delete_ref` message per garbage-collected
/// JsObject, references are queued and flushed as a single `gc` batch.
class GcBatcher {
  final void Function(Map<String, dynamic>) _sendFn;
  final List<int> _queue = [];
  Timer? _timer;

  /// Flush after this many refs accumulate.
  static const int batchThreshold = 100;

  /// Flush after this delay if threshold not reached.
  static const Duration flushDelay = Duration(milliseconds: 50);

  GcBatcher(this._sendFn);

  /// Queue a reference ID for batch deletion.
  void schedule(int refId) {
    _queue.add(refId);
    if (_queue.length >= batchThreshold) {
      flush();
    } else {
      _timer ??= Timer(flushDelay, flush);
    }
  }

  /// Send all queued references to the JS runtime for deletion.
  void flush() {
    _timer?.cancel();
    _timer = null;
    if (_queue.isEmpty) return;
    _sendFn({'action': 'gc', 'refs': List<int>.of(_queue)});
    _queue.clear();
  }

  /// Cancel pending timer and clear the queue.
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _queue.clear();
  }
}
