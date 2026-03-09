/// JavaScript bundler — creates self-contained JS bundles for web/mobile.
///
/// Since web and mobile platforms don't have Node.js or npm at runtime,
/// npm packages must be pre-bundled into a single JS file at dev time.
///
/// The bundler:
/// 1. Reads dependencies from `js_bridger.json`
/// 2. Generates an entry file that re-exports all modules
/// 3. Uses esbuild to create a platform-ready bundle
/// 4. Wraps the bundle with module registration for the embedded worker
///
/// Usage:
///   dart run flutter_js_bridger bundle [--output <path>]
library;

import 'dart:convert';
import 'dart:io';

import 'errors.dart';
import 'manifest.dart';

/// Bundles npm packages into a single JS file for web/mobile deployment.
class JsBundler {
  final String _workingDir;

  JsBundler(this._workingDir);

  /// Bundle all dependencies from a manifest into a single JS file.
  ///
  /// [manifest] — The loaded js_bridger.json manifest.
  /// [outputPath] — Where to write the bundle (default: `<workDir>/bundle.js`).
  ///
  /// Returns the absolute path of the generated bundle.
  Future<String> bundle(
    JsBridgerManifest manifest, {
    String? outputPath,
  }) async {
    final deps = manifest.dependencies;
    if (deps.isEmpty) {
      throw const JsBridgeException(
        JsErrorCode.protocolError,
        'No dependencies to bundle. Add packages first:\n'
        '  dart run flutter_js_bridger add <package>',
      );
    }

    final output =
        outputPath ?? '$_workingDir${Platform.pathSeparator}bundle.js';

    // 1. Generate entry file
    final entryPath = '$_workingDir${Platform.pathSeparator}.bundle_entry.js';
    final entrySrc = _generateEntry(deps.keys.toList());
    await File(entryPath).writeAsString(entrySrc);

    // 2. Try esbuild first (fast), then fallback to basic bundling
    try {
      await _bundleWithEsbuild(entryPath, output);
    } catch (_) {
      // Fallback: try npx esbuild
      try {
        await _bundleWithNpxEsbuild(entryPath, output);
      } catch (_) {
        // Last resort: basic concatenation
        await _bundleBasic(deps.keys.toList(), output);
      }
    }

    // 3. Wrap with module registration
    await _wrapBundle(output, deps.keys.toList());

    // Cleanup entry file
    try {
      await File(entryPath).delete();
    } catch (_) {}

    return output;
  }

  /// Generate the entry JS file that imports all modules.
  String _generateEntry(List<String> modules) {
    final buf = StringBuffer();
    buf.writeln('// Auto-generated entry — do not edit');
    for (final mod in modules) {
      buf.writeln('exports["$mod"] = require("$mod");');
    }
    return buf.toString();
  }

  /// Bundle using globally installed esbuild.
  Future<void> _bundleWithEsbuild(String entryPath, String outputPath) async {
    final result = await Process.run(
      'esbuild',
      [
        entryPath,
        '--bundle',
        '--format=cjs',
        '--platform=neutral',
        '--outfile=$outputPath',
        '--minify',
      ],
      workingDirectory: _workingDir,
      runInShell: Platform.isWindows,
    );
    if (result.exitCode != 0) {
      throw Exception('esbuild failed: ${result.stderr}');
    }
  }

  /// Bundle using npx esbuild (local or downloads).
  Future<void> _bundleWithNpxEsbuild(
      String entryPath, String outputPath) async {
    final result = await Process.run(
      'npx',
      [
        'esbuild',
        entryPath,
        '--bundle',
        '--format=cjs',
        '--platform=neutral',
        '--outfile=$outputPath',
        '--minify',
      ],
      workingDirectory: _workingDir,
      runInShell: Platform.isWindows,
    );
    if (result.exitCode != 0) {
      throw Exception('npx esbuild failed: ${result.stderr}');
    }
  }

  /// Basic bundling fallback — concatenates module main files.
  ///
  /// This is a simplified bundler that works without esbuild.
  /// It reads each package's main file and wraps it in a module factory.
  Future<void> _bundleBasic(List<String> modules, String outputPath) async {
    final buf = StringBuffer();
    buf.writeln('// flutter_js_bridger auto-bundle (basic mode)');
    buf.writeln('var __bundledModules = __bundledModules || {};');
    buf.writeln('var __moduleCache = __moduleCache || {};');
    buf.writeln();

    for (final mod in modules) {
      final mainFile = _resolveModuleMain(mod);
      if (mainFile != null && mainFile.existsSync()) {
        final src = mainFile.readAsStringSync();
        buf.writeln(
            '__bundledModules["$mod"] = function(module, exports, require) {');
        buf.writeln(src);
        buf.writeln('};');
        buf.writeln();
      }
    }

    await File(outputPath).writeAsString(buf.toString());
  }

  /// Resolve the main entry file of an npm package.
  File? _resolveModuleMain(String moduleName) {
    final sep = Platform.pathSeparator;
    final pkgJsonPath =
        '$_workingDir${sep}node_modules$sep$moduleName${sep}package.json';
    final pkgJsonFile = File(pkgJsonPath);
    if (!pkgJsonFile.existsSync()) return null;

    try {
      final json =
          jsonDecode(pkgJsonFile.readAsStringSync()) as Map<String, dynamic>;
      final main = json['main'] as String? ?? 'index.js';
      return File('$_workingDir${sep}node_modules$sep$moduleName$sep$main');
    } catch (_) {
      return null;
    }
  }

  /// Wrap the bundled output with __bundledModules registration.
  Future<void> _wrapBundle(String bundlePath, List<String> modules) async {
    final file = File(bundlePath);
    if (!file.existsSync()) return;

    final content = await file.readAsString();
    final buf = StringBuffer();
    buf.writeln('// flutter_js_bridger bundle');
    buf.writeln('// Generated: ${DateTime.now().toIso8601String()}');
    buf.writeln('// Modules: ${modules.join(", ")}');
    buf.writeln('(function() {');
    buf.writeln(
        '  var __bundledModules = (typeof globalThis !== "undefined" ? globalThis : this).__bundledModules = (typeof globalThis !== "undefined" ? globalThis : this).__bundledModules || {};');
    buf.writeln('  var _exports = {};');
    buf.writeln('  (function(exports) {');
    buf.writeln(content);
    buf.writeln('  })(_exports);');
    // Register each module from the exports
    for (final mod in modules) {
      buf.writeln('  if (_exports["$mod"]) {');
      buf.writeln('    var _mod = _exports["$mod"];');
      buf.writeln(
          '    __bundledModules["$mod"] = function(module, exports, require) {');
      buf.writeln('      module.exports = _mod;');
      buf.writeln('    };');
      buf.writeln('  }');
    }
    buf.writeln('})();');

    await file.writeAsString(buf.toString());
  }
}
