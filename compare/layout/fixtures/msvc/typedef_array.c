/* A typedef of an array with `aligned` under msvc: the member is laid out by the array below the
   typedef (int[4], align 4), the typedef's `aligned(1)` kept as its requirement; an array of an
   aligned typedef's elements keeps the element's alignment. */

typedef int arr4[4] __attribute__((aligned(1)));
typedef int int_a1 __attribute__((aligned(1)));
typedef int_a1 arr4b[4];
struct TA { char c; arr4 a; };
struct TB { char c; arr4b a; };
