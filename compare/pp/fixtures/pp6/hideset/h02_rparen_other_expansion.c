/* the invocation's name and its ')' come from different places (Prosser: HS = HS(name) ∩ HS(')') ∪ {name}) */
#define k2 h2(z)
#define h2(x) x k2
#define m h2
m(w)
#define m2 h2(v)
m2
#define LP (
#define RP )
#define call(f) f LP 1 RP
#define g(x) [x] g
call(g)
#define app(f, a) f a
app(g, (2))
app(app, (g, (3)))
