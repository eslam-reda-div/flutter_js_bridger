import 'dart:convert';
import 'dart:io';

import 'package:flutter_js_bridger/flutter_js_bridger.dart';
import 'package:flutter_js_bridger/src/package_manager.dart';
import 'package:test/test.dart';

void main() {
  late JsBridge js;
  final testWorkDir =
      '${Directory.current.path}${Platform.pathSeparator}.test_js_runtime';

  setUpAll(() async {
    js = JsBridge(JsBridgeConfig(
      workingDirectory: testWorkDir,
      manifestPath: '', // disable manifest for core tests
    ));
    await js.initialize();
  });

  tearDownAll(() async {
    await js.dispose();
    // Small delay to ensure the process has fully released file handles
    await Future.delayed(const Duration(milliseconds: 500));
    // Cleanup test working directory
    final dir = Directory(
        '${Directory.current.path}${Platform.pathSeparator}.test_js_runtime');
    if (dir.existsSync()) {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {
        // Best-effort cleanup
      }
    }
  });

  // ═══════════════════════════════════════════════════════
  //  Lifecycle
  // ═══════════════════════════════════════════════════════

  group('Lifecycle', () {
    test('bridge is initialized', () {
      expect(js.isInitialized, isTrue);
    });

    test('ping returns true', () async {
      expect(await js.ping(), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════
  //  eval
  // ═══════════════════════════════════════════════════════

  group('eval', () {
    test('evaluates arithmetic', () async {
      expect(await js.eval('2 + 2'), equals(4));
    });

    test('evaluates string operations', () async {
      expect(await js.eval('"hello".toUpperCase()'), equals('HELLO'));
    });

    test('evaluates array operations', () async {
      final result = await js.eval('[1, 2, 3].map(x => x * 2)');
      expect(result, equals([2, 4, 6]));
    });

    test('returns null for undefined', () async {
      expect(await js.eval('undefined'), isNull);
    });

    test('returns null for null', () async {
      expect(await js.eval('null'), isNull);
    });

    test('returns boolean', () async {
      expect(await js.eval('true'), isTrue);
      expect(await js.eval('false'), isFalse);
    });

    test('returns object as JsObject', () async {
      final dynamic result = await js.eval('({a: 1, b: "hello"})');
      expect(result, isA<JsObject>());
      expect(await result.a, equals(1));
      expect(await result.b, equals('hello'));
    });

    test('returns complex object as JsObject', () async {
      final result = await js.eval('new Date()');
      expect(result, isA<JsObject>());
    });
  });

  // ═══════════════════════════════════════════════════════
  //  require — built-in modules
  // ═══════════════════════════════════════════════════════

  group('require — built-in modules', () {
    test('require path module', () async {
      final dynamic path = await js.require('path');
      expect(path, isA<JsObject>());

      final joined = await path.join('a', 'b', 'c');
      expect(joined, isA<String>());
      expect(joined, contains('b'));
    });

    test('require os module', () async {
      final dynamic os = await js.require('os');
      final platform = await os.platform();
      expect(platform, isA<String>());
    });

    test('require url module', () async {
      final dynamic url = await js.require('url');
      expect(url, isA<JsObject>());
    });
  });

  // ═══════════════════════════════════════════════════════
  //  JsObject — property access and method calls
  // ═══════════════════════════════════════════════════════

  group('JsObject', () {
    test('method call returns primitive', () async {
      final dynamic path = await js.require('path');
      final ext = await path.extname('file.txt');
      expect(ext, equals('.txt'));
    });

    test('method call with multiple args', () async {
      final dynamic path = await js.require('path');
      final result = await path.join('users', 'eslam', 'docs');
      expect(result, isA<String>());
      expect(result, contains('eslam'));
    });

    test('property access returns value', () async {
      final dynamic path = await js.require('path');
      final sep = await path.sep;
      expect(sep, isA<String>());
    });

    test('chained property access', () async {
      final dynamic obj = await js.eval('({a: {b: {c: 42}}})');
      final value = await obj.a.b.c;
      expect(value, equals(42));
    });

    test('chained method call', () async {
      final dynamic obj = await js.eval('({math: {add: (a, b) => a + b}})');
      final result = await obj.math.add(3, 4);
      expect(result, equals(7));
    });

    test('\$get explicit property access', () async {
      final dynamic path = await js.require('path');
      final sep = await (path as JsObject).$get('sep');
      expect(sep, isA<String>());
    });

    test('\$call explicit method call', () async {
      final dynamic path = await js.require('path');
      final ext = await (path as JsObject).$call('extname', ['test.js']);
      expect(ext, equals('.js'));
    });

    test('\$keys returns object keys', () async {
      final dynamic obj = await js.eval('({x: 1, y: 2, z: 3})');
      final keys = await (obj as JsObject).$keys();
      expect(keys, containsAll(['x', 'y', 'z']));
    });

    test('\$typeof returns type', () async {
      final dynamic fn = await js.eval('(() => {})');
      final type = await (fn as JsObject).$typeof();
      expect(type, equals('function'));
    });

    test('\$has checks property existence', () async {
      final dynamic obj = await js.eval('({name: "test"})');
      expect(await (obj as JsObject).$has('name'), isTrue);
      expect(await (obj).$has('missing'), isFalse);
    });

    test('\$invoke calls as function', () async {
      final dynamic fn = await js.eval('((a, b) => a * b)');
      final result = await (fn as JsObject).$invoke([6, 7]);
      expect(result, equals(42));
    });

    test('\$new constructs instance', () async {
      final dynamic dateClass = await js.eval('Date');
      final instance = await (dateClass as JsObject).$new(['2026-01-01']);
      expect(instance, isA<JsObject>());
    });

    test('\$toJson converts to JSON string', () async {
      final dynamic obj = await js.eval('({a: 1, b: [2, 3]})');
      final json = await (obj as JsObject).$toJson();
      expect(json, contains('"a":1'));
    });

    test('\$length returns length', () async {
      final dynamic buf = await js.eval('Buffer.from("hello")');
      final len = await (buf as JsObject).$length();
      expect(len, equals(5));
    });

    test('\$toList converts to Dart list', () async {
      final dynamic s = await js.eval('new Set([10, 20, 30])');
      final list = await (s as JsObject).$toList();
      expect(list, containsAll([10, 20, 30]));
    });

    test('calling object as function', () async {
      final dynamic fn = await js.eval('((x) => x * 2)');
      // Use dynamic call syntax
      final result = await fn(21);
      expect(result, equals(42));
    });

    test('construct with \$new and use methods', () async {
      final dynamic mapClass = await js.eval('Map');
      final dynamic m = await (mapClass as JsObject).$new();
      await m.set('key', 'value');
      final val = await m.get('key');
      expect(val, equals('value'));
    });
  });

  // ═══════════════════════════════════════════════════════
  //  JsObject passed as argument
  // ═══════════════════════════════════════════════════════

  group('JsObject as argument', () {
    test('pass JsObject to another call', () async {
      final dynamic arr = await js.eval('[3, 1, 2]');
      // Create a function that accepts a JS object/array and stringifies it
      final dynamic stringify =
          await js.eval('(function(a) { return JSON.stringify(a); })');
      final str = await stringify(arr);
      expect(str, equals('[3,1,2]'));
    });
  });

  // ═══════════════════════════════════════════════════════
  //  Package Management
  // ═══════════════════════════════════════════════════════

  group('Package Management', () {
    test('install and require a package', () async {
      await js.install('lodash');

      final dynamic lo = await js.require('lodash');
      expect(lo, isA<JsObject>());

      // Use lodash
      final chunks = await lo.chunk([1, 2, 3, 4], 2);
      expect(
          chunks,
          equals([
            [1, 2],
            [3, 4]
          ]));
    });

    test('lodash uniq', () async {
      final dynamic lo = await js.require('lodash');
      final result = await lo.uniq([1, 1, 2, 2, 3]);
      expect(result, equals([1, 2, 3]));
    });

    test('lodash flatten', () async {
      final dynamic lo = await js.require('lodash');
      final result = await lo.flatten([
        [1, 2],
        [3, 4]
      ]);
      expect(result, equals([1, 2, 3, 4]));
    });

    test('lodash camelCase', () async {
      final dynamic lo = await js.require('lodash');
      final result = await lo.camelCase('hello world');
      expect(result, equals('helloWorld'));
    });

    test('lodash pick', () async {
      final dynamic lo = await js.require('lodash');
      final dynamic result =
          await lo.pick({'a': 1, 'b': 2, 'c': 3}, ['a', 'c']);
      expect(result, isA<JsObject>());
      expect(await result.a, equals(1));
      expect(await result.c, equals(3));
    });

    test('lodash range', () async {
      final dynamic lo = await js.require('lodash');
      final result = await lo.range(0, 5);
      expect(result, equals([0, 1, 2, 3, 4]));
    });

    test('lodash isEmpty', () async {
      final dynamic lo = await js.require('lodash');
      expect(await lo.isEmpty([]), isTrue);
      expect(await lo.isEmpty([1]), isFalse);
    });

    test('lodash merge', () async {
      final dynamic lo = await js.require('lodash');
      final dynamic result = await lo.merge({'a': 1}, {'b': 2});
      expect(result, isA<JsObject>());
      expect(await result.a, equals(1));
      expect(await result.b, equals(2));
    });

    test('list installed packages', () async {
      final packages = await js.listPackages();
      expect(packages, contains('lodash'));
    });

    test('isInstalled check', () async {
      expect(await js.isInstalled('lodash'), isTrue);
      expect(await js.isInstalled('nonexistent-pkg-xyz'), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════
  //  Error Handling
  // ═══════════════════════════════════════════════════════

  group('Error Handling', () {
    test('require nonexistent module throws', () async {
      expect(
        () => js.require('this-package-does-not-exist-xyz-12345'),
        throwsA(isA<JsBridgeException>()),
      );
    });

    test('calling non-function throws', () async {
      final dynamic obj = await js.eval('({value: 42})');
      expect(
        () async => await obj.value(1, 2, 3),
        throwsA(isA<JsBridgeException>()),
      );
    });

    test('eval syntax error throws', () async {
      expect(
        () => js.eval('function((('),
        throwsA(isA<JsBridgeException>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════════
  //  Complex Scenarios
  // ═══════════════════════════════════════════════════════

  group('Complex Scenarios', () {
    test('create and use a Map', () async {
      final dynamic m = await js.eval('new Map()');
      await m.set('hello', 'world');
      await m.set('answer', 42);
      final hello = await m.get('hello');
      final answer = await m.get('answer');
      final size = await m.size;
      expect(hello, equals('world'));
      expect(answer, equals(42));
      expect(size, equals(2));
    });

    test('create and use a Set', () async {
      final dynamic s = await js.eval('new Set([1, 2, 3, 2, 1])');
      final size = await s.size;
      expect(size, equals(3));
      final has2 = await s.has(2);
      expect(has2, isTrue);
    });

    test('work with Dates', () async {
      final dynamic d = await js.eval('new Date("2026-03-09T00:00:00Z")');
      final year = await d.getFullYear();
      final month = await d.getMonth(); // 0-indexed
      expect(year, equals(2026));
      expect(month, equals(2)); // March = 2 (0-indexed)
    });

    test('work with RegExp', () async {
      final dynamic re = await js.eval('/^hello/i');
      final result = await re.test('Hello World');
      expect(result, isTrue);
      final noMatch = await re.test('World Hello');
      expect(noMatch, isFalse);
    });

    test('work with JSON', () async {
      final dynamic parsed =
          await js.eval('JSON.parse(\'{"x": 1, "y": [2, 3]}\')');
      expect(parsed, isA<JsObject>());
      expect(await parsed.x, equals(1));
      expect(await parsed.y, equals([2, 3]));
    });

    test('lodash chained operations via temp vars', () async {
      final dynamic lo = await js.require('lodash');
      final result = await lo.sortBy(await lo.uniq(await lo.flatten([
        [3, 1],
        [2, 1],
        [4, 3]
      ])));
      expect(result, equals([1, 2, 3, 4]));
    });

    test('use Buffer', () async {
      final dynamic buf = await js.eval('Buffer.from("Hello, World!")');
      final str = await buf.toString('utf8');
      expect(str, equals('Hello, World!'));
      final len = await buf.length;
      expect(len, equals(13));
    });

    test('use Promise (async JS)', () async {
      final result = await js.eval('Promise.resolve(42)');
      // Promise should be awaited by the worker
      expect(result, equals(42));
    });

    test('use Promise.all', () async {
      final result = await js.eval(
          'Promise.all([Promise.resolve(1), Promise.resolve(2), Promise.resolve(3)])');
      expect(result, equals([1, 2, 3]));
    });

    test('multiple modules together', () async {
      final dynamic path = await js.require('path');
      final dynamic lo = await js.require('lodash');

      final ext = await path.extname('photo.jpg');
      expect(ext, equals('.jpg'));

      final result = await lo.last([1, 2, 3]);
      expect(result, equals(3));
    });
  });

  // ═══════════════════════════════════════════════════════
  //  Manifest — js_bridger.json management
  // ═══════════════════════════════════════════════════════

  group('Manifest', () {
    late String manifestDir;
    late String manifestPath;

    setUp(() {
      manifestDir =
          '${Directory.current.path}${Platform.pathSeparator}.test_manifest';
      manifestPath =
          '$manifestDir${Platform.pathSeparator}${JsBridgerManifest.defaultFileName}';
      Directory(manifestDir).createSync(recursive: true);
    });

    tearDown(() {
      final dir = Directory(manifestDir);
      if (dir.existsSync()) {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('create and save manifest', () {
      final manifest = JsBridgerManifest.create(manifestPath);
      manifest.addDependency('lodash', '^4.17.21');
      manifest.addDependency('axios', '^1.6.0');
      manifest.save();

      expect(File(manifestPath).existsSync(), isTrue);

      // Reload and verify
      final loaded = JsBridgerManifest.load(manifestPath);
      expect(loaded, isNotNull);
      expect(loaded!.dependencies, {'axios': '^1.6.0', 'lodash': '^4.17.21'});
      expect(loaded.version, '1.0.0');
      expect(loaded.nodeVersion, '>=16.0.0');
      expect(loaded.workingDirectory, '.js_runtime');
    });

    test('add and remove dependencies', () {
      final manifest = JsBridgerManifest.create(manifestPath);
      manifest.addDependency('lodash', '^4.17.21');
      expect(manifest.hasDependency('lodash'), isTrue);
      expect(manifest.hasDependency('axios'), isFalse);

      manifest.removeDependency('lodash');
      expect(manifest.hasDependency('lodash'), isFalse);
    });

    test('load returns null for missing file', () {
      final loaded = JsBridgerManifest.load(
        '$manifestDir${Platform.pathSeparator}nonexistent.json',
      );
      expect(loaded, isNull);
    });

    test('manifest file is valid JSON', () {
      final manifest = JsBridgerManifest.create(manifestPath);
      manifest.addDependency('lodash', '^4.17.21');
      manifest.save();

      final content = File(manifestPath).readAsStringSync();
      final json = jsonDecode(content) as Map<String, dynamic>;
      expect(json['version'], '1.0.0');
      expect(json['node'], '>=16.0.0');
      expect(json['working_directory'], '.js_runtime');
      expect(json['dependencies'], {'lodash': '^4.17.21'});
    });

    test('dependencies are saved sorted', () {
      final manifest = JsBridgerManifest.create(manifestPath);
      manifest.addDependency('zod', '^3.0.0');
      manifest.addDependency('axios', '^1.6.0');
      manifest.addDependency('moment', '^2.30.0');
      manifest.save();

      final content = File(manifestPath).readAsStringSync();
      final axiosPos = content.indexOf('axios');
      final momentPos = content.indexOf('moment');
      final zodPos = content.indexOf('zod');
      expect(axiosPos, lessThan(momentPos));
      expect(momentPos, lessThan(zodPos));
    });

    test('custom working directory', () {
      final manifest = JsBridgerManifest.create(
        manifestPath,
        workingDirectory: '.custom_runtime',
      );
      manifest.save();

      final loaded = JsBridgerManifest.load(manifestPath);
      expect(loaded!.workingDirectory, '.custom_runtime');
    });
  });

  // ═══════════════════════════════════════════════════════
  //  Manifest-based initialization
  // ═══════════════════════════════════════════════════════

  group('Manifest-based initialization', () {
    late String manifestDir;
    late String manifestPath;
    late String manifestWorkDir;

    setUp(() {
      manifestDir =
          '${Directory.current.path}${Platform.pathSeparator}.test_manifest_init';
      manifestPath =
          '$manifestDir${Platform.pathSeparator}${JsBridgerManifest.defaultFileName}';
      manifestWorkDir = '$manifestDir${Platform.pathSeparator}.js_runtime';
      Directory(manifestDir).createSync(recursive: true);
    });

    tearDown(() async {
      await Future.delayed(const Duration(milliseconds: 500));
      final dir = Directory(manifestDir);
      if (dir.existsSync()) {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('initialize with empty manifest succeeds', () async {
      final manifest = JsBridgerManifest.create(manifestPath);
      manifest.save();

      final bridge = JsBridge(JsBridgeConfig(
        manifestPath: manifestPath,
      ));
      await bridge.initialize();
      expect(bridge.isInitialized, isTrue);
      expect(bridge.manifest, isNotNull);
      expect(bridge.manifest!.dependencies, isEmpty);
      await bridge.dispose();
    });

    test('initialize with missing packages throws', () async {
      final manifest = JsBridgerManifest.create(manifestPath);
      manifest.addDependency('nonexistent-pkg-12345', '*');
      manifest.save();

      final bridge = JsBridge(JsBridgeConfig(
        manifestPath: manifestPath,
      ));

      expect(
        () => bridge.initialize(),
        throwsA(isA<JsPackageException>()),
      );
    });

    test('initialize with autoInstall installs missing packages', () async {
      final manifest = JsBridgerManifest.create(manifestPath);
      manifest.addDependency('is-number', 'latest');
      manifest.save();

      final bridge = JsBridge(JsBridgeConfig(
        manifestPath: manifestPath,
        autoInstall: true,
      ));
      await bridge.initialize();
      expect(bridge.isInitialized, isTrue);

      // The package should now be usable
      final dynamic isNum = await bridge.require('is-number');
      expect(isNum, isA<JsObject>());
      final result = await isNum(5);
      expect(result, isTrue);

      await bridge.dispose();
    });

    test('disabled manifest with empty string', () async {
      final bridge = JsBridge(JsBridgeConfig(
        workingDirectory: manifestWorkDir,
        manifestPath: '', // disable manifest
      ));
      await bridge.initialize();
      expect(bridge.manifest, isNull);
      await bridge.dispose();
    });

    test('package manager fast verification', () async {
      final pm = PackageManager(testWorkDir);
      await pm.install(['is-number']);

      expect(pm.isInstalledSync('is-number'), isTrue);
      expect(pm.isInstalledSync('nonexistent-xyz-12345'), isFalse);
      expect(pm.getInstalledVersionSync('is-number'), isNotNull);
      expect(pm.getInstalledVersionSync('nonexistent-xyz-12345'), isNull);
      expect(pm.findMissingPackages({'is-number': '*'}), isEmpty);
      expect(
        pm.findMissingPackages({'nonexistent-xyz-12345': '*'}),
        contains('nonexistent-xyz-12345'),
      );
    });
  });
}
