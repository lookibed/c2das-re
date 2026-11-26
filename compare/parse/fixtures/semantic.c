/* a clang semantic difference: a parameter of a function typedef's type is adjusted to a pointer,
   which the tree alone does not know */
typedef int F(int);
void g(F f);
