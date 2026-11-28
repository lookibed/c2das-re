/* empty arguments, nested parentheses, commas, newlines in an invocation */
#define ONE(a) [a]
#define TWO(a,b) [a|b]
#define VAR(...) [__VA_ARGS__]
#define NVAR(a,...) [a|__VA_ARGS__]
ONE() ONE( ) ONE((,)) ONE((a,b)) TWO(,) TWO(a,) TWO(,b) TWO((a,b),(c,d)) VAR() VAR(,) VAR(a,b,c) NVAR(a) NVAR(a,) NVAR(a,b,c)
ONE(
  multi
  line
) TWO(a,
#undef ONE
b)
#define f(x) x
#define g f(
g 1 ) f
(2) f f(3)
#define EMPTYARG(x) (x)
EMPTYARG(/**/) EMPTYARG(EMPTYARG())
#define LPAREN (
#define RPAREN )
#define F(x, y) x + y
#define ELLIP_FUNC(...) __VA_ARGS__
ELLIP_FUNC(F, LPAREN, 'a', 'b', RPAREN);
