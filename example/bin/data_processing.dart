// ignore_for_file: avoid_print
import 'package:flutter_js_bridger/flutter_js_bridger.dart';

/// ═══════════════════════════════════════════════════════════════
///  Data Processing with Lodash & Ramda — from Dart
/// ═══════════════════════════════════════════════════════════════
///
/// This example shows how to use powerful JS utility libraries
/// (lodash and ramda) for data transformation — all from Dart.
///
/// What you'll see:
///   1. Array manipulation with lodash (chunk, flatten, groupBy, etc.)
///   2. Object utilities (pick, omit, merge, defaults)
///   3. String helpers (camelCase, snakeCase, kebabCase)
///   4. Functional programming with Ramda (compose, pipe, curry)
///   5. Collection processing pipelines
///
/// Setup:
///   dart run flutter_js_bridger init
///   dart run flutter_js_bridger add lodash ramda
///
/// Run:
///   dart run example/bin/data_processing.dart
void main() async {
  final js = JsBridge();

  try {
    await js.initialize();
    print('📊 flutter_js_bridger — Data Processing Example\n');

    // ──────────────────────────────────────────────────
    //  Part A: Lodash — The Swiss Army Knife
    // ──────────────────────────────────────────────────
    print('════════════════════════');
    print(' Part A: Lodash');
    print('════════════════════════\n');

    dynamic lo = await js.require('lodash');

    // --- Array operations ---
    print('1. Array Operations:');

    final chunks = await lo.chunk([1, 2, 3, 4, 5, 6, 7, 8], 3);
    print('   chunk([1..8], 3) → $chunks');

    final flat = await lo.flatten([
      [1, 2],
      [
        3,
        [4, 5]
      ],
      [6]
    ]);
    print('   flatten([[1,2],[3,[4,5]],[6]]) → $flat');

    final unique = await lo.uniq([1, 2, 2, 3, 3, 3, 4, 4, 4, 4]);
    print('   uniq([1,2,2,3,3,3,4,4,4,4]) → $unique');

    final zipped = await lo.zip(['a', 'b', 'c'], [1, 2, 3]);
    print('   zip(["a","b","c"], [1,2,3]) → $zipped');

    final without = await lo.without([1, 2, 3, 4, 5], 2, 4);
    print('   without([1..5], 2, 4) → $without');

    final compact = await lo.compact([0, 1, false, 2, '', 3, null]);
    print('   compact([0,1,false,2,"",3,null]) → $compact');

    // --- String operations ---
    print('\n2. String Operations:');

    final camel = await lo.camelCase('hello world foo bar');
    print('   camelCase("hello world foo bar") → $camel');

    final snake = await lo.snakeCase('helloWorldFooBar');
    print('   snakeCase("helloWorldFooBar") → $snake');

    final kebab = await lo.kebabCase('Hello World Foo Bar');
    print('   kebabCase("Hello World Foo Bar") → $kebab');

    final capitalized = await lo.capitalize('hello world');
    print('   capitalize("hello world") → $capitalized');

    final truncated =
        await lo.truncate('This is a very long string that needs truncation', {
      'length': 30,
    });
    print('   truncate("This is a very long...") → $truncated');

    // --- Number operations ---
    print('\n3. Number Operations:');

    final clamped = await lo.clamp(15, 0, 10);
    print('   clamp(15, 0, 10) → $clamped');

    final inRange = await lo.inRange(5, 2, 8);
    print('   inRange(5, 2, 8) → $inRange');

    final random = await lo.random(1, 100);
    print('   random(1, 100) → $random');

    // --- Collection operations ---
    print('\n4. Collection Operations:');

    final data = [
      {'name': 'Alice', 'dept': 'Engineering', 'salary': 120000},
      {'name': 'Bob', 'dept': 'Marketing', 'salary': 85000},
      {'name': 'Charlie', 'dept': 'Engineering', 'salary': 110000},
      {'name': 'Diana', 'dept': 'Marketing', 'salary': 90000},
      {'name': 'Eve', 'dept': 'Engineering', 'salary': 130000},
    ];

    await lo.sortBy(data, 'salary');
    print('   sortBy(employees, "salary") → sorted by salary');

    final maxSalary = await lo.maxBy(data, 'salary');
    print('   maxBy(employees, "salary") → $maxSalary');

    final minSalary = await lo.minBy(data, 'salary');
    print('   minBy(employees, "salary") → $minSalary');

    final sum = await lo.sumBy(data, 'salary');
    print('   sumBy(employees, "salary") → \$$sum total');

    // --- Object operations ---
    print('\n5. Object Operations:');

    final user = {
      'name': 'Alice',
      'email': 'a@test.com',
      'age': 28,
      'password': 'secret'
    };

    final picked = await lo.pick(user, ['name', 'email']);
    print('   pick(user, ["name","email"]) → $picked');

    final omitted = await lo.omit(user, ['password']);
    print('   omit(user, ["password"]) → $omitted');

    final merged = await lo.merge({
      'a': 1,
      'b': {'x': 10}
    }, {
      'b': {'y': 20},
      'c': 3
    });
    print('   merge({a:1,b:{x:10}}, {b:{y:20},c:3}) → $merged');

    final defaulted = await lo.defaults({'a': 1}, {'a': 99, 'b': 2});
    print('   defaults({a:1}, {a:99,b:2}) → $defaulted');

    // ──────────────────────────────────────────────────
    //  Part B: Ramda — Functional Programming
    // ──────────────────────────────────────────────────
    print('\n════════════════════════');
    print(' Part B: Ramda (FP)');
    print('════════════════════════\n');

    dynamic R = await js.require('ramda');

    // --- Basic FP ---
    print('1. Functional Basics:');

    final doubled = await R.map(
      await js.createFunction(params: ['x'], body: 'return x * 2'),
      [1, 2, 3, 4, 5],
    );
    print('   map(x => x*2, [1..5]) → $doubled');

    final evens = await R.filter(
      await js.createFunction(params: ['x'], body: 'return x % 2 === 0'),
      [1, 2, 3, 4, 5, 6, 7, 8],
    );
    print('   filter(even, [1..8]) → $evens');

    final total = await R.reduce(
      await js.createFunction(params: ['acc', 'x'], body: 'return acc + x'),
      0,
      [10, 20, 30, 40],
    );
    print('   reduce(sum, 0, [10,20,30,40]) → $total');

    // --- Composition ---
    print('\n2. Function Composition:');

    final doubleFn =
        await js.createFunction(params: ['x'], body: 'return x * 2');
    final addOneFn =
        await js.createFunction(params: ['x'], body: 'return x + 1');

    final composed = await R.compose(doubleFn, addOneFn);
    final composedResult = await composed(5);
    print('   compose(double, addOne)(5) → $composedResult  // (5+1)*2 = 12');

    final piped = await R.pipe(doubleFn, addOneFn);
    final pipedResult = await piped(5);
    print('   pipe(double, addOne)(5)    → $pipedResult  // (5*2)+1 = 11');

    // --- Object manipulation ---
    print('\n3. Object Manipulation:');

    final rPicked = await R
        .pick(['name', 'age'], {'name': 'Bob', 'age': 34, 'secret': '123'});
    print('   pick(["name","age"], obj) → $rPicked');

    final assoc = await R.assoc('role', 'admin', {'name': 'Bob'});
    print('   assoc("role", "admin", {name:"Bob"}) → $assoc');

    final dissoc = await R.dissoc('password', {'name': 'Bob', 'password': 'x'});
    print('   dissoc("password", obj) → $dissoc');

    // --- List operations ---
    print('\n4. List Operations:');

    final head = await R.head([10, 20, 30]);
    print('   head([10,20,30]) → $head');

    final tail = await R.tail([10, 20, 30]);
    print('   tail([10,20,30]) → $tail');

    final reversed = await R.reverse([1, 2, 3, 4, 5]);
    print('   reverse([1..5]) → $reversed');

    final taken = await R.take(3, [1, 2, 3, 4, 5]);
    print('   take(3, [1..5]) → $taken');

    final flattened = await R.flatten([
      1,
      [
        2,
        [
          3,
          [4]
        ],
        5
      ]
    ]);
    print('   flatten([1,[2,[3,[4]],5]]) → $flattened');

    // --- Math ---
    print('\n5. Math:');

    final rSum = await R.sum([1, 2, 3, 4, 5]);
    print('   sum([1..5]) → $rSum');

    final mean = await R.mean([10, 20, 30, 40, 50]);
    print('   mean([10,20,30,40,50]) → $mean');

    final median = await R.median([1, 2, 3, 4, 5]);
    print('   median([1..5]) → $median');

    print('\n══════════════════════════════════════════════════════════');
    print(' Data Processing — lodash + ramda from Dart, zero JS!');
    print('══════════════════════════════════════════════════════════');
  } finally {
    await js.dispose();
  }
}
