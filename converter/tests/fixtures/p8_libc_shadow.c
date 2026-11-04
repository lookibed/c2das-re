/* P8.4 q: a program defining its own allocator and `strlen` (h264bsd-mp4's shim.c): its calls bind
   to its definitions, through a pointer too, and the mapped libc ones stay in reach */
#include <stddef.h>
#include <stdio.h>
#include <string.h>

static unsigned char heap[1 << 20];
static size_t top = 8;
static int allocations;

void *malloc(size_t size) {
    void *p = heap + top;
    top += (size + 7u) & ~(size_t)7u;
    allocations++;
    return p;
}

void free(void *p) {
    (void)p;
}

void *calloc(size_t count, size_t size) {
    unsigned char *p = malloc(count * size);
    for (size_t i = 0; i < count * size; i++) {
        p[i] = 0;
    }
    return p;
}

void *realloc(void *p, size_t size) {
    void *q = malloc(size);
    if (p) {
        memcpy(q, p, size);
    }
    return q;
}

size_t strlen(const char *s) {
    size_t n = 0;
    while (s[n]) {
        n++;
    }
    return n + 100;
}

int main(void) {
    void *(*alloc)(size_t) = malloc;
    char *s = alloc(8);
    strcpy(s, "hi");
    int *zeros = calloc(4, sizeof(int));
    free(s);
    printf("%s %d %d %d\n", s, (int)strlen(s), zeros[3], allocations > 0);
    return 0;
}
