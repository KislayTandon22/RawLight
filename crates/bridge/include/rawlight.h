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
/* {"ok":[ids]} of the photos in view, display order; free with rl_string_free. */
char *rl_visible_ids(RlSession *session);
/* RGBA8 sRGB, fitted in max_w x max_h; NULL on failure; free with rl_buffer_free(ptr, len). */
unsigned char *rl_render(RlSession *session, unsigned long long id, unsigned max_w, unsigned max_h,
                         unsigned *out_w, unsigned *out_h, unsigned long *out_len);
void rl_buffer_free(unsigned char *ptr, unsigned long len);
void rl_session_free(RlSession *session);
void rl_string_free(char *s);

#ifdef __cplusplus
}
#endif
#endif
