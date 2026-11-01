/* P7.0b lua's hook check per instruction: `if (l_unlikely(trap))` over `__builtin_expect`, the trap
   re-read from a `volatile` field (`updatetrap(ci)`) as the VM does after each protected step */
typedef struct CallInfo { volatile int trap; int savedpc; } CallInfo;
#define l_unlikely(x) __builtin_expect(((x) != 0), 0)
static volatile int rounds = 20000;
static CallInfo info;
static int result;
static int step(CallInfo *ci, int n) {
    int acc = 0;
    int trap = ci->trap;
    for (int r = 0; r < n; r++) {
        for (int pc = 0; pc < 64; pc++) {
            if (l_unlikely(trap)) {
                acc -= 1;
            }
            acc += pc;
            trap = ci->trap;
        }
    }
    return acc;
}
static void kernel_run(void) {
    info.trap = 0;
    result = step(&info, rounds);
}
static int kernel_result(void) { return result; }
