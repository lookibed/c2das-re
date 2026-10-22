/* P5.1 lua's VM dispatch: a loop over an opcode array whose switch cases jump into another
   case's block (`goto l_call`, `goto l_loop`, lvm.c's `l_tforcall` and `l_tforloop`) and into
   the middle of one (`goto done`, lvm.c's `ret`), each goto re-dispatching the switch */
static volatile int rounds = 40000;
static int result;
static const unsigned char code[16] = { 0, 1, 2, 3, 4, 1, 0, 2, 3, 4, 0, 0, 1, 2, 4, 3 };
static int run_code(int seed) {
    int acc = seed, pc = 0, n = 0;
    while (pc < 16) {
        switch (code[pc++]) {
        case 0:
            acc += 3;
            if (acc > 60000)
                goto done;
            break;
        case 1:
            acc ^= pc;
            goto l_call;
        case 2: {
          l_call: {
            acc = acc * 5 + 1;
            goto l_loop;
          }
        }
        case 3: {
          l_loop: {
            acc -= n;
            n++;
            break;
          }
        }
        case 4:
            if (acc & 1)
                acc >>= 1;
            else
                acc += 7;
          done:
            acc &= 0xffff;
            break;
        }
    }
    return acc;
}
static void kernel_run(void) {
    int n = rounds;
    unsigned acc = 0;
    int i;
    for (i = 0; i < n; i++)
        acc = acc * 31 + (unsigned) run_code((int) ((acc ^ (unsigned) i) & 1023));
    result = (int) (acc & 0x7fffffff);
}
static int kernel_result(void) { return result; }
