import 'dart:convert';
import 'dart:io';

import 'package:flutter_js_bridger/flutter_js_bridger.dart';
import 'package:test/test.dart';

import '../helpers/npm_test_helper.dart';

/// Tests for dotenv — environment variable loading from .env files.
///
/// All operations use the bridge's Dart-native proxy API:
///   - `dotenv.config()` — load .env file
///   - `dotenv.parse(text)` — parse env string directly
///   - Process.env accessed via `js.getGlobal('process')` — no eval
void main() {
  late JsBridge js;
  late dynamic dotenv;

  setUpAll(() async {
    js = await createNpmTestBridge();
    await ensureInstalled(js, 'dotenv');
    dotenv = await js.require('dotenv');

    // Create a .env file in the working directory for testing
    final envFile = File('$npmTestWorkDir/.env');
    await envFile.writeAsString('''
APP_NAME=BridgerTest
APP_PORT=3000
DB_HOST=localhost
DB_PORT=5432
DB_USER=admin
DB_PASSWORD=secret123
DEBUG=true
API_KEY=sk-test-abc123def456
''');

    // Create a .env.test file too
    final envTestFile = File('$npmTestWorkDir/.env.test');
    await envTestFile.writeAsString('''
APP_NAME=BridgerTestStaging
APP_PORT=4000
DEBUG=false
''');
  });

  tearDownAll(() async {
    await js.dispose();
  });

  group('dotenv — Dart-native proxy API', () {
    test('require dotenv — has config and parse', () async {
      expect(dotenv, isNotNull);
      final hasConfig = await dotenv.$has('config');
      final hasParse = await dotenv.$has('parse');
      expect(hasConfig, isTrue);
      expect(hasParse, isTrue);
    });

    test('config — load .env file', () async {
      dynamic result = await dotenv.config();
      dynamic parsed = await result.parsed;
      expect(parsed, isNotNull);
    });

    test('read loaded env variables', () async {
      await dotenv.config();
      dynamic process = await js.getGlobal('process');
      dynamic env = await process.env;
      final name = await env.$get('APP_NAME');
      final port = await env.$get('APP_PORT');
      final dbHost = await env.$get('DB_HOST');
      expect(name, equals('BridgerTest'));
      expect(port, equals('3000'));
      expect(dbHost, equals('localhost'));
    });

    test('parse — parse env string directly', () async {
      dynamic parsed = await dotenv.parse('MY_KEY=my_value\nOTHER=something');
      final json = await parsed.$toJson();
      final data = jsonDecode(json as String);
      expect(data['MY_KEY'], equals('my_value'));
      expect(data['OTHER'], equals('something'));
    });

    test('load custom path', () async {
      dynamic result = await dotenv.config({'path': '.env.test'});
      dynamic parsed = await result.parsed;
      final json = await parsed.$toJson();
      final data = jsonDecode(json as String);
      expect(data['APP_NAME'], equals('BridgerTestStaging'));
      expect(data['APP_PORT'], equals('4000'));
      expect(data['DEBUG'], equals('false'));
    });

    test('env values are always strings', () async {
      await dotenv.config();
      dynamic process = await js.getGlobal('process');
      dynamic env = await process.env;
      final portVal = await env.$get('APP_PORT');
      final debugVal = await env.$get('DEBUG');
      expect(portVal, isA<String>());
      expect(debugVal, isA<String>());
    });

    test('parse handles comments and empty lines', () async {
      dynamic parsed = await dotenv.parse(
        '# This is a comment\n\nKEY1=value1\nKEY2=value2\n# Another comment',
      );
      final keys = await parsed.$keys();
      expect(keys, hasLength(2));
      final json = await parsed.$toJson();
      final data = jsonDecode(json as String);
      expect(data['KEY1'], equals('value1'));
      expect(data['KEY2'], equals('value2'));
    });

    test('parse handles quoted values', () async {
      dynamic parsed =
          await dotenv.parse("SINGLE='quoted'\nDOUBLE=\"double quoted\"");
      final json = await parsed.$toJson();
      expect(json as String, contains('quoted'));
    });
  });
}
