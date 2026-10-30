#ifndef RAWLIGHT_H
#define RAWLIGHT_H
#ifdef __cplusplus
extern "C" {
#endif

typedef struct RlSession RlSession;

/* demo != 0 loads the generated demo library. NULL on failure. */
RlSession *rl_session_new(int demo);
/* Reply is {"ok": ...} or {"error": "..."}; free it with rl_string_free. */
char *rl_execute(RlSession *session, const char *id, const char *params_json);
void rl_session_free(RlSession *session);
void rl_string_free(char *s);

#ifdef __cplusplus
}
#endif
#endif
