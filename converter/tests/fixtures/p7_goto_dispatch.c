/* P7.0c2: switches under switch_dispatch goto: dense ones take the jump table (an enum VM dispatch with a
   goto into another case, a continue and a default; an int switch without default; an unsigned one; one
   nested in another's case), the rest keep their forms (sparse, falling through, under 8 values, past int,
   Duff's device); main returns 0 when every result is C's */
enum Op { A, B, C, D, E, F, G, H, I, J };
static int run(const unsigned char *code, int n) {
    int acc = 0;
    for (int pc = 0; pc < n; pc++) {
        switch ((enum Op)code[pc]) {
        case A: acc += 1; break;
        case B: acc += 2; break;
        case C: acc *= 3; break;
        case D: acc -= 4; goto shared;
        case E: acc += 5; break;
        case F: { shared: acc = acc * 2 + 1; break; }
        case G: acc ^= 7; break;
        case H: if (acc > 1000) return acc; acc += 8; break;
        case J: acc += 10; continue;
        default: acc += 100; break;
        }
        acc += 1;
    }
    return acc;
}
static int sparse(int x) {
    switch (x) { case 0: return 1; case 2: return 3; case 5: return 4; case 9: return 7; case 14: return 9; case 20: return 2; case 30: return 5; case 99: return 6; default: return 0; }
}
static int ints(int x) {
    int r = 0;
    switch (x) { case 3: r = 1; break; case 4: r = 2; break; case 5: r = 3; break; case 7: r = 4; break; case 8: r = 5; break; case 9: r = 6; break; case 10: r = 7; break; case 11: r = 8; break; }
    return r;
}
static int fall(int x) { int r = 0; switch (x) { case 0: r += 1; case 1: r += 2; break; case 2: r += 3; break; case 3: r += 4; break; case 4: r += 5; break; case 5: r += 6; break; case 6: r += 7; break; case 7: r += 8; break; } return r; }
static int small(int x) { switch (x) { case 0: return 5; case 1: return 6; case 2: return 7; case 3: return 8; case 4: return 9; case 5: return 10; case 6: return 11; default: return 0; } }
static int wide(long long x) { switch (x) { case 1099511627776LL: return 1; case 1099511627777LL: return 2; case 1099511627778LL: return 3; case 1099511627779LL: return 4; case 1099511627780LL: return 5; case 1099511627781LL: return 6; case 1099511627782LL: return 7; case 1099511627783LL: return 8; } return 0; }
static int uints(unsigned x) { switch (x) { case 1: return 1; case 2: return 2; case 3: return 3; case 4: return 4; case 5: return 5; case 6: return 6; case 7: return 7; case 8: return 8; } return 0; }
static int duff(int n) { int r = 0; switch (n % 8) { case 0: do { r++; case 7: r++; case 6: r++; case 5: r++; case 4: r++; case 3: r++; case 2: r++; case 1: r++; } while ((n -= 8) > 0); } return r; }
static int nested(int a, int b) {
    switch (a) {
    case 0: return 1; case 1: return 2; case 2: return 3; case 3: return 4; case 4: return 5; case 5: return 6; case 6: return 7;
    case 7:
        switch (b) { case 0: return 10; case 1: return 11; case 2: return 12; case 3: return 13; case 4: return 14; case 5: return 15; case 6: return 16; case 7: return 17; default: return 19; }
    }
    return 0;
}
int main(void) {
    unsigned char code[] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 200};
    int ok = run(code, 12) == 392 && sparse(5) + sparse(99) * 10 + sparse(3) * 100 == 64;
    ok = ok && ints(3) + ints(6) * 10 + ints(11) * 100 + ints(12) * 1000 + ints(-5) * 10000 == 801;
    ok = ok && fall(0) == 3 && fall(3) == 4 && small(4) == 9 && wide(1099511627779LL) == 4 && uints(5) == 5 && uints(9) == 0;
    ok = ok && duff(13) == 13 && nested(3, 0) == 4 && nested(7, 6) == 16 && nested(7, 99) == 19 && nested(9, 0) == 0;
    return ok ? 0 : 1;
}
