import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_js_bridger/flutter_js_bridger.dart';
import 'package:test/test.dart';

import '../helpers/npm_test_helper.dart';

/// Tests for csv-parser and chalk — data processing and CLI tools.
///
/// Uses Dart-native proxy API where possible:
///   - chalk: `chalk.red('text')`, `chalk.bold.underline.red(...)`, `chalk.hex(...)(...)`
///   - csv-parser: stream pipeline with createFunction collector + Dart end callback — zero eval
void main() {
  late JsBridge js;

  setUpAll(() async {
    js = await createNpmTestBridge();
    await ensureAllInstalled(js, ['csv-parser', 'chalk@4']);

    // Create a test CSV file
    final csvFile = File('$npmTestWorkDir/test_data.csv');
    await csvFile.writeAsString('''name,age,city,score
Alice,30,New York,95.5
Bob,25,London,88.0
Charlie,35,Tokyo,92.3
Diana,28,Paris,97.1
Eve,32,Berlin,85.7
''');

    // Create a CSV with edge cases
    final edgeCsv = File('$npmTestWorkDir/edge_cases.csv');
    await edgeCsv.writeAsString('''name,description,value
"Smith, John","Has a comma, in name",100
"O'Brien","Has 'quotes'",200
"Simple",No special chars,300
''');
  });

  tearDownAll(() async {
    await js.dispose();
  });

  // ─── csv-parser ────────────────────────────────────────────

  group('csv-parser', () {
    test('require csv-parser', () async {
      final dynamic csvParser = await js.require('csv-parser');
      expect(csvParser, isNotNull);
    });

    test('parse CSV file — read all rows', () async {
      dynamic fs = await js.require('fs');
      dynamic csvParser = await js.require('csv-parser');

      await js.setGlobal('__csvRows', []);
      final collectFn = await js.createFunction(
        params: ['row'],
        body: 'globalThis.__csvRows.push(row);',
      );

      final completer = Completer<void>();
      dynamic stream = await fs.createReadStream('test_data.csv');
      dynamic parser = await csvParser();
      dynamic piped = await stream.pipe(parser);
      // Attach 'end' before 'data' — 'data' starts flowing mode
      await piped.on('end', () {
        completer.complete();
      });
      await piped.on('data', collectFn);
      await completer.future;

      final getRows = await js.createFunction(
        body: 'return JSON.stringify(globalThis.__csvRows)',
      );
      final data = jsonDecode(await getRows.$invoke([]) as String) as List;
      expect(data.length, equals(5));
      expect(data[0]['name'], equals('Alice'));
      expect(data[4]['name'], equals('Eve'));
    });

    test('parse CSV — access individual fields', () async {
      dynamic fs = await js.require('fs');
      dynamic csvParser = await js.require('csv-parser');

      await js.setGlobal('__csvRows', []);
      final collectFn = await js.createFunction(
        params: ['row'],
        body: 'globalThis.__csvRows.push(row);',
      );

      final completer = Completer<void>();
      dynamic stream = await fs.createReadStream('test_data.csv');
      dynamic piped = await stream.pipe(await csvParser());
      await piped.on('end', () {
        completer.complete();
      });
      await piped.on('data', collectFn);
      await completer.future;

      final getRows = await js.createFunction(
        body: 'return JSON.stringify(globalThis.__csvRows)',
      );
      final data = jsonDecode(await getRows.$invoke([]) as String) as List;
      final alice = data[0] as Map<String, dynamic>;
      expect(alice['name'], equals('Alice'));
      expect(alice['age'], equals('30'));
      expect(alice['city'], equals('New York'));
      expect(alice['score'], equals('95.5'));
      // CSV values are always strings
      expect(alice['age'], isA<String>());
    });

    test('parse CSV — filter and transform', () async {
      dynamic fs = await js.require('fs');
      dynamic csvParser = await js.require('csv-parser');

      await js.setGlobal('__csvRows', []);
      final collectFn = await js.createFunction(
        params: ['row'],
        body: 'globalThis.__csvRows.push(row);',
      );

      final completer = Completer<void>();
      dynamic stream = await fs.createReadStream('test_data.csv');
      dynamic piped = await stream.pipe(await csvParser());
      await piped.on('end', () {
        completer.complete();
      });
      await piped.on('data', collectFn);
      await completer.future;

      final getRows = await js.createFunction(
        body: 'return JSON.stringify(globalThis.__csvRows)',
      );
      final rows = jsonDecode(await getRows.$invoke([]) as String) as List;

      // Filter and transform in Dart
      final highScorers =
          rows.where((r) => double.parse(r['score'] as String) > 90).toList();
      final avgScore = rows
              .map((r) => double.parse(r['score'] as String))
              .reduce((a, b) => a + b) /
          rows.length;

      expect(highScorers.length, equals(3));
      expect(highScorers.map((r) => r['name']).toList(),
          containsAll(['Alice', 'Charlie', 'Diana']));
      expect((avgScore * 10).round() / 10, equals(91.7));
    });

    test('parse CSV with edge cases (commas, quotes)', () async {
      dynamic fs = await js.require('fs');
      dynamic csvParser = await js.require('csv-parser');

      await js.setGlobal('__csvRows', []);
      final collectFn = await js.createFunction(
        params: ['row'],
        body: 'globalThis.__csvRows.push(row);',
      );

      final completer = Completer<void>();
      dynamic stream = await fs.createReadStream('edge_cases.csv');
      dynamic piped = await stream.pipe(await csvParser());
      await piped.on('end', () {
        completer.complete();
      });
      await piped.on('data', collectFn);
      await completer.future;

      final getRows = await js.createFunction(
        body: 'return JSON.stringify(globalThis.__csvRows)',
      );
      final rows = jsonDecode(await getRows.$invoke([]) as String) as List;
      expect(rows.length, equals(3));
      expect(rows[0]['name'], equals('Smith, John'));
      expect(rows[0]['description'], equals('Has a comma, in name'));
      expect(rows[1]['name'], equals("O'Brien"));
    });

    test('parse CSV with custom separator', () async {
      final tsv = File('$npmTestWorkDir/test.tsv');
      await tsv.writeAsString('name\tvalue\nAlpha\t100\nBeta\t200\n');

      dynamic fs = await js.require('fs');
      dynamic csvParser = await js.require('csv-parser');

      await js.setGlobal('__csvRows', []);
      final collectFn = await js.createFunction(
        params: ['row'],
        body: 'globalThis.__csvRows.push(row);',
      );

      final completer = Completer<void>();
      dynamic stream = await fs.createReadStream('test.tsv');
      dynamic piped = await stream.pipe(await csvParser({'separator': '\t'}));
      await piped.on('end', () {
        completer.complete();
      });
      await piped.on('data', collectFn);
      await completer.future;

      final getRows = await js.createFunction(
        body: 'return JSON.stringify(globalThis.__csvRows)',
      );
      final rows = jsonDecode(await getRows.$invoke([]) as String) as List;
      expect(rows.length, equals(2));
      expect(rows[0]['name'], equals('Alpha'));
      expect(rows[0]['value'], equals('100'));
    });
  });

  // ─── chalk ─────────────────────────────────────────────────

  group('chalk', () {
    test('require chalk', () async {
      final dynamic chalk = await js.require('chalk');
      expect(chalk, isNotNull);
      expect(chalk, isA<JsObject>());
    });

    test('basic colors — red, green, blue, yellow exist', () async {
      final dynamic chalk = await js.require('chalk');
      expect(await chalk.$has('red'), isTrue);
      expect(await chalk.$has('green'), isTrue);
      expect(await chalk.$has('blue'), isTrue);
      expect(await chalk.$has('yellow'), isTrue);
    });

    test('chalk.red creates colored string', () async {
      final dynamic chalk = await js.require('chalk');
      final colored = await chalk.red('Error!');
      expect(colored, isA<String>());
    });

    test('chalk chaining — bold, underline, etc.', () async {
      // Chalk chaining (chalk.bold.underline.red) uses getters that return
      // chalk instances — works through proxy chain
      final dynamic chalk = await js.require('chalk');
      dynamic bold = await chalk.bold;
      dynamic boldUnderline = await bold.underline;
      final styled = await boldUnderline.red('Important');
      expect(styled, isA<String>());
    });

    test('chalk.rgb and hex', () async {
      final dynamic chalk = await js.require('chalk');
      dynamic hexFn = await chalk.hex('#FF6600');
      final custom = await hexFn('Orange text');
      expect(custom, isA<String>());

      dynamic rgbFn = await chalk.rgb(255, 136, 0);
      final rgb = await rgbFn('RGB orange');
      expect(rgb, isA<String>());
    });

    test('chalk.level — check color support', () async {
      final dynamic chalk = await js.require('chalk');
      final level = await chalk.level;
      expect(level, isA<num>());
    });

    test('chalk template — concatenation', () async {
      final dynamic chalk = await js.require('chalk');
      final red = await chalk.red('Error: ') as String;
      final yellow = await chalk.yellow('Warning ') as String;
      final green = await chalk.green('OK') as String;
      final msg = red + yellow + green;
      expect(msg, isA<String>());
      expect(msg.length, greaterThan(0));
    });

    test('chalk bgColor', () async {
      final dynamic chalk = await js.require('chalk');
      dynamic bgRed = await chalk.bgRed;
      final bg = await bgRed.white('Alert');
      expect(bg, isA<String>());
    });
  });
}
