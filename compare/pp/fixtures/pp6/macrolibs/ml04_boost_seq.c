/* Boost.PP: BOOST_PP_SEQ_FOR_EACH, SEQ_FOR_EACH_I, SEQ_ENUM */
#include <boost/preprocessor/seq/for_each.hpp>
#include <boost/preprocessor/seq/for_each_i.hpp>
#include <boost/preprocessor/seq/enum.hpp>
#include <boost/preprocessor/cat.hpp>
#define SEQ (alpha)(beta)(gamma)(delta)
#define FIELD(r, data, elem) int BOOST_PP_CAT(data, elem);
struct s { BOOST_PP_SEQ_FOR_EACH(FIELD, m_, SEQ) };
#define CASE(r, data, i, elem) case i: return #elem;
const char *name(int k) { switch (k) { BOOST_PP_SEQ_FOR_EACH_I(CASE, _, SEQ) } return 0; }
int v[] = { BOOST_PP_SEQ_ENUM((1)(2)(3)) };
