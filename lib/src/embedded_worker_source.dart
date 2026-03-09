/// Embedded JS worker script for in-process engines (web, mobile).
///
/// Contains the same handler logic as the Node.js worker but without
/// readline/stdin/stdout. Exposes `__bridgerHandle(jsonString)` for
/// direct invocation from Dart via FFI or js_interop.
///
/// Includes a CommonJS-compatible `require` polyfill for bundled modules.
library;

const String embeddedWorkerSource = r'''
'use strict';

// ═══════════════════════════════════════════════════════
//  Bundled Module Registry (populated by bundler)
// ═══════════════════════════════════════════════════════

var __bundledModules = {};
var __moduleCache = {};

var _require = (typeof require !== 'undefined') ? require : function (name) {
  if (__moduleCache[name]) return __moduleCache[name];
  if (!__bundledModules[name]) {
    throw new Error('Cannot find module "' + name + '" (not bundled). ' +
      'Run: dart run flutter_js_bridger bundle');
  }
  var mod = { exports: {} };
  __bundledModules[name](mod, mod.exports, _require);
  __moduleCache[name] = mod.exports;
  return mod.exports;
};

// ═══════════════════════════════════════════════════════
//  Reference Store
// ═══════════════════════════════════════════════════════

var refs = new Map();
var nextRefId = 1;

function storeRef(val) {
  var id = nextRefId++;
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
//  Serialization: JS → Dart
// ═══════════════════════════════════════════════════════

function serialize(val, depth) {
  if (depth === undefined) depth = 0;
  if (val === null || val === undefined) return null;
  if (typeof val === 'boolean') return val;
  if (typeof val === 'number') {
    if (val !== val) return null;
    if (!isFinite(val)) return String(val);
    return val;
  }
  if (typeof val === 'string') return val;
  if (typeof val === 'function') {
    return { __ref__: storeRef(val), __type__: 'function' };
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
    if (val.__dart_callback__ !== undefined) {
      var cbId = val.__dart_callback__;
      return function () {
        // In embedded mode, callbacks are fire-and-forget
        // The host (Dart) will handle them via __bridgerCallbacks
        if (typeof __bridgerOnCallback === 'function') {
          var args = [];
          for (var i = 0; i < arguments.length; i++) {
            args.push(serialize(arguments[i], 0));
          }
          __bridgerOnCallback(cbId, JSON.stringify(args));
        }
      };
    }
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
  ping: function () { return 'pong'; },
  shutdown: function () { return true; },
  gc: function (msg) {
    var ids = msg.refs || [];
    for (var i = 0; i < ids.length; i++) refs.delete(ids[i]);
    return ids.length;
  },
  require: function (msg) { return _require(msg.module); },
  eval: function (msg) { return (0, eval)(msg.code); },
  get: function (msg) { return getRef(msg.ref)[msg.prop]; },
  set: function (msg) {
    getRef(msg.ref)[msg.prop] = deserialize(msg.value);
    return true;
  },
  has: function (msg) { return msg.prop in getRef(msg.ref); },
  keys: function (msg) { return Object.keys(getRef(msg.ref)); },
  typeof_ref: function (msg) { return typeof getRef(msg.ref); },
  delete_ref: function (msg) { return refs.delete(msg.ref); },
  call: function (msg) {
    var obj = getRef(msg.ref);
    var fn = obj[msg.method];
    if (typeof fn !== 'function') throw new TypeError('"' + msg.method + '" is not a function');
    return fn.apply(obj, (msg.args || []).map(deserialize));
  },
  invoke: function (msg) {
    var fn = getRef(msg.ref);
    if (typeof fn !== 'function') throw new TypeError('Value is not callable');
    return fn.apply(undefined, (msg.args || []).map(deserialize));
  },
  construct: function (msg) {
    var Ctor = getRef(msg.ref);
    if (typeof Ctor !== 'function') throw new TypeError('Value is not a constructor');
    var args = (msg.args || []).map(deserialize);
    return new (Function.prototype.bind.apply(Ctor, [null].concat(args)))();
  },
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
      if (obj === null || obj === undefined) throw new Error('Cannot read property "' + p[i + 1] + '" of ' + obj);
    }
    var method = p[p.length - 1];
    var fn = obj[method];
    if (typeof fn !== 'function') throw new TypeError('"' + p.join('.') + '" is not a function');
    return fn.apply(obj, (msg.args || []).map(deserialize));
  },
  invoke_path: function (msg) {
    var obj = getRef(msg.ref);
    var p = msg.path;
    for (var i = 0; i < p.length; i++) {
      if (obj === null || obj === undefined) throw new Error('Cannot read property "' + p[i] + '" of ' + obj);
      obj = obj[p[i]];
    }
    if (typeof obj !== 'function') throw new TypeError('"' + p.join('.') + '" is not callable');
    return obj.apply(undefined, (msg.args || []).map(deserialize));
  },
  to_list: function (msg) {
    var obj = getRef(msg.ref);
    if (typeof obj[Symbol.iterator] === 'function') return Array.from(obj);
    if (Array.isArray(obj)) return obj.slice();
    return Object.values(obj);
  },
  to_json_string: function (msg) { return JSON.stringify(getRef(msg.ref)); },
  length: function (msg) {
    var obj = getRef(msg.ref);
    if (obj.length !== undefined) return obj.length;
    if (obj.size !== undefined) return obj.size;
    return Object.keys(obj).length;
  },
  instanceof_check: function (msg) {
    return getRef(msg.ref) instanceof getRef(msg.ctor);
  },
  get_global: function (msg) {
    return (typeof globalThis !== 'undefined' ? globalThis : this)[msg.name];
  },
  set_global: function (msg) {
    (typeof globalThis !== 'undefined' ? globalThis : this)[msg.name] = deserialize(msg.value);
    return null;
  },
  create_function: function (msg) {
    var args = (msg.params || []).concat([msg.body]);
    return new (Function.prototype.bind.apply(Function, [null].concat(args)))();
  },
  batch: function (msg) {
    var requests = msg.requests || [];
    return requests.map(function (req) {
      try {
        var handler = actions[req.action];
        if (!handler) throw new Error('Unknown action: "' + req.action + '"');
        var result = handler(req);
        return { result: serialize(result, 0) };
      } catch (err) {
        return { error: { message: err.message || String(err), code: err.code } };
      }
    });
  },
};

// ═══════════════════════════════════════════════════════
//  Callback Queue (for in-process engines, polled by Dart)
// ═══════════════════════════════════════════════════════

var __bridgerCallbackQueue = [];

function __bridgerOnCallback(cbId, argsJson) {
  __bridgerCallbackQueue.push({ callbackId: cbId, args: argsJson });
}

function __bridgerDrainCallbacks() {
  var q = __bridgerCallbackQueue;
  __bridgerCallbackQueue = [];
  return JSON.stringify(q);
}

// ═══════════════════════════════════════════════════════
//  Direct Handler (for in-process engines)
// ═══════════════════════════════════════════════════════

function __bridgerHandle(msgJson) {
  try {
    var msg = (typeof msgJson === 'string') ? JSON.parse(msgJson) : msgJson;
    var handler = actions[msg.action];
    if (!handler) throw new Error('Unknown action: "' + msg.action + '"');
    var result = handler(msg);
    if (msg.action === 'batch') {
      return JSON.stringify({ id: msg.id, result: result });
    }
    return JSON.stringify({ id: msg.id, result: serialize(result, 0) });
  } catch (err) {
    return JSON.stringify({
      id: (typeof msgJson === 'object' ? msgJson.id : 0),
      error: { message: err.message || String(err), code: err.code }
    });
  }
}
''';
