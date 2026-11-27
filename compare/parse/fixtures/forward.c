/* a tag declared with no body is a line of its own; one a declaration names is not */
struct S;
union U;
enum E;
struct S *p;
void f(void) { struct L; struct L *q; union N; (void)q; }
struct Holder { struct In; int x; struct Fresh2 *f2; };
struct Fresh *fresh;
void g(void) { struct BlockFresh *bf; (void)bf; }
