#ifndef __BINDINGS_UDF_H
#define __BINDINGS_UDF_H
#ifdef __cplusplus
extern "C"
{
  #endif
  
  #include <stdint.h>
  #include <stdbool.h>
  
  typedef struct {
    char *ptr;
    size_t len;
  } udf_string_t;
  
  void udf_string_set(udf_string_t *ret, const char *s);
  void udf_string_dup(udf_string_t *ret, const char *s);
  void udf_string_free(udf_string_t *ret);
  typedef struct {
    uint8_t *ptr;
    size_t len;
  } udf_list_u8_t;
  void udf_list_u8_free(udf_list_u8_t *ptr);
  void udf_call(udf_string_t *name, udf_list_u8_t *args, udf_list_u8_t *ret0);
  int32_t udf_exec(udf_string_t *code);
  #ifdef __cplusplus
}
#endif
#endif
