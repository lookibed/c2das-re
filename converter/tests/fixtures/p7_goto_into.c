int printf(const char *, ...);

/* Duff's device: the case labels sit inside the do-while body */
static int duff(const int *from, int *to, int count) {
    int n = (count + 7) / 8;
    int copied = 0;
    if (count <= 0)
        return 0;
    switch (count % 8) {
    case 0: do { *to++ = *from++; copied++;
    case 7:      *to++ = *from++; copied++;
    case 6:      *to++ = *from++; copied++;
    case 5:      *to++ = *from++; copied++;
    case 4:      *to++ = *from++; copied++;
    case 3:      *to++ = *from++; copied++;
    case 2:      *to++ = *from++; copied++;
    case 1:      *to++ = *from++; copied++;
            } while (--n > 0);
    }
    return copied;
}

/* a goto into a for body that then continues the loop, with a continue and a break of it */
static int into_for(int start) {
    int i = 0, sum = 0;
    if (start)
        goto mid;
    for (i = 0; i < 10; i++) {
        if (i == 2)
            continue;
        sum += 100;
    mid:
        sum += i;
        if (sum > 600)
            break;
    }
    return sum * 100 + i;
}

/* a goto into an else branch */
static int into_else(int x) {
    int r = 0;
    if (x > 5)
        goto other;
    if (x > 0) {
        r = 1;
    } else {
        r = 2;
    other:
        r += 10;
    }
    return r;
}

/* a goto into a loop nested two levels down */
static int into_nested(int skip) {
    int i = 0, j = 1, r = 1;
    if (skip)
        goto deep;
    for (i = 0; i < 3; i++) {
        j = 0;
        while (j < 3) {
        deep:
            r = r * 3 + j;
            j++;
        }
    }
    return r * 10 + i;
}

/* F_CastTicker: a goto from one branch into a branch of an if two levels down */
static int frames, attacking, state;
static void cast_ticker(int tics) {
    if (tics == 0) {
        frames = 0;
    } else {
        if (state == 7)
            goto stopattack;
        frames++;
    }
    if (frames == 3)
        attacking = 1;
    if (attacking) {
        if (frames == 5 || state == 9) {
        stopattack:
            attacking = 0;
            frames = 0;
            state = 1;
        }
    }
    state++;
}

/* P_SlideMove: a backward retry and gotos into a then branch that returns */
static int moves;
static int try_move(int v) { moves++; return v % 4 == 0; }
static int slide_move(int v) {
    int hits = 0;
retry:
    if (++hits == 3)
        goto stairstep;
    if (v % 5 == 0) {
    stairstep:
        if (!try_move(v))
            try_move(v + 1);
        return hits * 100 + v;
    }
    v++;
    if (v % 7 == 0)
        goto stairstep;
    if (!try_move(v))
        goto retry;
    return v;
}

/* a goto into a case body from outside the switch: the default a label, break a goto to the end,
   a declaration a later case reads declared ahead */
static int into_case(int x, int jump) {
    int r = 0;
    if (jump)
        goto inside;
    switch (x) {
    case 1:
        r = 1;
        int v = 4;
        break;
    case 2:
        v = 2;
        r = v;
    inside:
        r += 10;
        break;
    default:
        r = 7;
    }
    return r;
}

/* gotos into both arms of one if */
static int into_both(int x) {
    int r = 0;
    if (x == 1)
        goto a;
    if (x == 2)
        goto b;
    if (x > 5) {
        r = 1;
    a:
        r += 2;
    } else {
        r = 3;
    b:
        r += 4;
    }
    return r;
}

/* the arm no goto enters returns: it keeps its braces, no jump past the entered arm */
static int then_or_return(int x) {
    int r = 5;
    if (x > 3)
        goto in;
    if (x > 0) {
    in:
        r += x;
    } else
        return -1;
    return r;
}

/* the arm no goto enters holds a label of its own: it keeps its braces */
static int arm_label(int x) {
    int r = 0;
    if (x > 9)
        goto in;
    if (x > 0) {
    in:
        r = 1;
    } else {
        r = 2;
    again:
        r++;
        if (r < 5)
            goto again;
    }
    return r;
}

/* a for with no test, and a do-while whose continue reaches its test */
static int into_forever(int k) {
    int n = 0;
    goto in;
    for (;;) {
        n += 2;
    in:
        n++;
        if (n > k)
            break;
    }
    return n;
}
static int into_do(int k) {
    int n = 0, i = 0;
    goto in;
    do {
        if (i == 1) {
            i++;
            continue;
        }
        n += 10;
    in:
        n += i;
        i++;
    } while (i < k);
    return n;
}

/* a for whose initializer declares the counter a later declaration names too */
static int into_for_decl(int s) {
    int t = 0;
    if (s)
        goto in;
    for (int i = 0; i < 4; i++) {
        t += i;
    in:
        if (s) {
            i = 2;
            s = 0;
        }
        t += 10;
    }
    int i = 100;
    return t + i;
}

/* an if whose arm is a loop with no block around it */
static int bare_arm(int x) {
    int r = 0;
    if (x > 5)
        goto in;
    if (x > 0)
        while (r < 20) {
        in:
            r += 7;
        }
    return r;
}

/* das loops and a matched-flag switch inside an open loop keep their own break */
static int nested_breaks(int s) {
    int i = 0, n = 0;
    if (s)
        goto in;
    while (i < 4) {
        int j = 0;
        while (1) {
            if (++j > 2)
                break;
            n++;
        }
    in:
        switch (i) {
        case 0:
            n += 100;
        case 1:
            n += 10;
            break;
        default:
            n += 1000;
        }
        i++;
    }
    return n;
}

/* a goto into a loop body past the body's early return, and a plain goto past one */
static int past_return(int start, int k) {
    int i = start;
    if (start)
        goto mid;
    do {
        if (i > k)
            return -i;
    mid:
        i += 2;
    } while (i < 10);
    return i;
}
static int plain_past_return(int c) {
    int r = 0;
    if (c == 1)
        goto out;
    if (c == 2)
        return 5;
    r = 7;
out:
    return r + 1;
}

/* an open loop inside a das loop's body, and a goto out of that body: the outer loop stays a das loop */
static int out_of_loop(int k) {
    int s = 0;
    for (int r = 0; r < 3; r++) {
        int i = 0;
        if (k)
            goto in;
        while (i < 5) {
            i++;
        in:
            s += i;
            if (s > 12)
                goto out;
        }
        s += 100;
    }
    s = -s;
out:
    return s;
}

/* an open loop inside an if's arm, and a goto out of the arm: the if keeps its braces */
static int out_of_arm(int k, int z) {
    int s = 0, i = 0;
    if (z) {
        if (k)
            goto in;
        while (i < 5) {
            i++;
        in:
            s += i;
            if (s > 6)
                goto out;
        }
        s += 100;
    }
    s = -s;
out:
    return s;
}

/* a branch that ends in an if whose arms all return, before a label a goto above names */
static int arms_return(int k) {
    int s = 0;
    if (k == 1)
        goto out;
    if (k == 2) {
        s = 1;
        if (k)
            return 5;
        else
            return 7;
    }
    s = 3;
out:
    s += 10;
    return s;
}

/* a branch that ends in a switch with a default whose every case returns */
static int switch_returns(int k) {
    int s = 0;
    if (k == 5)
        goto out;
    if (k < 3) {
        switch (k) {
        case 0:
            return 10;
        case 1:
            return 11;
        default:
            return 12;
        }
    }
out:
    s += 7;
    return s;
}

int main(void) {
    int src[19], dst[19], k;
    for (k = 0; k < 19; k++) { src[k] = k * 3; dst[k] = -1; }
    printf("%d %d %d %d\n", duff(src, dst, 19), duff(src, dst, 8), duff(src, dst, 3), duff(src, dst, 0));
    printf("%d %d %d\n", dst[0], dst[2], dst[18]);
    printf("%d %d\n", into_for(0), into_for(1));
    printf("%d %d %d\n", into_else(9), into_else(3), into_else(-1));
    printf("%d %d\n", into_nested(0), into_nested(1));
    for (k = 0; k < 12; k++) {
        cast_ticker(k % 5);
        printf("%d:%d:%d ", frames, attacking, state);
        if (k == 4) state = 7;
    }
    printf("\n%d %d %d %d %d\n", slide_move(5), slide_move(1), slide_move(6), slide_move(2), moves);
    printf("%d %d %d %d\n", into_case(1, 0), into_case(2, 0), into_case(3, 0), into_case(3, 1));
    printf("%d %d %d %d\n", into_both(1), into_both(2), into_both(7), into_both(0));
    printf("%d %d %d\n", then_or_return(9), then_or_return(2), then_or_return(0));
    printf("%d %d %d\n", arm_label(10), arm_label(3), arm_label(0));
    printf("%d %d %d %d\n", into_forever(0), into_forever(7), into_do(1), into_do(5));
    printf("%d %d %d %d %d\n", into_for_decl(0), into_for_decl(1), bare_arm(9), bare_arm(2), bare_arm(0));
    printf("%d %d\n", nested_breaks(0), nested_breaks(1));
    printf("%d %d %d %d %d %d %d %d\n", out_of_loop(0), out_of_loop(1), out_of_arm(0, 1), out_of_arm(1, 1), out_of_arm(1, 0), arms_return(1), arms_return(2), arms_return(3));
    printf("%d %d %d %d\n", switch_returns(1), switch_returns(5), switch_returns(4), switch_returns(2));
    printf("%d %d %d %d %d\n", past_return(1, 100), past_return(0, 5), plain_past_return(1), plain_past_return(2), plain_past_return(3));
    return 0;
}
