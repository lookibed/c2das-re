int printf(const char *, ...);
int sink(int v) { printf("s%d ", v); return v; }

/* a C89 counter used only by counted loops: its declaration goes, each loop counts in `i` */
int c89_only(int n) {
    int i, j, total = 0;
    for (i = 0; i < n; i++)
        for (j = 2; j < n; j++)
            total += i * j;
    for (i = 1; i < 4; i++) total += i;
    for (i = 0; i < 2; i++)
        for (j = 0; j < 2; j++) total++;
    return total;
}

/* a counter dead after one loop but read elsewhere: that loop counts in a free name */
int c89_fresh(int n) {
    int i = sink(n), total = i;
    for (i = 0; i < n; i++) total += i;
    do { i = 7; } while (0);
    return total + i;
}

/* a counter named like a das keyword counts in its das name's free variant */
int keyword_counter(int n) {
    int block = n, total = block;
    for (block = 0; block < n; block++) total += block;
    return total;
}

/* exclusions: read after the loop, address taken, a goto out of the body, read on the next
   pass of an enclosing loop, read after a `do` its `break` leaves early, read on the next pass
   through a switch's `continue`, read after an `if` arm that returns */
int read_after(int n) { int i, t = 0; for (i = 0; i < n; i++) { if (i == 1) continue; if (i == 3) break; t++; } return i + t; }
int address(int n) { int i, *p = &i, t = 0; for (i = 0; i < n; i++) t += *p; return t; }
int goto_out(int *a, int n) {
    int i;
    do { n--; } while (0); /* a function with a goto keeps the loop */
    n++;
    for (i = 0; i < n; i++) if (a[i] == 2) goto found;
    return -1;
found:
    return i;
}
int next_pass(int n) {
    int i = 0, k, t = 0;
    for (k = 0; k < 3; k++) {
        t += i;
        for (i = 0; i < n; i++) t++;
    }
    return t;
}
int do_break(int n) {
    int i, t = 0;
    for (i = 0; i < n; i++) t++;
    do { if (t > 2) break; i = 1; } while (0);
    return t + i;
}
int switch_continue(int n) {
    int i = 0, k, t = 0;
    for (k = 0; k < 3; k++) {
        t += i;
        for (i = 0; i < n; i++) t++;
        switch (k) { case 0: continue; }
        i = 0;
    }
    return t;
}
int do_continue(int n, int x) {
    int i = 0;
    for (i = 0; i < n; i++) ;
    do { if (x) continue; i = 0; } while (0);
    return i;
}
int while_continue(int n, int x) {
    int i = 0, k = 0;
    for (i = 0; i < n; i++) ;
    while (k < 1) { k++; if (x) continue; i = 0; }
    return i;
}
int volatile_counter(int n) { volatile int i; int t = 0; for (i = 0; i < n; i++) t += i; return t; }
int outer_reads(int n) {
    int i = 0, k, t = 0;
    for (k = 0; k < 3 + i; k++) { for (i = 0; i < n; i++) t++; }
    for (k = 0; k < 3; k += i) { for (i = 0; i < n; i++) t++; }
    return t;
}
int under_case(int n, int c) {
    int i, t = 0;
    switch (c) {
    case 1:
        for (i = 0; i < n; i++) t += i;
        break;
    default:
        t = -1;
    }
    return t;
}
int arm_return(int n) {
    int i, t = 0;
    for (i = 0; i < n; i++) t += 2;
    if (t > 100) return t;
    else t += i;
    return t;
}

/* do-while: tested at the bottom, the flag kept with a `continue`, `while (0)`, a body that
   always leaves, a condition with effects */
int bottom(int n) {
    int t = 0, k = 0;
    do { t += n; } while (--n > 0);
    do { k++; if (k == 2) continue; t += k; } while (k < 4);
    do { t++; } while (0);
    do { t += 100; break; } while (1);
    do { t += k; } while (sink(--k) > 1);
    return t;
}

/* do { } while (count--): from 0, positive, negative (the wrap, cut by a break), unsigned at
   its maximum (cut too); kept when count is read after or in the body */
int count_down(int count, unsigned u) {
    int t = 0, guard = 0, kept = 2, named = 2;
    do { t++; } while (count--);
    count = -3;
    do { if (++guard == 6) break; t += 10; } while (count--);
    do { t += 1000; if (t > 2000) break; } while (u--);
    do { t += 3; } while (kept--);
    do { t += named; } while (named--);
    return t + kept;
}

/* count-down kept: a cast on the test, the address taken, a goto in the function */
int count_cast(int n) {
    int t = 0;
    do { t++; if (t > 1000) break; } while ((unsigned char) n--);
    return t;
}
int count_kept(int m, int g) {
    int t = 0, *p = &m;
    do { t += 2; } while (m--);
    if (g) goto out;
    do { t += 3; } while (g--);
out:
    return t + *p;
}
/* do-while (0) with a continue or a return keeps the loop */
int once_kept(int n) {
    int t = 0;
    do { t++; if (n > 1) continue; t += 10; } while (0);
    do { t += 5; if (n > 2) return t; t++; } while (0);
    return t;
}

int main(void) {
    int a[4] = {1, 5, 2, 9};
    printf("%d %d %d\n", c89_only(5), c89_fresh(4), keyword_counter(3));
    printf("%d %d %d %d %d\n", read_after(9), address(3), goto_out(a, 4), next_pass(4), arm_return(5));
    printf("%d %d\n", do_break(4), switch_continue(3));
    printf("%d %d %d %d %d %d\n", do_continue(3, 1), while_continue(3, 1), volatile_counter(4), outer_reads(2), under_case(4, 1), under_case(4, 2));
    printf("%d %d %d %d %d\n", count_cast(256), count_kept(2, 0), count_kept(1, 1), once_kept(2), once_kept(3));
    printf("%d\n", bottom(3));
    printf("%d %d\n", count_down(0, 0xffffffffu), count_down(4, 1u));
    return 0;
}
