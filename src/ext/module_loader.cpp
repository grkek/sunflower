// Custom ES module loader bridge for Sunflower.

#include "quickjs/quickjs.h"
#include "quickjs/quickjs-libc.h"
#include <cstring>
#include <cstdlib>
#include <cstdio>
#include <limits.h>
#include <libgen.h>

static char *(*g_crystal_normalize)(const char *, const char *) = nullptr;
static char *(*g_crystal_load)(const char *, size_t *) = nullptr;

static char *custom_module_normalize(JSContext *ctx,
                                     const char *module_base_name,
                                     const char *module_name,
                                     void * /*opaque*/)
{
  if (g_crystal_normalize) {
    char *result = g_crystal_normalize(
      module_base_name ? module_base_name : "",
      module_name
    );
    if (result) {
      char *js_copy = js_strdup(ctx, result);
      free(result);
      return js_copy;
    }
  }

  if (module_name[0] != '.') {
    return js_strdup(ctx, module_name);
  }

  if (!module_base_name || module_base_name[0] == '\0') {
    return js_strdup(ctx, module_name);
  }

  char *base_copy = js_strdup(ctx, module_base_name);
  if (!base_copy) return nullptr;

  const char *dir = dirname(base_copy);
  size_t dir_len = strlen(dir);
  size_t name_len = strlen(module_name);
  size_t total = dir_len + 1 + name_len + 1;

  char *resolved = (char *)js_malloc(ctx, total);
  if (!resolved) {
    js_free(ctx, base_copy);
    return nullptr;
  }

  snprintf(resolved, total, "%s/%s", dir, module_name);
  js_free(ctx, base_copy);

  char real[PATH_MAX];
  if (realpath(resolved, real)) {
    js_free(ctx, resolved);
    return js_strdup(ctx, real);
  }

  return resolved;
}

static JSModuleDef *custom_module_loader(JSContext *ctx,
                                         const char *module_name,
                                         void * /*opaque*/)
{
  char *buf = nullptr;
  size_t buf_len = 0;

  if (g_crystal_load) {
    buf = g_crystal_load(module_name, &buf_len);
  }

  if (!buf) {
    FILE *f = fopen(module_name, "rb");
    if (!f) {
      JS_ThrowReferenceError(ctx, "Module not found: '%s'", module_name);
      return nullptr;
    }

    fseek(f, 0, SEEK_END);
    long file_size = ftell(f);
    fseek(f, 0, SEEK_SET);

    if (file_size < 0) {
      fclose(f);
      JS_ThrowReferenceError(ctx, "Could not read module: '%s'", module_name);
      return nullptr;
    }

    buf_len = (size_t)file_size;
    buf = (char *)malloc(buf_len + 1);
    if (!buf) {
      fclose(f);
      return nullptr;
    }

    if (fread(buf, 1, buf_len, f) != buf_len) {
      free(buf);
      fclose(f);
      return nullptr;
    }

    buf[buf_len] = '\0';
    fclose(f);
  }

  JSValue func_val = JS_Eval(ctx, buf, buf_len, module_name,
                             JS_EVAL_TYPE_MODULE | JS_EVAL_FLAG_COMPILE_ONLY);
  free(buf);

  if (JS_IsException(func_val)) {
    return nullptr;
  }

  JSModuleDef *m = (JSModuleDef *)JS_VALUE_GET_PTR(func_val);
  js_module_set_import_meta(ctx, func_val, 1, 0);
  JS_FreeValue(ctx, func_val);
  return m;
}

extern "C" void SetupCustomModuleLoader(
  JSRuntime *rt,
  char *(*normalize_cb)(const char *, const char *),
  char *(*load_cb)(const char *, size_t *)
)
{
  g_crystal_normalize = normalize_cb;
  g_crystal_load = load_cb;
  JS_SetModuleLoaderFunc(rt, custom_module_normalize, custom_module_loader, nullptr);
}