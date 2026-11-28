/* Boost.PP: BOOST_PP_REPEAT, nested */
#include <boost/preprocessor/repetition/repeat.hpp>
#include <boost/preprocessor/repetition/enum_params.hpp>
#define DECL(z, n, text) text##n = n;
BOOST_PP_REPEAT(5, DECL, int x)
#define ROW(z, n, _) { BOOST_PP_ENUM_PARAMS_Z(z, 4, c) },
#define OUTER(z, n, _) BOOST_PP_REPEAT_ ## z(3, ROW, _)
BOOST_PP_REPEAT(2, OUTER, ~)
void f(BOOST_PP_ENUM_PARAMS(6, int a));
