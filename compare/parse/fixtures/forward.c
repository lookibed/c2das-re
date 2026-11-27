/* a tag declared with no body is a line of its own; one a declaration names is not */
struct S;
union U;
enum E;
struct S *p;
void f(void) { struct L; struct L *q; union N; (void)q; }
struct Holder { struct In; int x; };
