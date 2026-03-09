/// Shared test utilities for npm package integration tests.
///
/// Provides a common setup/teardown pattern and a shared JsBridge instance
/// with a working directory that persists across all test suites that use it.
library;

import 'dart:io';

import 'package:flutter_js_bridger/flutter_js_bridger.dart';

/// Shared working directory for npm package tests.
final String npmTestWorkDir =
    '${Directory.current.path}${Platform.pathSeparator}.test_npm_packages';

/// Create and initialize a JsBridge for npm package testing.
///
/// Uses a shared working directory so packages installed in one test
/// are available to subsequent tests without reinstalling.
Future<JsBridge> createNpmTestBridge() async {
  final js = JsBridge(JsBridgeConfig(
    workingDirectory: npmTestWorkDir,
    manifestPath: '',
    requestTimeout: 120000, // 2 min — some npm operations are slow
  ));
  await js.initialize();
  return js;
}

/// Install a package if not already installed.
Future<void> ensureInstalled(JsBridge js, String package) async {
  if (!await js.isInstalled(package)) {
    await js.install(package);
  }
}

/// Install multiple packages if not already installed.
Future<void> ensureAllInstalled(JsBridge js, List<String> packages) async {
  final toInstall = <String>[];
  for (final pkg in packages) {
    if (!await js.isInstalled(pkg)) {
      toInstall.add(pkg);
    }
  }
  if (toInstall.isNotEmpty) {
    await js.installAll(toInstall);
  }
}
