/* Declarations whose types no expression names, inside an if's branches, a loop's body and an
   old-style definition's parameter list: the rebuilt walk must reach each, or the comparison
   reports the gap. */

int k(a) short a; { return 0; }

int main(void)
{
    if (1) { long x; } else { unsigned short y; }
    while (0) { signed char z; }
    return k(1);
}
