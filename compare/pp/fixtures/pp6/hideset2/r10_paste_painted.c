// r10: '##' creates a new name equal to a disabled macro, inside that macro's expansion
#define cat(a, b) a ## b
#define ab cat(a, b)
ab;
#define x2 cat(x, 2) cat(x,2)
x2;
