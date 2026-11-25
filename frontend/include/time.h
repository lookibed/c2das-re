/* <time.h> of the own libc header set (frontend/include/ARCHITECTURE.md). */
#ifndef _TIME_H
#define _TIME_H

#include <stddef.h>

typedef __INT64_TYPE__ clock_t;
typedef __INT64_TYPE__ time_t;
typedef int clockid_t;

#define CLOCKS_PER_SEC ((clock_t) 1000000)
#define CLOCK_REALTIME 0
#define CLOCK_MONOTONIC 1

struct tm {
    int tm_sec;
    int tm_min;
    int tm_hour;
    int tm_mday;
    int tm_mon;
    int tm_year;
    int tm_wday;
    int tm_yday;
    int tm_isdst;
    __INT64_TYPE__ __tm_gmtoff;
    const char *__tm_zone;
};

struct timespec {
    time_t tv_sec;
    __INT64_TYPE__ tv_nsec;
};

clock_t clock(void);
time_t time(time_t *);
double difftime(time_t, time_t);
time_t mktime(struct tm *);
size_t strftime(char *, size_t, const char *, const struct tm *);
struct tm *gmtime(const time_t *);
struct tm *localtime(const time_t *);
int clock_gettime(clockid_t, struct timespec *);

#endif
