/// Declarative npm dependency manifest (`js_bridger.json`).
///
/// Declares which npm packages the project needs, their versions,
/// and the working directory — so packages are managed via CLI
/// at development time rather than installed at runtime.
///
/// ```json
/// {
///   "version": "1.0.0",
///   "node": ">=16.0.0",
///   "working_directory": ".js_runtime",
///   "dependencies": {
///     "lodash": "^4.17.21",
///     "axios": "^1.6.0"
///   }
/// }
/// ```
library;

import 'dart:convert';
import 'dart:io';

/// Represents a `js_bridger.json` manifest file.
///
/// Use [load] to read an existing manifest, or [create] to start fresh.
/// After modifying [dependencies], call [save] to persist changes.
class JsBridgerManifest {
  /// Default manifest filename.
  static const String defaultFileName = 'js_bridger.json';

  /// Manifest schema version.
  String version;

  /// Required Node.js version constraint (e.g., `">=16.0.0"`).
  String nodeVersion;

  /// Working directory for `node_modules` and the worker script.
  String workingDirectory;

  /// npm dependencies — package name → version constraint.
  ///
  /// Version strings follow npm semver conventions:
  /// - `"^4.17.21"` — compatible with 4.17.21
  /// - `"~2.0.0"` — approximately 2.0.0
  /// - `"*"` or `"latest"` — any version
  /// - `"1.2.3"` — exact version
  final Map<String, String> dependencies;

  /// Absolute or relative path to the manifest file on disk.
  final String filePath;

  JsBridgerManifest._({
    required this.version,
    required this.nodeVersion,
    required this.workingDirectory,
    required this.dependencies,
    required this.filePath,
  });

  /// Load a manifest from [path]. Returns `null` if the file doesn't exist.
  static JsBridgerManifest? load(String path) {
    final file = File(path);
    if (!file.existsSync()) return null;

    final content = file.readAsStringSync();
    final json = jsonDecode(content) as Map<String, dynamic>;

    final deps = <String, String>{};
    final rawDeps = json['dependencies'] as Map<String, dynamic>?;
    if (rawDeps != null) {
      for (final entry in rawDeps.entries) {
        deps[entry.key] = entry.value.toString();
      }
    }

    return JsBridgerManifest._(
      version: (json['version'] as String?) ?? '1.0.0',
      nodeVersion: (json['node'] as String?) ?? '>=16.0.0',
      workingDirectory: (json['working_directory'] as String?) ?? '.js_runtime',
      dependencies: deps,
      filePath: path,
    );
  }

  /// Create a new empty manifest at [path].
  factory JsBridgerManifest.create(
    String path, {
    String workingDirectory = '.js_runtime',
  }) {
    return JsBridgerManifest._(
      version: '1.0.0',
      nodeVersion: '>=16.0.0',
      workingDirectory: workingDirectory,
      dependencies: {},
      filePath: path,
    );
  }

  /// Save the manifest to disk (sorted dependencies).
  void save() {
    final sorted = Map.fromEntries(
      dependencies.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    final data = <String, dynamic>{
      'version': version,
      'node': nodeVersion,
      'working_directory': workingDirectory,
      'dependencies': sorted,
    };
    final dir = File(filePath).parent;
    if (!dir.existsSync()) dir.createSync(recursive: true);
    File(filePath).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(data)}\n',
    );
  }

  /// Add or update a dependency.
  void addDependency(String name, [String version = 'latest']) {
    dependencies[name] = version;
  }

  /// Remove a dependency. Returns `true` if it was present.
  bool removeDependency(String name) {
    return dependencies.remove(name) != null;
  }

  /// Whether a dependency is declared.
  bool hasDependency(String name) => dependencies.containsKey(name);
}
