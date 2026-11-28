#if __has_include(<stddef.h>) && !__has_include(<no_such_header.h>) && __has_include("queries.c")
int includes;
#endif
#define HEADER <stdint.h>
#if __has_include(HEADER)
int include_by_macro;
#endif
#if defined __has_include && defined(__FILE__) && defined __has_builtin && !defined __has_cpp_attribute
int builtins_defined;
#endif
#ifdef __has_include
int ifdef_has_include;
#endif
#if __has_builtin(__builtin_expect) && !__has_builtin(__builtin_no_such) && __has_builtin(__builtin_ia32_pause)
int has_builtin;
#endif
#if __has_attribute(packed) && __has_attribute(__aligned__) && !__has_attribute(no_such)
int has_attribute;
#endif
#if __has_c_attribute(nodiscard) == 202003 && __has_c_attribute(gnu::packed) && !__has_c_attribute(clang::no_such)
int has_c_attribute;
#endif
#if __has_feature(c_atomic) && __has_extension(c_static_assert) && !__has_feature(cxx_rvalue_references)
int has_feature;
#endif
#if __has_warning("-Wunused") && !__has_warning("-Wno-such-warning")
int has_warning;
#endif
#define linux 1
#if __is_target_os(linux) && __is_target_arch(x86_64) && !__is_identifier(int) && __is_identifier(foo)
int targets;
#endif
