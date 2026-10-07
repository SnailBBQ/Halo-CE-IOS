#define HALO_CRASH_TEST 1
#define _GNU_SOURCE
#include "../../port/ios/HaloIOS/halo_crash_report.c"
#include "halo_launch_state.h"
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); failures++; } } while (0)


/* ---- helpers for the M2.6.35 regression tests */
static struct sigaction g_front_old;
static void front_handler(int sig, siginfo_t *info, void *context)
{
    (void)info; (void)context;
    sigaction(sig, &g_front_old, NULL);      /* what the PAGEZERO bridge does with a fault that is not the guest's */
}
static void looping_handler(int sig, siginfo_t *info, void *context)
{
    struct sigaction again;
    crash_handler(sig, info, context);
    memset(&again, 0, sizeof(again));
    again.sa_sigaction = looping_handler;    /* a handler that keeps coming back */
    sigemptyset(&again.sa_mask);
    again.sa_flags = SA_SIGINFO | SA_NODEFER;
    sigaction(sig, &again, NULL);
}
static int count_text(const char *haystack, const char *needle)
{
    int n = 0;
    for (const char *p = haystack; (p = strstr(p, needle)) != NULL; p += strlen(needle)) n++;
    return n;
}

int main(void)
{
    /* ---- decision logic */
    CHECK(halo_launch_next_level(NULL, 0, 0) == HALO_SAFE_NORMAL, "first ever launch is normal");
    CHECK(halo_launch_next_level("", 0, 0) == HALO_SAFE_NORMAL, "empty phase file is no information");
    CHECK(halo_launch_next_level("guest image", 0, 0) == HALO_SAFE_ON, "stopped while loading the image fails the start");
    CHECK(halo_launch_next_level("guest boot environment", 0, 0) == HALO_SAFE_ON, "boot environment phase");
    CHECK(halo_launch_next_level("guest entering __guest_start", 0, 0) == HALO_SAFE_ON, "prefix match");
    CHECK(halo_launch_next_level("nonjb 413 calling __guest_start", 0, 0) == HALO_SAFE_ON, "Non-JB persistent execution breadcrumbs count as startup");
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

    /* ---- M2.6.35's failure: a handler in front hands the fault back and returns. One small report, then the
       process dies from the signal. (A hang ends in SIGALRM and fails the test.) */
    {
        char dir[] = "/tmp/halo-crash-chain-XXXXXX";
        struct stat st;
        char path[300], phase2[200], crash2[700];
        CHECK(mkdtemp(dir) != NULL, "temp folder 2");
        child = fork();
        if (child == 0)
        {
            struct sigaction front;
            alarm(10);
            halo_crash_install(dir);
            halo_crash_phase("guest image");
            memset(&front, 0, sizeof(front));
            front.sa_sigaction = front_handler;
            sigemptyset(&front.sa_mask);
            front.sa_flags = SA_SIGINFO | SA_NODEFER;
            sigaction(SIGSEGV, &front, &g_front_old);
            *(volatile int *)(uintptr_t)0x20 = 1;
            _exit(99);
        }
        waitpid(child, &status, 0);
        CHECK(WIFSIGNALED(status) && WTERMSIG(status) == SIGSEGV, "chained fault ends in SIGSEGV, not a hang or a clean exit (status %d)", status);
        snprintf(path, sizeof(path), "%s/crash.txt", dir);
        CHECK(stat(path, &st) == 0 && st.st_size > 0 && st.st_size < 1024, "crash.txt is one small report, %lld bytes", (long long)st.st_size);
        halo_crash_read_previous(dir, phase2, sizeof(phase2), crash2, sizeof(crash2));
        CHECK(count_text(crash2, "signal=") == 1 && strstr(crash2, "last_step=guest image"), "exactly one report: %s", crash2);
    }

    /* ---- a handler that is entered again and again ends the process itself after three entries */
    {
        char dir[] = "/tmp/halo-crash-loop-XXXXXX";
        struct stat st;
        char path[300], phase2[200], crash2[700];
        CHECK(mkdtemp(dir) != NULL, "temp folder 3");
        child = fork();
        if (child == 0)
        {
            struct sigaction loop;
            alarm(10);
            halo_crash_install(dir);
            halo_crash_phase("guest bridge installed");
            memset(&loop, 0, sizeof(loop));
            loop.sa_sigaction = looping_handler;
            sigemptyset(&loop.sa_mask);
            loop.sa_flags = SA_SIGINFO | SA_NODEFER;
            sigaction(SIGSEGV, &loop, NULL);
            *(volatile int *)(uintptr_t)0x30 = 1;
            _exit(99);
        }
        waitpid(child, &status, 0);
        CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 128 + SIGSEGV, "a looping handler ends the process with status %d (got %d)", 128 + SIGSEGV, status);
        snprintf(path, sizeof(path), "%s/crash.txt", dir);
        CHECK(stat(path, &st) == 0 && st.st_size > 0 && st.st_size < 1024, "still one small report, %lld bytes", (long long)st.st_size);
        halo_crash_read_previous(dir, phase2, sizeof(phase2), crash2, sizeof(crash2));
        CHECK(count_text(crash2, "signal=") == 1, "looping handler wrote one report: %s", crash2);
    }

    /* ---- the history of runs that ended badly (M2.6.78) */
    {
        char line[300], merged[1200], tiny[8];
        CHECK(!halo_launch_history_line("t", NULL, 0, line, sizeof(line)), "a first launch records nothing");
        CHECK(!halo_launch_history_line("t", "", 0, line, sizeof(line)), "an empty phase records nothing");
        CHECK(!halo_launch_history_line("t", "backgrounded", 0, line, sizeof(line)), "going to the background is not recorded");
        CHECK(!halo_launch_history_line("t", "exited", 0, line, sizeof(line)), "a normal exit is not recorded");
        CHECK(!halo_launch_history_line("t", "waiting for maps", 0, line, sizeof(line)), "waiting on the setup screen is not recorded");
        CHECK(!halo_launch_history_line("t", "backgrounded", 0, NULL, 0), "no room, nothing written");
        CHECK(halo_launch_history_line("2026-10-06 02:31:07", "guest thread started", 0, line, sizeof(line)) == 1, "a start that stopped is recorded");
        CHECK(strstr(line, "2026-10-06 02:31:07") && strstr(line, "'guest thread started'") && strstr(line, "stopped without a report") && line[strlen(line) - 1] == '\n',
              "the line names the time, the step and what happened: %s", line);
        CHECK(halo_launch_history_line("t", "running ok", 0, line, sizeof(line)) == 1 && strstr(line, "was running normally"), "a run that was going well is recorded: %s", line);
        CHECK(halo_launch_history_line("t", "guest image: protected", 1, line, sizeof(line)) == 1 && strstr(line, "crashed") && strstr(line, "'guest image: protected'"), "a crash is recorded with its step: %s", line);
        CHECK(halo_launch_history_line(NULL, "guest start", 0, line, sizeof(line)) == 1 && !strncmp(line, "?  launch", 9), "a missing time is shown as ?: %s", line);
        CHECK(halo_launch_history_line("t", NULL, 1, line, sizeof(line)) == 1 && strstr(line, "'unknown'"), "a crash with no step still gets a line: %s", line);

        merged[0] = 0;
        for (int i = 1; i <= 25; i++)
        {
            char one[40], next[1200];
            snprintf(one, sizeof(one), "line %d\n", i);
            halo_launch_history_append(merged, one, 20, next, sizeof(next));
            memcpy(merged, next, strlen(next) + 1);
        }
        CHECK(count_text(merged, "\n") == 20, "the history keeps 20 lines, has %d", count_text(merged, "\n"));
        CHECK(strstr(merged, "line 25\n") && strstr(merged, "line 6\n") && !strstr(merged, "line 5\n"), "the newest lines are kept, the oldest dropped");
        CHECK(halo_launch_history_append("one", "two\n", 20, merged, sizeof(merged)) == 8 && !strcmp(merged, "one\ntwo\n"), "a missing newline is repaired: %s", merged);
        CHECK(halo_launch_history_append(NULL, "only\n", 20, merged, sizeof(merged)) == 5 && !strcmp(merged, "only\n"), "no earlier history");
        CHECK(halo_launch_history_append("a\nb\n", "c\n", 1, merged, sizeof(merged)) == 2 && !strcmp(merged, "c\n"), "a limit of one keeps only the new line");
        CHECK(halo_launch_history_append("abcdefghij\n", "klmnop\n", 20, tiny, sizeof(tiny)) < sizeof(tiny) && strlen(tiny) < sizeof(tiny), "a small buffer is never overflowed");
        CHECK(halo_launch_history_append("x\n", "y\n", 20, NULL, 0) == 0, "no room, nothing written");
    }

    if (!failures) printf("PASS: launch-state decisions, report formatting, the start history and the real crash handler (SIGSEGV and abort, reported then still fatal)\n");
    return failures ? 1 : 0;
}
