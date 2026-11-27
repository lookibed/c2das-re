/* clang semantic differences: a parameter of a function typedef's type is adjusted to a pointer,
   which the tree alone does not know; a definition takes the type of the prototype before it */
typedef int F(int);
void g(F f);
int m(void);
int m() { return 0; }
