#include <setjmp.h>

int printf(const char *, ...);

/* the general setjmp form: the value stored (`r = setjmp(buf)`), declared (`int r =
   setjmp(buf)`), switched on, compared with a value other than zero, discarded, and returned (no
   longjmp reaches that one, whose frame is gone); after a re-entry the code reads only
   volatiles, globals and the value just stored, the C rule (a non-volatile local changed since
   the setjmp is indeterminate after longjmp) */
static jmp_buf buf;
static int sum;

static void jump(int v) { longjmp(buf, v); }

static void stored(void) {
    volatile int count = 0;
    int r;
    r = setjmp(buf);
    sum += r;
    count++;
    if (count <= 3) {
        jump(count);
    }
    printf("stored %d %d %d\n", r, sum, count);
}

static void declared(void) {
    volatile int seen = 0;
    int r = setjmp(buf);
    seen += r;
    if (r < 2) {
        jump(r + 1);
    }
    printf("declared %d %d\n", r, seen);
}

static void switched(void) {
    volatile int trail = 0;
    switch (setjmp(buf)) {
    case 0:
        trail = trail * 10 + 1;
        jump(2);
        break;
    case 2:
        trail = trail * 10 + 2;
        jump(5);
        break;
    default:
        trail = trail * 10 + 9;
        break;
    }
    printf("switched %d\n", trail);
}

static int compared(void) {
    static int passes;
    if (setjmp(buf) == 4) {
        printf("compared again after %d\n", passes);
        return passes;
    } else {
        passes++;
    }
    jump(4);
    return -1;
}

static int discarded(void) {
    static int stop;
    setjmp(buf);
    if (!stop) {
        stop = 1;
        jump(1);
    }
    return stop + 10;
}

static int returned(void) {
    return setjmp(buf);
}

int main(void) {
    stored();
    declared();
    switched();
    printf("compared %d\n", compared());
    printf("discarded %d\n", discarded());
    printf("returned %d\n", returned());
    return 0;
}
