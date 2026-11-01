/* P7.0b lua's opcode as an enum: `GET_OPCODE(i)` cast to `OpCode` on every instruction
   (lopcodes.h `cast(OpCode, ...)`), then compared against the enum's values */
typedef enum { OP_MOVE, OP_LOADI, OP_LOADF, OP_LOADK, OP_ADD, OP_SUB, OP_CALL, OP_RETURN } OpCode;
static volatile int rounds = 20000;
static unsigned code[64];
static int result;
static int count(int n) {
    int acc = 0;
    for (int r = 0; r < n; r++) {
        for (int pc = 0; pc < 64; pc++) {
            OpCode op = (OpCode) ((code[pc] ^ (unsigned) r) & 7u);
            if (op == OP_CALL) {
                acc += 3;
            } else if (op == OP_ADD) {
                acc += 1;
            } else {
                acc ^= (int) op;
            }
        }
    }
    return acc;
}
static void kernel_run(void) {
    for (int k = 0; k < 64; k++) code[k] = (unsigned) k * 2654435761u;
    result = count(rounds);
}
static int kernel_result(void) { return result; }
