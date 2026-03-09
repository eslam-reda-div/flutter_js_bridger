import 'dart:convert';

import 'package:flutter_js_bridger/flutter_js_bridger.dart';
import 'package:test/test.dart';

import '../helpers/npm_test_helper.dart';

/// Tests for database/ORM packages — mongoose, knex, better-sqlite3.
///
/// Uses Dart-native proxy API for module loading and API surface checks.
/// Complex DB operations use createFunction/getGlobal/setGlobal/proxy — zero eval.
void main() {
  late JsBridge js;

  setUpAll(() async {
    js = await createNpmTestBridge();
    await ensureAllInstalled(js, ['mongoose', 'knex', 'better-sqlite3']);
  });

  tearDownAll(() async {
    await js.dispose();
  });

  // ─── mongoose ──────────────────────────────────────────────

  group('mongoose', () {
    test('require mongoose', () async {
      final dynamic mongoose = await js.require('mongoose');
      expect(mongoose, isNotNull);
      expect(mongoose, isA<JsObject>());
    });

    test('mongoose has core API', () async {
      final dynamic mongoose = await js.require('mongoose');
      expect(await mongoose.$has('connect'), isTrue);
      expect(await mongoose.$has('model'), isTrue);
      expect(await mongoose.$has('Schema'), isTrue);
      expect(await mongoose.$has('disconnect'), isTrue);
      final version = await mongoose.version;
      expect(version, isA<String>());
    });

    test('define a mongoose Schema', () async {
      final dynamic mongoose = await js.require('mongoose');
      dynamic Schema = await mongoose.Schema;
      final JsString = await js.getGlobal('String');
      final JsNumber = await js.getGlobal('Number');
      final JsDate = await js.getGlobal('Date');
      dynamic dateNow = await JsDate.$get('now');

      dynamic schema = await Schema.$new([
        {
          'name': {'type': JsString, 'required': true},
          'email': {'type': JsString, 'required': true},
          'age': {'type': JsNumber, 'min': 0},
          'createdAt': {'type': JsDate, 'default': dateNow},
        }
      ]);

      dynamic paths = await schema.paths;
      final hasName = await paths.$has('name');
      final hasEmail = await paths.$has('email');
      final hasAge = await paths.$has('age');
      expect(hasName, isTrue);
      expect(hasEmail, isTrue);
      expect(hasAge, isTrue);
    });

    test('schema with virtuals and methods', () async {
      final dynamic mongoose = await js.require('mongoose');
      dynamic Schema = await mongoose.Schema;
      final JsString = await js.getGlobal('String');

      dynamic schema = await Schema.$new([
        {'firstName': JsString, 'lastName': JsString}
      ]);

      final fullNameGetter = await js.createFunction(
        body: 'return this.firstName + " " + this.lastName;',
      );
      dynamic virtual = await schema.virtual('fullName');
      await virtual.get(fullNameGetter);

      final greetFn = await js.createFunction(
        body: 'return "Hello, " + this.firstName;',
      );
      dynamic methods = await schema.methods;
      await methods.$set('greet', greetFn);

      dynamic virtuals = await schema.virtuals;
      final keys = await virtuals.$keys();
      expect(keys.length, greaterThan(0));
    });

    test('schema validation rules', () async {
      final dynamic mongoose = await js.require('mongoose');
      dynamic Schema = await mongoose.Schema;
      final JsString = await js.getGlobal('String');
      final JsNumber = await js.getGlobal('Number');
      final RegExpCtor = await js.getGlobal('RegExp');
      final emailRegex = await RegExpCtor.$new(['^\\S+@\\S+\\.\\S+\$']);

      dynamic schema = await Schema.$new([
        {
          'email': {
            'type': JsString,
            'required': [true, 'Email is required'],
            'match': [emailRegex, 'Invalid email format'],
          },
          'age': {
            'type': JsNumber,
            'min': [0, 'Age cannot be negative'],
            'max': [150, 'Age too high'],
          },
          'status': {
            'type': JsString,
            'enum': ['active', 'inactive', 'pending'],
          },
        }
      ]);

      dynamic paths = await schema.paths;
      dynamic emailPath = await paths.email;
      final emailRequired = await emailPath.isRequired;
      expect(emailRequired, isTrue);

      dynamic agePath = await paths.age;
      dynamic ageOpts = await agePath.options;
      final ageMinJson = await ageOpts.$toJson();
      final ageMinData = jsonDecode(ageMinJson as String);
      expect(ageMinData['min'][0], equals(0));

      dynamic statusPath = await paths.status;
      dynamic statusOpts = await statusPath.options;
      final statusJson = await statusOpts.$toJson();
      final statusData = jsonDecode(statusJson as String);
      expect(statusData['enum'], contains('active'));
    });

    test('mongoose model from schema', () async {
      final dynamic mongoose = await js.require('mongoose');
      // Clean up any existing model
      dynamic models = await mongoose.models;
      if (await models.$has('TestProduct') == true) {
        await models.$set('TestProduct', null);
      }
      dynamic Schema = await mongoose.Schema;
      final JsString = await js.getGlobal('String');
      final JsNumber = await js.getGlobal('Number');

      dynamic schema = await Schema.$new([
        {'name': JsString, 'price': JsNumber}
      ]);
      dynamic Product = await mongoose.model('TestProduct', schema);

      final modelName = await Product.modelName;
      final hasFind = await Product.$has('find');
      final hasCreate = await Product.$has('create');
      final hasFindById = await Product.$has('findById');
      expect(modelName, equals('TestProduct'));
      expect(hasFind, isTrue);
      expect(hasCreate, isTrue);
      expect(hasFindById, isTrue);
    });
  });

  // ─── knex ──────────────────────────────────────────────────

  group('knex', () {
    test('require knex', () async {
      final dynamic knex = await js.require('knex');
      expect(knex, isNotNull);
    });

    test('knex query builder — build SQL strings', () async {
      final dynamic knexMod = await js.require('knex');
      dynamic db = await knexMod({
        'client': 'better-sqlite3',
        'connection': {'filename': ':memory:'},
      });
      await js.setGlobal('__db', db);

      // Build queries synchronously via createFunction to avoid thenable resolution
      final selectFn = await js.createFunction(
        body:
            "return globalThis.__db('users').select('*').where('age', '>', 18).toString()",
      );
      final selectQuery = await selectFn.$invoke([]);

      final insertFn = await js.createFunction(
        body:
            "return globalThis.__db('users').insert({name: 'Alice', age: 30}).toString()",
      );
      final insertQuery = await insertFn.$invoke([]);

      final updateFn = await js.createFunction(
        body:
            "return globalThis.__db('users').where('id', 1).update({name: 'Bob'}).toString()",
      );
      final updateQuery = await updateFn.$invoke([]);

      final deleteFn = await js.createFunction(
        body: "return globalThis.__db('users').where('id', 2).del().toString()",
      );
      final deleteQuery = await deleteFn.$invoke([]);

      await db.destroy();
      expect(selectQuery as String, contains('users'));
      expect(insertQuery as String, contains('insert'));
      expect(updateQuery as String, contains('update'));
      expect(deleteQuery as String, contains('delete'));
    });

    test('knex with SQLite — create table and insert', () async {
      final dynamic knexMod = await js.require('knex');
      dynamic db = await knexMod({
        'client': 'better-sqlite3',
        'connection': {'filename': ':memory:'},
        'useNullAsDefault': true,
      });
      await js.setGlobal('__knex', db);

      // Use createFunction for all knex operations (knex objects are thenable)
      final createTableFn = await js.createFunction(
        body: "var db = globalThis.__knex; "
            "return db.schema.createTable('todos', function(table) { "
            "  table.increments('id'); "
            "  table.string('title').notNullable(); "
            "  table.boolean('completed').defaultTo(false); "
            "  table.timestamp('created_at').defaultTo(db.fn.now()); "
            "});",
      );
      await createTableFn.$invoke([]);

      final insertFn = await js.createFunction(
        body: "return globalThis.__knex('todos').insert(["
            "  {title: 'Learn Dart'},"
            "  {title: 'Learn Flutter'},"
            "  {title: 'Build Bridge', completed: true}"
            "]);",
      );
      await insertFn.$invoke([]);

      final allFn = await js.createFunction(
        body:
            "return globalThis.__knex('todos').select('*').then(function(r) { return JSON.stringify(r); })",
      );
      final allStr = await allFn.$invoke([]);
      final allData = jsonDecode(allStr as String) as List;

      final completedFn = await js.createFunction(
        body:
            "return globalThis.__knex('todos').where('completed', true).then(function(r) { return JSON.stringify(r); })",
      );
      final completedStr = await completedFn.$invoke([]);
      final completedData = jsonDecode(completedStr as String) as List;

      final countFn = await js.createFunction(
        body:
            "return globalThis.__knex('todos').count('* as total').then(function(r) { return JSON.stringify(r); })",
      );
      final countStr = await countFn.$invoke([]);
      final countData = jsonDecode(countStr as String) as List;

      await db.destroy();
      expect(allData.length, equals(3));
      expect(completedData.length, equals(1));
      expect(countData[0]['total'], equals(3));
      expect(allData[0]['title'], equals('Learn Dart'));
    });

    test('knex complex queries with SQLite', () async {
      final dynamic knexMod = await js.require('knex');
      dynamic db = await knexMod({
        'client': 'better-sqlite3',
        'connection': {'filename': ':memory:'},
        'useNullAsDefault': true,
      });
      await js.setGlobal('__knex', db);

      // Create table + insert via createFunction (knex objects are thenable)
      final setupFn = await js.createFunction(
        body: "var db = globalThis.__knex; "
            "return db.schema.createTable('products', function(table) { "
            "  table.increments('id'); "
            "  table.string('name'); "
            "  table.string('category'); "
            "  table.decimal('price'); "
            "  table.integer('stock'); "
            "}).then(function() { "
            "  return db('products').insert(["
            "    {name: 'Laptop', category: 'electronics', price: 999.99, stock: 10},"
            "    {name: 'Phone', category: 'electronics', price: 699.99, stock: 25},"
            "    {name: 'Shirt', category: 'clothing', price: 29.99, stock: 100},"
            "    {name: 'Pants', category: 'clothing', price: 49.99, stock: 50},"
            "    {name: 'Book', category: 'education', price: 19.99, stock: 200}"
            "  ]); "
            "});",
      );
      await setupFn.$invoke([]);

      // Category stats
      final catFn = await js.createFunction(
        body: "return globalThis.__knex('products')"
            ".select('category')"
            ".count('* as count')"
            ".avg('price as avgPrice')"
            ".groupBy('category')"
            ".orderBy('category')"
            ".then(function(r) { return JSON.stringify(r); });",
      );
      final categoryStats =
          jsonDecode(await catFn.$invoke([]) as String) as List;

      // Expensive items
      final expFn = await js.createFunction(
        body: "return globalThis.__knex('products')"
            ".where('price', '>', 100)"
            ".orderBy('price', 'desc')"
            ".select('name', 'price')"
            ".then(function(r) { return JSON.stringify(r); });",
      );
      final expensive = jsonDecode(await expFn.$invoke([]) as String) as List;

      // Update stock
      final updateFn = await js.createFunction(
        body: "var db = globalThis.__knex; "
            "return db('products').where('category', 'clothing')"
            ".update({stock: db.raw('stock + 10')});",
      );
      await updateFn.$invoke([]);

      // Read updated clothing
      final clothFn = await js.createFunction(
        body: "return globalThis.__knex('products')"
            ".where('category', 'clothing')"
            ".select('name', 'stock')"
            ".then(function(r) { return JSON.stringify(r); });",
      );
      final updatedClothing =
          jsonDecode(await clothFn.$invoke([]) as String) as List;

      await db.destroy();
      expect(categoryStats.length, equals(3));
      expect(expensive.length, equals(2));
      expect(expensive[0]['name'], equals('Laptop'));
      final shirt = updatedClothing.firstWhere((p) => p['name'] == 'Shirt');
      expect(shirt['stock'], equals(110));
    });

    test('knex transactions with SQLite', () async {
      final dynamic knexMod = await js.require('knex');
      dynamic db = await knexMod({
        'client': 'better-sqlite3',
        'connection': {'filename': ':memory:'},
        'useNullAsDefault': true,
      });
      await js.setGlobal('__knex', db);

      // Setup table + data via createFunction
      final setupFn = await js.createFunction(
        body: "var db = globalThis.__knex; "
            "return db.schema.createTable('accounts', function(table) { "
            "  table.increments('id'); "
            "  table.string('name'); "
            "  table.decimal('balance'); "
            "}).then(function() { "
            "  return db('accounts').insert(["
            "    {name: 'Alice', balance: 1000},"
            "    {name: 'Bob', balance: 500}"
            "  ]); "
            "});",
      );
      await setupFn.$invoke([]);

      // Transaction
      final trxFn = await js.createFunction(
        body: "var db = globalThis.__knex; "
            "return db.transaction(function(trx) { "
            "  return trx('accounts').where('name', 'Alice').decrement('balance', 200)"
            "    .then(function() { "
            "      return trx('accounts').where('name', 'Bob').increment('balance', 200); "
            "    }); "
            "});",
      );
      await trxFn.$invoke([]);

      // Read results
      final readFn = await js.createFunction(
        body: "return globalThis.__knex('accounts')"
            ".select('*').orderBy('name')"
            ".then(function(r) { return JSON.stringify(r); });",
      );
      final accData = jsonDecode(await readFn.$invoke([]) as String) as List;

      await db.destroy();
      expect(accData[0]['balance'], equals(800));
      expect(accData[1]['balance'], equals(700));
    });
  });

  // ─── better-sqlite3 ───────────────────────────────────────

  group('better-sqlite3', () {
    test('require better-sqlite3', () async {
      final dynamic sqlite = await js.require('better-sqlite3');
      expect(sqlite, isNotNull);
    });

    test('in-memory database — full CRUD', () async {
      final dynamic Database = await js.require('better-sqlite3');
      dynamic db = await Database.$new([':memory:']);

      await db.exec(
        'CREATE TABLE users ('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'name TEXT NOT NULL, '
        'email TEXT UNIQUE NOT NULL, '
        'age INTEGER)',
      );

      dynamic insert = await db
          .prepare('INSERT INTO users (name, email, age) VALUES (?, ?, ?)');
      await insert.run('Alice', 'alice@test.com', 30);
      await insert.run('Bob', 'bob@test.com', 25);
      await insert.run('Charlie', 'charlie@test.com', 35);

      dynamic allStmt = await db.prepare('SELECT * FROM users');
      dynamic all = await allStmt.all();

      dynamic olderStmt = await db.prepare('SELECT * FROM users WHERE age > ?');
      dynamic older = await olderStmt.all(28);

      dynamic updateStmt =
          await db.prepare('UPDATE users SET age = ? WHERE name = ?');
      await updateStmt.run(31, 'Alice');

      dynamic getStmt = await db.prepare('SELECT * FROM users WHERE name = ?');
      dynamic alice = await getStmt.get('Alice');
      final aliceAge = await alice.age;

      dynamic deleteStmt = await db.prepare('DELETE FROM users WHERE name = ?');
      await deleteStmt.run('Charlie');

      dynamic countStmt =
          await db.prepare('SELECT COUNT(*) as count FROM users');
      dynamic remaining = await countStmt.get();
      final remainingCount = await remaining.count;

      await db.close();
      expect(all.length, equals(3));
      expect(older.length, equals(2));
      expect(aliceAge, equals(31));
      expect(remainingCount, equals(2));
    });

    test('prepared statements and transactions', () async {
      final dynamic Database = await js.require('better-sqlite3');
      dynamic db = await Database.$new([':memory:']);
      await db.exec('CREATE TABLE inventory (item TEXT, qty INTEGER)');

      // Store db on globalThis so createFunction body can access it
      await js.setGlobal('__db', db);
      final insertFn = await js.createFunction(
        params: ['items'],
        body:
            "var stmt = globalThis.__db.prepare('INSERT INTO inventory (item, qty) VALUES (?, ?)'); "
            'for (var i = 0; i < items.length; i++) { stmt.run(items[i].name, items[i].qty); }',
      );
      dynamic insertMany = await db.transaction(insertFn);
      await insertMany.$invoke([
        [
          {'name': 'Apple', 'qty': 50},
          {'name': 'Banana', 'qty': 30},
          {'name': 'Cherry', 'qty': 100},
        ]
      ]);

      dynamic totalStmt =
          await db.prepare('SELECT SUM(qty) as total FROM inventory');
      dynamic total = await totalStmt.get();
      final totalQty = await total.total;

      dynamic itemsStmt =
          await db.prepare('SELECT * FROM inventory ORDER BY qty DESC');
      dynamic items = await itemsStmt.all();

      await db.close();
      expect(totalQty, equals(180));
      expect(items.length, equals(3));
      final topItem = items[0];
      expect(await topItem.item, equals('Cherry'));
    });

    test('aggregation and joins', () async {
      final dynamic Database = await js.require('better-sqlite3');
      dynamic db = await Database.$new([':memory:']);

      await db.exec(
        "CREATE TABLE departments (id INTEGER PRIMARY KEY, name TEXT); "
        "CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, dept_id INTEGER, salary REAL); "
        "INSERT INTO departments VALUES (1, 'Engineering'), (2, 'Marketing'), (3, 'Sales'); "
        "INSERT INTO employees VALUES "
        "(1, 'Alice', 1, 120000), "
        "(2, 'Bob', 1, 110000), "
        "(3, 'Charlie', 2, 90000), "
        "(4, 'Diana', 3, 95000), "
        "(5, 'Eve', 1, 130000)",
      );

      dynamic stmt = await db.prepare(
        'SELECT d.name as dept, COUNT(e.id) as count, AVG(e.salary) as avgSalary '
        'FROM departments d '
        'LEFT JOIN employees e ON d.id = e.dept_id '
        'GROUP BY d.id '
        'ORDER BY avgSalary DESC',
      );
      dynamic rows = await stmt.all();

      dynamic first = rows[0];
      final topDept = await first.dept;
      final topAvg = await first.avgSalary;

      await db.close();
      expect(rows.length, equals(3));
      expect(topDept, equals('Engineering'));
      expect((topAvg as num).round(), equals(120000));
    });
  });
}
