import 'package:flutter_js_bridger/flutter_js_bridger.dart';
import 'package:test/test.dart';

import '../helpers/npm_test_helper.dart';

/// Tests for commander and inquirer — CLI argument parsing.
///
/// Uses Dart-native proxy API:
///   - Commander: `new Command()` via $new, chained `.name()`, `.option()`, `.parse()`, `.opts()`
///   - Subcommands with `.action()` use createFunction for the capture callback
///   - Inquirer: module loading and API surface checks via proxy
void main() {
  late JsBridge js;

  setUpAll(() async {
    js = await createNpmTestBridge();
    await ensureAllInstalled(js, ['commander', 'inquirer']);
  });

  tearDownAll(() async {
    await js.dispose();
  });

  group('commander', () {
    test('require commander', () async {
      final dynamic commander = await js.require('commander');
      expect(commander, isNotNull);
      expect(commander, isA<JsObject>());
    });

    test('create Command and parse arguments', () async {
      final dynamic commander = await js.require('commander');
      dynamic Command = await commander.$get('Command');
      dynamic program = await Command.$new();
      await program.name('myapp');
      await program.description('A test CLI app');
      await program.version('1.0.0');
      await program.option('-d, --debug', 'enable debug mode');
      await program.option('-p, --port <number>', 'port number', '3000');
      await program.option('-n, --name <string>', 'your name');
      await program.parse(
          ['node', 'myapp', '--debug', '--port', '8080', '--name', 'Alice']);
      dynamic opts = await program.opts();
      final debug = await opts.debug;
      final port = await opts.port;
      final name = await opts.name;
      expect(debug, isTrue);
      expect(port, equals('8080'));
      expect(name, equals('Alice'));
    });

    test('commander subcommands', () async {
      final dynamic commander = await js.require('commander');
      dynamic Command = await commander.$get('Command');
      dynamic program = await Command.$new();

      final actionFn = await js.createFunction(
        params: ['env', 'options'],
        body:
            'globalThis.__capturedArgs = JSON.stringify({ env: env, force: !!options.force });',
      );

      dynamic deploy = await program.command('deploy <env>');
      await deploy.description('Deploy to environment');
      await deploy.option('-f, --force', 'Force deploy');
      await deploy.action(actionFn);

      await program.parse(['node', 'test', 'deploy', 'production', '--force']);
      final result = await js.getGlobal('__capturedArgs');
      expect(result, contains('"env":"production"'));
      expect(result, contains('"force":true'));
    });

    test('commander variadic arguments', () async {
      final dynamic commander = await js.require('commander');
      dynamic Command = await commander.$get('Command');
      dynamic program = await Command.$new();

      final actionFn = await js.createFunction(
        params: ['packages'],
        body:
            'globalThis.__capturedPackages = JSON.stringify({ packages: Array.from(packages) });',
      );

      dynamic install = await program.command('install <packages...>');
      await install.description('Install packages');
      await install.action(actionFn);

      await program
          .parse(['node', 'test', 'install', 'express', 'lodash', 'axios']);
      final result = await js.getGlobal('__capturedPackages');
      expect(result, contains('"packages":["express","lodash","axios"]'));
    });

    test('commander default values', () async {
      final dynamic commander = await js.require('commander');
      dynamic Command = await commander.$get('Command');
      dynamic program = await Command.$new();
      await program.option('-c, --config <path>', 'config file', 'config.json');
      await program.option('-v, --verbose', 'verbose output', false);
      await program.option('-r, --retries <count>', 'retry count', '3');
      await program.parse(['node', 'test']); // No args — use defaults
      dynamic opts = await program.opts();
      final config = await opts.config;
      final verbose = await opts.verbose;
      final retries = await opts.retries;
      expect(config, equals('config.json'));
      expect(verbose, isFalse);
      expect(retries, equals('3'));
    });
  });

  group('inquirer', () {
    test('require inquirer', () async {
      final dynamic inquirer = await js.require('inquirer');
      expect(inquirer, isNotNull);
      expect(inquirer, isA<JsObject>());
    });

    test('inquirer has prompt method', () async {
      final dynamic inquirer = await js.require('inquirer');
      final hasPrompt = await inquirer.$has('prompt');
      final hasCreatePromptModule = await inquirer.$has('createPromptModule');
      expect(hasPrompt == true || hasCreatePromptModule == true, isTrue);
    });

    test('inquirer Separator or ui module available', () async {
      final dynamic inquirer = await js.require('inquirer');
      final hasSeparator = await inquirer.$has('Separator');
      final hasUi = await inquirer.$has('ui');
      final hasCreatePromptModule = await inquirer.$has('createPromptModule');
      expect(
          hasSeparator == true ||
              hasUi == true ||
              hasCreatePromptModule == true,
          isTrue);
    });
  });
}
