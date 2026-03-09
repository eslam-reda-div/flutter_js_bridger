import 'dart:convert';

import 'package:flutter_js_bridger/flutter_js_bridger.dart';
import 'package:test/test.dart';

import '../helpers/npm_test_helper.dart';

/// Tests for Ramda — functional programming utility library.
///
/// Uses Dart-native proxy API for all Ramda operations:
///   - Direct calls: `R.add(2, 3)`, `R.multiply(3, 7)`, `R.uniq(list)`
///   - Object manipulation: `R.pick(keys, obj)`, `R.mergeAll(list)`, `R.path()`
///   - For higher-order functions (map, filter, sort, pipe, groupBy, curry),
///     JS lambda functions are created via eval and passed as JsObject refs
///     to Ramda's proxy calls — since the bridge's callback system is
///     fire-and-forget (async IPC), synchronous return-value callbacks
///     cannot be expressed as Dart closures for Ramda.
void main() {
  late JsBridge js;
  late dynamic R;

  setUpAll(() async {
    js = await createNpmTestBridge();
    await ensureInstalled(js, 'ramda');
    R = await js.require('ramda');
  });

  tearDownAll(() async {
    await js.dispose();
  });

  /// Helper: create a JS function via createFunction — no eval.
  Future<dynamic> jsFunc(JsBridge js, String body,
      {List<String> params = const []}) async {
    return await js.createFunction(params: params, body: body);
  }

  group('Ramda — Dart-native proxy API', () {
    test('require ramda — returns object with functions', () async {
      expect(R, isA<JsObject>());
      final hasAdd = await R.$has('add');
      final hasMap = await R.$has('map');
      final hasPipe = await R.$has('pipe');
      expect(hasAdd, isTrue);
      expect(hasMap, isTrue);
      expect(hasPipe, isTrue);
    });

    test('R.add — basic arithmetic', () async {
      final result = await R.add(2, 3);
      expect(result, equals(5));
    });

    test('R.multiply', () async {
      final result = await R.multiply(3, 7);
      expect(result, equals(21));
    });

    test('R.map — transform array with JS function', () async {
      final double = await jsFunc(js, 'return x * 2', params: ['x']);
      final result = await R.map(double, [1, 2, 3, 4, 5]);
      expect(result, equals([2, 4, 6, 8, 10]));
    });

    test('R.filter — filter array with JS function', () async {
      final gt3 = await jsFunc(js, 'return x > 3', params: ['x']);
      final result = await R.filter(gt3, [1, 2, 3, 4, 5, 6]);
      expect(result, equals([4, 5, 6]));
    });

    test('R.pipe — compose functions', () async {
      final filterEven = await jsFunc(js, 'return x % 2 === 0', params: ['x']);
      final times10 = await jsFunc(js, 'return x * 10', params: ['x']);
      dynamic pFilterEven = await R.filter(filterEven);
      dynamic pMapTimes10 = await R.map(times10);
      dynamic rSum = await R.$get('sum');
      dynamic transform = await R.pipe(pFilterEven, pMapTimes10, rSum);
      final result = await transform([1, 2, 3, 4, 5, 6]);
      expect(result, equals(120)); // (2+4+6)*10 = 120
    });

    test('R.sort — sort array with JS comparator', () async {
      final cmp = await jsFunc(js, 'return a - b', params: ['a', 'b']);
      final result = await R.sort(cmp, [5, 3, 1, 4, 2]);
      expect(result, equals([1, 2, 3, 4, 5]));
    });

    test('R.uniq — unique values', () async {
      final result = await R.uniq([1, 1, 2, 2, 3, 3]);
      expect(result, equals([1, 2, 3]));
    });

    test('R.flatten — flatten nested arrays', () async {
      final result = await R.flatten([
        1,
        [2, 3],
        [
          4,
          [5, 6]
        ]
      ]);
      expect(result, equals([1, 2, 3, 4, 5, 6]));
    });

    test('R.pick — select object properties', () async {
      dynamic result =
          await R.pick(['a', 'c'], {'a': 1, 'b': 2, 'c': 3, 'd': 4});
      final a = await result.a;
      final c = await result.c;
      expect(a, equals(1));
      expect(c, equals(3));
    });

    test('R.mergeAll — merge multiple objects', () async {
      dynamic result = await R.mergeAll([
        {'a': 1},
        {'b': 2},
        {'c': 3},
      ]);
      final json = await result.$toJson();
      final data = jsonDecode(json as String);
      expect(data['a'], equals(1));
      expect(data['b'], equals(2));
      expect(data['c'], equals(3));
    });

    test('R.groupBy — group with JS function', () async {
      final classify =
          await jsFunc(js, "return x > 3 ? 'big' : 'small'", params: ['x']);
      dynamic result = await R.groupBy(classify, [1, 2, 3, 4, 5, 6]);
      final json = await result.$toJson();
      final data = jsonDecode(json as String);
      expect(data['small'], equals([1, 2, 3]));
      expect(data['big'], equals([4, 5, 6]));
    });

    test('R.curry — create curried function', () async {
      final addFn =
          await jsFunc(js, 'return a + b + c', params: ['a', 'b', 'c']);
      dynamic add3 = await R.curry(addFn);
      dynamic add1And2 = await add3(1);
      dynamic add1And2And3 = await add1And2(2);
      final result = await add1And2And3(3);
      expect(result, equals(6));
    });

    test('R.path — deep property access', () async {
      final result = await R.path(
        ['a', 'b', 'c'],
        {
          'a': {
            'b': {'c': 42}
          }
        },
      );
      expect(result, equals(42));
    });

    test('R.zip', () async {
      final result = await R.zip([1, 2, 3], ['a', 'b', 'c']);
      expect(
          result,
          equals([
            [1, 'a'],
            [2, 'b'],
            [3, 'c']
          ]));
    });
  });
}
