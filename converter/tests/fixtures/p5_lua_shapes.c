/* the shapes lua 5.4.8 showed the converter, one per defect P5.1 fixed, each named by the lua
   line that met it */
#include <ctype.h>
#include <errno.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "p5_lua_shapes.h"

typedef int (*handler)(int);

static int twice(int v) {
    return v * 2;
}

/* lstate.h:325 `volatile lua_Hook hook;`, liolib.c:216 `volatile lua_CFunction cf` */
struct hooked {
    volatile handler hook;
    int calls;
};

static int volatile_pointers(void) {
    struct hooked h;
    volatile handler local = twice;
    h.hook = twice;
    h.calls = 0;
    h.calls += h.hook(3);
    return h.calls + local(4);
}

/* ltm.c:30 `LUAI_DDEF const char *const luaT_typenames_[LUA_TOTALTYPES] = {` */
const char *const shape_names[3] = {"nil", "cell", "table"};

/* lapi.c:35 `const char lua_ident[] = "$LuaVersion: " ...` */
const char shapes_ident[] = "$Shapes: " "5.4" " $";

/* luac.c:37 `static char Output[]={ OUTPUT };`: a string literal in braces */
#define OUTPUT "luac" ".out"
static char output[] = {OUTPUT};

/* ldump.c:73 `dumpVector(D, buff + DIBS - n, n)`: a computed pointer less a count */
#define DIBS 10
static int computed_back(int n, unsigned long k) {
    unsigned char buff[DIBS];
    unsigned char *last = buff + DIBS - n;
    unsigned char *first = buff + DIBS - k;
    return (int) (last - buff) * 100 + (int) (first - buff);
}

/* luaconf.h:684 `luai_likely`: GCC's branch hint */
#define likely(x) (__builtin_expect(((x) != 0), 1))
#define unlikely(x) (__builtin_expect(((x) != 0), 0))
static int hinted(int x) {
    if (likely(x > 2)) {
        return 1;
    }
    return unlikely(x < 0) ? -1 : 0;
}

/* lbaselib.c:66 `isalnum((unsigned char)*s)`, lstrlib.c:131 `tolower`: <ctype.h> as functions */
static int classified(const char *s) {
    int n = 0;
    for (; *s; s++) {
        n = n * 2 + (isalnum((unsigned char) *s) != 0);
        n += isspace((unsigned char) *s) != 0 ? 100 : 0;
        n += toupper((unsigned char) *s) == 'Q' ? 1000 : 0;
    }
    return n;
}

/* lmathlib.c, ltable.c:134 `frexp`, llimits.h:334 `luai_nummod`'s `fmod`: <math.h> */
static void math_calls(double x) {
    int e = 0;
    double m = frexp(x, &e);
    printf("math %g %g %g %g %g %g %d %g\n", floor(x), ceil(x), fabs(-x), sqrt(x), pow(x, 2.0), fmod(x, 2.0), e, m);
    printf("math %.6f %.6f %.6f %.6f %.6f %.6f\n", sin(x), cos(x), atan2(x, 1.0), exp(1.0), log(x), log10(1000.0));
    printf("math %g %g %g\n", ldexp(m, e), log2(8.0), tan(0.0) + asin(0.0) + acos(1.0) + atan(0.0));
}

/* lstrlib.c:1490 `struct cD { char c; union { LUAI_MAXALIGN; } u; };` in `getoption(Header *, const
   char **, int *)`: a record of a function whose parameters spell pointers */
static int max_align(const char **fmt, int *size) {
    struct cD { char c; union { double n; void *s; long long i; } u; } probe;
    probe.u.i = 7;
    *size = (int) sizeof(struct cD);
    return (int) offsetof(struct cD, u) + (fmt == 0) + (int) probe.u.i;
}

/* lstrlib.c:749 `strpbrk(p + upto, SPECIALS)`, lobject.c:362 `strspn`, lvm.c:387 `strcoll`, lstrlib.c:433
   `isgraph`, lauxlib.c:247 `int en = errno;`, lstrlib.c:1026 `HUGE_VAL` */
static void libc_pieces(void) {
    const char *s = "ab^$cd";
    errno = 0;
    strtol("99999999999999999999", 0, 10);
    printf("libc %d %d %d %d", (int) (strpbrk(s, "^$*") - s), (int) strspn(s, "abc"), strcoll("abc", "abd") < 0, isgraph('!') != 0);
    printf(" %d %d\n", errno == ERANGE, HUGE_VAL > 1e308 && -HUGE_VAL < -1e308);
    errno = 0;
}

/* lvm.c:638 `} while (--n > 0);` in `copy2buff`: a do-while whose condition has an effect, with a
   `continue` that reaches it; the guard turns a lowering that never runs the condition into a
   wrong value rather than a hang */
static int countdown(int n) {
    int total = 0;
    int guard = 0;
    do {
        if (++guard > 100) {
            return -1;
        }
        total += n;
        if (n == 3) {
            continue;
        }
        total *= 2;
    } while (--n > 0);
    return total * 100 + n;
}

int main(void) {
    int size = 0;
    printf("volatile pointers %d\n", volatile_pointers());
    printf("offsetof %d %d %d %d\n", (int) cell_offset(0), (int) cell_offset(2), cell_size(3), (int) offsetof(cell, count));
    printf("names %s %s %s %d\n", shape_names[1], shape_names[2], shapes_ident, (int) sizeof(shapes_ident));
    output[0] = 'L';
    printf("output %s %d\n", output, (int) sizeof(output));
    printf("computed %d\n", computed_back(3, 4ul));
    printf("hinted %d %d %d\n", hinted(5), hinted(1), hinted(-4));
    printf("classified %d\n", classified("aq Q!"));
    math_calls(5.5);
    libc_pieces();
    printf("countdown %d %d\n", countdown(5), countdown(0));
    printf("max_align %d", max_align(0, &size));
    printf(" %d\n", size);
    return 0;
}
