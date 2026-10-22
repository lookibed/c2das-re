/* P4.9 the general setjmp form: `r = setjmp(buf)` re-entered by longjmp in a hot loop, each value
   it returns accumulated; after a re-entry the code reads only volatiles, statics and the value
   just stored, the C rule */
/* glibc's `jmp_buf` (200 bytes), declared here since a kernel includes no header */
struct __jmp_buf_tag { long long words[25]; };
typedef struct __jmp_buf_tag jmp_buf[1];
int _setjmp(jmp_buf);
void longjmp(jmp_buf, int);
static volatile int rounds = 20000;
static int result;
static jmp_buf buf;
static unsigned total;
static void bounce(int v) { longjmp(buf, v); }
static void spin(int n) {
    volatile int left = n;
    int r;
    r = _setjmp(buf);
    total = total * 33 + (unsigned) r;
    if (left > 0) {
        left = left - 1;
        bounce((left & 7) + 1);
    }
}
static void kernel_run(void) {
    total = 0;
    spin(rounds);
    result = (int) (total & 0x7fffffff);
}
static int kernel_result(void) { return result; }
