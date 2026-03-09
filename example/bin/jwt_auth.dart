// ignore_for_file: avoid_print
import 'package:flutter_js_bridger/flutter_js_bridger.dart';

/// ═══════════════════════════════════════════════════════════════
///  JWT Authentication & Password Hashing — from Dart
/// ═══════════════════════════════════════════════════════════════
///
/// This example demonstrates a complete auth workflow using
/// jsonwebtoken + bcryptjs — entirely from Dart with zero JS code.
///
/// What you'll see:
///   1. Hash passwords with bcryptjs (like bcrypt in Node.js)
///   2. Verify passwords against hashes
///   3. Create JWT tokens with jsonwebtoken
///   4. Verify and decode JWT tokens
///   5. Handle expired and invalid tokens
///   6. Simulate a full login/register flow
///
/// Setup:
///   dart run flutter_js_bridger init
///   dart run flutter_js_bridger add jsonwebtoken bcryptjs
///
/// Run:
///   dart run example/bin/jwt_auth.dart
void main() async {
  final js = JsBridge();

  try {
    await js.initialize();
    print('🔐 flutter_js_bridger — JWT Auth Example\n');

    // ──────────────────────────────────────────────────
    //  Step 1: Import the auth packages
    // ──────────────────────────────────────────────────
    print('Step 1: Importing auth packages...');
    dynamic jwt = await js.require('jsonwebtoken');
    dynamic bcrypt = await js.require('bcryptjs');
    print('  ✓ jsonwebtoken imported');
    print('  ✓ bcryptjs imported');

    // ──────────────────────────────────────────────────
    //  Step 2: Password hashing — register a user
    // ──────────────────────────────────────────────────
    print('\nStep 2: Hashing passwords...');

    const password = 'MySecretP@ss123';
    final hash = await bcrypt.hashSync(password, 10) as String;
    print('  Password:  "$password"');
    print('  Hash:      "${hash.substring(0, 30)}..."');
    print('  Hash algo: ${hash.substring(0, 4)} (bcrypt)');

    // Verify correct password
    final correctMatch = await bcrypt.compareSync(password, hash);
    print('  Verify correct password: $correctMatch ✓');

    // Verify wrong password
    final wrongMatch = await bcrypt.compareSync('wrong-password', hash);
    print('  Verify wrong password:   $wrongMatch ✗');

    // ──────────────────────────────────────────────────
    //  Step 3: Create a JWT token — like after login
    // ──────────────────────────────────────────────────
    print('\nStep 3: Creating JWT tokens...');

    const secret = 'my-app-secret-key-2024';
    final token = await jwt.sign(
      {
        'userId': 42,
        'email': 'alice@example.com',
        'role': 'admin',
      },
      secret,
      {'expiresIn': '1h'},
    ) as String;

    print('  Payload: {userId: 42, email: alice@example.com, role: admin}');
    print('  Token:   ${token.substring(0, 40)}...');
    print('  Parts:   ${token.split('.').length} (header.payload.signature)');

    // ──────────────────────────────────────────────────
    //  Step 4: Verify and decode the token
    // ──────────────────────────────────────────────────
    print('\nStep 4: Verifying JWT token...');

    dynamic decoded = await jwt.verify(token, secret);
    final userId = await decoded.userId;
    final email = await decoded.email;
    final role = await decoded.role;
    final exp = await decoded.exp;
    final iat = await decoded.iat;

    print('  ✓ Token verified successfully');
    print('  Decoded payload:');
    print('    userId: $userId');
    print('    email:  $email');
    print('    role:   $role');
    print('    iat:    $iat (issued at)');
    print('    exp:    $exp (expires at)');

    // ──────────────────────────────────────────────────
    //  Step 5: Decode without verification
    // ──────────────────────────────────────────────────
    print('\nStep 5: Decoding without verification...');

    dynamic rawDecoded = await jwt.decode(token, {'complete': true});
    dynamic header = await rawDecoded.header;
    final alg = await header.alg;
    final typ = await header.typ;
    print('  Header: {alg: $alg, typ: $typ}');

    // ──────────────────────────────────────────────────
    //  Step 6: Handle invalid tokens
    // ──────────────────────────────────────────────────
    print('\nStep 6: Error handling...');

    // Wrong secret
    try {
      await jwt.verify(token, 'wrong-secret');
      print('  Wrong secret: Should not reach here');
    } catch (e) {
      print('  ✓ Wrong secret rejected: ${e.toString().split('\n').first}');
    }

    // Expired token
    final expiredToken = await jwt.sign(
      {'data': 'test'},
      secret,
      {'expiresIn': '0s'},
    );
    await Future.delayed(const Duration(milliseconds: 1100));
    try {
      await jwt.verify(expiredToken, secret);
      print('  Expired token: Should not reach here');
    } catch (e) {
      print('  ✓ Expired token rejected: ${e.toString().split('\n').first}');
    }

    // ──────────────────────────────────────────────────
    //  Step 7: Simulate a full register + login flow
    // ──────────────────────────────────────────────────
    print('\nStep 7: Full auth flow simulation...\n');

    // "Database" of users (Dart Map)
    final users = <String, Map<String, dynamic>>{};

    // --- Register ---
    print('  📝 Register user "alice@example.com"...');
    final regPassword = 'SuperSecret123!';
    final regHash = await bcrypt.hashSync(regPassword, 10) as String;
    users['alice@example.com'] = {
      'id': 1,
      'email': 'alice@example.com',
      'passwordHash': regHash,
      'role': 'user',
    };
    print('     ✓ User registered (password hashed with bcrypt)');

    // --- Login ---
    print('\n  🔑 Login as "alice@example.com"...');
    final loginEmail = 'alice@example.com';
    final loginPassword = 'SuperSecret123!';

    final user = users[loginEmail];
    if (user == null) {
      print('     ✗ User not found');
    } else {
      final passwordValid = await bcrypt.compareSync(
        loginPassword,
        user['passwordHash'],
      );
      if (passwordValid != true) {
        print('     ✗ Invalid password');
      } else {
        print('     ✓ Password verified');

        // Create access token
        final accessToken = await jwt.sign(
          {'userId': user['id'], 'email': user['email'], 'role': user['role']},
          secret,
          {'expiresIn': '15m'},
        );
        print('     ✓ Access token created (expires in 15m)');

        // Create refresh token
        await jwt.sign(
          {'userId': user['id'], 'type': 'refresh'},
          secret,
          {'expiresIn': '7d'},
        );
        print('     ✓ Refresh token created (expires in 7d)');

        // --- Protected resource ---
        print('\n  🛡️  Accessing protected resource...');
        try {
          dynamic verified = await jwt.verify(accessToken, secret);
          final verifiedRole = await verified.role;
          print('     ✓ Token valid — role: $verifiedRole');
          print('     ✓ Access granted!');
        } catch (e) {
          print('     ✗ Access denied: $e');
        }
      }
    }

    print('\n════════════════════════════════════════════════');
    print(' JWT + bcrypt Auth — all from Dart, zero JS!');
    print('════════════════════════════════════════════════');
  } finally {
    await js.dispose();
  }
}
