import 'dart:convert';

import 'package:flutter_js_bridger/flutter_js_bridger.dart';
import 'package:test/test.dart';

import '../helpers/npm_test_helper.dart';

/// Tests for axios and node-fetch — HTTP client libraries.
///
/// Uses Dart-native proxy API:
///   - `axios.get(url, options)`, `axios.post(url, data)` — async calls, read properties
///   - `fetch(url, options)` → `res.json()` → property access
///   - Error handling / interceptors use eval (require JS try-catch or sync closures)
void main() {
  late JsBridge js;

  setUpAll(() async {
    js = await createNpmTestBridge();
    await ensureAllInstalled(js, ['axios', 'node-fetch@2']);
  });

  tearDownAll(() async {
    await js.dispose();
  });

  // ─── axios ─────────────────────────────────────────────────

  group('axios', () {
    test('require axios', () async {
      final dynamic axios = await js.require('axios');
      expect(axios, isNotNull);
      expect(axios, isA<JsObject>());
    });

    test('GET request — httpbin', () async {
      final dynamic axios = await js.require('axios');
      dynamic res = await axios.get('https://httpbin.org/get', {
        'params': {'test': 'bridger'}
      });
      final status = await res.status;
      expect(status, equals(200));
      dynamic data = await res.data;
      dynamic args = await data.args;
      final testParam = await args.test;
      expect(testParam, equals('bridger'));
    });

    test('POST request', () async {
      final dynamic axios = await js.require('axios');
      dynamic res = await axios.post('https://httpbin.org/post', {
        'name': 'bridger',
        'version': '2.0',
      });
      final status = await res.status;
      expect(status, equals(200));
      dynamic data = await res.data;
      // httpbin echoes the sent body in data.data as a JSON string
      final sentRaw = await data.data as String;
      final sent = jsonDecode(sentRaw);
      expect(sent['name'], equals('bridger'));
    });

    test('PUT request', () async {
      final dynamic axios = await js.require('axios');
      dynamic res =
          await axios.put('https://httpbin.org/put', {'updated': true});
      final status = await res.status;
      expect(status, equals(200));
    });

    test('DELETE request', () async {
      final dynamic axios = await js.require('axios');
      dynamic res = await axios.delete('https://httpbin.org/delete');
      final status = await res.status;
      expect(status, equals(200));
    });

    test('custom headers', () async {
      final dynamic axios = await js.require('axios');
      dynamic res = await axios.get('https://httpbin.org/headers', {
        'headers': {
          'X-Custom-Header': 'BridgerTest',
          'Accept': 'application/json',
        }
      });
      dynamic data = await res.data;
      dynamic headers = await data.headers;
      final customHeader = await headers.$get('X-Custom-Header');
      expect(customHeader, equals('BridgerTest'));
    });

    test('error handling — 404', () async {
      final dynamic axios = await js.require('axios');
      try {
        await axios.get('https://httpbin.org/status/404');
        fail('Expected error for 404');
      } catch (e) {
        expect(e.toString(), contains('404'));
      }
    });

    test('axios.create — instance with defaults', () async {
      final dynamic axios = await js.require('axios');
      dynamic client = await axios.create({
        'baseURL': 'https://httpbin.org',
        'timeout': 10000,
        'headers': {'X-Instance': 'test'},
      });
      dynamic res = await client.get('/headers');
      final status = await res.status;
      expect(status, equals(200));
      dynamic data = await res.data;
      dynamic headers = await data.headers;
      final instanceHeader = await headers.$get('X-Instance');
      expect(instanceHeader, equals('test'));
    });

    test('concurrent requests with Future.wait', () async {
      final dynamic axios = await js.require('axios');
      final results = await Future.wait([
        axios.get('https://httpbin.org/get?q=1') as Future,
        axios.get('https://httpbin.org/get?q=2') as Future,
      ]);
      final s1 = await (results[0] as dynamic).status;
      final s2 = await (results[1] as dynamic).status;
      expect(s1, equals(200));
      expect(s2, equals(200));
    });

    test('response interceptors concept', () async {
      final dynamic axios = await js.require('axios');
      dynamic client = await axios.create({});

      await js.setGlobal('__intercepted', false);
      final interceptFn = await js.createFunction(
        params: ['response'],
        body: 'globalThis.__intercepted = true; return response;',
      );
      dynamic interceptors = await client.interceptors;
      dynamic responseInterceptors = await interceptors.response;
      await responseInterceptors.use(interceptFn);

      await client.get('https://httpbin.org/get');
      final intercepted = await js.getGlobal('__intercepted');
      expect(intercepted, isTrue);
    });
  });

  // ─── node-fetch ────────────────────────────────────────────

  group('node-fetch', () {
    test('require node-fetch', () async {
      final dynamic fetch = await js.require('node-fetch');
      expect(fetch, isNotNull);
    });

    test('GET request', () async {
      final dynamic fetch = await js.require('node-fetch');
      dynamic res = await fetch('https://httpbin.org/get');
      final status = await res.status;
      expect(status, equals(200));
      dynamic data = await res.json();
      final url = await data.url;
      expect(url, isNotNull);
    });

    test('POST request with JSON body', () async {
      final dynamic fetch = await js.require('node-fetch');
      dynamic res = await fetch('https://httpbin.org/post', {
        'method': 'POST',
        'headers': {'Content-Type': 'application/json'},
        'body': jsonEncode({'hello': 'world'}),
      });
      final status = await res.status;
      expect(status, equals(200));
      dynamic data = await res.json();
      final sentRaw = await data.data as String;
      final sent = jsonDecode(sentRaw);
      expect(sent['hello'], equals('world'));
    });

    test('response headers', () async {
      final dynamic fetch = await js.require('node-fetch');
      dynamic res =
          await fetch('https://httpbin.org/response-headers?X-Test=hello');
      dynamic headers = await res.headers;
      final testHeader = await headers.get('x-test');
      expect(testHeader, equals('hello'));
    });

    test('response text', () async {
      final dynamic fetch = await js.require('node-fetch');
      dynamic res = await fetch('https://httpbin.org/html');
      final text = await res.text() as String;
      expect(
          text.contains('<html') ||
              text.contains('<!DOCTYPE') ||
              text.contains('<h1'),
          isTrue);
    });
  });
}
