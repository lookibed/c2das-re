// A sampling profiler loaded with LD_PRELOAD: a timer signal stores the interrupted RIP and the
// word at the stack top (a leaf's return address, the caller of a frameless runtime helper);
// the samples and /proc/self/maps go to SAMPLER_OUT.<pid> at exit or _exit; symbolize.sh names
// the PCs.
// SAMPLER_US is the period in microseconds (default 250) on CLOCK_MONOTONIC, delivered to the
// thread that loaded the library. SAMPLER_GATE=clock records only between the first and the
// second call of clock(), the window doom/host/doom_main.c times, and writes the file there.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <time.h>
#include <ucontext.h>
#include <unistd.h>

// overridable at the build (-D), the test's small caps among them
#ifndef MAX_SAMPLES
#define MAX_SAMPLES (1 << 21)
#endif

static uintptr_t samples[MAX_SAMPLES];
static uintptr_t stack_tops[MAX_SAMPLES];
static volatile long sample_count;
static volatile long dropped;
static volatile int recording;
static int gated;
static int clock_calls;
static timer_t timer;
static int timer_armed;
static char out_path[4096];
static int written;

static void on_tick(int sig, siginfo_t *info, void *context)
{
    (void)sig;
    (void)info;
    if (!recording)
        return;
    ucontext_t *uc = (ucontext_t *)context;
    uintptr_t pc = (uintptr_t)uc->uc_mcontext.gregs[REG_RIP];
    uintptr_t sp = (uintptr_t)uc->uc_mcontext.gregs[REG_RSP];
    if (sample_count < MAX_SAMPLES) {
        stack_tops[sample_count] = *(const uintptr_t *)sp;
        samples[sample_count++] = pc;
    }
    else
        dropped++;
}

#ifndef MAPS_BYTES
#define MAPS_BYTES (1 << 22)
#endif
// the room the dlclose snapshots leave for the one written at the end
#ifndef MAPS_FINAL_RESERVE
#define MAPS_FINAL_RESERVE (1 << 20)
#endif

// every snapshot of /proc/self/maps, so a library unloaded before exit still names its PCs
static char maps[MAPS_BYTES];
static size_t maps_used;
// a snapshot cut short by the buffer's end: the file says so
static int maps_truncated;

static void snapshot_maps(size_t limit)
{
    int fd = open("/proc/self/maps", O_RDONLY);
    if (fd < 0)
        return;
    ssize_t got = 1;
    while (maps_used < limit && (got = read(fd, maps + maps_used, limit - maps_used)) > 0)
        maps_used += (size_t)got;
    if (maps_used >= limit && got > 0)
        maps_truncated = 1;
    close(fd);
}

static void write_samples(void)
{
    if (written || !out_path[0] || (sample_count == 0 && clock_calls == 0))
        return;
    written = 1;
    recording = 0;
    if (timer_armed) {
        // no SIGPROF after the file: a later syscall would see EINTR
        timer_delete(timer);
        timer_armed = 0;
    }
    char path[4200];
    snprintf(path, sizeof path, "%s.%d", out_path, (int)getpid());
    FILE *out = fopen(path, "w");
    if (!out)
        return;
    fprintf(out, "# samples %ld dropped %ld clock_calls %d\n", sample_count, dropped, clock_calls);
    for (long i = 0; i < sample_count; i++)
        fprintf(out, "%lx %lx\n", (unsigned long)samples[i], (unsigned long)stack_tops[i]);
    snapshot_maps(MAPS_BYTES);
    fprintf(out, "# maps\n");
    if (maps_truncated)
        fprintf(out, "# maps truncated: the snapshots filled %d bytes\n", MAPS_BYTES);
    fwrite(maps, 1, maps_used, out);
    fclose(out);
}

int dlclose(void *handle)
{
    static int (*real_dlclose)(void *);
    if (!real_dlclose)
        real_dlclose = (int (*)(void *))dlsym(RTLD_NEXT, "dlclose");
    if (out_path[0])
        snapshot_maps(MAPS_BYTES - MAPS_FINAL_RESERVE);
    return real_dlclose(handle);
}

// daslang's c_exit and C's _Exit skip atexit: the file is written before them
void _exit(int code)
{
    static void (*real_exit)(int);
    if (!real_exit)
        real_exit = (void (*)(int))dlsym(RTLD_NEXT, "_exit");
    write_samples();
    real_exit(code);
    __builtin_unreachable();
}

void _Exit(int code)
{
    _exit(code);
}

// a forked child inherits the atexit handler and the samples, not the timer: it writes nothing
static void forked_child(void)
{
    out_path[0] = 0;
    recording = 0;
    timer_armed = 0;
}

clock_t clock(void)
{
    static clock_t (*real_clock)(void);
    if (!real_clock)
        real_clock = (clock_t (*)(void))dlsym(RTLD_NEXT, "clock");
    clock_calls++;
    if (gated) {
        if (clock_calls == 1)
            recording = 1;
        else if (clock_calls == 2) {
            // daslang's c_exit leaves through _exit: no atexit handler or destructor runs
            clock_t now = real_clock();
            write_samples();
            return now;
        }
    }
    return real_clock();
}

__attribute__((constructor)) static void sampler_start(void)
{
    const char *out = getenv("SAMPLER_OUT");
    if (!out || !out[0])
        return;
    snprintf(out_path, sizeof out_path, "%s", out);
    const char *us_text = getenv("SAMPLER_US");
    long us = us_text ? atol(us_text) : 250;
    if (us <= 0)
        us = 250;
    const char *gate = getenv("SAMPLER_GATE");
    gated = gate && strcmp(gate, "clock") == 0;
    recording = !gated;
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = on_tick;
    sa.sa_flags = SA_SIGINFO | SA_RESTART;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGPROF, &sa, NULL);
    struct sigevent ev;
    memset(&ev, 0, sizeof ev);
    ev.sigev_notify = SIGEV_THREAD_ID;
    ev.sigev_signo = SIGPROF;
    ev._sigev_un._tid = (pid_t)syscall(SYS_gettid);
    if (timer_create(CLOCK_MONOTONIC, &ev, &timer) != 0)
        return;
    timer_armed = 1;
    struct itimerspec period;
    period.it_interval.tv_sec = us / 1000000;
    period.it_interval.tv_nsec = (us % 1000000) * 1000;
    period.it_value = period.it_interval;
    timer_settime(timer, 0, &period, NULL);
    atexit(write_samples);
    pthread_atfork(NULL, NULL, forked_child);
}

__attribute__((destructor)) static void sampler_stop(void)
{
    write_samples();
}
