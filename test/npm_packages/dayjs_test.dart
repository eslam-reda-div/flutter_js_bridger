import 'package:flutter_js_bridger/flutter_js_bridger.dart';
import 'package:test/test.dart';

import '../helpers/npm_test_helper.dart';

/// Tests for Day.js — lightweight date manipulation library.
///
/// All operations use the bridge's Dart-native proxy API:
///   - `js.require('dayjs')` to import
///   - `dayjs('2024-01-15')` to create a date instance
///   - `.format()`, `.add()`, `.subtract()`, `.diff()` called directly from Dart
///   - No eval — everything is bridged through JsObject proxies
void main() {
  late JsBridge js;
  late dynamic dayjs;

  setUpAll(() async {
    js = await createNpmTestBridge();
    await ensureInstalled(js, 'dayjs');
    dayjs = await js.require('dayjs');
  });

  tearDownAll(() async {
    await js.dispose();
  });

  group('Day.js — Dart-native proxy API', () {
    test('require dayjs — returns callable function', () async {
      expect(dayjs, isNotNull);
      final type = await dayjs.$typeof();
      expect(type, equals('function'));
    });

    test('create date from string and format', () async {
      dynamic d = await dayjs('2024-01-15');
      final result = await d.format('YYYY-MM-DD');
      expect(result, equals('2024-01-15'));
    });

    test('format with full pattern', () async {
      dynamic d = await dayjs('2024-06-15T14:30:00');
      final result = await d.format('dddd, MMMM D, YYYY h:mm A');
      expect(result, isA<String>());
      expect(result, contains('2024'));
    });

    test('add time', () async {
      dynamic d = await dayjs('2024-01-01');
      dynamic added = await d.add(7, 'day');
      final result = await added.format('YYYY-MM-DD');
      expect(result, equals('2024-01-08'));
    });

    test('subtract time', () async {
      dynamic d = await dayjs('2024-01-15');
      dynamic subtracted = await d.subtract(1, 'month');
      final result = await subtracted.format('YYYY-MM-DD');
      expect(result, equals('2023-12-15'));
    });

    test('diff between dates', () async {
      dynamic a = await dayjs('2024-06-15');
      final result = await a.diff('2024-01-01', 'day');
      expect(result, equals(166));
    });

    test('startOf month', () async {
      dynamic d = await dayjs('2024-06-15');
      dynamic sof = await d.startOf('month');
      final result = await sof.format('YYYY-MM-DD');
      expect(result, equals('2024-06-01'));
    });

    test('isBefore / isAfter', () async {
      dynamic a = await dayjs('2024-01-01');
      dynamic b = await dayjs('2024-12-31');
      final before = await a.isBefore(b);
      final after = await a.isAfter(b);
      expect(before, isTrue);
      expect(after, isFalse);
    });

    test('unix timestamp', () async {
      dynamic d = await dayjs('2024-01-01');
      final ts = await d.unix();
      expect(ts, isA<num>());
      expect(ts, greaterThan(0));
    });

    test('toISOString', () async {
      dynamic d = await dayjs('2024-01-15T00:00:00Z');
      final result = await d.toISOString();
      expect(result, isA<String>());
      expect(result, contains('2024-01-15'));
    });

    test('get year/month/day components', () async {
      dynamic d = await dayjs('2024-06-15');
      final year = await d.year();
      final month = await d.month();
      final date = await d.date();
      expect(year, equals(2024));
      expect(month, equals(5)); // 0-indexed
      expect(date, equals(15));
    });

    test('isValid', () async {
      dynamic valid = await dayjs('2024-01-15');
      dynamic invalid = await dayjs('not-a-date');
      final isValid = await valid.isValid();
      final isInvalid = await invalid.isValid();
      expect(isValid, isTrue);
      expect(isInvalid, isFalse);
    });
  });
}
