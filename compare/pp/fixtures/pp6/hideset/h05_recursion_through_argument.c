/* a macro's own name reaching it through an argument */
#define id(x) x
#define r id(r)
r id(r) id(id(r))
#define twice(x) x x
#define s twice(s)
s twice(s)
