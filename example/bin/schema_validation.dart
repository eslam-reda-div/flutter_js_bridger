// ignore_for_file: avoid_print
import 'package:flutter_js_bridger/flutter_js_bridger.dart';

/// ═══════════════════════════════════════════════════════════════
///  Schema Validation with Zod & Joi — from Dart
/// ═══════════════════════════════════════════════════════════════
///
/// This example demonstrates input validation using popular JS
/// validation libraries — entirely from Dart.
///
/// What you'll see:
///   1. Zod: Type-safe schema validation with method chaining
///   2. Joi: Expressive validation with custom rules
///   3. Validate strings, numbers, emails, objects
///   4. Handle validation errors gracefully
///   5. Practical form validation patterns
///
/// Setup:
///   dart run flutter_js_bridger init
///   dart run flutter_js_bridger add zod joi
///
/// Run:
///   dart run example/bin/schema_validation.dart
void main() async {
  final js = JsBridge();

  try {
    await js.initialize();
    print('✅ flutter_js_bridger — Schema Validation Example\n');

    // ──────────────────────────────────────────────────
    //  Part A: Zod — TypeScript-first Validation
    // ──────────────────────────────────────────────────
    print('════════════════════════');
    print(' Part A: Zod');
    print('════════════════════════\n');

    dynamic zod = await js.require('zod');
    dynamic z = await zod.$get('z');

    // --- String validation ---
    print('1. String Validation:');
    dynamic strSchema = await z.string();

    final valid1 = await strSchema.parse('hello');
    print('   z.string().parse("hello") → "$valid1" ✓');

    dynamic result1 = await strSchema.safeParse(123);
    final success1 = await result1.success;
    print('   z.string().safeParse(123) → success: $success1 ✗');

    // --- Number validation ---
    print('\n2. Number Validation:');
    dynamic numSchema = await z.number();

    final valid2 = await numSchema.parse(42);
    print('   z.number().parse(42) → $valid2 ✓');

    dynamic minSchema = await (await z.number()).min(0);
    minSchema = await minSchema.max(100);
    dynamic result2 = await minSchema.safeParse(50);
    print(
        '   z.number().min(0).max(100).safeParse(50) → success: ${await result2.success} ✓');

    dynamic result3 = await minSchema.safeParse(-5);
    print(
        '   z.number().min(0).max(100).safeParse(-5) → success: ${await result3.success} ✗');

    // --- Email validation ---
    print('\n3. Email Validation:');
    dynamic emailSchema = await (await z.string()).email();

    dynamic emailOk = await emailSchema.safeParse('alice@example.com');
    print(
        '   z.string().email().safeParse("alice@example.com") → success: ${await emailOk.success} ✓');

    dynamic emailBad = await emailSchema.safeParse('not-an-email');
    print(
        '   z.string().email().safeParse("not-an-email") → success: ${await emailBad.success} ✗');

    // --- Object schema ---
    print('\n4. Object Schema:');
    dynamic nameField = await z.string();
    dynamic ageField = await (await z.number()).min(0);
    ageField = await ageField.max(150);
    dynamic emailField = await (await z.string()).email();

    dynamic userSchema = await z.object({
      'name': nameField,
      'age': ageField,
      'email': emailField,
    });

    // Valid data
    dynamic validUser = await userSchema.safeParse({
      'name': 'Alice',
      'age': 28,
      'email': 'alice@example.com',
    });
    print('   Valid user → success: ${await validUser.success} ✓');

    // Invalid data
    dynamic invalidUser = await userSchema.safeParse({
      'name': 'Bob',
      'age': -5,
      'email': 'not-an-email',
    });
    print(
        '   Invalid user (age: -5, bad email) → success: ${await invalidUser.success} ✗');

    // --- Enum ---
    print('\n5. Enum Schema:');
    dynamic enumFn = await z.$get('enum');
    dynamic colorSchema = await enumFn.$invoke([
      ['red', 'green', 'blue']
    ]);

    final red = await colorSchema.parse('red');
    print('   z.enum(["red","green","blue"]).parse("red") → "$red" ✓');

    try {
      await colorSchema.parse('yellow');
      print('   .parse("yellow") → Should not reach here');
    } catch (e) {
      print('   .parse("yellow") → Error: invalid value ✗');
    }

    // ──────────────────────────────────────────────────
    //  Part B: Joi — Expressive Validation
    // ──────────────────────────────────────────────────
    print('\n════════════════════════');
    print(' Part B: Joi');
    print('════════════════════════\n');

    dynamic Joi = await js.require('joi');

    // --- String validation ---
    print('1. String Validation:');
    dynamic joiStr = await (await Joi.string()).min(3);
    joiStr = await joiStr.max(30);

    dynamic r1 = await joiStr.validate('hello');
    print('   Joi.string().min(3).max(30).validate("hello")');
    final v1 = await r1.value;
    final e1 = await r1.error;
    print('     value: "$v1", error: $e1 ✓');

    dynamic r2 = await joiStr.validate('ab');
    final e2 = await r2.error;
    final hasError = e2 != null;
    print('   .validate("ab") → has error: $hasError ✗');

    // --- Number validation ---
    print('\n2. Number Validation:');
    dynamic joiNum = await (await Joi.number()).integer();
    joiNum = await joiNum.min(1);
    joiNum = await joiNum.max(999);

    dynamic r3 = await joiNum.validate(42);
    print('   Joi.number().integer().min(1).max(999).validate(42)');
    print('     value: ${await r3.value}, error: ${await r3.error} ✓');

    // --- Email ---
    print('\n3. Email Validation:');
    dynamic joiEmail = await (await Joi.string()).email();

    dynamic r4 = await joiEmail.validate('test@example.com');
    print('   Joi.string().email().validate("test@example.com")');
    print('     value: "${await r4.value}", error: ${await r4.error} ✓');

    dynamic r5 = await joiEmail.validate('bad-email');
    final e5 = await r5.error;
    print('   .validate("bad-email") → has error: ${e5 != null} ✗');

    // --- Object schema ---
    print('\n4. Object Schema (User Registration):');
    dynamic regSchema = await Joi.object({
      'username': await (await (await Joi.string()).alphanum()).min(3),
      'email': await (await Joi.string()).email(),
      'password': await (await Joi.string()).min(8),
      'age': await (await (await Joi.number()).integer()).min(13),
    });

    // Valid registration
    dynamic validReg = await regSchema.validate({
      'username': 'alice123',
      'email': 'alice@example.com',
      'password': 'strongpassword',
      'age': 25,
    });
    print('   Valid registration:');
    print('     error: ${await validReg.error} ✓');

    // Invalid registration
    dynamic invalidReg = await regSchema.validate({
      'username': 'ab',
      'email': 'not-email',
      'password': 'short',
      'age': 10,
    });
    final regError = await invalidReg.error;
    print('   Invalid registration:');
    print('     has error: ${regError != null} ✗');

    // --- Allowed values ---
    print('\n5. Allowed Values:');
    dynamic roleSchema =
        await (await Joi.string()).valid('admin', 'user', 'moderator');

    dynamic r6 = await roleSchema.validate('admin');
    print(
        '   .valid("admin","user","moderator").validate("admin") → error: ${await r6.error} ✓');

    dynamic r7 = await roleSchema.validate('superuser');
    print(
        '   .validate("superuser") → has error: ${(await r7.error) != null} ✗');

    // ──────────────────────────────────────────────────
    //  Part C: Practical — Form Validation
    // ──────────────────────────────────────────────────
    print('\n════════════════════════════');
    print(' Part C: Form Validation');
    print('════════════════════════════\n');

    // Simulate validating a sign-up form
    final formData = [
      {
        'username': 'alice',
        'email': 'alice@test.com',
        'password': 'Str0ngP@ss!',
        'age': 25
      },
      {'username': 'b', 'email': 'bad', 'password': '123', 'age': 8},
      {
        'username': 'charlie99',
        'email': 'charlie@dev.io',
        'password': 'secure1234',
        'age': 30
      },
      {'username': 'x', 'email': '', 'password': '', 'age': -1},
    ];

    dynamic formSchema = await Joi.object({
      'username': await (await (await Joi.string()).alphanum()).min(3),
      'email': await (await (await Joi.string()).email()).required(),
      'password': await (await (await Joi.string()).min(8)).required(),
      'age': await (await (await Joi.number()).integer()).min(13),
    });

    print('Validating sign-up forms:');
    for (var i = 0; i < formData.length; i++) {
      final form = formData[i];
      dynamic result = await formSchema.validate(form);
      final error = await result.error;
      final isValid = error == null;
      final icon = isValid ? '✓' : '✗';
      print(
          '  Form ${i + 1}: username="${form['username']}", email="${form['email']}"');
      print('    → $icon ${isValid ? "Valid!" : "Invalid"}');
    }

    print('\n══════════════════════════════════════════════════════════');
    print(' Schema Validation — zod + joi from Dart, zero JS!');
    print('══════════════════════════════════════════════════════════');
  } finally {
    await js.dispose();
  }
}
