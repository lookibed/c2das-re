/* a header outside every fixture's folder, so outside the program root: what it defines is
   external to the program that includes it (BSD's MAX, as <sys/param.h> spells it) */
#define MAX(a, b) (((a) > (b)) ? (a) : (b))
