import 'dart:io';

import 'package:flutter_js_bridger/flutter_js_bridger.dart';
import 'package:test/test.dart';

/// Integration tests that exercise the full bridge with a real Node.js engine.
///
/// These complement the main test suite by testing:
/// - NodeEngine lifecycle directly
/// - Callback round-trips (Dart→JS→Dart)
/// - Batch operations
/// - Engine events and error recovery
/// - Concurrent operations
///
/// Requires Node.js in PATH.
void main() {
  late JsBridge js;
  final workDir =
      '${Directory.current.path}${Platform.pathSeparator}.test_integration';

  setUpAll(() async {
    js = JsBridge(JsBridgeConfig(
      workingDirectory: workDir,
      manifestPath: '',
    ));
    await js.initialize();
  });

  tearDownAll(() async {
    await js.dispose();
    await Future.delayed(const Duration(milliseconds: 500));
    final dir = Directory(workDir);
    if (dir.existsSync()) {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  // ═══════════════════════════════════════════════════════
  //  Engine lifecycle
  // ═══════════════════════════════════════════════════════

  group('Engine lifecycle', () {
    test('engine is NodeEngine on desktop', () {
      expect(js.engine, isA<NodeEngine>());
    });

    test('engine is ready after init', () {
      expect(js.engine.isReady, isTrue);
    });

    test('events stream is available', () {
      expect(js.events, isA<Stream<EngineEvent>>());
    });

    test('ping succeeds', () async {
      expect(await js.ping(), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════
  //  Callback round-trips
  // ═══════════════════════════════════════════════════════

  group('Callbacks', () {
    test('register and check callback exists', () {
      final id = js.registerCallback((List<dynamic> args) => args[0]);
      expect(id, isA<int>());
      expect(id, greaterThan(0));
      js.unregisterCallback(id);
    });

    test('register one-shot callback', () {
      final id = js.registerOneShotCallback(
        (List<dynamic> args) => 'once',
      );
      expect(id, isA<int>());
      expect(js.callbacks.has(id), isTrue);
      expect(js.callbacks.isOneShot(id), isTrue);
      js.unregisterCallback(id);
    });

    test('callback manager clears on dispose', () async {
      final tempBridge = JsBridge(JsBridgeConfig(
        workingDirectory: workDir,
        manifestPath: '',
      ));
      await tempBridge.initialize();

      tempBridge.registerCallback((_) => 'test');
      tempBridge.registerCallback((_) => 'test2');
      expect(tempBridge.callbacks.length, equals(2));

      await tempBridge.dispose();
      expect(tempBridge.callbacks.length, equals(0));
    });
  });

  // ═══════════════════════════════════════════════════════
  //  Batch operations
  // ═══════════════════════════════════════════════════════

  group('Batch operations', () {
    test('batch eval returns correct results', () async {
      final results = await js.batch([
        {'action': 'eval', 'code': '1 + 1'},
        {'action': 'eval', 'code': '2 * 3'},
        {'action': 'eval', 'code': '"hello".length'},
      ]);
      expect(results, equals([2, 6, 5]));
    });

    test('batch with mixed actions', () async {
      final results = await js.batch([
        {'action': 'eval', 'code': 'Math.PI'},
        {'action': 'eval', 'code': 'true'},
        {'action': 'eval', 'code': 'null'},
        {'action': 'ping'},
      ]);
      expect(results[0], closeTo(3.14159, 0.001));
      expect(results[1], isTrue);
      expect(results[2], isNull);
      expect(results[3], equals('pong'));
    });

    test('empty batch returns empty list', () async {
      final results = await js.batch([]);
      expect(results, isEmpty);
    });

    test('single-item batch works', () async {
      final results = await js.batch([
        {'action': 'eval', 'code': '42'},
      ]);
      expect(results, equals([42]));
    });

    test('large batch', () async {
      final requests = List.generate(
        50,
        (i) => {'action': 'eval', 'code': '$i * 2'},
      );
      final results = await js.batch(requests);
      expect(results.length, equals(50));
      for (var i = 0; i < 50; i++) {
        expect(results[i], equals(i * 2));
      }
    });
  });

  // ═══════════════════════════════════════════════════════
  //  Concurrent operations
  // ═══════════════════════════════════════════════════════

  group('Concurrent operations', () {
    test('parallel evals complete correctly', () async {
      final futures = List.generate(
        10,
        (i) => js.eval('$i * $i'),
      );
      final results = await Future.wait(futures);
      for (var i = 0; i < 10; i++) {
        expect(results[i], equals(i * i));
      }
    });

    test('parallel requires use cache', () async {
      final futures = List.generate(5, (_) => js.require('path'));
      final results = await Future.wait(futures);
      // All should return the same cached JsObject
      for (final r in results) {
        expect(r, isA<JsObject>());
      }
    });

    test('mixed concurrent operations', () async {
      final results = await Future.wait([
        js.eval('1 + 1'),
        js.require('path'),
        js.eval('"hello".toUpperCase()'),
        js.ping(),
        js.eval('[1,2,3].length'),
      ]);
      expect(results[0], equals(2));
      expect(results[1], isA<JsObject>());
      expect(results[2], equals('HELLO'));
      expect(results[3], isTrue);
      expect(results[4], equals(3));
    });
  });

  // ═══════════════════════════════════════════════════════
  //  Error recovery
  // ═══════════════════════════════════════════════════════

  group('Error recovery', () {
    test('engine recovers after eval error', () async {
      // Cause an error
      try {
        await js.eval('throw new Error("test error")');
      } catch (_) {}

      // Should still work
      final result = await js.eval('42');
      expect(result, equals(42));
    });

    test('engine recovers after require error', () async {
      try {
        await js.require('nonexistent-package-xyz-12345');
      } catch (_) {}

      // Should still work
      final result = await js.eval('"recovered"');
      expect(result, equals('recovered'));
    });

    test('multiple errors then recovery', () async {
      for (var i = 0; i < 5; i++) {
        try {
          await js.eval('throw new Error("error $i")');
        } catch (_) {}
      }

      expect(await js.ping(), isTrue);
      expect(await js.eval('100'), equals(100));
    });
  });

  // ═══════════════════════════════════════════════════════
  //  Advanced JS features
  // ═══════════════════════════════════════════════════════

  group('Advanced JS features', () {
    test('async/await in eval', () async {
      final result = await js.eval('''
        (async () => {
          const val = await Promise.resolve(42);
          return val * 2;
        })()
      ''');
      expect(result, equals(84));
    });

    test('closures work across calls', () async {
      await js.eval('''
        globalThis.__counter = 0;
        globalThis.__increment = () => ++globalThis.__counter;
      ''');

      expect(await js.eval('__increment()'), equals(1));
      expect(await js.eval('__increment()'), equals(2));
      expect(await js.eval('__increment()'), equals(3));
      expect(await js.eval('__counter'), equals(3));
    });

    test('typed arrays', () async {
      final result = await js.eval('''
        Array.from(new Uint8Array([1, 2, 3, 4, 5]))
      ''');
      expect(result, equals([1, 2, 3, 4, 5]));
    });

    test('template literals', () async {
      final result = await js.eval('''
        const name = "World";
        `Hello, \${name}!`
      ''');
      expect(result, equals('Hello, World!'));
    });

    test('destructuring', () async {
      final result = await js.eval('''
        const [a, b, ...rest] = [1, 2, 3, 4, 5];
        rest
      ''');
      expect(result, equals([3, 4, 5]));
    });

    test('Map and Set interop', () async {
      final dynamic m = await js.eval('new Map([["a", 1], ["b", 2]])');
      expect(await m.get('a'), equals(1));
      expect(await m.size, equals(2));

      final dynamic s = await js.eval('new Set([1, 1, 2, 2, 3])');
      expect(await s.size, equals(3));
      expect(await s.has(2), isTrue);
    });

    test('Error objects', () async {
      expect(
        () => js.eval('throw new TypeError("test type error")'),
        throwsA(isA<JsBridgeException>()),
      );
    });

    test('JSON round-trip', () async {
      final result = await js.eval('''
        JSON.parse('{"name":"test","values":[1,2,3],"nested":{"a":true}}')
      ''');
      // Just verify it comes back as JsObject
      expect(result, isA<JsObject>());
    });
  });

  // ═══════════════════════════════════════════════════════
  //  JsObject deep operations
  // ═══════════════════════════════════════════════════════

  group('JsObject deep operations', () {
    test('pass JsObject as argument to method', () async {
      final dynamic obj = await js.eval('({data: [1, 2, 3]})');
      final dynamic fn =
          await js.eval('(function(o) { return o.data.length; })');
      final result = await fn(obj);
      expect(result, equals(3));
    });

    test('chain of method calls', () async {
      // Create an object with a method that returns a value
      final dynamic obj = await js.eval('({double: (x) => x * 2})');
      final result = await obj.double(21);
      expect(result, equals(42));
    });

    test('property set and get', () async {
      final obj = await js.eval('({})') as JsObject;
      await obj.$set('name', 'flutter');
      final name = await obj.$get('name');
      expect(name, equals('flutter'));
    });

    test('dispose releases reference', () async {
      final dynamic obj = await js.eval('({value: 123})') as JsObject;
      await obj.dispose();
      // After dispose, operations on this ref should fail
      expect(
        () async => await obj.$get('value'),
        throwsA(anything),
      );
    });

    test('nested object creation and access', () async {
      await js.eval('''
        globalThis.__testObj = {
          level1: {
            level2: {
              level3: {
                value: "deep"
              }
            }
          }
        };
      ''');
      final dynamic obj = await js.eval('__testObj');
      final value = await obj.level1.level2.level3.value;
      expect(value, equals('deep'));
    });
  });

  // ═══════════════════════════════════════════════════════
  //  Separate bridge instances
  // ═══════════════════════════════════════════════════════

  group('Multiple bridge instances', () {
    test('two bridges run independently', () async {
      final js2 = JsBridge(JsBridgeConfig(
        workingDirectory:
            '${Directory.current.path}${Platform.pathSeparator}.test_integration_2',
        manifestPath: '',
      ));
      await js2.initialize();

      // Set different state in each
      await js.eval('globalThis.__bridgeId = 1');
      await js2.eval('globalThis.__bridgeId = 2');

      // Verify they're independent
      expect(await js.eval('__bridgeId'), equals(1));
      expect(await js2.eval('__bridgeId'), equals(2));

      await js2.dispose();

      // Cleanup
      await Future.delayed(const Duration(milliseconds: 300));
      final dir2 = Directory(
          '${Directory.current.path}${Platform.pathSeparator}.test_integration_2');
      if (dir2.existsSync()) {
        try {
          dir2.deleteSync(recursive: true);
        } catch (_) {}
      }
    });
  });
}
