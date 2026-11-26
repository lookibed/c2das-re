/* <assert.h> of the own libc header set (frontend/include/ARCHITECTURE.md). */
void __assert_fail(const char *, const char *, unsigned int, const char *);

#undef assert
#ifdef NDEBUG
#define assert(expr) ((void) (0))
#else
#define assert(expr) ((expr) ? (void) (0) : __assert_fail (#expr, __FILE__, __LINE__, __func__))
#endif
