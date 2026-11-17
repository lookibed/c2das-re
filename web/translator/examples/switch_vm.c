// A tiny register machine: its dense switch is the shape the --switch-dispatch knob changes
// (chain: cases tested in turn; goto: a jump table; table: flat labels).
#include <stdio.h>

enum { SET, MOV, ADD, SUB, MUL, DEC, JNZ, PRINT, NOP, HALT };

static int run(const int *code)
{
    int r[4] = {0, 0, 0, 0};
    int pc = 0;
    for (;;) {
        int op = code[pc++];
        switch (op) {
        case SET: r[code[pc]] = code[pc + 1]; pc += 2; break;
        case MOV: r[code[pc]] = r[code[pc + 1]]; pc += 2; break;
        case ADD: r[code[pc]] += r[code[pc + 1]]; pc += 2; break;
        case SUB: r[code[pc]] -= r[code[pc + 1]]; pc += 2; break;
        case MUL: r[code[pc]] *= r[code[pc + 1]]; pc += 2; break;
        case DEC: r[code[pc]]--; pc += 1; break;
        case JNZ: pc = r[code[pc]] ? code[pc + 1] : pc + 2; break;
        case PRINT: printf("r%d = %d\n", code[pc], r[code[pc]]); pc += 1; break;
        case NOP: break;
        case HALT: return r[code[pc]];
        default: return -1;
        }
    }
}

int main(void)
{
    // r0 = 1, r1 = 5; loop: print r1; r0 *= r1; r1--; if r1 goto loop; halt with r0 = 5!
    static const int code[] = {
        SET, 0, 1, SET, 1, 5,
        PRINT, 1, MUL, 0, 1, DEC, 1, JNZ, 1, 6,
        NOP, HALT, 0,
    };
    printf("5! = %d\n", run(code));
    return 0;
}
