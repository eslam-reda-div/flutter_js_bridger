import 'dart:io';

import 'package:flutter_js_bridger/flutter_js_bridger.dart';
import 'package:test/test.dart';

/// Integration tests for the JS bundler.
///
/// These tests require Node.js and npm in PATH.
/// They test the full bundling pipeline: entry generation, esbuild/fallback,
/// and the resulting bundle's usability.
void main() {
  late String workDir;

  setUp(() {
    workDir = '${Directory.current.path}${Platform.pathSeparator}.test_bundler';
    Directory(workDir).createSync(recursive: true);
  });

  tearDown(() async {
    await Future.delayed(const Duration(milliseconds: 300));
    final dir = Directory(workDir);
    if (dir.existsSync()) {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('JsBundler', () {
    test('bundle throws on empty dependencies', () async {
      final manifest = JsBridgerManifest.create(
        '$workDir${Platform.pathSeparator}js_bridger.json',
      );
      manifest.save();

      final bundler = JsBundler(workDir);
      expect(
        () => bundler.bundle(manifest),
        throwsA(isA<JsBridgeException>()),
      );
    });

    test('bundle creates output file with a real package', () async {
      // Install a tiny package first
      final pm = PackageManager(workDir);
      await pm.install(['is-number']);

      final manifest = JsBridgerManifest.create(
        '$workDir${Platform.pathSeparator}js_bridger.json',
      );
      manifest.addDependency('is-number', '*');
      manifest.save();

      final bundler = JsBundler(workDir);
      final outputPath = '$workDir${Platform.pathSeparator}test_bundle.js';
      final result = await bundler.bundle(manifest, outputPath: outputPath);

      expect(File(result).existsSync(), isTrue);

      final content = File(result).readAsStringSync();
      expect(content, contains('flutter_js_bridger'));
      expect(content, contains('is-number'));
      expect(content.length, greaterThan(100));
    });

    test('bundle custom output path', () async {
      final pm = PackageManager(workDir);
      await pm.install(['is-number']);

      final manifest = JsBridgerManifest.create(
        '$workDir${Platform.pathSeparator}js_bridger.json',
      );
      manifest.addDependency('is-number', '*');
      manifest.save();

      final bundler = JsBundler(workDir);
      final customPath =
          '$workDir${Platform.pathSeparator}custom${Platform.pathSeparator}output.js';
      Directory('$workDir${Platform.pathSeparator}custom')
          .createSync(recursive: true);

      final result = await bundler.bundle(manifest, outputPath: customPath);
      expect(result, equals(customPath));
      expect(File(customPath).existsSync(), isTrue);
    });

    test('bundle cleans up temp entry file', () async {
      final pm = PackageManager(workDir);
      await pm.install(['is-number']);

      final manifest = JsBridgerManifest.create(
        '$workDir${Platform.pathSeparator}js_bridger.json',
      );
      manifest.addDependency('is-number', '*');
      manifest.save();

      final bundler = JsBundler(workDir);
      await bundler.bundle(manifest);

      final entryFile =
          File('$workDir${Platform.pathSeparator}.bundle_entry.js');
      expect(entryFile.existsSync(), isFalse);
    });

    test('bundled output wraps with module registration', () async {
      final pm = PackageManager(workDir);
      await pm.install(['is-number']);

      final manifest = JsBridgerManifest.create(
        '$workDir${Platform.pathSeparator}js_bridger.json',
      );
      manifest.addDependency('is-number', '*');
      manifest.save();

      final bundler = JsBundler(workDir);
      final result = await bundler.bundle(manifest);
      final content = File(result).readAsStringSync();

      // Should contain module registration wrapper
      expect(content, contains('__bundledModules'));
      expect(content, contains('is-number'));
    });

    test('bundled code is loadable by NodeEngine', () async {
      // Full round-trip: bundle → load → use
      final pm = PackageManager(workDir);
      await pm.install(['is-number']);

      final manifest = JsBridgerManifest.create(
        '$workDir${Platform.pathSeparator}js_bridger.json',
      );
      manifest.addDependency('is-number', '*');
      manifest.save();

      final bundler = JsBundler(workDir);
      final bundlePath = await bundler.bundle(manifest);

      // Now create a bridge that uses this bundle
      final bridge = JsBridge(JsBridgeConfig(
        workingDirectory: workDir,
        manifestPath: '',
      ));
      await bridge.initialize();

      // Load and execute the bundle content
      final bundleContent = File(bundlePath).readAsStringSync();
      await bridge.eval(bundleContent);

      await bridge.dispose();
    });

    test('bundle with multiple packages', () async {
      final pm = PackageManager(workDir);
      await pm.install(['is-number', 'is-even']);

      final manifest = JsBridgerManifest.create(
        '$workDir${Platform.pathSeparator}js_bridger.json',
      );
      manifest.addDependency('is-number', '*');
      manifest.addDependency('is-even', '*');
      manifest.save();

      final bundler = JsBundler(workDir);
      final bundlePath = await bundler.bundle(manifest);
      final content = File(bundlePath).readAsStringSync();

      expect(content, contains('is-number'));
      expect(content, contains('is-even'));
      expect(File(bundlePath).existsSync(), isTrue);
    });
  });
}
