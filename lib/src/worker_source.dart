/// Embedded Node.js worker script.
///
/// This JavaScript source runs as a subprocess and handles all IPC
/// communication between Dart and the JavaScript runtime.
/// It manages object references, serialization, and npm module loading.
///
/// Supports: batch requests, batch GC, and Dart callback invocations.
library;

const String workerJsSource = r'''
'use strict';

const readline = require('readline');

// Make require, module, and __dirname available inside eval()
// (indirect eval runs in global scope where CJS locals are absent)
global.require = require;
global.module = module;
global.__dirname = __dirname;
global.__filename = __filename;

// ═══════════════════════════════════════════════════════
//  Reference Store
// ═══════════════════════════════════════════════════════

const refs = new Map();
let nextRefId = 1;

function storeRef(val) {
  const id = nextRefId++;
  refs.set(id, val);
  return id;
}

function getRef(id) {
  if (!refs.has(id)) {
    throw new Error('Reference #' + id + ' not found (may have been disposed)');
  }
  return refs.get(id);
}

// ═══════════════════════════════════════════════════════
//  Dart Callback Support (Promise-returning)
// ═══════════════════════════════════════════════════════

var pendingCallbackResolvers = {};
var nextInvokeId = 1;

function createDartCallback(callbackId) {
  return function () {
    var args = [];
    for (var i = 0; i < arguments.length; i++) {
      args.push(serialize(arguments[i], 0));
    }
    var invokeId = nextInvokeId++;
    send({ type: 'callback', callbackId: callbackId, invokeId: invokeId, args: args });
    return new Promise(function(resolve, reject) {
      pendingCallbackResolvers[invokeId] = { resolve: resolve, reject: reject };
    });
  };
}

// ═══════════════════════════════════════════════════════
//  Serialization: JS → Dart
// ═══════════════════════════════════════════════════════

function serialize(val, depth) {
  if (depth === undefined) depth = 0;
  if (val === null || val === undefined) return null;

  if (typeof val === 'boolean') return val;

  if (typeof val === 'number') {
    if (val !== val) return null;                    // NaN
    if (!Number.isFinite(val)) return String(val);   // ±Infinity
    return val;
  }

  if (typeof val === 'string') return val;

  if (typeof val === 'function') {
    return { __ref__: storeRef(val), __type__: 'function' };
  }

  if (typeof Buffer !== 'undefined' && Buffer.isBuffer(val)) {
    return { __ref__: storeRef(val), __type__: 'Buffer' };
  }

  if (val instanceof Promise) {
    return { __ref__: storeRef(val), __type__: 'Promise' };
  }

  if (Array.isArray(val)) {
    if (depth > 5) return { __ref__: storeRef(val), __type__: 'Array' };
    return val.map(function (v) { return serialize(v, depth + 1); });
  }

  if (typeof val === 'object') {
    var typeName = (val.constructor && val.constructor.name) || 'Object';
    return { __ref__: storeRef(val), __type__: typeName };
  }

  return null;
}

// ═══════════════════════════════════════════════════════
//  Deserialization: Dart → JS
// ═══════════════════════════════════════════════════════

function deserialize(val) {
  if (val === null || val === undefined) return val;
  if (typeof val === 'boolean' || typeof val === 'number' || typeof val === 'string') return val;
  if (Array.isArray(val)) return val.map(deserialize);
  if (typeof val === 'object') {
    if (val.__ref__ !== undefined) return getRef(val.__ref__);
    if (val.__dart_callback__ !== undefined) return createDartCallback(val.__dart_callback__);
    var result = {};
    var keys = Object.keys(val);
    for (var i = 0; i < keys.length; i++) {
      result[keys[i]] = deserialize(val[keys[i]]);
    }
    return result;
  }
  return val;
}

// ═══════════════════════════════════════════════════════
//  Action Handlers
// ═══════════════════════════════════════════════════════

var actions = {

  // ─── Lifecycle ───

  ping: function () { return 'pong'; },

  shutdown: function () {
    setTimeout(function () { process.exit(0); }, 50);
    return true;
  },

  gc: function (msg) {
    var ids = msg.refs || [];
    for (var i = 0; i < ids.length; i++) refs.delete(ids[i]);
    return ids.length;
  },

  // ─── Module Loading ───

  require: function (msg) {
    return require(msg.module);
  },

  // ─── Code Evaluation ───

  eval: function (msg) {
    try {
      return (0, eval)(msg.code);
    } catch (e) {
      // If the code contains top-level await, eval() throws a SyntaxError.
      // Retry by wrapping in an async IIFE with require and CJS locals in scope.
      // Users must use explicit `return` for their final value in this path.
      if (e instanceof SyntaxError && /\bawait\b/.test(e.message)) {
        return new Function('require', '__dirname', '__filename', 'module', 'exports',
          '"use strict"; return (async () => {\n' + msg.code + '\n})();'
        )(require, __dirname, __filename, module, module.exports);
      }
      throw e;
    }
  },

  // ─── Property Access ───

  get: function (msg) {
    return getRef(msg.ref)[msg.prop];
  },

  set: function (msg) {
    getRef(msg.ref)[msg.prop] = deserialize(msg.value);
    return true;
  },

  has: function (msg) {
    return msg.prop in getRef(msg.ref);
  },

  keys: function (msg) {
    return Object.keys(getRef(msg.ref));
  },

  typeof_ref: function (msg) {
    return typeof getRef(msg.ref);
  },

  delete_ref: function (msg) {
    return refs.delete(msg.ref);
  },

  // ─── Method Calls ───

  call: function (msg) {
    var obj = getRef(msg.ref);
    var fn = obj[msg.method];
    if (typeof fn !== 'function') {
      throw new TypeError('"' + msg.method + '" is not a function');
    }
    return fn.apply(obj, (msg.args || []).map(deserialize));
  },

  invoke: function (msg) {
    var fn = getRef(msg.ref);
    if (typeof fn !== 'function') {
      throw new TypeError('Value is not callable');
    }
    return fn.apply(undefined, (msg.args || []).map(deserialize));
  },

  construct: function (msg) {
    var Ctor = getRef(msg.ref);
    if (typeof Ctor !== 'function') {
      throw new TypeError('Value is not a constructor');
    }
    var args = (msg.args || []).map(deserialize);
    return new (Function.prototype.bind.apply(Ctor, [null].concat(args)))();
  },

  // ─── Path-based Operations (for chaining) ───

  get_path: function (msg) {
    var obj = getRef(msg.ref);
    var p = msg.path;
    for (var i = 0; i < p.length; i++) {
      if (obj === null || obj === undefined) return obj;
      obj = obj[p[i]];
    }
    return obj;
  },

  call_path: function (msg) {
    var obj = getRef(msg.ref);
    var p = msg.path;
    for (var i = 0; i < p.length - 1; i++) {
      obj = obj[p[i]];
      if (obj === null || obj === undefined) {
        throw new Error('Cannot read property "' + p[i + 1] + '" of ' + obj);
      }
    }
    var method = p[p.length - 1];
    var fn = obj[method];
    if (typeof fn !== 'function') {
      throw new TypeError('"' + p.join('.') + '" is not a function');
    }
    return fn.apply(obj, (msg.args || []).map(deserialize));
  },

  invoke_path: function (msg) {
    var obj = getRef(msg.ref);
    var p = msg.path;
    for (var i = 0; i < p.length; i++) {
      if (obj === null || obj === undefined) {
        throw new Error('Cannot read property "' + p[i] + '" of ' + obj);
      }
      obj = obj[p[i]];
    }
    if (typeof obj !== 'function') {
      throw new TypeError('"' + p.join('.') + '" is not callable');
    }
    return obj.apply(undefined, (msg.args || []).map(deserialize));
  },

  // ─── Iteration & Conversion ───

  to_list: function (msg) {
    var obj = getRef(msg.ref);
    if (typeof obj[Symbol.iterator] === 'function') return Array.from(obj);
    if (Array.isArray(obj)) return obj.slice();
    return Object.values(obj);
  },

  to_json_string: function (msg) {
    return JSON.stringify(getRef(msg.ref));
  },

  length: function (msg) {
    var obj = getRef(msg.ref);
    if (obj.length !== undefined) return obj.length;
    if (obj.size !== undefined) return obj.size;
    return Object.keys(obj).length;
  },

  instanceof_check: function (msg) {
    return getRef(msg.ref) instanceof getRef(msg.ctor);
  },

  // ─── Global Access ───

  get_global: function (msg) {
    return globalThis[msg.name];
  },

  set_global: function (msg) {
    globalThis[msg.name] = deserialize(msg.value);
    return null;
  },

  // ─── Function Creation ───

  create_function: function (msg) {
    var args = (msg.params || []).concat([msg.body]);
    return new (Function.prototype.bind.apply(Function, [null].concat(args)))();
  },

  // ─── Batch Operations ───

  batch: function (msg) {
    var requests = msg.requests || [];
    return Promise.all(requests.map(function (req) {
      try {
        var handler = actions[req.action];
        if (!handler) throw new Error('Unknown action: "' + req.action + '"');
        return Promise.resolve(handler(req)).then(function (result) {
          return { result: serialize(result, 0) };
        }).catch(function (err) {
          return { error: { message: err.message || String(err), code: err.code } };
        });
      } catch (err) {
        return Promise.resolve({
          error: { message: err.message || String(err), code: err.code }
        });
      }
    }));
  },
};

// ═══════════════════════════════════════════════════════
//  Message Processing
// ═══════════════════════════════════════════════════════

var rl = readline.createInterface({ input: process.stdin, terminal: false });

rl.on('line', function (line) {
  var id;
  try {
    var msg = JSON.parse(line);

    // Callback response from Dart — resolve the pending Promise
    if (msg.type === 'callback_response') {
      var entry = pendingCallbackResolvers[msg.invokeId];
      if (entry) {
        if (msg.error) {
          entry.reject(new Error(msg.error.message || 'Callback error'));
        } else {
          entry.resolve(deserialize(msg.result));
        }
        delete pendingCallbackResolvers[msg.invokeId];
      }
      return;
    }

    id = msg.id;
    var handler = actions[msg.action];
    if (!handler) throw new Error('Unknown action: "' + msg.action + '"');

    Promise.resolve(handler(msg)).then(function (result) {
      // Batch results are already serialized
      if (msg.action === 'batch') {
        send({ id: id, result: result });
      } else {
        send({ id: id, result: serialize(result, 0) });
      }
    }).catch(function (err) {
      send({
        id: id,
        error: {
          message: err.message || String(err),
          code: err.code || undefined,
          stack: err.stack || undefined,
        },
      });
    });
  } catch (err) {
    send({
      id: id,
      error: {
        message: err.message || String(err),
        code: err.code || undefined,
        stack: err.stack || undefined,
      },
    });
  }
});

function send(data) {
  process.stdout.write(JSON.stringify(data) + '\n');
}

// ═══════════════════════════════════════════════════════
//  Error Handling
// ═══════════════════════════════════════════════════════

process.on('uncaughtException', function (err) {
  process.stderr.write('[worker] Uncaught: ' + err.message + '\n');
});

process.on('unhandledRejection', function (err) {
  process.stderr.write('[worker] Unhandled rejection: ' + err + '\n');
});

// ═══════════════════════════════════════════════════════
//  Ready Signal
// ═══════════════════════════════════════════════════════

send({ type: 'ready' });
''';
