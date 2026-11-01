/* `__attribute__((musttail))` (P8.4 (c)), as wasm3's threaded ops end in the dispatch to the next
   op: the attributed `return f(...)` converts as a plain call whose value is returned, the same
   value with no tail call guaranteed; the chains here are short, so the stack holds them */
#include <stdio.h>

typedef int (*op_t)(const int *code, int pc, int acc);

static int op_add(const int *code, int pc, int acc);
static int op_double(const int *code, int pc, int acc);
static int op_end(const int *code, int pc, int acc);

static int dispatch(const int *code, int pc, int acc) {
    op_t next = code[pc] == 0 ? op_add : code[pc] == 1 ? op_double : op_end;
    __attribute__((musttail)) return next(code, pc + 1, acc);
}

static int op_add(const int *code, int pc, int acc) {
    __attribute__((musttail)) return dispatch(code, pc, acc + 1);
}

static int op_double(const int *code, int pc, int acc) {
    __attribute__((musttail)) return dispatch(code, pc, acc * 2);
}

static int op_end(const int *code, int pc, int acc) {
    (void)code;
    return acc * 100 + pc;
}

static int count_down(int n, int acc) {
    if (n == 0) {
        return acc;
    }
    __attribute__((musttail)) return count_down(n - 1, acc + n);
}

int main(void) {
    const int program[] = { 0, 0, 1, 0, 1, 2 };
    printf("program %d\n", dispatch(program, 0, 0));
    printf("count_down %d\n", count_down(100, 0));
    return 0;
}
