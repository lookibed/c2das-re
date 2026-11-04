/* P8.4 i: a calling convention in a type, as wasm3 spells `vectorcall` for
   `__attribute__((preserve_none))`: through the macro, the attribute itself, a typedef, a pointer
   declarator and a definition; das has one convention, so each keeps its result and parameters */
#include <stdio.h>
#define vectorcall __attribute__((preserve_none))
typedef int m3ret_t;
typedef m3ret_t(vectorcall *op_t)(int *pc, int acc);
static inline m3ret_t vectorcall op_add(int *pc, int acc) { return acc + pc[0]; }
static inline m3ret_t __attribute__((preserve_none)) op_mul(int *pc, int acc) { return acc * pc[0]; }
static m3ret_t (__attribute__((preserve_none)) *direct)(int *, int) = op_mul;
static m3ret_t (vectorcall *by_macro)(int *, int) = op_add;
static int run(op_t f, int *pc, int acc) { return f(pc, acc); }
int main(void) {
    int code[1] = {2};
    op_t f = op_add;
    printf("%d %d %d %d\n", f(code, 3), run(op_mul, code, 4), direct(code, 5), by_macro(code, 6));
    return 0;
}
