int printf(const char *, ...);
int cond(int i) { printf("c%d ", i); return i < 4; }
int main(void) {
    int i = 0, n = 0, total = 0;
    while (i < 3) { i = i * 2 + 1; }
    printf("w%d\n", i);
    i = 0;
    do {
        i++;
        if (i == 2) continue;
        n += i;
    } while (cond(i));
    printf("\nd%d %d\n", i, n);
    for (int j = 0; j < 10; j++) {
        if (j == 1) continue;
        if (j == 4) break;
        total += j;
    }
    printf("f%d\n", total);
    for (;;) { total++; if (total > 10) break; }
    for (i = 0, n = 10; i < n; i += 3, n--) { }
    printf("%d %d %d\n", total, i, n);
    if (i > 100) printf("a\n"); else if (i > 50) printf("b\n"); else if (n) printf("c\n"); else printf("d\n");
    while (i-- > 0) if (i % 2) continue; else n++;
    printf("%d %d\n", i, n);
    return 42;
}
