/// Manages Dart callback functions that can be invoked from JavaScript.
///
/// When a Dart function is passed to JS, it gets registered here with
/// a unique integer ID. The JS side receives a `{__dart_callback__: id}`
/// marker, which creates a proxy function that sends the callback
/// invocation back to Dart.
library;

/// Tracks registered Dart callbacks for JS→Dart invocations.
class CallbackManager {
  final Map<int, Function> _callbacks = {};
  final Set<int> _oneShot = {};
  int _nextId = 0;

  /// Register a Dart function and get a unique ID.
  ///
  /// The ID is sent to JS as `{__dart_callback__: id}`.
  int register(Function callback) {
    final id = ++_nextId;
    _callbacks[id] = callback;
    return id;
  }

  /// Register a one-shot callback that auto-unregisters after first invocation.
  ///
  /// Useful for `.then()`, `.catch()`, event listeners that fire once, etc.
  int registerOneShot(Function callback) {
    final id = register(callback);
    _oneShot.add(id);
    return id;
  }

  /// Remove a registered callback.
  void unregister(int id) {
    _callbacks.remove(id);
    _oneShot.remove(id);
  }

  /// Invoke a registered callback with the given arguments.
  ///
  /// Returns the callback's return value, or `null` if not found.
  /// One-shot callbacks are automatically unregistered after invocation.
  ///
  /// If the callback doesn't accept all arguments (e.g. JS passes 3 args
  /// but Dart function only accepts 2), extra arguments are trimmed
  /// automatically.
  dynamic invoke(int id, List<dynamic> args) {
    final fn = _callbacks[id];
    if (fn == null) return null;
    final result = _applyWithArgTrimming(fn, args);
    if (_oneShot.contains(id)) {
      _callbacks.remove(id);
      _oneShot.remove(id);
    }
    return result;
  }

  /// Try Function.apply, trimming trailing args on NoSuchMethodError.
  static dynamic _applyWithArgTrimming(Function fn, List<dynamic> args) {
    for (var count = args.length; count >= 0; count--) {
      try {
        return Function.apply(fn, args.sublist(0, count));
      } on NoSuchMethodError {
        // Too many args — try with fewer
        continue;
      }
    }
    // Fallback: try with no args
    return Function.apply(fn, []);
  }

  /// Check if a callback ID is registered.
  bool has(int id) => _callbacks.containsKey(id);

  /// Whether a callback is one-shot.
  bool isOneShot(int id) => _oneShot.contains(id);

  /// Remove all registered callbacks.
  void clear() {
    _callbacks.clear();
    _oneShot.clear();
  }

  /// Number of currently registered callbacks.
  int get length => _callbacks.length;
}
