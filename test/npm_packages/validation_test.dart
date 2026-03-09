import 'dart:convert';

import 'package:flutter_js_bridger/flutter_js_bridger.dart';
import 'package:test/test.dart';

import '../helpers/npm_test_helper.dart';

/// Tests for Zod, Joi, and Yup — schema validation libraries.
///
/// Uses Dart-native proxy API for chained builder patterns:
///   - `z.string().min(3).parse('hello')` — method chaining via proxy
///   - `Joi.string().email().validate(...)` — chained schema building + validation
///   - `yup.string().required().isValid(...)` — async validation
///
/// Some tests use eval for complex patterns:
///   - JS regex constructors (`new RegExp(...)`) for Joi patterns
///   - Joi `.when()` with `is/then/otherwise` (complex JS object structure)
void main() {
  late JsBridge js;

  setUpAll(() async {
    js = await createNpmTestBridge();
    await ensureAllInstalled(js, ['zod', 'joi', 'yup']);
  });

  tearDownAll(() async {
    await js.dispose();
  });

  // ─── Zod ───────────────────────────────────────────────────

  group('Zod', () {
    test('require zod', () async {
      final dynamic zod = await js.require('zod');
      expect(zod, isNotNull);
      expect(zod, isA<JsObject>());
    });

    test('string schema — parse valid', () async {
      final dynamic zod = await js.require('zod');
      dynamic z = await zod.$get('z');
      dynamic schema = await z.string();
      final result = await schema.parse('hello');
      expect(result, equals('hello'));
    });

    test('number schema — parse valid', () async {
      final dynamic zod = await js.require('zod');
      dynamic z = await zod.$get('z');
      dynamic schema = await z.number();
      final result = await schema.parse(42);
      expect(result, equals(42));
    });

    test('string validation — safeParse invalid', () async {
      final dynamic zod = await js.require('zod');
      dynamic z = await zod.$get('z');
      dynamic schema = await z.string();
      dynamic r = await schema.safeParse(123);
      final success = await r.success;
      expect(success, isFalse);
    });

    test('object schema', () async {
      final dynamic zod = await js.require('zod');
      dynamic z = await zod.$get('z');
      dynamic nameField = await z.string();
      dynamic ageField = await (await z.number()).min(0);
      ageField = await ageField.max(150);
      dynamic emailField = await (await z.string()).email();
      dynamic schema = await z.object({
        'name': nameField,
        'age': ageField,
        'email': emailField,
      });
      dynamic r = await schema.safeParse({
        'name': 'John',
        'age': 30,
        'email': 'john@example.com',
      });
      final success = await r.success;
      expect(success, isTrue);
    });

    test('object schema — invalid data', () async {
      final dynamic zod = await js.require('zod');
      dynamic z = await zod.$get('z');
      dynamic nameField = await z.string();
      dynamic ageField = await (await z.number()).min(0);
      dynamic emailField = await (await z.string()).email();
      dynamic schema = await z.object({
        'name': nameField,
        'age': ageField,
        'email': emailField,
      });
      dynamic r = await schema.safeParse({
        'name': 'John',
        'age': -5,
        'email': 'not-an-email',
      });
      final success = await r.success;
      expect(success, isFalse);
    });

    test('enum schema', () async {
      final dynamic zod = await js.require('zod');
      dynamic z = await zod.$get('z');
      // z.enum() — 'enum' is a keyword, access via $get + $call
      dynamic enumFn = await z.$get('enum');
      dynamic schema = await enumFn.$invoke([
        ['red', 'green', 'blue']
      ]);
      final result = await schema.parse('red');
      expect(result, equals('red'));
    });

    test('array schema', () async {
      final dynamic zod = await js.require('zod');
      dynamic z = await zod.$get('z');
      dynamic numSchema = await z.number();
      dynamic schema = await z.array(numSchema);
      dynamic r = await schema.safeParse([1, 2, 3]);
      final success = await r.success;
      expect(success, isTrue);
    });

    test('transform / coerce', () async {
      final dynamic zod = await js.require('zod');
      dynamic z = await zod.$get('z');
      dynamic coerce = await z.coerce;
      dynamic schema = await coerce.number();
      final result = await schema.parse('42');
      expect(result, equals(42));
    });

    test('optional and default', () async {
      final dynamic zod = await js.require('zod');
      dynamic z = await zod.$get('z');
      dynamic nameField = await z.string();
      dynamic roleField = await (await z.string()).$call('default', ['user']);
      dynamic schema = await z.object({
        'name': nameField,
        'role': roleField,
      });
      dynamic parsed = await schema.parse({'name': 'Alice'});
      final json = await parsed.$toJson();
      final data = jsonDecode(json as String);
      expect(data['name'], equals('Alice'));
      expect(data['role'], equals('user'));
    });

    test('union type', () async {
      final dynamic zod = await js.require('zod');
      dynamic z = await zod.$get('z');
      dynamic strSchema = await z.string();
      dynamic numSchema = await z.number();
      dynamic schema = await z.union([strSchema, numSchema]);
      dynamic r1 = await schema.safeParse('hello');
      dynamic r2 = await schema.safeParse(42);
      dynamic r3 = await schema.safeParse(true);
      expect(await r1.success, isTrue);
      expect(await r2.success, isTrue);
      expect(await r3.success, isFalse);
    });
  });

  // ─── Joi ───────────────────────────────────────────────────

  group('Joi', () {
    test('require joi', () async {
      final dynamic joi = await js.require('joi');
      expect(joi, isNotNull);
      expect(joi, isA<JsObject>());
    });

    test('string validation', () async {
      final dynamic Joi = await js.require('joi');
      dynamic schema = await (await (await Joi.string()).min(3)).max(30);
      dynamic result = await schema.validate('hello');
      final error = await result.error;
      final value = await result.value;
      expect(error, isNull);
      expect(value, equals('hello'));
    });

    test('string validation — too short', () async {
      final dynamic Joi = await js.require('joi');
      dynamic schema = await (await (await Joi.string()).min(3)).max(30);
      dynamic result = await schema.validate('ab');
      final error = await result.error;
      expect(error, isNotNull);
    });

    test('object schema validation', () async {
      final dynamic Joi = await js.require('joi');
      final RegExpCtor = await js.getGlobal('RegExp');
      final regex = await RegExpCtor.$new(['^[a-zA-Z0-9]{3,30}\$']);

      dynamic username =
          await (await (await (await Joi.string()).alphanum()).min(3)).max(30);
      username = await username.required();
      dynamic password = await (await Joi.string()).pattern(regex);
      dynamic age = await (await (await Joi.number()).integer()).min(0);
      age = await age.max(150);
      dynamic schema = await Joi.object({
        'username': username,
        'password': password,
        'age': age,
      });

      dynamic result = await schema.validate({
        'username': 'john123',
        'password': 'secret123',
        'age': 25,
      });
      expect(await result.error, isNull);
    });

    test('number validation', () async {
      final dynamic Joi = await js.require('joi');
      dynamic schema = await (await (await Joi.number()).min(1)).max(100);
      dynamic r1 = await schema.validate(50);
      dynamic r2 = await schema.validate(200);
      final err1 = await r1.error;
      final err2 = await r2.error;
      expect(err1, isNull);
      expect(err2, isNotNull);
    });

    test('email validation', () async {
      final dynamic Joi = await js.require('joi');
      dynamic schema = await (await Joi.string()).email();
      dynamic r1 = await schema.validate('test@example.com');
      dynamic r2 = await schema.validate('not-an-email');
      expect(await r1.error, isNull);
      expect(await r2.error, isNotNull);
    });

    test('array validation', () async {
      final dynamic Joi = await js.require('joi');
      dynamic numItem = await Joi.number();
      dynamic schema =
          await (await (await (await Joi.array()).items(numItem)).min(1))
              .max(5);
      dynamic r1 = await schema.validate([1, 2, 3]);
      dynamic r2 = await schema.validate([]);
      expect(await r1.error, isNull);
      expect(await r2.error, isNotNull);
    });

    test('date validation', () async {
      final dynamic Joi = await js.require('joi');
      dynamic schema =
          await (await (await Joi.date()).min('2024-01-01')).max('2025-12-31');
      dynamic r = await schema.validate('2024-06-15');
      expect(await r.error, isNull);
    });

    test('conditional (when)', () async {
      final dynamic Joi = await js.require('joi');
      final RegExpCtor = await js.getGlobal('RegExp');
      final phoneRegex = await RegExpCtor.$new(['^\\d{10}\$']);

      dynamic typeSchema =
          await (await (await Joi.string()).valid('email', 'phone')).required();
      dynamic emailSchema =
          await (await (await Joi.string()).email()).required();
      dynamic phoneSchema =
          await (await (await Joi.string()).pattern(phoneRegex)).required();

      dynamic contactSchema = await Joi.when('type', {
        'is': 'email',
        'then': emailSchema,
        'otherwise': phoneSchema,
      });
      dynamic schema = await Joi.object({
        'type': typeSchema,
        'contact': contactSchema,
      });

      dynamic emailResult =
          await schema.validate({'type': 'email', 'contact': 'a@b.com'});
      expect(await emailResult.error, isNull);

      dynamic phoneResult =
          await schema.validate({'type': 'phone', 'contact': '1234567890'});
      expect(await phoneResult.error, isNull);
    });
  });

  // ─── Yup ───────────────────────────────────────────────────

  group('Yup', () {
    test('require yup', () async {
      final dynamic yup = await js.require('yup');
      expect(yup, isNotNull);
      expect(yup, isA<JsObject>());
    });

    test('string validation', () async {
      final dynamic yup = await js.require('yup');
      dynamic schema = await (await (await yup.string()).required()).min(3);
      final valid = await schema.isValid('hello');
      expect(valid, isTrue);
    });

    test('string validation — too short', () async {
      final dynamic yup = await js.require('yup');
      dynamic schema = await (await yup.string()).min(5);
      final valid = await schema.isValid('hi');
      expect(valid, isFalse);
    });

    test('object schema', () async {
      final dynamic yup = await js.require('yup');
      dynamic nameField = await (await yup.string()).required();
      dynamic ageField =
          await (await (await yup.number()).positive()).integer();
      ageField = await ageField.required();
      dynamic emailField = await (await yup.string()).email();
      dynamic schema = await yup.object({
        'name': nameField,
        'age': ageField,
        'email': emailField,
      });
      final valid = await schema.isValid({
        'name': 'Alice',
        'age': 30,
        'email': 'alice@example.com',
      });
      expect(valid, isTrue);
    });

    test('object schema — invalid', () async {
      final dynamic yup = await js.require('yup');
      dynamic nameField = await (await yup.string()).required();
      dynamic ageField = await (await yup.number()).positive();
      dynamic schema = await yup.object({
        'name': nameField,
        'age': ageField,
      });
      final valid = await schema.isValid({'name': '', 'age': -5});
      expect(valid, isFalse);
    });

    test('cast / transform', () async {
      final dynamic yup = await js.require('yup');
      dynamic schema = await yup.number();
      final result = await schema.cast('42');
      expect(result, equals(42));
    });

    test('array validation', () async {
      final dynamic yup = await js.require('yup');
      dynamic numPositive = await (await yup.number()).positive();
      dynamic schema = await (await (await yup.array()).of(numPositive)).min(1);
      final valid = await schema.isValid([1, 2, 3]);
      final invalid = await schema.isValid([1, -2, 3]);
      expect(valid, isTrue);
      expect(invalid, isFalse);
    });
  });
}
