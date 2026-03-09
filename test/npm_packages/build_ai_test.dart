import 'dart:convert';

import 'package:flutter_js_bridger/flutter_js_bridger.dart';
import 'package:test/test.dart';

import '../helpers/npm_test_helper.dart';

/// Tests for build tools (esbuild), AI (openai â€” load-only), and uuid.
///
/// Uses Dart-native proxy API:
///   - `esbuild.transform(code, options)` â€” async call, read result properties
///   - `new OpenAI({apiKey: ...})` â€” construct instance via $new(), read properties
///   - `uuid.v4()`, `uuid.validate(id)` â€” direct proxy calls
void main() {
  late JsBridge js;

  setUpAll(() async {
    js = await createNpmTestBridge();
    await ensureAllInstalled(js, ['esbuild', 'openai', 'uuid']);
  });

  tearDownAll(() async {
    await js.dispose();
  });

  // â”€â”€â”€ esbuild â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  group('esbuild', () {
    test('require esbuild', () async {
      final dynamic esbuild = await js.require('esbuild');
      expect(esbuild, isNotNull);
      expect(esbuild, isA<JsObject>());
    });

    test('esbuild.transform â€” minify JS', () async {
      final dynamic esbuild = await js.require('esbuild');
      final jsCode = '''
        function greet(name) {
          const message = "Hello, " + name + "!";
          console.log(message);
          return message;
        }
      ''';
      dynamic result = await esbuild.transform(jsCode, {'minify': true});
      final code = await result.code as String;
      expect(code.length, greaterThan(0));
      expect(code.contains('const message'), isFalse);
    });

    test('esbuild.transform â€” TypeScript to JS', () async {
      final dynamic esbuild = await js.require('esbuild');
      final tsCode = '''
        interface User {
          name: string;
          age: number;
        }
        const greet = (user: User): string => {
          return \`Hello \${user.name}, age \${user.age}\`;
        };
      ''';
      dynamic result = await esbuild.transform(tsCode, {'loader': 'ts'});
      final code = await result.code as String;
      expect(code.length, greaterThan(0));
      expect(code.contains('interface'), isFalse);
      expect(code.contains(': string'), isFalse);
    });

    test('esbuild.transform â€” JSX', () async {
      final dynamic esbuild = await js.require('esbuild');
      final jsxCode =
          'const App = () => <div className="app"><h1>Hello</h1></div>;';
      dynamic result = await esbuild.transform(jsxCode, {'loader': 'jsx'});
      final code = await result.code as String;
      expect(code.length, greaterThan(0));
      expect(code.contains('<div'), isFalse);
    });

    test('esbuild.transform â€” ES2015 target', () async {
      final dynamic esbuild = await js.require('esbuild');
      final es6Code = '''
        const fn = async () => {
          const result = await fetch('/api');
          return result;
        };
      ''';
      dynamic result = await esbuild.transform(es6Code, {'target': 'es2015'});
      final code = await result.code as String;
      expect(code.length, greaterThan(0));
    });

    test('esbuild.build â€” bundle from string (stdin)', () async {
      // Write entry file
      // Write entry file using fs proxy - no eval
      final fs = await js.require('fs');
      await fs.writeFileSync(
        'esbuild_entry.js',
        'const add = (a, b) => a + b;\nconst multiply = (a, b) => a * b;\nmodule.exports = { add, multiply };\n',
      );
      final dynamic esbuild = await js.require('esbuild');
      dynamic result = await esbuild.build({
        'entryPoints': ['esbuild_entry.js'],
        'bundle': true,
        'write': false,
        'format': 'cjs',
        'minify': true,
        'platform': 'node',
      });
      dynamic outputFiles = await result.outputFiles;
      dynamic errors = await result.errors;
      // outputFiles may come back as Dart List or JsObject
      if (outputFiles is List) {
        expect(outputFiles.length, equals(1));
      } else {
        final json = await outputFiles.$toJson();
        final list = jsonDecode(json as String) as List;
        expect(list.length, equals(1));
      }
      if (errors is List) {
        expect(errors.length, equals(0));
      } else {
        final json = await errors.$toJson();
        final list = jsonDecode(json as String) as List;
        expect(list.length, equals(0));
      }
    });

    test('esbuild.transform â€” CSS minification', () async {
      final dynamic esbuild = await js.require('esbuild');
      final cssCode = '''
        .container {
          display: flex;
          justify-content: center;
          align-items: center;
          background-color: #ffffff;
          padding: 16px;
          margin: 0 auto;
        }
        .title {
          font-size: 24px;
          font-weight: bold;
          color: #333333;
        }
      ''';
      dynamic result =
          await esbuild.transform(cssCode, {'loader': 'css', 'minify': true});
      final code = await result.code as String;
      expect(code.length, greaterThan(0));
      expect(code.length, lessThan(200));
    });
  });

  // â”€â”€â”€ openai (load-only â€” no API key needed for API tests) â”€â”€

  group('openai', () {
    test('require openai', () async {
      final dynamic openai = await js.require('openai');
      expect(openai, isNotNull);
      expect(openai, isA<JsObject>());
    });

    test('OpenAI class exists', () async {
      final dynamic openai = await js.require('openai');
      dynamic OpenAI = await openai.$get('OpenAI');
      final typeOf = await OpenAI.$typeof();
      expect(typeOf, equals('function'));
    });

    test('create OpenAI client instance', () async {
      final dynamic openai = await js.require('openai');
      dynamic OpenAI = await openai.$get('OpenAI');
      dynamic client = await OpenAI.$new([
        {'apiKey': 'sk-test-fake-key'}
      ]);
      final hasChat = await client.$has('chat');
      expect(hasChat, isTrue);
      // Deep property check
      dynamic chat = await client.chat;
      final hasCompletions = await chat.$has('completions');
      expect(hasCompletions, isTrue);
    });

    test('OpenAI client has CRUD-like methods', () async {
      final dynamic openai = await js.require('openai');
      dynamic OpenAI = await openai.$get('OpenAI');
      dynamic client = await OpenAI.$new([
        {'apiKey': 'sk-test-fake-key'}
      ]);
      dynamic completions = await client.chat.completions;
      final hasCreate = await completions.$has('create');
      expect(hasCreate, isTrue);
    });
  });

  // â”€â”€â”€ uuid â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  group('uuid', () {
    test('require uuid', () async {
      final dynamic uuid = await js.require('uuid');
      expect(uuid, isNotNull);
      expect(uuid, isA<JsObject>());
    });

    test('generate v4 UUID', () async {
      final dynamic uuid = await js.require('uuid');
      final id = await uuid.v4() as String;
      expect(id.length, equals(36));
      expect(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
            .hasMatch(id),
        isTrue,
      );
    });

    test('v4 UUIDs are unique', () async {
      final dynamic uuid = await js.require('uuid');
      final ids = <String>{};
      for (int i = 0; i < 100; i++) {
        ids.add(await uuid.v4() as String);
      }
      expect(ids.length, equals(100));
    });

    test('validate UUID', () async {
      final dynamic uuid = await js.require('uuid');
      final id = await uuid.v4() as String;
      final valid = await uuid.validate(id);
      final version = await uuid.version(id);
      final invalidCheck = await uuid.validate('not-a-uuid');
      expect(valid, isTrue);
      expect(version, equals(4));
      expect(invalidCheck, isFalse);
    });

    test('v1 UUID (timestamp-based)', () async {
      final dynamic uuid = await js.require('uuid');
      final id = await uuid.v1() as String;
      expect(id.length, equals(36));
      final valid = await uuid.validate(id);
      final version = await uuid.version(id);
      expect(valid, isTrue);
      expect(version, equals(1));
    });

    test('v5 UUID (namespace-based)', () async {
      final dynamic uuid = await js.require('uuid');
      final namespace = '1b671a64-40d5-491e-99b0-da01ff1f3341';
      final id1 = await uuid.v5('hello', namespace) as String;
      final id2 = await uuid.v5('hello', namespace) as String;
      final id3 = await uuid.v5('world', namespace) as String;
      final valid = await uuid.validate(id1);
      expect(id1, equals(id2)); // deterministic
      expect(id1, isNot(equals(id3))); // different input
      expect(valid, isTrue);
    });
  });
}
