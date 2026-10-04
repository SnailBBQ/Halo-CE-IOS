#import "halo_ios_gl_host.h"

#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES3/gl.h>
#import <OpenGLES/ES3/glext.h>
#import <QuartzCore/CAEAGLLayer.h>

#include <dlfcn.h>
#include <time.h>
#include "halo_frame_pacer.h"
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>

NSString * const HaloIOSFirstFramePresentedNotification =
    @"HaloIOSFirstFramePresentedNotification";

@interface HaloIOSGLView : UIView
@end

@implementation HaloIOSGLView
+ (Class)layerClass
{
    return [CAEAGLLayer class];
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self)
    {
        self.backgroundColor = UIColor.blackColor;
        self.contentScaleFactor = UIScreen.mainScreen.nativeScale > 0.0
            ? UIScreen.mainScreen.nativeScale
            : UIScreen.mainScreen.scale;

        CAEAGLLayer *layer = (CAEAGLLayer *)self.layer;
        layer.opaque = YES;
        layer.drawableProperties = @{
            kEAGLDrawablePropertyRetainedBacking : @NO,
            kEAGLDrawablePropertyColorFormat : kEAGLColorFormatRGBA8,
        };
    }
    return self;
}
@end

static __weak HaloIOSGLView *g_view;
static EAGLContext *g_context;
static GLuint g_drawable_fbo;
static GLuint g_drawable_color;
static int g_drawable_width = 640;
static int g_drawable_height = 480;
static int g_requested_major = 3;
static int g_requested_minor = 0;
static char g_error[256];
static atomic_int g_first_presented;
static unsigned long g_present_attempts;
static unsigned long g_present_failures;
static void (^g_logger)(const char *);

void halo_ios_gl_set_logger(void (^logger)(const char *))
{
    // Installed before the guest starts; immutable during execution.
    g_logger = [logger copy];
}

static void report_gl(const char *format, ...)
{
    char message[768];
    va_list args;
    va_start(args, format);
    vsnprintf(message, sizeof(message), format, args);
    va_end(args);
    NSLog(@"[HaloIOS-GL] %s", message);
    if (g_logger) {
        char line[800];
        snprintf(line, sizeof(line), "[iOS-GL] %s", message);
        g_logger(line);
    }
}

static pthread_mutex_t g_gl_lock = PTHREAD_MUTEX_INITIALIZER;

#define FRAME_FENCE_SLOTS 8
static GLsync g_frame_fences[FRAME_FENCE_SLOTS];

static void set_error(const char *text)
{
    snprintf(g_error, sizeof(g_error), "%s", text ? text : "");
    report_gl("%s", g_error);
}

UIView *halo_ios_gl_create_view(void)
{
    HaloIOSGLView *view = [[HaloIOSGLView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    g_view = view;
    return view;
}

static int ensure_drawable(void)
{
    if (!g_context)
    {
        set_error("OpenGL ES context does not exist");
        return 0;
    }

    if (![EAGLContext setCurrentContext:g_context])
    {
        set_error("EAGLContext could not be made current");
        return 0;
    }

    HaloIOSGLView *view = g_view;
    if (!view)
    {
        set_error("iOS drawable view is unavailable");
        return 0;
    }

    CAEAGLLayer *layer = (CAEAGLLayer *)view.layer;

    if (!g_drawable_fbo)
        glGenFramebuffers(1, &g_drawable_fbo);
    if (!g_drawable_color)
        glGenRenderbuffers(1, &g_drawable_color);

    glBindFramebuffer(GL_FRAMEBUFFER, g_drawable_fbo);
    glBindRenderbuffer(GL_RENDERBUFFER, g_drawable_color);

    if (![g_context renderbufferStorage:GL_RENDERBUFFER fromDrawable:layer])
    {
        set_error("renderbufferStorage:fromDrawable failed");
        return 0;
    }

    glFramebufferRenderbuffer(GL_FRAMEBUFFER,
                              GL_COLOR_ATTACHMENT0,
                              GL_RENDERBUFFER,
                              g_drawable_color);

    GLint width = 0, height = 0;
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &width);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &height);
    if (width <= 0 || height <= 0)
    {
        set_error("iOS drawable has zero size");
        return 0;
    }

    g_drawable_width = width;
    g_drawable_height = height;

    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (status != GL_FRAMEBUFFER_COMPLETE)
    {
        snprintf(g_error, sizeof(g_error), "drawable framebuffer incomplete: 0x%04x", status);
        report_gl("%s", g_error);
        return 0;
    }

    glBindFramebuffer(GL_FRAMEBUFFER, g_drawable_fbo);
    glViewport(0, 0, width, height);
    return 1;
}

int halo_ios_gl_sdl_init(uint32_t flags)
{
    (void)flags;
    return g_view != nil;
}

int halo_ios_gl_set_hint(const char *name, const char *value)
{
    (void)name;
    (void)value;
    return 1;
}

void halo_ios_gl_get_error(char *buffer, uint32_t size)
{
    if (!buffer || !size)
        return;
    snprintf(buffer, size, "%s", g_error);
}

uint32_t halo_ios_gl_create_window(const char *title, int width, int height, int64_t flags)
{
    (void)title;
    (void)width;
    (void)height;
    (void)flags;
    if (!g_view)
    {
        set_error("HaloGLView was not created before SDL_CreateWindow");
        return 0;
    }
    return 1;
}

void halo_ios_gl_window_size(int *width, int *height)
{
    if (width) *width = g_drawable_width;
    if (height) *height = g_drawable_height;
}

int halo_ios_gl_set_relative_mouse(uint32_t window, int enabled)
{
    (void)window;
    (void)enabled;
    return 1;
}

int halo_ios_gl_set_attribute(int attribute, int value)
{
    /*
     * SDL_GLAttr values are deliberately not duplicated here. The recovered
     * Android path asks for ES 3.2 first and then ES 3.0. iOS supplies ES 3.0,
     * so the request is advisory and context creation below chooses API 3.
     */
    if (attribute == 17) /* SDL_GL_CONTEXT_MAJOR_VERSION */
        g_requested_major = value;
    else if (attribute == 18) /* SDL_GL_CONTEXT_MINOR_VERSION */
        g_requested_minor = value;
    return 1;
}

uint32_t halo_ios_gl_create_context(uint32_t window)
{
    (void)window;

    pthread_mutex_lock(&g_gl_lock);
    if (!g_context)
        g_context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];

    int ok = g_context != nil;
    if (ok)
        ok = ensure_drawable();
    pthread_mutex_unlock(&g_gl_lock);

    if (!ok)
        return 0;

    report_gl("OpenGL ES 3 context ready (guest requested %d.%d), drawable %dx%d",
          g_requested_major, g_requested_minor, g_drawable_width, g_drawable_height);
    return 1;
}

int halo_ios_gl_make_current(uint32_t window, uint32_t context)
{
    (void)window;
    if (!context || !g_context)
        return 0;
    return [EAGLContext setCurrentContext:g_context] ? 1 : 0;
}

int halo_ios_gl_set_swap_interval(int interval)
{
    (void)interval;
    /* EAGL presentation is display paced by iOS. */
    return 1;
}

/* Settings > Display: 60 holds the presented rate there; 0 lets the display's refresh decide. */
static _Atomic int g_frame_cap;
static HaloFramePacer g_pacer;
static HaloPresentTiming g_last_present_timing;
HaloPresentTiming halo_ios_gl_last_present_timing(void) { return g_last_present_timing; }

void halo_ios_gl_set_frame_cap(int fps)
{
    atomic_store_explicit(&g_frame_cap, fps < 0 ? 0 : fps, memory_order_relaxed);
}

static void pace_present(void)
{
    int cap = atomic_load_explicit(&g_frame_cap, memory_order_relaxed);
    uint64_t started=clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    uint64_t wait = halo_pacer_wait(&g_pacer, started, cap);

    if (wait) {
        struct timespec nap = { (time_t)(wait / 1000000000ull), (long)(wait % 1000000000ull) };
        nanosleep(&nap, NULL);
        g_last_present_timing.cap_wait_ns=clock_gettime_nsec_np(CLOCK_UPTIME_RAW)-started;
    }
}

int halo_ios_gl_swap_window(uint32_t window)
{
    (void)window;
    g_last_present_timing=(HaloPresentTiming){0};
    if (!g_context)
        return 0;
    pace_present();

    if ([EAGLContext currentContext] != g_context &&
        ![EAGLContext setCurrentContext:g_context])
        return 0;

    ++g_present_attempts;
    GLenum error;
    static unsigned error_reports;
    while ((error = glGetError()) != GL_NO_ERROR) {
        if (error_reports++ < 20)
            report_gl("GL error 0x%04x before presentation %lu", error, g_present_attempts);
    }
    glBindRenderbuffer(GL_RENDERBUFFER, g_drawable_color);
    uint64_t drawable_started=clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    BOOL ok = [g_context presentRenderbuffer:GL_RENDERBUFFER];
    g_last_present_timing.drawable_ns=clock_gettime_nsec_np(CLOCK_UPTIME_RAW)-drawable_started;

    if (!ok) ++g_present_failures;
    if (g_present_attempts == 1 || g_present_attempts == 60 ||
        g_present_attempts == 300 || g_present_attempts == 1800) {
        GLint previous_fbo;
        glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &previous_fbo);
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, g_drawable_fbo);
        GLenum status = glCheckFramebufferStatus(GL_DRAW_FRAMEBUFFER);
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, (GLuint)previous_fbo);
        report_gl("present %lu: failures=%lu drawable=%dx%d FBO=0x%04x",
                  g_present_attempts, g_present_failures, g_drawable_width, g_drawable_height, status);
    }

    if (ok && !atomic_exchange(&g_first_presented, 1))
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter]
                postNotificationName:HaloIOSFirstFramePresentedNotification
                              object:nil];
        });
    }
    return ok ? 1 : 0;
}

/*
 * EAGL drawables live in a non-zero framebuffer object. Halo's renderer
 * treats framebuffer 0 as the window framebuffer, as it would under EGL.
 * Redirect only the default-window binding; all game-created FBOs retain
 * their real object names.
 */
static void halo_glBindFramebuffer(GLenum target, GLuint framebuffer)
{
    if (framebuffer == 0 &&
        (target == GL_FRAMEBUFFER || target == GL_DRAW_FRAMEBUFFER))
        framebuffer = g_drawable_fbo;
    glBindFramebuffer(target, framebuffer);
}

/*
 * The guest bridge widens spilled integer arguments to 8-byte slots.
 * Apple's arm64 ABI packs native 32-bit stack arguments together, so calling
 * glBlitFramebuffer directly reads filter from the upper half of mask.
 * Receive the guest layout here and let the compiler repack the native call.
 */
static void halo_glBlitFramebuffer(GLint srcX0, GLint srcY0, GLint srcX1, GLint srcY1,
                                   GLint dstX0, GLint dstY0, GLint dstX1, GLint dstY1,
                                   long long mask, long long filter)
{
    static int reported;
    if (!reported)
    {
        reported = 1;
        report_gl("window blit ABI adapter: mask=0x%04x filter=0x%04x",
                  (unsigned int)mask, (unsigned int)filter);
    }
    glBlitFramebuffer(srcX0, srcY0, srcX1, srcY1,
                      dstX0, dstY0, dstX1, dstY1,
                      (GLbitfield)mask, (GLenum)filter);
}

static void halo_glCopyImageSubData_fallback(GLuint srcName, GLenum srcTarget, GLint srcLevel,
                                             GLint srcX, GLint srcY, GLint srcZ,
                                             GLuint dstName, GLenum dstTarget, GLint dstLevel,
                                             GLint dstX, GLint dstY, GLint dstZ,
                                             GLsizei srcWidth, GLsizei srcHeight, GLsizei srcDepth)
{
    (void)srcName; (void)srcTarget; (void)srcLevel; (void)srcX; (void)srcY; (void)srcZ;
    (void)dstName; (void)dstTarget; (void)dstLevel; (void)dstX; (void)dstY; (void)dstZ;
    (void)srcWidth; (void)srcHeight; (void)srcDepth;
}

static void halo_glDrawElementsBaseVertex_fallback(GLenum mode, GLsizei count, GLenum type,
                                                    const void *indices, GLint basevertex)
{
    /*
     * The Android renderer disables base-vertex rendering on ES 3.0, so this
     * is only a load-time placeholder. If it is unexpectedly reached, a
     * basevertex of zero is still safe to draw normally.
     */
    if (basevertex == 0)
        glDrawElements(mode, count, type, indices);
}

static uint64_t halo_gl_unavailable(void)
{
    return 0;
}

void *halo_ios_gl_resolve_import(const char *import_name)
{
    if (!import_name || strncmp(import_name, "hostgl_", 7))
        return NULL;

    const char *name = import_name + 7;

    if (!strcmp(name, "glBindFramebuffer"))
        return (void *)halo_glBindFramebuffer;

    if (!strcmp(name, "glBlitFramebuffer"))
        return (void *)halo_glBlitFramebuffer;

    void *function = dlsym(RTLD_DEFAULT, name);
    if (function)
        return function;

    if (!strcmp(name, "glCopyImageSubData"))
    {
        function = dlsym(RTLD_DEFAULT, "glCopyImageSubDataEXT");
        if (!function)
            function = dlsym(RTLD_DEFAULT, "glCopyImageSubDataOES");
        return function ? function : (void *)halo_glCopyImageSubData_fallback;
    }

    if (!strcmp(name, "glDrawElementsBaseVertex"))
    {
        function = dlsym(RTLD_DEFAULT, "glDrawElementsBaseVertexOES");
        return function ? function : (void *)halo_glDrawElementsBaseVertex_fallback;
    }

    report_gl("OpenGL ES import unavailable: %s (guarded fallback)", name);
    return (void *)halo_gl_unavailable;
}

void halo_ios_gl_get_string(uint32_t name, int index, char *buffer, uint32_t size)
{
    if (!buffer || !size)
        return;

    buffer[0] = 0;
    const GLubyte *value = NULL;
    if (index >= 0)
        value = glGetStringi((GLenum)name, (GLuint)index);
    else
        value = glGetString((GLenum)name);

    if (value)
    {
        strncpy(buffer, (const char *)value, size - 1);
        buffer[size - 1] = 0;
    }
}

int halo_ios_gl_has_extension(const char *name)
{
    if (!name || !*name)
        return 0;

    GLint count = 0;
    glGetIntegerv(GL_NUM_EXTENSIONS, &count);
    for (GLint i = 0; i < count; ++i)
    {
        const char *extension = (const char *)glGetStringi(GL_EXTENSIONS, (GLuint)i);
        if (extension && !strcmp(extension, name))
            return 1;
    }
    return 0;
}

uint32_t halo_ios_gl_read_buffer_word(uint32_t buffer, uint32_t offset)
{
    uint32_t value = 0;
    GLint previous = 0;

#ifdef GL_ATOMIC_COUNTER_BUFFER_BINDING
    glGetIntegerv(GL_ATOMIC_COUNTER_BUFFER_BINDING, &previous);
    glBindBuffer(GL_ATOMIC_COUNTER_BUFFER, buffer);
    const void *mapping = glMapBufferRange(GL_ATOMIC_COUNTER_BUFFER,
                                           offset,
                                           sizeof(value),
                                           GL_MAP_READ_BIT);
    if (mapping)
    {
        memcpy(&value, mapping, sizeof(value));
        glUnmapBuffer(GL_ATOMIC_COUNTER_BUFFER);
    }
    glBindBuffer(GL_ATOMIC_COUNTER_BUFFER, (GLuint)previous);
#else
    (void)buffer;
    (void)offset;
#endif
    return value;
}

void halo_ios_gl_buffer_write(uint32_t target, uint32_t offset, uint32_t size, const void *data)
{
    if (!size)
        return;

    void *mapping = glMapBufferRange((GLenum)target,
                                     (GLintptr)offset,
                                     (GLsizeiptr)size,
                                     GL_MAP_WRITE_BIT | GL_MAP_UNSYNCHRONIZED_BIT);
    if (mapping)
    {
        if (data)
            memcpy(mapping, data, size);
        glUnmapBuffer((GLenum)target);
    }
    else if (data)
        glBufferSubData((GLenum)target, (GLintptr)offset, (GLsizeiptr)size, data);
}

void halo_ios_gl_fence_frame(uint32_t slot)
{
    if (slot >= FRAME_FENCE_SLOTS)
        return;
    if (g_frame_fences[slot])
        glDeleteSync(g_frame_fences[slot]);
    g_frame_fences[slot] = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
}

void halo_ios_gl_wait_frame(uint32_t slot)
{
    if (slot >= FRAME_FENCE_SLOTS || !g_frame_fences[slot])
        return;

    glClientWaitSync(g_frame_fences[slot],
                     GL_SYNC_FLUSH_COMMANDS_BIT,
                     1000000000ull);
    glDeleteSync(g_frame_fences[slot]);
    g_frame_fences[slot] = NULL;
}
