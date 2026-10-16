// SwiftPM 的 C target 要有源文件。顺便在编译时检查函数表的下标没写错。
#include "rime_api_prefix.h"

_Static_assert(offsetof(RimeApiPrefix, setup) == 8 + 0 * sizeof(void *), "setup 应该是下标 0");
_Static_assert(offsetof(RimeApiPrefix, create_session) == 8 + 13 * sizeof(void *), "create_session 应该是下标 13");
_Static_assert(offsetof(RimeApiPrefix, process_key) == 8 + 18 * sizeof(void *), "process_key 应该是下标 18");
_Static_assert(offsetof(RimeApiPrefix, free_context) == 8 + 24 * sizeof(void *), "free_context 应该是下标 24");
_Static_assert(offsetof(RimeApiPrefix, get_current_schema) == 8 + 33 * sizeof(void *), "get_current_schema 应该是下标 33");
_Static_assert(offsetof(RimeApiPrefix, get_version) == 8 + 72 * sizeof(void *), "get_version 应该是下标 72");
_Static_assert(offsetof(RimeApiPrefix, select_candidate_on_current_page) == 8 + 74 * sizeof(void *),
               "select_candidate_on_current_page 应该是下标 74");
