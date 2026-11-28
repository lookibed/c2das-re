/* Argument copies next to source tokens: a token read after an expansion that ends in an argument
   copy is in no copy, and the arguments of the next call are copies of that call alone. */
#define W(x) x
#define E(f, y) ((f) + (y))

int copies(int a, int b) {
    int r = W(a) + b;
    return r + W(b) * E(a, b);
}
