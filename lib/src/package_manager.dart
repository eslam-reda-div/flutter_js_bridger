/// npm package manager — install, remove, update, and list npm packages.
///
/// Runs npm commands via [Process.run] in the bridge working directory.
/// Ensures a package.json exists before any operation.
library;

import 'dart:convert';
import 'dart:io';

import 'errors.dart';

/// Manages npm packages in the bridge working directory.
class PackageManager {
  final String _workingDir;

  PackageManager(this._workingDir);

  // ─── Public API ────────────────────────────────────

  /// Install one or more npm packages.
  ///
  /// Supports version specifiers: `'lodash'`, `'lodash@4.17.21'`,
  /// `'axios@^1.0.0'`.
  Future<void> install(List<String> packages) async {
    await _ensurePackageJson();
    final result = await _npm(['install', ...packages]);
    if (result.exitCode != 0) {
      throw JsPackageException(
        JsErrorCode.installFailed,
        'Failed to install ${packages.join(", ")}',
        stderr: result.stderr.toString(),
      );
    }
  }

  /// Remove one or more npm packages.
  Future<void> remove(List<String> packages) async {
    final result = await _npm(['uninstall', ...packages]);
    if (result.exitCode != 0) {
      throw JsPackageException(
        JsErrorCode.removeFailed,
        'Failed to remove ${packages.join(", ")}',
        stderr: result.stderr.toString(),
      );
    }
  }

  /// Update one or more npm packages. If empty, updates all.
  Future<void> update([List<String> packages = const []]) async {
    final result = await _npm(['update', ...packages]);
    if (result.exitCode != 0) {
      throw JsPackageException(
        JsErrorCode.installFailed,
        'Failed to update ${packages.isEmpty ? "all" : packages.join(", ")}',
        stderr: result.stderr.toString(),
      );
    }
  }

  /// List installed packages with their versions.
  ///
  /// Returns a map of `{packageName: version}`.
  Future<Map<String, String>> list() async {
    final result = await _npm(['list', '--json', '--depth=0']);
    if (result.exitCode != 0 && result.stdout.toString().trim().isEmpty) {
      return {};
    }
    try {
      final json = jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
      final deps = json['dependencies'] as Map<String, dynamic>? ?? {};
      return deps.map(
        (key, value) => MapEntry(
          key,
          (value as Map<String, dynamic>)['version']?.toString() ?? 'unknown',
        ),
      );
    } catch (_) {
      return {};
    }
  }

  /// Check if a specific package is installed.
  Future<bool> isInstalled(String packageName) async {
    final packages = await list();
    return packages.containsKey(packageName);
  }

  // ─── Fast filesystem-based verification ────────────

  /// Check if a package is installed by inspecting node_modules directly.
  ///
  /// Much faster than running `npm list` — no process spawn needed.
  bool isInstalledSync(String packageName) {
    final pkgJson = File(
      '$_workingDir${Platform.pathSeparator}node_modules'
      '${Platform.pathSeparator}$packageName'
      '${Platform.pathSeparator}package.json',
    );
    return pkgJson.existsSync();
  }

  /// Get the installed version of a package from its package.json.
  ///
  /// Returns `null` if the package is not installed.
  String? getInstalledVersionSync(String packageName) {
    final pkgJson = File(
      '$_workingDir${Platform.pathSeparator}node_modules'
      '${Platform.pathSeparator}$packageName'
      '${Platform.pathSeparator}package.json',
    );
    if (!pkgJson.existsSync()) return null;
    try {
      final json =
          jsonDecode(pkgJson.readAsStringSync()) as Map<String, dynamic>;
      return json['version'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Find which packages from a dependency map are not installed.
  ///
  /// Uses fast filesystem checks — no npm process spawned.
  List<String> findMissingPackages(Map<String, String> required) {
    return required.keys.where((pkg) => !isInstalledSync(pkg)).toList();
  }

  // ─── Private ───────────────────────────────────────

  /// Ensure a package.json exists in the working directory.
  ///
  /// Writes a minimal package.json directly instead of spawning `npm init`.
  Future<void> _ensurePackageJson() async {
    final dir = Directory(_workingDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final file = File('$_workingDir${Platform.pathSeparator}package.json');
    if (!file.existsSync()) {
      file.writeAsStringSync(
        '{"name":"js_runtime","version":"1.0.0","private":true}',
      );
    }
  }

  /// Run an npm command in the working directory.
  ///
  /// Uses `--prefix` to prevent npm from walking up the directory tree
  /// and installing into a parent project's node_modules.
  Future<ProcessResult> _npm(List<String> args) {
    // On Windows, npm is a .cmd file — use runInShell
    return Process.run(
      'npm',
      [...args, '--prefix', _workingDir],
      workingDirectory: _workingDir,
      runInShell: Platform.isWindows,
    );
  }
}
