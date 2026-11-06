/* The program test_sampler.das runs under perf/sampler/sampler.c: main times hot_caller between
   two clock() calls, the window SAMPLER_GATE=clock records; hot_caller calls hot_leaf, a loop in
   registers that keeps no frame, so its samples' stack-top word is hot_caller's return address.
   Each define is one more case: NO_CLOCK never calls clock(); EXIT_AFTER leaves through _exit
   after the window; SLEEP_AFTER sleeps after it and prints whether the sleep was interrupted;
   FORK forks a child that runs hot_caller and leaves through exit; DLOPEN runs lib_run of the
   library argv[1] names in the window and dlcloses it before the second clock(); GETTIME never
   calls clock(): it reads clock_gettime three times, cold_leaf between the first two and
   hot_caller between the last two, the pair gate_shim.c turns into the gate. */
#include <stdio.h>
#include <time.h>
#ifdef DLOPEN
#include <dlfcn.h>
#endif
#if defined(EXIT_AFTER) || defined(FORK)
#include <stdlib.h>
#include <unistd.h>
#endif
#ifdef FORK
#include <sys/wait.h>
#endif

static volatile unsigned rounds = 300000000u;

__attribute__((noinline)) unsigned hot_leaf(unsigned n)
{
    unsigned x = 1;
    for (unsigned i = 0; i < n; i++)
        x = x * 1664525u + 1013904223u;
    return x;
}

__attribute__((noinline)) unsigned hot_caller(unsigned n)
{
    return hot_leaf(n) ^ 7u;
}

#ifdef GETTIME
static long now_ns(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000000000L + ts.tv_nsec;
}

__attribute__((noinline)) unsigned cold_leaf(unsigned n)
{
    unsigned x = 0;
    for (unsigned i = 0; i < n; i++)
        x += i ^ (x >> 3);
    return x;
}
#endif

int main(int argc, char **argv)
{
    (void)argc;
    (void)argv;
#ifdef NO_CLOCK
    printf("%u\n", hot_caller(rounds));
#elif defined(GETTIME)
    long t0 = now_ns();
    unsigned c = cold_leaf(rounds / 2);
    long t1 = now_ns();
    unsigned r = hot_caller(rounds);
    long t2 = now_ns();
    printf("%u %u %ld %ld\n", c, r, t1 - t0, t2 - t1);
#else
    clock_t start = clock();
#ifdef DLOPEN
    void *lib = dlopen(argv[1], RTLD_NOW);
    if (!lib)
        return 3;
    unsigned (*lib_run)(unsigned) = (unsigned (*)(unsigned))dlsym(lib, "lib_run");
    unsigned r = lib_run(rounds);
    dlclose(lib);
#elif defined(FORK)
    pid_t child = fork();
    if (child == 0) {
        printf("child %u\n", hot_caller(rounds / 4));
        exit(0);
    }
    unsigned r = hot_caller(rounds);
    waitpid(child, NULL, 0);
#else
    unsigned r = hot_caller(rounds);
#endif
    printf("%u %ld\n", r, (long)(clock() - start));
#ifdef SLEEP_AFTER
    struct timespec pause = { 0, 20000000 };
    printf("sleep rc %d\n", nanosleep(&pause, NULL));
#endif
#ifdef EXIT_AFTER
    fflush(stdout);
    _exit(0);
#endif
#endif
    return 0;
}
