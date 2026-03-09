import 'package:flutter_js_bridger/flutter_js_bridger.dart';
import 'package:test/test.dart';

import '../helpers/npm_test_helper.dart';

/// Tests for Moment.js — full-featured date library.
///
/// All operations use the bridge's Dart-native proxy API.
void main() {
  late JsBridge js;
  late dynamic moment;

  setUpAll(() async {
    js = await createNpmTestBridge();
    await ensureInstalled(js, 'moment');
    moment = await js.require('moment');
  });

  tearDownAll(() async {
    await js.dispose();
  });

  group('Moment.js — Dart-native proxy API', () {
    test('require moment — returns callable function', () async {
      expect(moment, isNotNull);
      final type = await moment.$typeof();
      expect(type, equals('function'));
    });

    test('parse and format date', () async {
      dynamic m = await moment('2024-03-15');
      final result = await m.format('MMMM Do YYYY');
      expect(result, equals('March 15th 2024'));
    });

    test('relative time — fromNow', () async {
      dynamic m = await moment('2020-01-01');
      final result = await m.fromNow();
      expect(result, isA<String>());
    });

    test('add days', () async {
      dynamic m = await moment('2024-01-01');
      dynamic added = await m.add(10, 'days');
      final result = await added.format('YYYY-MM-DD');
      expect(result, equals('2024-01-11'));
    });

    test('diff between dates', () async {
      dynamic a = await moment('2024-01-01');
      dynamic b = await moment('2024-12-31');
      final result = await b.diff(a, 'days');
      expect(result, equals(365));
    });

    test('duration', () async {
      dynamic dur = await moment.duration(90, 'minutes');
      final hours = await dur.hours();
      final minutes = await dur.minutes();
      expect(hours, equals(1));
      expect(minutes, equals(30));
    });

    test('calendar time', () async {
      dynamic m = await moment();
      final result = await m.calendar();
      expect(result, isA<String>());
    });

    test('isBefore / isAfter / isSame', () async {
      dynamic jan = await moment('2024-01-01');
      dynamic dec = await moment('2024-12-31');
      dynamic janClone = await moment('2024-01-01');
      final before = await jan.isBefore(dec);
      final after = await jan.isAfter(dec);
      final same = await jan.isSame(janClone, 'day');
      expect(before, isTrue);
      expect(after, isFalse);
      expect(same, isTrue);
    });

    test('startOf month', () async {
      dynamic m = await moment('2024-06-15');
      dynamic sof = await m.startOf('month');
      final result = await sof.format('YYYY-MM-DD');
      expect(result, equals('2024-06-01'));
    });

    test('isValid', () async {
      dynamic valid = await moment('2024-01-15');
      dynamic invalid = await moment('xyzzy');
      final isValid = await valid.isValid();
      final isInvalid = await invalid.isValid();
      expect(isValid, isTrue);
      expect(isInvalid, isFalse);
    });

    test('locale — English day name', () async {
      await moment.locale('en');
      dynamic m = await moment('2024-01-15');
      final result = await m.format('dddd');
      expect(result, equals('Monday'));
    });

    test('UTC mode', () async {
      dynamic utc = await moment.utc('2024-06-15T12:00:00Z');
      final result = await utc.format('HH:mm');
      expect(result, equals('12:00'));
    });
  });
}
