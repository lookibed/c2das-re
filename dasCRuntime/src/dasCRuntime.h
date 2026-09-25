// dasCRuntime.h: the fixed-arity forwarders module `crt` binds, one per CRT entry, spelled in
// fixed-width types and raw pointers so the das side sees uint8? for char*, void? for void*,
// uint64 for size_t and int64 for long / time_t. AOT output includes this header by name.
#pragma once
#include <cerrno>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <cctype>
#include <cstdio>
#include <cstdint>

namespace crt {

inline void * c_malloc(uint64_t size) { return ::malloc(size_t(size)); }
inline void * c_calloc(uint64_t count, uint64_t size) { return ::calloc(size_t(count), size_t(size)); }
inline void * c_realloc(void * ptr, uint64_t size) { return ::realloc(ptr, size_t(size)); }
inline void c_free(void * ptr) { ::free(ptr); }

inline void * c_memcpy(void * dst, const void * src, uint64_t n) { return ::memcpy(dst, src, size_t(n)); }
inline void * c_memmove(void * dst, const void * src, uint64_t n) { return ::memmove(dst, src, size_t(n)); }
inline void * c_memset(void * dst, int32_t value, uint64_t n) { return ::memset(dst, value, size_t(n)); }
inline int32_t c_memcmp(const void * a, const void * b, uint64_t n) { return ::memcmp(a, b, size_t(n)); }
inline void * c_memchr(const void * s, int32_t c, uint64_t n) { return const_cast<void *>(::memchr(s, c, size_t(n))); }

inline uint64_t c_strlen(const uint8_t * s) { return ::strlen((const char *) s); }
inline uint8_t * c_strcpy(uint8_t * dst, const uint8_t * src) { return (uint8_t *) ::strcpy((char *) dst, (const char *) src); }
inline uint8_t * c_strncpy(uint8_t * dst, const uint8_t * src, uint64_t n) { return (uint8_t *) ::strncpy((char *) dst, (const char *) src, size_t(n)); }
inline uint8_t * c_strcat(uint8_t * dst, const uint8_t * src) { return (uint8_t *) ::strcat((char *) dst, (const char *) src); }
inline uint8_t * c_strncat(uint8_t * dst, const uint8_t * src, uint64_t n) { return (uint8_t *) ::strncat((char *) dst, (const char *) src, size_t(n)); }
inline int32_t c_strcmp(const uint8_t * a, const uint8_t * b) { return ::strcmp((const char *) a, (const char *) b); }
inline int32_t c_strncmp(const uint8_t * a, const uint8_t * b, uint64_t n) { return ::strncmp((const char *) a, (const char *) b, size_t(n)); }
inline uint8_t * c_strchr(const uint8_t * s, int32_t c) { return (uint8_t *) ::strchr((const char *) s, c); }
inline uint8_t * c_strrchr(const uint8_t * s, int32_t c) { return (uint8_t *) ::strrchr((const char *) s, c); }
inline uint8_t * c_strstr(const uint8_t * s, const uint8_t * needle) { return (uint8_t *) ::strstr((const char *) s, (const char *) needle); }
inline uint8_t * c_strerror(int32_t errnum) { return (uint8_t *) ::strerror(errnum); }

inline int64_t c_strtol(const uint8_t * s, uint8_t ** end, int32_t base) { return ::strtol((const char *) s, (char **) end, base); }
inline uint64_t c_strtoul(const uint8_t * s, uint8_t ** end, int32_t base) { return ::strtoul((const char *) s, (char **) end, base); }
inline int64_t c_strtoll(const uint8_t * s, uint8_t ** end, int32_t base) { return ::strtoll((const char *) s, (char **) end, base); }
inline uint64_t c_strtoull(const uint8_t * s, uint8_t ** end, int32_t base) { return ::strtoull((const char *) s, (char **) end, base); }
inline double c_strtod(const uint8_t * s, uint8_t ** end) { return ::strtod((const char *) s, (char **) end); }
inline int32_t c_atoi(const uint8_t * s) { return ::atoi((const char *) s); }
inline int64_t c_atol(const uint8_t * s) { return ::atol((const char *) s); }
inline double c_atof(const uint8_t * s) { return ::atof((const char *) s); }
inline int32_t c_abs(int32_t v) { return ::abs(v); }
inline int64_t c_llabs(int64_t v) { return ::llabs(v); }

inline uint8_t * c_getenv(const uint8_t * name) { return (uint8_t *) ::getenv((const char *) name); }
inline int32_t c_rand() { return ::rand(); }
inline void c_srand(uint32_t seed) { ::srand(seed); }

inline int32_t c_errno() { return errno; }
inline void c_set_errno(int32_t value) { errno = value; }

inline int64_t c_time() { return int64_t(::time(nullptr)); }
inline int64_t c_clock() { return int64_t(::clock()); }

inline double c_fmod(double a, double b) { return ::fmod(a, b); }
inline float c_fmodf(float a, float b) { return ::fmodf(a, b); }
inline double c_frexp(double v, int32_t * exp) { return ::frexp(v, exp); }
inline double c_ldexp(double v, int32_t exp) { return ::ldexp(v, exp); }
inline double c_modf(double v, double * ipart) { return ::modf(v, ipart); }
inline double c_nextafter(double from, double to) { return ::nextafter(from, to); }
inline double c_hypot(double a, double b) { return ::hypot(a, b); }
inline double c_cbrt(double v) { return ::cbrt(v); }
inline double c_expm1(double v) { return ::expm1(v); }
inline double c_log1p(double v) { return ::log1p(v); }
inline double c_copysign(double v, double sign) { return ::copysign(v, sign); }
inline double c_remainder(double a, double b) { return ::remainder(a, b); }
inline double c_trunc(double v) { return ::trunc(v); }
inline double c_round(double v) { return ::round(v); }
inline double c_erf(double v) { return ::erf(v); }
inline double c_erfc(double v) { return ::erfc(v); }
inline double c_tgamma(double v) { return ::tgamma(v); }
inline double c_lgamma(double v) { return ::lgamma(v); }
inline double c_fma(double a, double b, double c) { return ::fma(a, b, c); }

inline int32_t c_isalpha(int32_t c) { return ::isalpha(c); }
inline int32_t c_isdigit(int32_t c) { return ::isdigit(c); }
inline int32_t c_isalnum(int32_t c) { return ::isalnum(c); }
inline int32_t c_isspace(int32_t c) { return ::isspace(c); }
inline int32_t c_isupper(int32_t c) { return ::isupper(c); }
inline int32_t c_islower(int32_t c) { return ::islower(c); }
inline int32_t c_isxdigit(int32_t c) { return ::isxdigit(c); }
inline int32_t c_ispunct(int32_t c) { return ::ispunct(c); }
inline int32_t c_isprint(int32_t c) { return ::isprint(c); }
inline int32_t c_iscntrl(int32_t c) { return ::iscntrl(c); }
inline int32_t c_toupper(int32_t c) { return ::toupper(c); }
inline int32_t c_tolower(int32_t c) { return ::tolower(c); }

//! snprintf, one conversion per call: `fmt` holds one directive of the value's C type, or none.
#if defined(__GNUC__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wformat-nonliteral"
#pragma GCC diagnostic ignored "-Wformat-security"
#endif
inline int32_t c_snprintf_none(uint8_t * buf, uint64_t size, const uint8_t * fmt) { return ::snprintf((char *) buf, size_t(size), (const char *) fmt); }
inline int32_t c_snprintf_int(uint8_t * buf, uint64_t size, const uint8_t * fmt, int32_t v) { return ::snprintf((char *) buf, size_t(size), (const char *) fmt, v); }
inline int32_t c_snprintf_uint(uint8_t * buf, uint64_t size, const uint8_t * fmt, uint32_t v) { return ::snprintf((char *) buf, size_t(size), (const char *) fmt, v); }
inline int32_t c_snprintf_int64(uint8_t * buf, uint64_t size, const uint8_t * fmt, int64_t v) { return ::snprintf((char *) buf, size_t(size), (const char *) fmt, (long long) v); }
inline int32_t c_snprintf_uint64(uint8_t * buf, uint64_t size, const uint8_t * fmt, uint64_t v) { return ::snprintf((char *) buf, size_t(size), (const char *) fmt, (unsigned long long) v); }
inline int32_t c_snprintf_double(uint8_t * buf, uint64_t size, const uint8_t * fmt, double v) { return ::snprintf((char *) buf, size_t(size), (const char *) fmt, v); }
inline int32_t c_snprintf_str(uint8_t * buf, uint64_t size, const uint8_t * fmt, const uint8_t * v) { return ::snprintf((char *) buf, size_t(size), (const char *) fmt, (const char *) v); }
inline int32_t c_snprintf_ptr(uint8_t * buf, uint64_t size, const uint8_t * fmt, const void * v) { return ::snprintf((char *) buf, size_t(size), (const char *) fmt, v); }
#if defined(__GNUC__)
#pragma GCC diagnostic pop
#endif

} // namespace crt
