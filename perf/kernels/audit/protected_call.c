/* P7.0b lua's protected call: luaD_rawrunprotected's `setjmp` around a call on every pass, no
   error raised, as each `pcall` and each `lua_resume` runs it */
struct __jmp_buf_tag { long long words[25]; };
typedef struct __jmp_buf_tag jmp_buf[1];
int _setjmp(jmp_buf);
void longjmp(jmp_buf, int);
struct lua_longjmp { struct lua_longjmp *previous; jmp_buf b; volatile int status; };
static volatile int rounds = 2000;
static struct lua_longjmp *error_jmp;
static int result;
static int counter;
static void body(int k) { counter += k & 3; }
static int rawrunprotected(int k) {
    struct lua_longjmp lj;
    lj.status = 0;
    lj.previous = error_jmp;
    error_jmp = &lj;
    if (_setjmp(lj.b) == 0) {
        body(k);
    }
    error_jmp = lj.previous;
    return lj.status;
}
static void kernel_run(void) {
    int n = rounds;
    int bad = 0;
    counter = 0;
    for (int k = 0; k < n; k++) bad += rawrunprotected(k);
    result = counter + bad;
}
static int kernel_result(void) { return result; }
