// librime 1.16 的结构体和函数表前缀（鼠须管自带的 librime.1.dylib 只导出 rime_get_api）。
// 字段和 tools/vm/rime-type-probe.c 一样，函数表下标见 docs/verified-facts.md 第 8、8.1 节。
// 只给用到的十七个函数写类型和名字，其余用 void * 占位，保证下标对得上。
#ifndef RIME_API_PREFIX_H
#define RIME_API_PREFIX_H

#include <stddef.h>
#include <stdint.h>

typedef uintptr_t RimeSessionId;
// librime 里叫 Bool；这里换个名字，免得在 Swift 里盖住 Swift 自己的 Bool
typedef int RimeBool;

typedef struct {
  int data_size;
  const char *shared_data_dir;
  const char *user_data_dir;
  const char *distribution_name;
  const char *distribution_code_name;
  const char *distribution_version;
  const char *app_name;
  const char **modules;
  int min_log_level;
  const char *log_dir;
  const char *prebuilt_data_dir;
  const char *staging_dir;
} RimeTraits;

typedef struct {
  int length;
  int cursor_pos;
  int sel_start;
  int sel_end;
  char *preedit;
} RimeComposition;

typedef struct {
  char *text;
  char *comment;
  void *reserved;
} RimeCandidate;

typedef struct {
  int page_size;
  int page_no;
  RimeBool is_last_page;
  int highlighted_candidate_index;
  int num_candidates;
  RimeCandidate *candidates;
  char *select_keys;
} RimeMenu;

typedef struct {
  int data_size;
  char *text;
} RimeCommit;

typedef struct {
  int data_size;
  RimeComposition composition;
  RimeMenu menu;
  char *commit_text_preview;
  char **select_labels;
} RimeContext;

// 函数表：开头是 int data_size（表示后面有多少字节），后面是函数指针，下标从 0 开始
typedef struct {
  int data_size;
  void (*setup)(RimeTraits *traits);                                          // 0
  void *unused_1_1[1];                                                        // 1
  void (*initialize)(RimeTraits *traits);                                     // 2
  void (*finalize)(void);                                                     // 3
  void *unused_4_12[9];                                                       // 4..12
  RimeSessionId (*create_session)(void);                                      // 13
  void *unused_14_14[1];                                                      // 14
  RimeBool (*destroy_session)(RimeSessionId session);                         // 15
  void *unused_16_17[2];                                                      // 16..17
  RimeBool (*process_key)(RimeSessionId session, int keycode, int mask);      // 18
  void *unused_19_19[1];                                                      // 19
  void (*clear_composition)(RimeSessionId session);                           // 20
  RimeBool (*get_commit)(RimeSessionId session, RimeCommit *commit);          // 21
  RimeBool (*free_commit)(RimeCommit *commit);                                // 22
  RimeBool (*get_context)(RimeSessionId session, RimeContext *context);       // 23
  RimeBool (*free_context)(RimeContext *context);                             // 24
  void *unused_25_27[3];                                                      // 25..27
  RimeBool (*get_option)(RimeSessionId session, const char *option);          // 28
  void *unused_29_32[4];                                                      // 29..32
  RimeBool (*get_current_schema)(RimeSessionId session, char *schema_id, size_t buffer_size);  // 33
  RimeBool (*select_schema)(RimeSessionId session, const char *schema_id);    // 34
  void *unused_35_68[34];                                                     // 35..68
  const char *(*get_input)(RimeSessionId session);                            // 69
  void *unused_70_71[2];                                                      // 70..71
  const char *(*get_version)(void);                                           // 72
  void *unused_73_73[1];                                                      // 73
  RimeBool (*select_candidate_on_current_page)(RimeSessionId session, size_t index);  // 74
} RimeApiPrefix;

#endif
