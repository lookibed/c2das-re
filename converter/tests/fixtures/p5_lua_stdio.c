/* The C library surface lua 5.4.8 reaches (P5.1 phase B): <stdio.h> through a FILE * the crt
   module takes as void *, the standard streams, fprintf, <time.h> with struct tm laid out from
   the system header, and <locale.h>'s struct lconv. The one argument is a directory the test
   creates and removes; every named file lives under it. lprefix.h's macros come first, as in
   every lua source: under _XOPEN_SOURCE glibc names struct tm's tail __tm_gmtoff and __tm_zone. */
#define _XOPEN_SOURCE 600
#define _LARGEFILE_SOURCE 1
#define _FILE_OFFSET_BITS 64
#include <locale.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef struct Stream { FILE *f; int closed; } Stream;

static char path[512];

static const char *in_dir(const char *dir, const char *name) {
    snprintf(path, sizeof(path), "%s/%s", dir, name);
    return path;
}

/* liolib.c:514 test_eof, liolib.c:522 read_line: getc, ungetc, fgets over a stream */
static int read_back(FILE *f) {
    char line[16];
    int c = getc(f);
    ungetc(c, f);
    if (fgets(line, sizeof(line), f) == NULL)
        return -1;
    printf("line: %s", line);
    return c;
}

/* liolib.c:269 io_open, liolib.c:664 g_write, liolib.c:703 f_seek, liolib.c:723 f_setvbuf,
   liolib.c:222 f_close: fopen, setvbuf, fputs, fwrite, fseek, ftell, fread, feof, freopen, fclose */
static void streams(const char *dir) {
    Stream s;
    char buf[8];
    size_t n;
    s.f = fopen(in_dir(dir, "a.txt"), "w+");
    s.closed = 0;
    if (s.f == NULL) {
        printf("fopen failed\n");
        return;
    }
    setvbuf(s.f, NULL, _IOFBF, 64);
    fputs("first\n", s.f);
    fwrite("xyz", 1, 3, s.f);
    fprintf(s.f, "%d-%s\n", 42, "go");
    fflush(s.f);
    printf("tell %ld\n", ftell(s.f));
    fseek(s.f, 0, SEEK_SET);
    printf("first char %c\n", read_back(s.f));
    n = fread(buf, 1, sizeof(buf) - 1, s.f);
    buf[n] = '\0';
    printf("read %d: %s|", (int) n, buf);
    n = fread(buf, 1, sizeof(buf) - 1, s.f);
    printf("then %d, eof %d, error %d\n", (int) n, feof(s.f) != 0, ferror(s.f));
    clearerr(s.f);
    printf("cleared eof %d\n", feof(s.f));
    s.f = freopen(in_dir(dir, "a.txt"), "r", s.f);
    printf("reopened %c\n", getc(s.f));
    s.closed = fclose(s.f) == 0;
    printf("closed %d\n", s.closed);
}

/* liolib.c:303 io_tmpfile */
static int write_and_close(FILE *t) {
    int ok = fputs("x", t) >= 0;
    fclose(t);
    return ok;
}

/* loslib.c:156 os_remove, loslib.c:163 os_rename, loslib.c:171 os_tmpname */
static void files(const char *dir) {
    char from[512], to[512], name[L_tmpnam];
    FILE *t = tmpfile();
    strcpy(from, in_dir(dir, "a.txt"));
    strcpy(to, in_dir(dir, "b.txt"));
    printf("rename %d\n", rename(from, to));
    printf("open old %d\n", fopen(from, "r") == NULL);
    printf("remove %d then %d\n", remove(to), remove(to) != 0);
    printf("tmpnam %d\n", tmpnam(name) != NULL);
    printf("tmpfile %d\n", t != NULL && write_and_close(t));
}

/* lauxlib.h:270 lua_writestringerror, lauxlib.c:792 the `=stdin` chunk, liolib.c:836
   createstdfile: the standard streams; loslib.c:142 os_execute */
static void standard(void) {
    FILE *out = stdout;
    printf("streams %d %d %d\n", stdin != NULL, out == stdout, stderr != NULL);
    fprintf(stdout, "through %s\n", "stdout");
    fflush(stdout);
    fprintf(stderr, "to %s\n", "stderr");
    fflush(stderr);
    printf("system %d\n", system(NULL) != 0);
    /* liolib.c:182 f_tostring's `%p` of a FILE *, a record pointer among the trailing arguments */
    snprintf(path, sizeof(path), "%p", out);
    printf("pointer %d\n", path[0] != '\0');
}

/* loslib.c:232 setallfields, loslib.c:346 os_time: struct tm from the system header */
static void times(void) {
    struct tm ts, *stm;
    time_t t = 86400 * 365;
    char buf[64];
    memset(&ts, 0, sizeof(ts));
    ts.tm_year = 100;
    ts.tm_mon = 0;
    ts.tm_mday = 32;
    ts.tm_hour = 12;
    ts.tm_isdst = -1;
    printf("mktime ok %d\n", mktime(&ts) != (time_t) -1);
    printf("normalized %d-%d\n", ts.tm_mon, ts.tm_mday);
    strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M", &ts);
    printf("strftime %s\n", buf);
    stm = gmtime(&t);
    printf("gmtime %d %d %d\n", stm->tm_year, stm->tm_mon, stm->tm_mday);
    stm = localtime(&t);
    printf("localtime %d\n", stm != NULL && stm->tm_year >= 70);
    printf("difftime %.1f\n", difftime(t + 30, t));
    printf("time %d clock %d\n", time(NULL) > 1700000000, clock() >= 0);
    printf("tm fits %d\n", (int) sizeof(struct tm) >= 9 * (int) sizeof(int));
}

/* lobject.c:264 lua_getlocaledecpoint, loslib.c:382 os_setlocale: the C locale */
static void locale(void) {
    printf("point %c\n", localeconv()->decimal_point[0]);
    printf("setlocale %s\n", setlocale(LC_ALL, "C"));
    printf("query %s\n", setlocale(LC_NUMERIC, NULL));
}

int main(int argc, char **argv) {
    if (argc < 2)
        return 2;
    streams(argv[1]);
    files(argv[1]);
    standard();
    times();
    locale();
    return 0;
}
