import 'package:flutter_js_bridger/flutter_js_bridger.dart';
import 'package:flutter_js_bridger/src/serializer.dart';
import 'package:test/test.dart';

/// Tests for serializer — serializeArg and wrapResult.
void main() {
  group('serializeArg', () {
    test('primitives pass through', () {
      expect(serializeArg(null), isNull);
      expect(serializeArg(true), isTrue);
      expect(serializeArg(false), isFalse);
      expect(serializeArg(42), equals(42));
      expect(serializeArg(3.14), equals(3.14));
      expect(serializeArg('hello'), equals('hello'));
    });

    test('lists are recursively serialized', () {
      final result = serializeArg([1, 'two', true, null]);
      expect(result, equals([1, 'two', true, null]));
    });

    test('maps are recursively serialized', () {
      final result = serializeArg({'a': 1, 'b': 'two'});
      expect(result, equals({'a': 1, 'b': 'two'}));
    });

    test('nested structures', () {
      final result = serializeArg({
        'list': [1, 2, 3],
        'nested': {'inner': true},
      });
      expect(
          result,
          equals({
            'list': [1, 2, 3],
            'nested': {'inner': true},
          }));
    });

    test('unknown type falls back to toString', () {
      final result = serializeArg(DateTime(2026, 1, 1));
      expect(result, isA<String>());
    });

    test('Function without CallbackManager falls back to toString', () {
      final result = serializeArg(() => 42);
      expect(result, isA<String>());
    });

    test('Function with CallbackManager registers callback', () {
      final cm = CallbackManager();
      final fn = (int x) => x + 1;

      final result = serializeArg(fn, callbacks: cm);
      expect(result, isA<Map<String, dynamic>>());
      expect(result['__dart_callback__'], isA<int>());
      expect(cm.length, equals(1));

      // Can invoke the registered callback
      final cbId = result['__dart_callback__'] as int;
      expect(cm.invoke(cbId, [41]), equals(42));
    });

    test('nested Function in list gets registered', () {
      final cm = CallbackManager();
      final fn = () => 'callback';

      final result = serializeArg([1, fn, 'three'], callbacks: cm);
      expect(result[0], equals(1));
      expect(result[1], isA<Map<String, dynamic>>());
      expect(result[1]['__dart_callback__'], isA<int>());
      expect(result[2], equals('three'));
      expect(cm.length, equals(1));
    });

    test('nested Function in map gets registered', () {
      final cm = CallbackManager();
      final fn = () => 'callback';

      final result = serializeArg({'handler': fn, 'value': 42}, callbacks: cm);
      expect(result['handler'], isA<Map<String, dynamic>>());
      expect(result['handler']['__dart_callback__'], isA<int>());
      expect(result['value'], equals(42));
      expect(cm.length, equals(1));
    });
  });

  group('symbolToString', () {
    test('extracts name from Symbol', () {
      expect(symbolToString(#hello), equals('hello'));
      expect(symbolToString(#camelCase), equals('camelCase'));
      expect(symbolToString(#snake_case), equals('snake_case'));
    });
  });
}
