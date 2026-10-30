#ifndef RAWLIGHT_H
#define RAWLIGHT_H
#ifdef __cplusplus
extern "C" {
#endif

typedef struct RlSession RlSession;

/* demo != 0 loads the generated demo library. NULL on failure. */
RlSession *rl_session_new(int demo);
/* Opens/creates a persistent library; seed_demo fills a new one with demo photos. */
char *rl_open_library(RlSession *session, const char *dir, int seed_demo);
/* Reply is {"ok": ...} or {"error": "..."}; free it with rl_string_free. */
char *rl_execute(RlSession *session, const char *id, const char *params_json);
/* {"ok":[ids]} of the photos in view, display order; free with rl_string_free. */
char *rl_visible_ids(RlSession *session);
/* RGBA8 sRGB, fitted in max_w x max_h; NULL on failure; free with rl_buffer_free(ptr, len). */
unsigned char *rl_render(RlSession *session, unsigned long long id, unsigned max_w, unsigned max_h,
                         unsigned *out_w, unsigned *out_h, unsigned long *out_len);
/* Like rl_render, plus hist[1024] = 256 bins each of red, green, blue, luma (hist may be NULL). */
unsigned char *rl_render_hist(RlSession *session, unsigned long long id, unsigned max_w, unsigned max_h,
                              unsigned *out_w, unsigned *out_h, unsigned long *out_len, unsigned *hist);
/* Detached render: build (fast), run on any thread (slow), finish on the session.
   kind: 0 full, 1 thumbnail (disk cached), 2 draft, 3 uncropped. */
typedef struct RlJob RlJob;
RlJob *rl_job_new(RlSession *session, unsigned long long id, unsigned max_w, unsigned max_h, int kind);
RlJob *rl_job_new_mask_overlay(RlSession *session, unsigned long long id, unsigned max_w, unsigned max_h, int kind, unsigned mask_id);
RlJob *rl_job_new_preset(RlSession *session, unsigned long long id, unsigned max_w, unsigned max_h, const char *preset_id, unsigned amount);
unsigned char *rl_job_run(RlJob *job, unsigned *out_w, unsigned *out_h, unsigned long *out_len, unsigned *hist);
void rl_job_finish(RlSession *session, RlJob *job);
/* Registers the host's segmenter (Apple Vision). cb(rgb, w, h, key, clicks[x,y,include]*, n, out_logits, side) -> 1 ok, 0 none, <0 error. */
typedef int (*RlSegmentCb)(const unsigned char *, int, int, unsigned long long, const float *, int, float *, int);
void rl_set_segmenter(RlSegmentCb cb);
void rl_buffer_free(unsigned char *ptr, unsigned long len);
void rl_session_free(RlSession *session);
void rl_string_free(char *s);

#ifdef __cplusplus
}
#endif
#endif
