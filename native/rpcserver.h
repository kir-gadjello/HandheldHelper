#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int init(const char *cmd);

void init_async(const char* cmd);

const char* tokenize(const char* req_json);

const char *poll_system_status();

// const char *json_rpc(const char *method, const char *path, const char *headers,
//                      const char *body);

const char* get_completion(const char* req_json);

const char* async_completion_init(const char* req_json);

const char* async_completion_poll(const char* cmd_json);

const char* async_completion_cancel(const char* req_json);

const char* save_state(const char* req_json);

const char* load_state(const char* req_json);


void deinit();

#ifdef __cplusplus
}
#endif
