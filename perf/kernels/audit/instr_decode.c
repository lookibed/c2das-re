/* P7.0b lua's instruction decode: lopcodes.h's GETARG_* on a 32-bit unsigned instruction, each a
   shift and a mask spelled `~((~(Instruction)0) << n)`, positions spelled as sums of sizes */
typedef unsigned int Instruction;
#define SIZE_OP 7
#define SIZE_A 8
#define SIZE_B 8
#define SIZE_C 8
#define POS_OP 0
#define POS_A (POS_OP + SIZE_OP)
#define POS_k (POS_A + SIZE_A)
#define POS_B (POS_k + 1)
#define POS_C (POS_B + SIZE_B)
#define MASK1(n, p) ((~((~(Instruction) 0) << (n))) << (p))
#define getarg(i, pos, size) ((int) (((i) >> (pos)) & MASK1(size, 0)))
#define GET_OPCODE(i) ((int) (((i) >> POS_OP) & MASK1(SIZE_OP, 0)))
static volatile int rounds = 20000;
static Instruction code[64];
static int result;
static int decode(int n) {
    int acc = 0;
    for (int r = 0; r < n; r++) {
        for (int pc = 0; pc < 64; pc++) {
            Instruction i = code[pc] ^ (Instruction) r;
            acc += GET_OPCODE(i) + getarg(i, POS_A, SIZE_A) + getarg(i, POS_B, SIZE_B) - getarg(i, POS_C, SIZE_C);
        }
    }
    return acc;
}
static void kernel_run(void) {
    for (int k = 0; k < 64; k++) code[k] = (Instruction) k * 2654435761u;
    result = decode(rounds);
}
static int kernel_result(void) { return result; }
