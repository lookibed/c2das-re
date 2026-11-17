// glibc_rand.cpp - glibc's rand() and srand() for the wasm64 archive only (ARCHITECTURE.md section 8).
//
// The converted programs' reference runs are recorded on glibc, and the C standard leaves rand()'s
// sequence to the implementation: emscripten's libc (musl) gives another one, so a program that
// draws random numbers (quakegeneric's particles and monsters) leaves its reference frames. Linked
// before emscripten's libc, this file's definitions are the ones crt's `rand` forwarder reaches.
// The algorithm is glibc's random_r with its default TYPE_3 state: a 31-word additive feedback
// generator, x**31 + x**3 + 1, seeded by a Park-Miller sequence and run 310 steps before use; an
// unseeded program draws as after srand(1). tests/test_crt_rand.das holds it to the host's glibc.

#include <stdint.h>

namespace {
    int32_t table[31];
    int front = 3;
    int rear = 0;
    bool seeded = false;

    int32_t step() {
        table[front] = (int32_t)((uint32_t)table[front] + (uint32_t)table[rear]);
        int32_t result = (int32_t)((uint32_t)table[front] >> 1);
        front = front == 30 ? 0 : front + 1;
        rear = rear == 30 ? 0 : rear + 1;
        return result;
    }

    void seed(unsigned int s) {
        if (s == 0) s = 1;
        int32_t word = (int32_t)s;
        table[0] = word;
        for (int i = 1; i < 31; i++) {
            int32_t hi = word / 127773;
            int32_t lo = word % 127773;
            word = 16807 * lo - 2836 * hi;
            if (word < 0) word += 2147483647;
            table[i] = word;
        }
        front = 3;
        rear = 0;
        for (int i = 0; i < 310; i++) step();
        seeded = true;
    }
}

extern "C" void srand(unsigned int s) { seed(s); }

extern "C" int rand(void) {
    if (!seeded) seed(1);
    return step();
}
