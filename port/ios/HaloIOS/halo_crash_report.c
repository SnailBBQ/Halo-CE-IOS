/* ucontext.h needs this on Darwin (the PAGEZERO bridge defines it the same way) */
#ifndef _XOPEN_SOURCE
#define _XOPEN_SOURCE 700
#endif

#include "halo_crash_report.h"

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <ucontext.h>
#include <unistd.h>

#ifdef HALO_CRASH_TEST
/* tests build on Linux for x86-64 and arm64 */
#define HALO_CRASH_BASE() 0ull
#else
extern void *halo_guest_base_address(void);
#define HALO_CRASH_BASE() ((uint64_t)(uintptr_t)halo_guest_base_address())
#endif

static int g_crash_fd = -1;
static int g_phase_fd = -1;
static char g_phase[160];
static const int g_signals[] = { SIGSEGV, SIGBUS, SIGILL, SIGABRT, SIGTRAP, SIGFPE };

static uint64_t context_pc(const ucontext_t *context)
{
#if defined(__APPLE__) && (defined(__arm64__) || defined(__aarch64__))
    return context->uc_mcontext->__ss.__pc;
#elif defined(__aarch64__)
    return context->uc_mcontext.pc;
#elif defined(__x86_64__) && defined(__linux__)
    return (uint64_t)context->uc_mcontext.gregs[REG_RIP];
#else
    (void)context;
    return 0;
#endif
}

static uint64_t context_lr(const ucontext_t *context)
{
#if defined(__APPLE__) && (defined(__arm64__) || defined(__aarch64__))
    return context->uc_mcontext->__ss.__lr;
#elif defined(__aarch64__)
    return context->uc_mcontext.regs[30];
#else
    (void)context;
    return 0;
#endif
}

/* async-signal-safe formatting: no printf, no malloc */
static size_t put_text(char *out, size_t at, size_t size, const char *text)
{
    while (*text && at + 1 < size)
        out[at++] = *text++;
    return at;
}

static size_t put_hex(char *out, size_t at, size_t size, uint64_t value)
{
    static const char digits[] = "0123456789abcdef";
    char tmp[17];
    int n = 0;

    at = put_text(out, at, size, "0x");
    do
    {
        tmp[n++] = digits[value & 15];
        value >>= 4;
    } while (value && n < 16);
    while (n && at + 1 < size)
        out[at++] = tmp[--n];
    return at;
}

static size_t put_decimal(char *out, size_t at, size_t size, long value)
{
    char tmp[24];
    int n = 0;
    unsigned long v = value < 0 ? (unsigned long)(-value) : (unsigned long)value;

    if (value < 0 && at + 1 < size)
        out[at++] = '-';
    do
    {
        tmp[n++] = (char)('0' + v % 10);
        v /= 10;
    } while (v && n < 22);
    while (n && at + 1 < size)
        out[at++] = tmp[--n];
    return at;
}

/* Builds the report text; used by the handler and by the tests. Returns its length. */
size_t halo_crash_format(char *out, size_t size, int signal_number, uint64_t fault, long code, uint64_t pc, uint64_t lr,
                         uint64_t arena, const char *phase)
{
    size_t at = 0;

    at = put_text(out, at, size, "signal=");
    at = put_decimal(out, at, size, signal_number);
    at = put_text(out, at, size, "\nfault_address=");
    at = put_hex(out, at, size, fault);
    at = put_text(out, at, size, "\nsi_code=");
    at = put_decimal(out, at, size, code);
    at = put_text(out, at, size, "\nlast_step=");
    at = put_text(out, at, size, phase && *phase ? phase : "unknown");
    if (arena && pc >= arena && pc - arena < 0x100000000ull)
    {
        at = put_text(out, at, size, "\nguest_pc=");
        at = put_hex(out, at, size, pc - arena);
        at = put_text(out, at, size, "\nguest_lr=");
        at = put_hex(out, at, size, lr >= arena && lr - arena < 0x100000000ull ? lr - arena : lr);
    }
    else
    {
        at = put_text(out, at, size, "\nhost_pc=");
        at = put_hex(out, at, size, pc);
        at = put_text(out, at, size, "\nhost_lr=");
        at = put_hex(out, at, size, lr);
    }
    at = put_text(out, at, size, "\n");
    if (at >= size)
        at = size ? size - 1 : 0;
    if (size)
        out[at] = 0;
    return at;
}

static volatile sig_atomic_t g_hits;

static void crash_handler(int signal_number, siginfo_t *info, void *opaque)
{
    char report[640];
    const ucontext_t *context = (const ucontext_t *)opaque;
    int hits = ++g_hits;

    /* Only the first fault is written: a fault that returns into the same instruction repeats, and
       M2.6.35 filled crash.txt with 111 MB of the same report and left the app hung. */
    if (hits == 1 && g_crash_fd >= 0)
    {
        size_t length = halo_crash_format(report, sizeof(report), signal_number,
                                          info ? (uint64_t)(uintptr_t)info->si_addr : 0, info ? info->si_code : 0,
                                          context ? context_pc(context) : 0, context ? context_lr(context) : 0,
                                          HALO_CRASH_BASE(), g_phase);
        if (write(g_crash_fd, report, length) >= 0)
            fsync(g_crash_fd);
    }
    /* Put the default action back so the re-run of the faulting instruction ends the process (and the system
       writes its own crash log); whatever handler comes back after this one, a handler entered again and again
       ends the process itself. */
    signal(signal_number, SIG_DFL);
    if (hits >= 3)
        _exit(128 + signal_number);
}

void halo_crash_phase(const char *phase)
{
    size_t n = 0;

    if (!phase)
        return;
    while (phase[n] && n + 1 < sizeof(g_phase))
    {
        g_phase[n] = phase[n];
        n++;
    }
    g_phase[n] = 0;
    if (g_phase_fd >= 0)
    {
        if (ftruncate(g_phase_fd, 0) == 0 && pwrite(g_phase_fd, g_phase, n, 0) >= 0)
            fsync(g_phase_fd);
    }
}

static int read_file(const char *folder, const char *name, char *out, size_t size)
{
    char path[1100];
    int fd;
    ssize_t n;

    if (size)
        out[0] = 0;
    snprintf(path, sizeof(path), "%s/%s", folder, name);
    fd = open(path, O_RDONLY);
    if (fd < 0)
        return 0;
    n = read(fd, out, size - 1);
    close(fd);
    if (n < 0)
        n = 0;
    out[n] = 0;
    return (int)n;
}

int halo_crash_read_previous(const char *folder, char *phase, size_t phase_size, char *crash, size_t crash_size)
{
    int crash_length;

    read_file(folder, "launch-phase.txt", phase, phase_size);
    crash_length = read_file(folder, "crash.txt", crash, crash_size);
    /* a trailing newline is not part of the phase */
    for (size_t n = strlen(phase); n && (phase[n - 1] == '\n' || phase[n - 1] == '\r'); n--)
        phase[n - 1] = 0;
    return crash_length > 0;
}

void halo_crash_clear(const char *folder)
{
    char path[1100];

    snprintf(path, sizeof(path), "%s/crash.txt", folder);
    unlink(path);
}

void halo_crash_install(const char *folder)
{
    char path[1100];
    struct sigaction action;

    mkdir(folder, 0755);
    snprintf(path, sizeof(path), "%s/crash.txt", folder);
    g_crash_fd = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_APPEND, 0644);
    /* an empty crash.txt means "no crash": a report only exists once the handler wrote one */
    snprintf(path, sizeof(path), "%s/launch-phase.txt", folder);
    g_phase_fd = open(path, O_WRONLY | O_CREAT, 0644);
    memset(&action, 0, sizeof(action));
    action.sa_sigaction = crash_handler;
    sigemptyset(&action.sa_mask);
    action.sa_flags = SA_SIGINFO | SA_NODEFER;
    for (unsigned i = 0; i < sizeof(g_signals) / sizeof(g_signals[0]); i++)
        sigaction(g_signals[i], &action, NULL);
}
