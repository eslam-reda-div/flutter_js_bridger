import 'package:flutter_js_bridger/flutter_js_bridger.dart';
import 'package:test/test.dart';

/// Tests for CallbackManager — registration, invocation, one-shot, cleanup.
void main() {
  late CallbackManager cm;

  setUp(() {
    cm = CallbackManager();
  });

  group('CallbackManager', () {
    test('register and invoke callback', () {
      final id = cm.register((int a, int b) => a + b);
      expect(cm.has(id), isTrue);
      expect(cm.length, equals(1));

      final result = cm.invoke(id, [3, 4]);
      expect(result, equals(7));
    });

    test('register multiple callbacks', () {
      final id1 = cm.register(() => 'first');
      final id2 = cm.register(() => 'second');
      expect(id1, isNot(equals(id2)));
      expect(cm.length, equals(2));

      expect(cm.invoke(id1, []), equals('first'));
      expect(cm.invoke(id2, []), equals('second'));
    });

    test('unregister removes callback', () {
      final id = cm.register(() => 'test');
      expect(cm.has(id), isTrue);

      cm.unregister(id);
      expect(cm.has(id), isFalse);
      expect(cm.length, equals(0));
    });

    test('invoke unknown id returns null', () {
      expect(cm.invoke(999, []), isNull);
    });

    test('clear removes all callbacks', () {
      cm.register(() => 'a');
      cm.register(() => 'b');
      cm.register(() => 'c');
      expect(cm.length, equals(3));

      cm.clear();
      expect(cm.length, equals(0));
    });

    test('one-shot callback auto-unregisters after invocation', () {
      final id = cm.registerOneShot((int x) => x * 2);
      expect(cm.has(id), isTrue);
      expect(cm.isOneShot(id), isTrue);

      // First invocation works
      final result = cm.invoke(id, [21]);
      expect(result, equals(42));

      // Now it should be auto-unregistered
      expect(cm.has(id), isFalse);
      expect(cm.isOneShot(id), isFalse);
      expect(cm.length, equals(0));
    });

    test('one-shot does not affect regular callbacks', () {
      final regularId = cm.register(() => 'persistent');
      final oneShotId = cm.registerOneShot(() => 'once');

      // Invoke one-shot
      cm.invoke(oneShotId, []);
      expect(cm.has(oneShotId), isFalse);

      // Regular should still be there
      expect(cm.has(regularId), isTrue);
      expect(cm.invoke(regularId, []), equals('persistent'));
    });

    test('unregister one-shot before invocation', () {
      final id = cm.registerOneShot(() => 'once');
      expect(cm.has(id), isTrue);

      cm.unregister(id);
      expect(cm.has(id), isFalse);
      expect(cm.isOneShot(id), isFalse);
    });

    test('clear removes one-shot tracking', () {
      cm.registerOneShot(() => 'a');
      cm.registerOneShot(() => 'b');
      expect(cm.length, equals(2));

      cm.clear();
      expect(cm.length, equals(0));
    });

    test('callback with no args', () {
      final id = cm.register(() => 'no-args');
      expect(cm.invoke(id, []), equals('no-args'));
    });

    test('callback returning null', () {
      final id = cm.register(() => null);
      expect(cm.invoke(id, []), isNull);
      // Should still be registered (not one-shot)
      expect(cm.has(id), isTrue);
    });

    test('IDs are always unique and incrementing', () {
      final ids = <int>[];
      for (var i = 0; i < 100; i++) {
        ids.add(cm.register(() => i));
      }
      expect(ids.toSet().length, equals(100));
      // Each ID should be greater than the last
      for (var i = 1; i < ids.length; i++) {
        expect(ids[i], greaterThan(ids[i - 1]));
      }
    });
  });
}
