/*
 * quickjs_bridger_shim.c — FFI shim for flutter_js_bridger
 *
 * Provides two functions called from Dart via dart:ffi:
 *   - qjs_eval_to_string(ctx, code) → char*
 *   - qjs_free_cstring(ctx, ptr)
 *
 * Compile this alongside QuickJS sources into libquickjs.so.
 * See CMakeLists.txt and the setup guide for build instructions.
 */

#include "quickjs.h"
#include <string.h>
#include <stdlib.h>

/*
 * Evaluate JS code and return the result as a C string.
 *
 * On success: returns the stringified result.
 * On error:   returns "ERROR:<message>".
 *
 * The caller MUST free the returned string with qjs_free_cstring().
 */
const char *qjs_eval_to_string(JSContext *ctx, const char *code)
{
    JSValue val = JS_Eval(ctx, code, strlen(code), "<eval>",
                          JS_EVAL_TYPE_GLOBAL);

    if (JS_IsException(val))
    {
        JSValue exc = JS_GetException(ctx);
        const char *msg = JS_ToCString(ctx, exc);
        if (!msg)
            msg = "Unknown error";

        /* Build "ERROR:<message>" string */
        size_t msg_len = strlen(msg);
        size_t buf_len = 6 + msg_len + 1; /* "ERROR:" + msg + NUL */
        char *buf = js_malloc(ctx, buf_len);
        if (buf)
        {
            memcpy(buf, "ERROR:", 6);
            memcpy(buf + 6, msg, msg_len + 1);
        }

        JS_FreeCString(ctx, msg);
        JS_FreeValue(ctx, exc);
        JS_FreeValue(ctx, val);
        return buf ? buf : "ERROR:out of memory";
    }

    const char *str = JS_ToCString(ctx, val);
    JS_FreeValue(ctx, val);
    return str;
}

/*
 * Free a C string returned by qjs_eval_to_string().
 */
void qjs_free_cstring(JSContext *ctx, const char *ptr)
{
    JS_FreeCString(ctx, ptr);
}
