#include <setjmp.h>
int printf(const char *, ...);
static jmp_buf outer;
static int depth_reached;
static void deep(int n, jmp_buf *target, int v) {
    depth_reached = n;
    if (n == 0) longjmp(*target, v);
    deep(n - 1, target, v);
}
static int protected_call(int fail_at, int value) {
    jmp_buf buf;
    int status = 0;
    if (setjmp(buf) == 0) {
        if (fail_at) deep(fail_at, &buf, value);
        status = 100;
    } else {
        status = -1;
    }
    return status + depth_reached;
}
static int targeted(int to_outer) {
    jmp_buf inner;
    int log = 0;
    if (!setjmp(inner)) {
        if (to_outer) deep(2, &outer, 3);
        deep(1, &inner, 5);
        log = 999;
    } else {
        log = 10;
    }
    return log;
}
static int zero_value(void) {
    jmp_buf buf;
    if (setjmp(buf)) {
        return 1;
    }
    longjmp(buf, 0);
    return 2;
}
/* a single-branch site whose tail calls nothing: the flat form; longjmp's 0 arrives as 1, so the
   branch is left and the tail runs once */
static int flat_not(int fail) {
    jmp_buf buf;
    volatile int st = 0;
    if (!setjmp(buf)) {
        if (fail) deep(2, &buf, 0);
        st = 1;
    }
    st = st + 20;
    return st + depth_reached;
}
/* a single-branch site whose tail longjmps to its own buffer: the trampoline reruns the tail */
static int again(void) {
    jmp_buf buf;
    volatile int passes = 0;
    if (setjmp(buf) == 0) {
        passes = passes + 1;
    }
    passes = passes + 10;
    if (passes < 30) longjmp(buf, 2);
    return passes;
}
int main(void) {
    int r = 0;
    int kept = flat_not(0);
    int left = flat_not(1);
    printf("%d %d %d\n", kept, left, again());
    printf("%d %d %d %d\n", protected_call(0, 1), protected_call(3, 7), targeted(0), zero_value());
    if (setjmp(outer) == 0) {
        r = targeted(1);
    } else {
        r = 1000;
    }
    printf("%d %d\n", r, depth_reached);
    return r / 100;
}
