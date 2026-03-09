/// Serialization utilities for converting between Dart and JS values.
///
/// Handles:
/// - Dart → JS: converts JsObject references to `{__ref__: id}` markers
/// - JS → Dart: converts `{__ref__: id}` markers back to JsObject proxies
/// - Symbol → String conversion for noSuchMethod interception
library;

import 'callback_manager.dart';
import 'engines/engine_interface.dart';
import 'js_object.dart';

/// Convert a Symbol to its string name.
///
/// Dart's Symbol.toString() returns `Symbol("name")`, so we extract the name.
String symbolToString(Symbol symbol) {
  final s = symbol.toString();
  // Symbol("name") → name
  return s.substring(8, s.length - 2);
}

/// Serialize a Dart value for sending to the JS worker.
///
/// - Primitives pass through unchanged
/// - [JsObject] instances serialize to `{__ref__: refId}`
/// - [Function] instances serialize to `{__dart_callback__: id}` if
///   a [CallbackManager] is provided
/// - Lists and Maps are recursively serialized
dynamic serializeArg(dynamic value, {CallbackManager? callbacks}) {
  if (value == null) return null;
  if (value is bool || value is num || value is String) return value;
  if (value is JsObject) return {'__ref__': value.refId};
  if (value is Function && callbacks != null) {
    final id = callbacks.register(value);
    return {'__dart_callback__': id};
  }
  if (value is List) {
    return value.map((v) => serializeArg(v, callbacks: callbacks)).toList();
  }
  if (value is Map) {
    return value.map(
      (k, v) => MapEntry(k.toString(), serializeArg(v, callbacks: callbacks)),
    );
  }
  return value.toString();
}

/// Wrap a raw result from the JS worker into appropriate Dart types.
///
/// - `{__ref__: id}` maps become [JsObject] proxies
/// - Lists are recursively wrapped
/// - Plain maps are recursively wrapped
/// - Primitives pass through unchanged
dynamic wrapResult(JsEngine engine, dynamic value,
    {CallbackManager? callbacks}) {
  if (value == null) return null;
  if (value is bool || value is num || value is String) return value;

  if (value is List) {
    return value
        .map((item) => wrapResult(engine, item, callbacks: callbacks))
        .toList();
  }

  if (value is Map) {
    // Check for JS object reference marker
    if (value.containsKey('__ref__')) {
      final refId = value['__ref__'] as int;
      final type = value['__type__'] as String? ?? 'object';
      return JsObject.create(engine, refId, jsType: type, callbacks: callbacks);
    }
    // Regular map — recursively wrap nested values
    return Map<String, dynamic>.fromEntries(
      value.entries.map(
        (e) => MapEntry(e.key.toString(),
            wrapResult(engine, e.value, callbacks: callbacks)),
      ),
    );
  }

  return value;
}
