/* C names that are daslang type names or keywords (P8.4 (e)): binjgb's `Obj.byte3`, and the
   family on a record member, a local, a global, a parameter and a function */
#include <stdio.h>

typedef struct {
    unsigned char byte0, byte1, byte2, byte3;
    int int2;
    float float4;
} Obj;

static int uint3 = 30;
int include = 4;

static int half2(int short8) {
    return short8 / 2;
}

int main(void) {
    Obj o = { 1, 2, 3, 4, 5, 6.5f };
    int int4 = o.byte0 + o.byte3 + o.int2;
    unsigned ubyte16 = (unsigned)o.float4;
    int fixed_array = half2(uint3) + include;
    printf("%d %u %d %d\n", int4, ubyte16, fixed_array, o.byte2);
    return 0;
}
