/* Boost.PP: BOOST_PP_WHILE, BOOST_PP_FOR, BOOST_PP_ENUM, arithmetic */
#include <boost/preprocessor/control/while.hpp>
#include <boost/preprocessor/repetition/for.hpp>
#include <boost/preprocessor/repetition/enum.hpp>
#include <boost/preprocessor/arithmetic/add.hpp>
#include <boost/preprocessor/arithmetic/mul.hpp>
#include <boost/preprocessor/arithmetic/dec.hpp>
#include <boost/preprocessor/arithmetic/inc.hpp>
#include <boost/preprocessor/comparison/not_equal.hpp>
#include <boost/preprocessor/tuple/elem.hpp>
#define PRED(d, st) BOOST_PP_TUPLE_ELEM(2, 0, st)
#define OP(d, st) (BOOST_PP_DEC(BOOST_PP_TUPLE_ELEM(2, 0, st)), BOOST_PP_ADD_D(d, BOOST_PP_TUPLE_ELEM(2, 1, st), 2))
int w = BOOST_PP_TUPLE_ELEM(2, 1, BOOST_PP_WHILE(PRED, OP, (5, 0)));
int m = BOOST_PP_MUL(7, 6);
#define FPRED(r, st) BOOST_PP_NOT_EQUAL(st, 4)
#define FOP(r, st) BOOST_PP_INC(st)
#define FMAC(r, st) int f##st;
BOOST_PP_FOR(0, FPRED, FOP, FMAC)
#define E(z, n, d) d + n
int e[] = { BOOST_PP_ENUM(4, E, 10) };
