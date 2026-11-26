/* The pp-token edge cases of frontend/pp_lexer.das, a unit the oracle preprocesses and compares. */
x %: <: :> <% %> %:%: %:% ;
u8"s" u8'c' U"x" u"y" L"z" L'y' u'a' U'b' "\e" '\%' "a\"b" "é" '\U0001F600'
1..2 .5e 1e-5 0x1.p-3 12abc 1é 1$ 1é 1e+ 1p- 1.e+5 0x1P+4f 1-2 1+e
éx xé \U0001F600 étoile x$y $z a$b \u12
@ ` \ a\b
... .. ->* <<= >>= &= ^= |= ## # a+++b x->y
in\
t s\
= 1;
a /* c
 */ b // d
  c
