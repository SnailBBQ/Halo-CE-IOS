#define HALO_CRASH_TEST 1
#define _GNU_SOURCE
#include "../../port/ios/HaloIOS/halo_crash_report.c"
#include "halo_launch_state.h"
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); failures++; } } while (0)

int main(void)
{
    /* ---- decision logic */
    CHECK(halo_launch_next_level(NULL, 0, 0) == HALO_SAFE_NORMAL, "first ever launch is normal");
    CHECK(halo_launch_next_level("", 0, 0) == HALO_SAFE_NORMAL, "empty phase file is no information");
    CHECK(halo_launch_next_level("guest image", 0, 0) == HALO_SAFE_ON, "stopped while loading the image fails the start");
    CHECK(halo_launch_next_level("guest boot environment", 0, 0) == HALO_SAFE_ON, "boot environment phase");
    CHECK(halo_launch_next_level("guest entering __guest_start", 0, 0) == HALO_SAFE_ON, "prefix match");
    CHECK(halo_launch_next_level("waiting for maps", 0, 0) == HALO_SAFE_NORMAL, "waiting on the setup screen is not a failed start");
    CHECK(halo_launch_next_level("first frame presented", 0, 0) == HALO_SAFE_ON, "stopped before it ran long enough");
    CHECK(halo_launch_next_level("backgrounded", 0, 0) == HALO_SAFE_NORMAL, "going to the background is not a failure");
    CHECK(halo_launch_next_level("backgrounded", 0, 1) == HALO_SAFE_ON, "safe mode stays until a start succeeds");
    CHECK(halo_launch_next_level("exited", 0, 0) == HALO_SAFE_NORMAL, "exited");
    CHECK(halo_launch_next_level("running ok", 0, 1) == HALO_SAFE_NORMAL, "a good run leaves safe mode");
    CHECK(halo_launch_next_level("running ok", 1, 0) == HALO_SAFE_ON, "a crash report beats everything");
    CHECK(halo_launch_next_level("backgrounded", 1, 0) == HALO_SAFE_ON, "crash report with a stale phase");
    char text[200];
    CHECK(halo_launch_describe("guest image", 1, text, sizeof(text)) && strstr(text, "crashed") && strstr(text, "guest image"), "describe crash: %s", text);
    CHECK(halo_launch_describe("guest thread started", 0, text, sizeof(text)) && strstr(text, "stopped without a report"), "describe silent stop: %s", text);
    CHECK(!halo_launch_describe("running ok", 0, text, sizeof(text)) && text[0] == 0, "nothing to say after a good run");
    char tiny[10];
    halo_launch_describe("guest image", 1, tiny, sizeof(tiny));
    CHECK(strlen(tiny) < sizeof(tiny), "describe never overflows");

    /* ---- report formatting */
    char report[640];
    size_t n = halo_crash_format(report, sizeof(report), 11, 0x1234, 1, 0x300000000ull + 0x88001234, 0x300000000ull + 0x88000000, 0x300000000ull, "guest image");
    CHECK(n == strlen(report) && strstr(report, "signal=11") && strstr(report, "fault_address=0x1234") && strstr(report, "last_step=guest image"), "format basics: %s", report);
    CHECK(strstr(report, "guest_pc=0x88001234") && strstr(report, "guest_lr=0x88000000"), "guest addresses are relative to the arena: %s", report);
    n = halo_crash_format(report, sizeof(report), 6, 0, 0, 0x1000abcdull, 0x1000abd0ull, 0x300000000ull, "");
    CHECK(strstr(report, "host_pc=0x1000abcd") && strstr(report, "last_step=unknown"), "host pc: %s", report);
    char small[24];
    n = halo_crash_format(small, sizeof(small), -3, ~0ull, -1, 0, 0, 0, "x");
    CHECK(n < sizeof(small) && strlen(small) == n, "a tiny buffer is never overflowed (%zu)", n);

    /* ---- the real handler: a child process crashes and the report appears on disk */
    char folder[] = "/tmp/halo-crash-test-XXXXXX";
    CHECK(mkdtemp(folder) != NULL, "temp folder");
    pid_t child = fork();
    if (child == 0)
    {
        halo_crash_install(folder);
        halo_crash_phase("guest boot environment");
        volatile int *bad = (volatile int *)(uintptr_t)0x10;
        *bad = 1;
        _exit(0);
    }
    int status = 0;
    waitpid(child, &status, 0);
    CHECK(WIFSIGNALED(status) && WTERMSIG(status) == SIGSEGV, "the process still dies from SIGSEGV after reporting (status %d)", status);
    char phase[200], crash[700];
    int had = halo_crash_read_previous(folder, phase, sizeof(phase), crash, sizeof(crash));
    CHECK(had, "a crash report was written");
    CHECK(!strcmp(phase, "guest boot environment"), "phase on disk is '%s'", phase);
    CHECK(strstr(crash, "signal=11") && strstr(crash, "fault_address=0x10") && strstr(crash, "last_step=guest boot environment") && strstr(crash, "host_pc=0x"), "report: %s", crash);
    CHECK(halo_launch_next_level(phase, had, 0) == HALO_SAFE_ON, "the next start is a safe start");

    child = fork();
    if (child == 0) { halo_crash_install(folder); halo_crash_phase("running ok"); _exit(0); }
    waitpid(child, &status, 0);
    had = halo_crash_read_previous(folder, phase, sizeof(phase), crash, sizeof(crash));
    CHECK(!had && !strcmp(phase, "running ok"), "a clean run leaves no report (had %d, phase '%s')", had, phase);
    CHECK(halo_launch_next_level(phase, had, 1) == HALO_SAFE_NORMAL, "and returns to the normal start");

    child = fork();
    if (child == 0) { halo_crash_install(folder); halo_crash_phase("engine boot"); abort(); }
    waitpid(child, &status, 0);
    had = halo_crash_read_previous(folder, phase, sizeof(phase), crash, sizeof(crash));
    CHECK(had && strstr(crash, "signal=6") && WTERMSIG(status) == SIGABRT, "abort() is reported too: %s", crash);
    halo_crash_clear(folder);
    had = halo_crash_read_previous(folder, phase, sizeof(phase), crash, sizeof(crash));
    CHECK(!had, "clearing removes the report");

    if (!failures) printf("PASS: launch-state decisions, report formatting and the real crash handler (SIGSEGV and abort, reported then still fatal)\n");
    return failures ? 1 : 0;
}
