#ifndef OMNICLOCK_WEB_WINDOW_H
#define OMNICLOCK_WEB_WINDOW_H
#ifdef __cplusplus
extern "C" {
#endif
typedef void (*omni_web_callback)(void *context, const char *key, const char *message);
void omni_web_initialize(void);
void *omni_web_open(const char *key, const char *title, const char *assets, const char *profile, const char *url, const char *startup_script, int width, int height, omni_web_callback callback, void *context);
void omni_web_send(void *window, const char *json);
void omni_web_script(void *window, const char *script);
void omni_web_opacity(void *window, double opacity);
void omni_web_show(void *window, int visible);
void omni_web_close(void *window);
void omni_web_anchor(void *window, void *owner);
int omni_web_visible(void *window);
int omni_web_capture(void *window, const char *path);
#ifdef __cplusplus
}
#endif
#endif
