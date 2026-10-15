// 测试工具：在一份 Rime 用户目录（必须是副本）上模拟打字，打印上屏文字和候选。
// 用法：rime-type-probe <用户目录> <方案id> <编码>...
// 用户目录要先用 rime_deployer --build 编译过。拒绝在真实的 ~/Library/Rime（以及它里面的目录）上运行。
#include <dlfcn.h>
#include <limits.h>
#include <pwd.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <unistd.h>

#define SQUIRREL "/Library/Input Methods/Squirrel.app/Contents"

typedef uintptr_t RimeSessionId;
typedef int Bool;

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

typedef struct { int length, cursor_pos, sel_start, sel_end; char *preedit; } RimeComposition;
typedef struct { char *text; char *comment; void *reserved; } RimeCandidate;
typedef struct {
  int page_size, page_no;
  Bool is_last_page;
  int highlighted_candidate_index;
  int num_candidates;
  RimeCandidate *candidates;
  char *select_keys;
} RimeMenu;
typedef struct { int data_size; char *text; } RimeCommit;
typedef struct {
  int data_size;
  RimeComposition composition;
  RimeMenu menu;
  char *commit_text_preview;
  char **select_labels;
} RimeContext;

// librime 1.16 的函数表，只声明用到的前 35 项（下标见 docs/verified-facts.md 第 8 节）
typedef struct {
  int data_size;
  void (*setup)(RimeTraits *);                          // 0
  void *set_notification_handler;                       // 1
  void (*initialize)(RimeTraits *);                     // 2
  void (*finalize)(void);                               // 3
  void *unused_4_12[9];                                 // 4..12
  RimeSessionId (*create_session)(void);                // 13
  void *unused_14_17[4];                                // 14..17
  Bool (*process_key)(RimeSessionId, int, int);         // 18
  void *commit_composition;                             // 19
  void (*clear_composition)(RimeSessionId);             // 20
  Bool (*get_commit)(RimeSessionId, RimeCommit *);      // 21
  Bool (*free_commit)(RimeCommit *);                    // 22
  Bool (*get_context)(RimeSessionId, RimeContext *);    // 23
  Bool (*free_context)(RimeContext *);                  // 24
  void *unused_25_33[9];                                // 25..33
  Bool (*select_schema)(RimeSessionId, const char *);   // 34
} RimeApiPrefix;

// 用设备号 + inode 比较目录，firmlink（/System/Volumes/Data/…）和符号链接都能认出来
typedef struct { dev_t dev; ino_t ino; } FileId;

static int file_id(const char *path, FileId *out) {
  struct stat st;
  if (stat(path, &st) != 0) return 0;
  out->dev = st.st_dev;
  out->ino = st.st_ino;
  return 1;
}

static int add_library_dir(FileId *libs, int n, const char *home) {
  if (!home || !*home || n >= 3) return n;
  char path[PATH_MAX];
  snprintf(path, sizeof path, "%s/Library", home);
  return file_id(path, &libs[n]) ? n + 1 : n;
}

// 给定路径或它的任何一级上级是「某个家目录/Library/Rime」时拒绝（返回 0）。
// 家目录同时看 passwd、$HOME、sudo 前的用户。任何一步解析失败都按拒绝处理。
static int is_safe_dir(const char *dir) {
  FileId libs[3];
  int n = 0;
  struct passwd *pw = getpwuid(getuid());
  if (pw) n = add_library_dir(libs, n, pw->pw_dir);
  n = add_library_dir(libs, n, getenv("HOME"));
  const char *sudo_uid = getenv("SUDO_UID");
  if (sudo_uid) {
    struct passwd *sp = getpwuid((uid_t)strtoul(sudo_uid, NULL, 10));
    if (sp) n = add_library_dir(libs, n, sp->pw_dir);
  }
  if (n == 0) return 0;

  char cur[PATH_MAX];
  if (!realpath(dir, cur)) return 0;
  for (;;) {
    char *slash = strrchr(cur, '/');
    if (!slash || slash == cur) return 1;   // 查到根目录了
    int is_rime = strcasecmp(slash + 1, "Rime") == 0;
    *slash = '\0';                           // cur 变成上一级
    if (is_rime) {
      FileId parent;
      if (!file_id(cur, &parent)) return 0;
      for (int i = 0; i < n; i++)
        if (libs[i].dev == parent.dev && libs[i].ino == parent.ino) return 0;
    }
  }
}

int main(int argc, char **argv) {
  // --guard-only <目录>：只做防误用检查，不加载 librime（给测试用）
  if (argc == 3 && strcmp(argv[1], "--guard-only") == 0) return is_safe_dir(argv[2]) ? 0 : 3;
  if (argc < 4) {
    fprintf(stderr, "用法：%s <用户目录> <方案id> <编码>...\n", argv[0]);
    return 2;
  }
  if (!is_safe_dir(argv[1])) {
    fprintf(stderr, "拒绝运行：这是真实的 ~/Library/Rime（或它里面的目录），或者路径无法解析。请传一份副本\n");
    return 3;
  }
  void *lib = dlopen(SQUIRREL "/Frameworks/librime.1.dylib", RTLD_NOW);
  if (!lib) { fprintf(stderr, "加载 librime 失败：%s\n", dlerror()); return 1; }
  RimeApiPrefix *(*get_api)(void) = (RimeApiPrefix *(*)(void))dlsym(lib, "rime_get_api");
  if (!get_api) { fprintf(stderr, "找不到 rime_get_api\n"); return 1; }
  RimeApiPrefix *api = get_api();

  RimeTraits traits;
  memset(&traits, 0, sizeof traits);
  traits.data_size = (int)(sizeof(RimeTraits) - sizeof(int));
  traits.shared_data_dir = SQUIRREL "/SharedSupport";
  traits.user_data_dir = argv[1];
  traits.distribution_name = "rime-type-probe";
  traits.distribution_code_name = "rime-type-probe";
  traits.distribution_version = "0.1";
  traits.app_name = "rime.probe";
  traits.min_log_level = 3;           // 只记 FATAL
  traits.log_dir = argv[1];           // 日志写进副本目录，不碰鼠须管的日志
  api->setup(&traits);
  api->initialize(&traits);

  RimeSessionId session = api->create_session();
  if (!session) { fprintf(stderr, "创建会话失败\n"); return 1; }
  if (!api->select_schema(session, argv[2])) {
    fprintf(stderr, "选择方案失败：%s\n", argv[2]);
    return 1;
  }
  for (int i = 3; i < argc; i++) {
    api->clear_composition(session);
    for (const char *p = argv[i]; *p; p++) api->process_key(session, (unsigned char)*p, 0);
    printf("%s\t", argv[i]);
    // 先读上屏：四码唯一会自动上屏，这时候选为空不算失败
    RimeCommit commit = {0};
    commit.data_size = (int)(sizeof(RimeCommit) - sizeof(int));
    if (api->get_commit(session, &commit)) {
      printf("[上屏]%s ", commit.text);
      api->free_commit(&commit);
    }
    RimeContext ctx;
    memset(&ctx, 0, sizeof ctx);
    ctx.data_size = (int)(sizeof(RimeContext) - sizeof(int));
    if (api->get_context(session, &ctx)) {
      for (int k = 0; k < ctx.menu.num_candidates && k < 5; k++)
        printf("%s%s", k ? " | " : "", ctx.menu.candidates[k].text);
      api->free_context(&ctx);
    }
    printf("\n");
  }
  api->finalize();
  return 0;
}
