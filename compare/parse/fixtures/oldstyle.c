/* an old-style definition: each parameter typed by the declaration list, the function's type with
   the parameters promoted as clang writes it */
int f(a, b, c) char a; float b; long c; { return a; }
int g(p, q) char *p; double q[3]; { return 0; }
int h() { return 1; }
int k(int x, int y[2]) { return x; }
