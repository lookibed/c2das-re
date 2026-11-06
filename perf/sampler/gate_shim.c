/* A gate for programs that read clock_gettime instead of clock(): preloaded after sampler.c
   (LD_PRELOAD=libsampler.so:libgate_shim.so, SAMPLER_GATE=clock), it counts the clock_gettime
   calls whose caller's mapped file holds one of SHIM_CALLER's comma-separated substrings (dladdr's
   file name: the bench's executable, or libstdc++ when crt's clock_gettime bind reaches libc through
   chrono) and calls clock() at the SHIM_OPEN-th and the SHIM_CLOSE-th (1-based, default 1 and 2),
   which the sampler takes as its gate's open and close. SHIM_LOG=1 reports each counted call on
   stderr. Build: clang -O2 -fPIC -shared -o libgate_shim.so gate_shim.c -ldl. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static int (*real_clock_gettime)(clockid_t, struct timespec *);
static int counted;

static int caller_matches(const char *file, const char *wanted)
{
    char list[256];
    strncpy(list, wanted, sizeof list - 1);
    list[sizeof list - 1] = 0;
    for (char *part = strtok(list, ","); part; part = strtok(NULL, ","))
        if (strstr(file, part))
            return 1;
    return 0;
}

int clock_gettime(clockid_t id, struct timespec *ts)
{
    if (!real_clock_gettime)
        real_clock_gettime = dlsym(RTLD_NEXT, "clock_gettime");
    int rc = real_clock_gettime(id, ts);
    const char *wanted = getenv("SHIM_CALLER");
    Dl_info info;
    if (!wanted || !dladdr(__builtin_return_address(0), &info) || !info.dli_fname || !caller_matches(info.dli_fname, wanted))
        return rc;
    counted++;
    const char *open = getenv("SHIM_OPEN"), *close = getenv("SHIM_CLOSE");
    int at_open = open ? atoi(open) : 1, at_close = close ? atoi(close) : 2;
    if (getenv("SHIM_LOG"))
        fprintf(stderr, "gate_shim: clock_gettime #%d from %s\n", counted, info.dli_fname);
    if (counted == at_open || counted == at_close)
        clock();
    return rc;
}
