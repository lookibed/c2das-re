/* `clock_gettime` (P8.4 (f)), as the Rust corpora's bench units time their loops: both clocks
   read into a `struct timespec`, the monotonic one never going back, the realtime one past 2023,
   an unknown clock refused; the values themselves are not printed, so both builds agree */
#include <stdio.h>
#include <errno.h>
#include <time.h>

static long long ns_of(const struct timespec *ts) {
    return (long long)ts->tv_sec * 1000000000LL + ts->tv_nsec;
}

int main(void) {
    struct timespec a, b, wall;
    int rc = clock_gettime(CLOCK_MONOTONIC, &a);
    volatile unsigned spin = 0;
    for (unsigned i = 0; i < 100000u; i++) {
        spin += i;
    }
    rc |= clock_gettime(CLOCK_MONOTONIC, &b);
    rc |= clock_gettime(CLOCK_REALTIME, &wall);
    printf("rc %d\n", rc);
    printf("monotonic forward %d\n", ns_of(&b) >= ns_of(&a));
    printf("nsec in range %d\n", a.tv_nsec >= 0 && a.tv_nsec < 1000000000L && wall.tv_nsec < 1000000000L);
    printf("realtime past 2023 %d\n", wall.tv_sec > 1700000000L);
    errno = 0;
    rc = clock_gettime((clockid_t)12345, &a);
    printf("unknown clock %d einval %d\n", rc, errno == EINVAL);
    return 0;
}
