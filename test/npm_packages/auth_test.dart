import 'dart:convert';

import 'package:flutter_js_bridger/flutter_js_bridger.dart';
import 'package:test/test.dart';

import '../helpers/npm_test_helper.dart';

/// Tests for jsonwebtoken and bcryptjs — all via Dart-native proxy API.
///
/// Demonstrates calling auth libraries as if they were Dart libraries:
///   - `jwt.sign(payload, secret)` — create JWT tokens
///   - `jwt.verify(token, secret)` — verify and decode
///   - `bcrypt.hashSync(password, rounds)` — hash passwords
///   - `bcrypt.compareSync(password, hash)` — verify passwords
void main() {
  late JsBridge js;
  late dynamic jwt;
  late dynamic bcrypt;

  setUpAll(() async {
    js = await createNpmTestBridge();
    await ensureAllInstalled(js, ['jsonwebtoken', 'bcryptjs']);
    jwt = await js.require('jsonwebtoken');
    bcrypt = await js.require('bcryptjs');
  });

  tearDownAll(() async {
    await js.dispose();
  });

  // ─── jsonwebtoken ──────────────────────────────────────────

  group('jsonwebtoken — Dart-native proxy API', () {
    test('require jsonwebtoken — callable', () async {
      expect(jwt, isNotNull);
      final hasSign = await jwt.$has('sign');
      final hasVerify = await jwt.$has('verify');
      final hasDecode = await jwt.$has('decode');
      expect(hasSign, isTrue);
      expect(hasVerify, isTrue);
      expect(hasDecode, isTrue);
    });

    test('sign a token — returns string', () async {
      final token =
          await jwt.sign({'userId': 123, 'role': 'admin'}, 'my-secret-key');
      expect(token, isA<String>());
      expect((token as String).split('.').length, equals(3)); // JWT has 3 parts
    });

    test('sign and verify token', () async {
      final secret = 'test-secret-key-123';
      final token = await jwt.sign(
        {'userId': 42, 'role': 'admin'},
        secret,
        {'expiresIn': '1h'},
      );
      dynamic decoded = await jwt.verify(token, secret);
      final userId = await decoded.userId;
      final role = await decoded.role;
      expect(userId, equals(42));
      expect(role, equals('admin'));
    });

    test('verify with wrong secret throws', () async {
      final token = await jwt.sign({'data': 'test'}, 'correct-secret');
      try {
        await jwt.verify(token, 'wrong-secret');
        fail('Should have thrown');
      } catch (e) {
        expect(e.toString(), contains('invalid signature'));
      }
    });

    test('decode without verification', () async {
      final token = await jwt.sign({'userId': 99, 'name': 'Bob'}, 'secret');
      dynamic decoded = await jwt.decode(token);
      final userId = await decoded.userId;
      final name = await decoded.name;
      expect(userId, equals(99));
      expect(name, equals('Bob'));
    });

    test('token with custom expiration has exp and iat', () async {
      final token =
          await jwt.sign({'data': 'test'}, 'secret', {'expiresIn': '2h'});
      dynamic decoded = await jwt.decode(token);
      final exp = await decoded.exp;
      final iat = await decoded.iat;
      expect(exp, isNotNull);
      expect(iat, isNotNull);
      expect(exp, isA<num>());
    });

    test('expired token throws TokenExpiredError', () async {
      final token =
          await jwt.sign({'data': 'test'}, 'secret', {'expiresIn': '0s'});
      // Wait for token to expire
      await Future.delayed(const Duration(milliseconds: 1100));
      try {
        await jwt.verify(token, 'secret');
        fail('Should have thrown');
      } catch (e) {
        expect(e.toString(), contains('TokenExpiredError'));
      }
    });

    test('token with HS384 algorithm', () async {
      final token =
          await jwt.sign({'sub': '123'}, 'secret', {'algorithm': 'HS384'});
      dynamic decoded = await jwt.decode(token, {'complete': true});
      dynamic header = await decoded.header;
      final alg = await header.alg;
      expect(alg, equals('HS384'));
    });

    test('token with nested objects', () async {
      final secret = 'nested-test';
      final payload = {
        'user': {'id': 1, 'name': 'Test'},
        'permissions': ['read', 'write'],
        'metadata': {'created': '2024-01-01'},
      };
      final token = await jwt.sign(payload, secret);
      dynamic decoded = await jwt.verify(token, secret);

      dynamic user = await decoded.user;
      final userName = await user.name;
      expect(userName, equals('Test'));

      final perms = await decoded.permissions;
      // Small arrays may come as Dart List directly
      if (perms is List) {
        expect(perms.length, equals(2));
      } else {
        final permsJson = await (perms as JsObject).$toJson();
        final permsList = jsonDecode(permsJson) as List<dynamic>;
        expect(permsList.length, equals(2));
      }

      dynamic meta = await decoded.metadata;
      final created = await meta.created;
      expect(created, equals('2024-01-01'));
    });
  });

  // ─── bcryptjs ──────────────────────────────────────────────

  group('bcryptjs — Dart-native proxy API', () {
    test('require bcryptjs — has expected methods', () async {
      expect(bcrypt, isNotNull);
      final hasHashSync = await bcrypt.$has('hashSync');
      final hasCompareSync = await bcrypt.$has('compareSync');
      expect(hasHashSync, isTrue);
      expect(hasCompareSync, isTrue);
    });

    test('hash a password (sync)', () async {
      final hash = await bcrypt.hashSync('myPassword123', 10);
      expect(hash, isA<String>());
    });

    test('hash starts with bcrypt prefix', () async {
      final hash = await bcrypt.hashSync('test', 10);
      expect(hash as String, anyOf(startsWith('\$2a\$'), startsWith('\$2b\$')));
    });

    test('compare correct password', () async {
      final hash = await bcrypt.hashSync('correctPassword', 10);
      final result = await bcrypt.compareSync('correctPassword', hash);
      expect(result, isTrue);
    });

    test('compare wrong password', () async {
      final hash = await bcrypt.hashSync('correctPassword', 10);
      final result = await bcrypt.compareSync('wrongPassword', hash);
      expect(result, isFalse);
    });

    test('hash async', () async {
      final hash = await bcrypt.hash('asyncPassword', 10);
      final match = await bcrypt.compare('asyncPassword', hash);
      expect(hash, isA<String>());
      expect(match, isTrue);
    });

    test('genSaltSync', () async {
      final salt = await bcrypt.genSaltSync(12);
      expect(salt, isA<String>());
    });

    test('getRounds — extract cost factor', () async {
      final hash = await bcrypt.hashSync('test', 12);
      final rounds = await bcrypt.getRounds(hash);
      expect(rounds, equals(12));
    });

    test('different passwords produce different hashes', () async {
      final h1 = await bcrypt.hashSync('password1', 10);
      final h2 = await bcrypt.hashSync('password2', 10);
      expect(h1, isNot(equals(h2)));
    });
  });
}
