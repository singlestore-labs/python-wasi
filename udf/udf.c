#include <stdlib.h>
#include <udf.h>

__attribute__((weak, export_name("canonical_abi_realloc")))
void *canonical_abi_realloc(
void *ptr,
size_t orig_size,
size_t org_align,
size_t new_size
) {
  void *ret = realloc(ptr, new_size);
  if (!ret)
  abort();
  return ret;
}

__attribute__((weak, export_name("canonical_abi_free")))
void canonical_abi_free(
void *ptr,
size_t size,
size_t align
) {
  free(ptr);
}
#include <string.h>

void udf_string_set(udf_string_t *ret, const char *s) {
  ret->ptr = (char*) s;
  ret->len = strlen(s);
}

void udf_string_dup(udf_string_t *ret, const char *s) {
  ret->len = strlen(s);
  ret->ptr = canonical_abi_realloc(NULL, 0, 1, ret->len);
  memcpy(ret->ptr, s, ret->len);
}

void udf_string_free(udf_string_t *ret) {
  canonical_abi_free(ret->ptr, ret->len, 1);
  ret->ptr = NULL;
  ret->len = 0;
}
void udf_list_u8_free(udf_list_u8_t *ptr) {
  canonical_abi_free(ptr->ptr, ptr->len * 1, 1);
}

__attribute__((aligned(4)))
static uint8_t RET_AREA[8];
__attribute__((export_name("call")))
int32_t __wasm_export_udf_call(int32_t arg, int32_t arg0, int32_t arg1, int32_t arg2) {
  udf_string_t arg3 = (udf_string_t) { (char*)(arg), (size_t)(arg0) };
  udf_list_u8_t arg4 = (udf_list_u8_t) { (uint8_t*)(arg1), (size_t)(arg2) };
  udf_list_u8_t ret;
  udf_call(&arg3, &arg4, &ret);
  int32_t ptr = (int32_t) &RET_AREA;
  *((int32_t*)(ptr + 4)) = (int32_t) (ret).len;
  *((int32_t*)(ptr + 0)) = (int32_t) (ret).ptr;
  return ptr;
}
__attribute__((export_name("exec")))
int32_t __wasm_export_udf_exec(int32_t arg, int32_t arg0) {
  udf_string_t arg1 = (udf_string_t) { (char*)(arg), (size_t)(arg0) };
  int32_t ret = udf_exec(&arg1);
  return ret;
}
