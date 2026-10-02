#ifndef HALO_IOS_GL_HOST_H
#define HALO_IOS_GL_HOST_H

#include <stdint.h>

#ifdef __OBJC__
#import <UIKit/UIKit.h>
UIView *halo_ios_gl_create_view(void);
void halo_ios_gl_set_logger(void (^logger)(const char *));
#endif

int halo_ios_gl_sdl_init(uint32_t flags);
int halo_ios_gl_set_hint(const char *name, const char *value);
void halo_ios_gl_get_error(char *buffer, uint32_t size);
uint32_t halo_ios_gl_create_window(const char *title, int width, int height, int64_t flags);
void halo_ios_gl_window_size(int *width, int *height);
int halo_ios_gl_set_relative_mouse(uint32_t window, int enabled);
int halo_ios_gl_set_attribute(int attribute, int value);
uint32_t halo_ios_gl_create_context(uint32_t window);
int halo_ios_gl_make_current(uint32_t window, uint32_t context);
int halo_ios_gl_set_swap_interval(int interval);
int halo_ios_gl_swap_window(uint32_t window);
/* Caps the presented frame rate (0: only the display limits it); takes effect on the next frame. */
void halo_ios_gl_set_frame_cap(int fps);

void *halo_ios_gl_resolve_import(const char *import_name);
void halo_ios_gl_get_string(uint32_t name, int index, char *buffer, uint32_t size);
int halo_ios_gl_has_extension(const char *name);
uint32_t halo_ios_gl_read_buffer_word(uint32_t buffer, uint32_t offset);
void halo_ios_gl_buffer_write(uint32_t target, uint32_t offset, uint32_t size, const void *data);
void halo_ios_gl_fence_frame(uint32_t slot);
void halo_ios_gl_wait_frame(uint32_t slot);

#endif
