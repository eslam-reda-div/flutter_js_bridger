/// CLI tool for managing npm packages declaratively.
///
/// Usage: `dart run flutter_js_bridger [command] [arguments]`
///
/// Commands:
///   init                    Create a new js_bridger.json manifest
///   add `pkg[@version]`     Add a package and install it
///   remove `pkg`            Remove a package
///   install                 Install all packages from the manifest
///   update [pkg]            Update packages (all or specific)
///   list                    Show declared vs installed packages
///   check                   Verify all manifest packages are installed
///   bundle                  Bundle npm packages for web/mobile deployment
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_js_bridger/src/bundler.dart';
import 'package:flutter_js_bridger/src/manifest.dart';
import 'package:flutter_js_bridger/src/package_manager.dart';

// ─── ANSI colors ─────────────────────────────────────

const _bold = '\x1B[1m';
const _green = '\x1B[32m';
const _red = '\x1B[31m';
const _yellow = '\x1B[33m';
const _cyan = '\x1B[36m';
const _dim = '\x1B[2m';
const _reset = '\x1B[0m';

// ─── Entry point ─────────────────────────────────────

void main(List<String> args) async {
  if (args.isEmpty ||
      args.first == 'help' ||
      args.first == '--help' ||
      args.first == '-h') {
    _printUsage();
    return;
  }

  final command = args.first;
  final rest = args.sublist(1);

  try {
    switch (command) {
      case 'init':
        await _init(rest);
      case 'add':
        await _add(rest);
      case 'remove':
        await _remove(rest);
      case 'install':
        await _install(rest);
      case 'update':
        await _update(rest);
      case 'list':
        await _list();
      case 'check':
        await _check();
      case 'bundle':
        await _bundle(rest);
      default:
        _error('Unknown command: $command');
        _printUsage();
        exit(1);
    }
  } catch (e) {
    _error('$e');
    exit(1);
  }
}

// ─── Commands ────────────────────────────────────────

/// `init` — Create a new js_bridger.json manifest.
Future<void> _init(List<String> args) async {
  final path = _manifestPath();
  if (File(path).existsSync()) {
    _warn('${JsBridgerManifest.defaultFileName} already exists.');
    return;
  }

  // Determine working directory
  var workDir = '.js_runtime';
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--dir' || args[i] == '-d') {
      workDir = args[i + 1];
    }
  }

  final manifest = JsBridgerManifest.create(path, workingDirectory: workDir);
  manifest.save();
  _success('Created ${JsBridgerManifest.defaultFileName}');
}

/// `add pkg[@version]` — Add a package to the manifest and install it.
Future<void> _add(List<String> args) async {
  if (args.isEmpty) {
    _error('Usage: dart run flutter_js_bridger add <package>[@version]');
    exit(1);
  }

  final manifest = _loadManifest();
  final pm = PackageManager(_resolveWorkingDir(manifest));

  for (final arg in args) {
    if (arg.startsWith('-')) continue;

    String name;
    String version;

    // Parse "lodash@^4.17.21" or "lodash"
    final atIndex = arg.lastIndexOf('@');
    if (atIndex > 0) {
      name = arg.substring(0, atIndex);
      version = arg.substring(atIndex + 1);
    } else {
      name = arg;
      version = 'latest';
    }

    _info('Installing $name...');
    await pm.install([arg]);

    // Read actual installed version from node_modules
    final installedVersion = _getInstalledVersion(
      _resolveWorkingDir(manifest),
      name,
    );
    final resolvedVersion = installedVersion != null
        ? (version == 'latest' ? '^$installedVersion' : version)
        : version;

    manifest.addDependency(name, resolvedVersion);
    _success('Added $name@$resolvedVersion');
  }

  manifest.save();
  _info('Saved ${JsBridgerManifest.defaultFileName}');
}

/// `remove pkg` — Remove a package from the manifest and uninstall it.
Future<void> _remove(List<String> args) async {
  if (args.isEmpty) {
    _error('Usage: dart run flutter_js_bridger remove <package>');
    exit(1);
  }

  final manifest = _loadManifest();
  final pm = PackageManager(_resolveWorkingDir(manifest));

  for (final name in args) {
    if (name.startsWith('-')) continue;
    if (!manifest.hasDependency(name)) {
      _warn('$name is not in the manifest.');
      continue;
    }
    _info('Removing $name...');
    await pm.remove([name]);
    manifest.removeDependency(name);
    _success('Removed $name');
  }

  manifest.save();
  _info('Saved ${JsBridgerManifest.defaultFileName}');
}

/// `install` — Install all packages from the manifest.
Future<void> _install(List<String> args) async {
  final manifest = _loadManifest();
  final workDir = _resolveWorkingDir(manifest);
  final pm = PackageManager(workDir);

  if (manifest.dependencies.isEmpty) {
    _info('No dependencies declared in ${JsBridgerManifest.defaultFileName}.');
    return;
  }

  // Build install args: "package@version"
  final installArgs = manifest.dependencies.entries.map((e) {
    final version = e.value;
    if (version == '*' || version == 'latest' || version.isEmpty) {
      return e.key;
    }
    return '${e.key}@$version';
  }).toList();

  _info('Installing ${installArgs.length} package(s)...');
  await pm.install(installArgs);

  // Show what got installed
  for (final entry in manifest.dependencies.entries) {
    final installed = _getInstalledVersion(workDir, entry.key);
    if (installed != null) {
      stdout.writeln(
        '  $_green✓$_reset ${entry.key} $_dim$installed$_reset',
      );
    } else {
      stdout.writeln('  $_red✗$_reset ${entry.key} $_dim(failed)$_reset');
    }
  }

  _success(
    'Installed ${installArgs.length} package(s) to '
    '${manifest.workingDirectory}/',
  );
}

/// `update [pkg]` — Update packages.
Future<void> _update(List<String> args) async {
  final manifest = _loadManifest();
  final pm = PackageManager(_resolveWorkingDir(manifest));

  final packages = args.where((a) => !a.startsWith('-')).toList();

  if (packages.isEmpty) {
    _info('Updating all packages...');
    await pm.update();
  } else {
    _info('Updating ${packages.join(", ")}...');
    await pm.update(packages);
  }
  _success('Update complete.');
}

/// `list` — Show declared vs installed packages.
Future<void> _list() async {
  final manifest = _loadManifest();
  final workDir = _resolveWorkingDir(manifest);

  if (manifest.dependencies.isEmpty) {
    _info('No dependencies declared.');
    return;
  }

  stdout
      .writeln('${_bold}Package              Declared        Installed$_reset');
  stdout.writeln('─' * 55);
  for (final entry in manifest.dependencies.entries) {
    final installed = _getInstalledVersion(workDir, entry.key);
    final status = installed != null
        ? '$_green$installed$_reset'
        : '$_red(missing)$_reset';
    final name = entry.key.padRight(20);
    final declared = entry.value.padRight(15);
    stdout.writeln('  $name $declared $status');
  }
}

/// `check` — Verify all manifest packages are installed.
Future<void> _check() async {
  final manifest = _loadManifest();
  final workDir = _resolveWorkingDir(manifest);

  if (manifest.dependencies.isEmpty) {
    _success('No dependencies to check.');
    return;
  }

  final missing = <String>[];
  for (final name in manifest.dependencies.keys) {
    final installed = _getInstalledVersion(workDir, name);
    if (installed != null) {
      stdout.writeln('  $_green✓$_reset $name ${_dim}v$installed$_reset');
    } else {
      stdout.writeln('  $_red✗$_reset $name $_dim(not installed)$_reset');
      missing.add(name);
    }
  }

  if (missing.isEmpty) {
    _success('All ${manifest.dependencies.length} package(s) installed.');
  } else {
    _error(
      '${missing.length} package(s) missing: ${missing.join(", ")}\n'
      '  Run: dart run flutter_js_bridger install',
    );
    exit(1);
  }
}

/// `bundle` — Bundle npm packages into a single JS file for web/mobile.
Future<void> _bundle(List<String> args) async {
  final manifest = _loadManifest();
  final workDir = _resolveWorkingDir(manifest);

  // Parse --output option
  String? outputPath;
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--output' || args[i] == '-o') {
      outputPath = args[i + 1];
    }
  }

  if (manifest.dependencies.isEmpty) {
    _warn('No dependencies to bundle.');
    return;
  }

  _info('Bundling ${manifest.dependencies.length} package(s)...');
  final bundler = JsBundler(workDir);
  final output = await bundler.bundle(manifest, outputPath: outputPath);
  _success('Bundle created: $output');
  _info('Use this bundle for web/mobile deployment.');
}

// ─── Helpers ─────────────────────────────────────────

/// Manifest file path in the current directory.
String _manifestPath() =>
    '${Directory.current.path}${Platform.pathSeparator}${JsBridgerManifest.defaultFileName}';

/// Load or fail.
JsBridgerManifest _loadManifest() {
  final path = _manifestPath();
  final manifest = JsBridgerManifest.load(path);
  if (manifest == null) {
    _error(
      '${JsBridgerManifest.defaultFileName} not found.\n'
      '  Run: dart run flutter_js_bridger init',
    );
    exit(1);
  }
  return manifest;
}

/// Resolve the absolute working directory from the manifest.
String _resolveWorkingDir(JsBridgerManifest manifest) {
  final dir = manifest.workingDirectory;
  if (dir.startsWith('/') || dir.contains(':\\')) return dir;
  // Relative to manifest location
  final manifestDir = File(manifest.filePath).parent.path;
  final resolved = '$manifestDir${Platform.pathSeparator}$dir';
  // Ensure the directory exists
  final d = Directory(resolved);
  if (!d.existsSync()) d.createSync(recursive: true);
  return resolved;
}

/// Read the installed version of a package from node_modules.
String? _getInstalledVersion(String workDir, String packageName) {
  final pkgJson = File(
    '$workDir${Platform.pathSeparator}node_modules'
    '${Platform.pathSeparator}$packageName'
    '${Platform.pathSeparator}package.json',
  );
  if (!pkgJson.existsSync()) return null;
  try {
    final json = jsonDecode(pkgJson.readAsStringSync()) as Map<String, dynamic>;
    return json['version'] as String?;
  } catch (_) {
    return null;
  }
}

// ─── Output helpers ──────────────────────────────────

void _info(String msg) => stdout.writeln('$_cyan▸$_reset $msg');
void _success(String msg) => stdout.writeln('$_green✓$_reset $msg');
void _warn(String msg) => stdout.writeln('$_yellow⚠$_reset $msg');
void _error(String msg) => stderr.writeln('$_red✗$_reset $msg');

void _printUsage() {
  stdout.writeln('''
${_bold}Flutter JS Bridger$_reset — npm package manager for Dart

${_bold}Usage:$_reset dart run flutter_js_bridger <command> [arguments]

${_bold}Commands:$_reset
  init                    Create a new ${JsBridgerManifest.defaultFileName}
  add <pkg>[@version]     Add a package to the manifest and install it
  remove <pkg>            Remove a package from the manifest
  install                 Install all packages from the manifest
  update [pkg]            Update package(s) — all if none specified
  list                    Show declared vs installed packages
  check                   Verify all manifest packages are installed
  bundle [-o <path>]      Bundle packages for web/mobile deployment

${_bold}Examples:$_reset
  dart run flutter_js_bridger init
  dart run flutter_js_bridger add lodash
  dart run flutter_js_bridger add axios@^1.6.0
  dart run flutter_js_bridger install
  dart run flutter_js_bridger list
  dart run flutter_js_bridger check
''');
}
