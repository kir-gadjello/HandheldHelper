#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int init(const char *cmd);

const char *json_rpc(const char *method, const char *path, const char *headers,
                     const char *body);

const char* get_completion(const char* req_json);

void deinit();

#ifdef __cplusplus
}
#endif
