/* P7.0b lua's VM dispatch: a switch over 48 opcodes in a hot loop, one case jumping into another's
   block as luaV_execute's do, the hot opcodes late in the case order as OP_CALL and OP_RETURN1 are */
static volatile int rounds = 2000;
static unsigned char code[64];
static int result;
static int run(int n) {
    int acc = 0;
    for (int r = 0; r < n; r++) {
        for (int pc = 0; pc < 64; pc++) {
            switch (code[pc]) {
            case 0: acc += 1; break;
            case 1: acc += 2; break;
            case 2: acc += 3; break;
            case 3: acc ^= 4; break;
            case 4: acc += 5; break;
            case 5: acc -= 6; break;
            case 6: acc += 7; break;
            case 7: acc ^= 8; break;
            case 8: acc += 9; break;
            case 9: acc -= 10; break;
            case 10: acc += 11; break;
            case 11: acc ^= 12; break;
            case 12: acc += 13; break;
            case 13: acc -= 14; break;
            case 14: acc += 15; break;
            case 15: acc ^= 16; break;
            case 16: acc += 17; break;
            case 17: acc -= 18; break;
            case 18: acc += 19; break;
            case 19: acc ^= 20; break;
            case 20: acc += 21; break;
            case 21: acc -= 22; break;
            case 22: acc += 23; break;
            case 23: acc ^= 24; break;
            case 24: acc += 25; break;
            case 25: acc -= 26; break;
            case 26: acc += 27; break;
            case 27: acc ^= 28; break;
            case 28: acc += 29; break;
            case 29: acc -= 30; break;
            case 30: acc += 31; break;
            case 31: acc ^= 32; break;
            case 32: acc += 33; break;
            case 33: acc -= 34; break;
            case 34: acc += 35; break;
            case 35: acc ^= 36; break;
            case 36: acc += 37; break;
            case 37: acc -= 38; break;
            case 38: acc += 39; break;
            case 39: acc ^= 40; break;
            case 40: acc += 41; goto shared;
            case 41: acc -= 42; break;
            case 42: acc += 43; break;
            case 43: acc ^= 44; break;
            case 44: acc += 45; break;
            case 45: acc -= 46; break;
            case 46: { shared: acc = acc * 3 + 1; break; }
            default: acc += 48; break;
            }
        }
    }
    return acc;
}
static void kernel_run(void) {
    for (int i = 0; i < 64; i++) code[i] = (unsigned char) (30 + (i * 7) % 18);
    result = run(rounds);
}
static int kernel_result(void) { return result; }
