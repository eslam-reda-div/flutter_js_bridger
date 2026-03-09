/// Proxy objects for transparently interacting with JavaScript values.
///
/// [JsObject] wraps a JS object reference and intercepts all property
/// access and method calls via [noSuchMethod], forwarding them to the
/// Node.js worker over IPC.
///
/// [JsChain] accumulates a property path for lazy resolution. It
/// implements [Future<dynamic>] so it can be awaited (resolving the
/// property) or chained further (adding to the path). This enables
/// natural syntax like: `await np.random.randint(0, 10)`.
library;

import 'dart:async';

import 'callback_manager.dart';
import 'engines/engine_interface.dart';
import 'serializer.dart';

/// Reference disposer attached to [Finalizer] for automatic cleanup.
class _RefDisposer {
  final JsEngine engine;
  final int refId;
  _RefDisposer(this.engine, this.refId);

  void dispose() {
    engine.scheduleGc(refId);
  }
}

/// Weak reference cleanup — releases JS references when Dart objects
/// are garbage collected.
final Finalizer<_RefDisposer> _pointerFinalizer =
    Finalizer<_RefDisposer>((d) => d.dispose());

// ═══════════════════════════════════════════════════════
//  JsObject — Proxied JS object reference
// ═══════════════════════════════════════════════════════

/// A Dart proxy for a JavaScript object living in the Node.js worker.
///
/// All property access and method calls are transparently forwarded
/// to the JS runtime. Use `dynamic` typing for seamless access:
///
/// ```dart
/// dynamic lodash = await js.require('lodash');
/// var chunks = await lodash.chunk([1, 2, 3, 4, 5], 2);
/// ```
///
/// Property access returns a [JsChain] that can be:
/// - **awaited** to get the property value
/// - **chained further** for nested access
/// - **called** as a method
class JsObject {
  final JsEngine _engine;
  final int _refId;
  final String _jsType;
  final CallbackManager? _callbacks;

  JsObject._(this._engine, this._refId, this._jsType, this._callbacks) {
    _pointerFinalizer.attach(
      this,
      _RefDisposer(_engine, _refId),
      detach: this,
    );
  }

  /// Create a JsObject (used internally by the serializer).
  factory JsObject.create(
    JsEngine engine,
    int refId, {
    String jsType = 'object',
    CallbackManager? callbacks,
  }) {
    return JsObject._(engine, refId, jsType, callbacks);
  }

  /// The internal reference ID (for serialization).
  int get refId => _refId;

  /// The JS type name of this object.
  String get jsType => _jsType;

  // ─── Explicit API ($-prefixed) ─────────────────────

  /// Get a property by name.
  Future<dynamic> $get(String prop) async {
    final result = await _engine.send({
      'action': 'get',
      'ref': _refId,
      'prop': prop,
    });
    return wrapResult(_engine, result, callbacks: _callbacks);
  }

  /// Set a property by name.
  Future<void> $set(String prop, dynamic value) async {
    await _engine.send({
      'action': 'set',
      'ref': _refId,
      'prop': prop,
      'value': serializeArg(value, callbacks: _callbacks),
    });
  }

  /// Call a method by name with positional arguments.
  Future<dynamic> $call(String method, [List<dynamic> args = const []]) async {
    final result = await _engine.send({
      'action': 'call',
      'ref': _refId,
      'method': method,
      'args': args.map((a) => serializeArg(a, callbacks: _callbacks)).toList(),
    });
    return wrapResult(_engine, result, callbacks: _callbacks);
  }

  /// Invoke this object as a function.
  Future<dynamic> $invoke([List<dynamic> args = const []]) async {
    final result = await _engine.send({
      'action': 'invoke',
      'ref': _refId,
      'args': args.map((a) => serializeArg(a, callbacks: _callbacks)).toList(),
    });
    return wrapResult(_engine, result, callbacks: _callbacks);
  }

  /// Construct a new instance (call with `new`).
  Future<dynamic> $new([List<dynamic> args = const []]) async {
    final result = await _engine.send({
      'action': 'construct',
      'ref': _refId,
      'args': args.map((a) => serializeArg(a, callbacks: _callbacks)).toList(),
    });
    return wrapResult(_engine, result, callbacks: _callbacks);
  }

  /// Get the keys of this object.
  Future<List<String>> $keys() async {
    final result = await _engine.send({
      'action': 'keys',
      'ref': _refId,
    });
    return (result as List).cast<String>();
  }

  /// Get the typeof this reference in JS.
  Future<String> $typeof() async {
    final result = await _engine.send({
      'action': 'typeof_ref',
      'ref': _refId,
    });
    return result as String;
  }

  /// Check if this object has a property.
  Future<bool> $has(String prop) async {
    final result = await _engine.send({
      'action': 'has',
      'ref': _refId,
      'prop': prop,
    });
    return result as bool;
  }

  /// Get the length/size of this object.
  Future<int> $length() async {
    final result = await _engine.send({
      'action': 'length',
      'ref': _refId,
    });
    return result as int;
  }

  /// Convert to a Dart List (for iterable JS objects).
  Future<List<dynamic>> $toList() async {
    final result = await _engine.send({
      'action': 'to_list',
      'ref': _refId,
    });
    return (result as List)
        .map((item) => wrapResult(_engine, item, callbacks: _callbacks))
        .toList();
  }

  /// Convert to a JSON string.
  Future<String> $toJson() async {
    final result = await _engine.send({
      'action': 'to_json_string',
      'ref': _refId,
    });
    return result as String;
  }

  /// Explicitly release this reference in the JS worker.
  Future<void> dispose() async {
    _pointerFinalizer.detach(this);
    await _engine.send({
      'action': 'delete_ref',
      'ref': _refId,
    });
  }

  // ─── Dynamic dispatch via noSuchMethod ─────────────

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = symbolToString(invocation.memberName);

    if (invocation.isGetter) {
      // Property access → return JsChain for lazy resolution
      return JsChain._(_engine, _refId, [name], _callbacks);
    }

    if (invocation.isMethod) {
      if (name == 'call') {
        // obj() → invoke as function
        return _engine.send({
          'action': 'invoke',
          'ref': _refId,
          'args': invocation.positionalArguments
              .map((a) => serializeArg(a, callbacks: _callbacks))
              .toList(),
        }).then((result) => wrapResult(_engine, result, callbacks: _callbacks));
      }
      // obj.method(args) → call method
      return _engine.send({
        'action': 'call',
        'ref': _refId,
        'method': name,
        'args': invocation.positionalArguments
            .map((a) => serializeArg(a, callbacks: _callbacks))
            .toList(),
      }).then((result) => wrapResult(_engine, result, callbacks: _callbacks));
    }

    if (invocation.isSetter) {
      final propName =
          name.endsWith('=') ? name.substring(0, name.length - 1) : name;
      // Fire-and-forget set
      _engine.sendFireAndForget({
        'action': 'set',
        'ref': _refId,
        'prop': propName,
        'value': serializeArg(invocation.positionalArguments.first,
            callbacks: _callbacks),
      });
      return null;
    }

    return super.noSuchMethod(invocation);
  }

  @override
  String toString() => 'JsObject(ref: $_refId, type: $_jsType)';

  @override
  int get hashCode => _refId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is JsObject && other._refId == _refId);
}

// ═══════════════════════════════════════════════════════
//  JsChain — Lazy property path accumulator
// ═══════════════════════════════════════════════════════

/// A lazy chaining proxy that accumulates a property access path.
///
/// Implements [Future<dynamic>] so it can be awaited to resolve
/// the property, or chained further for deeper access.
///
/// ```dart
/// // Single step (await resolves the property):
/// var version = await lodash.VERSION;
///
/// // Multi-step chain (only the final call triggers IPC):
/// var result = await np.random.randint(0, 10);
/// ```
class JsChain implements Future<dynamic> {
  final JsEngine _engine;
  final int _refId;
  final List<String> _path;
  final CallbackManager? _callbacks;

  JsChain._(this._engine, this._refId, this._path, this._callbacks);

  // Lazy future — only created when awaited
  Future<dynamic>? _cachedFuture;

  Future<dynamic> get _future {
    return _cachedFuture ??= _engine
        .send({'action': 'get_path', 'ref': _refId, 'path': _path}).then(
            (result) => wrapResult(_engine, result, callbacks: _callbacks));
  }

  // ─── Future<dynamic> implementation (delegation) ───

  @override
  Stream<dynamic> asStream() => _future.asStream();

  @override
  Future<dynamic> catchError(
    Function onError, {
    bool Function(Object error)? test,
  }) =>
      _future.catchError(onError, test: test);

  @override
  Future<R> then<R>(
    FutureOr<R> Function(dynamic value) onValue, {
    Function? onError,
  }) =>
      _future.then(onValue, onError: onError);

  @override
  Future<dynamic> whenComplete(FutureOr<void> Function() action) =>
      _future.whenComplete(action);

  @override
  Future<dynamic> timeout(
    Duration timeLimit, {
    FutureOr<dynamic> Function()? onTimeout,
  }) =>
      _future.timeout(timeLimit, onTimeout: onTimeout);

  // ─── Dynamic chaining via noSuchMethod ─────────────

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = symbolToString(invocation.memberName);

    if (invocation.isGetter) {
      // Further chaining — no IPC call yet
      return JsChain._(_engine, _refId, [..._path, name], _callbacks);
    }

    if (invocation.isMethod) {
      final args = invocation.positionalArguments;
      if (name == 'call') {
        // chain() → invoke the resolved path object as a function
        return _engine.send({
          'action': 'invoke_path',
          'ref': _refId,
          'path': _path,
          'args':
              args.map((a) => serializeArg(a, callbacks: _callbacks)).toList(),
        }).then((result) => wrapResult(_engine, result, callbacks: _callbacks));
      }
      // chain.method(args) → call method with full path
      return _engine.send({
        'action': 'call_path',
        'ref': _refId,
        'path': [..._path, name],
        'args':
            args.map((a) => serializeArg(a, callbacks: _callbacks)).toList(),
      }).then((result) => wrapResult(_engine, result, callbacks: _callbacks));
    }

    return super.noSuchMethod(invocation);
  }

  @override
  String toString() => 'JsChain(ref: $_refId, path: ${_path.join(".")})';
}
