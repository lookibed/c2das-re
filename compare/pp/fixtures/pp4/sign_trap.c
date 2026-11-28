/* glibc's bits/wchar.h picks WCHAR_MIN by the sign of wchar_t: L'\0' - 1 > 0 is false here */
#if L'\0' - 1 > 0
# define WCHAR_MIN_ 0
#else
# define WCHAR_MIN_ (-0x7fffffff - 1)
#endif
int wchar_min = WCHAR_MIN_;
#if '\0' - 1 > 0
int plain_char_is_unsigned;
#endif
#if 0u - 1 > 0 && -1 > 0u && !(-1 > 0)
int unsigned_wins;
#endif
#if (1 ? -1 : 0u) > 0
int conditional_is_unsigned;
#endif
#if u'\0' - 1 > 0 && U'\0' - 1 > 0
int utf_chars_are_unsigned;
#endif
