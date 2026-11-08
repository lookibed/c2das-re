/* a program defining its own `memset` (h264bsd-mp4's shim.c): its calls reach its definition,
   never the builtin, while libc's `memcpy` beside it is the builtin */
#include <stddef.h>
#include <stdio.h>
#include <string.h>

static int fills;

void *memset(void *dest, int value, size_t count) {
    unsigned char *p = dest;
    fills++;
    for (size_t i = 0; i < count; i++) {
        p[i] = (unsigned char) (value + 1);
    }
    return dest;
}

int main(void) {
    unsigned char buf[8];
    memset(buf, 4, sizeof(buf));
    memcpy(buf, buf + 4, 2);
    printf("%d %d %d\n", buf[0], buf[7], fills);
    return 0;
}
