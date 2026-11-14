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
#include <clocale>
#include <csignal>
#include <chrono>
#include <strings.h>
#include <sys/stat.h>

namespace crt {

//! A block of 128 KiB and up (glibc's starting mmap threshold) comes zeroed, as fresh pages give it
//! to a fresh native process: inside daslang the compiler's own frees have raised glibc's dynamic
//! threshold, and the block would come from a used heap (a program reading its fresh memory before
//! writing it, Doom's zone, then reads what native does). The one branch a forwarder holds
//! (ARCHITECTURE.md section 7).
inline void * c_malloc(uint64_t size) { return size >= 128 * 1024 ? ::calloc(1, size_t(size)) : ::malloc(size_t(size)); }
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
inline uint8_t * c_strpbrk(const uint8_t * s, const uint8_t * accept) { return (uint8_t *) ::strpbrk((const char *) s, (const char *) accept); }
//! POSIX `<strings.h>` and `strdup`: the case-blind compares and the malloc'd copy, which `crt::free` releases
inline int32_t c_strcasecmp(const uint8_t * a, const uint8_t * b) { return ::strcasecmp((const char *) a, (const char *) b); }
inline int32_t c_strncasecmp(const uint8_t * a, const uint8_t * b, uint64_t n) { return ::strncasecmp((const char *) a, (const char *) b, size_t(n)); }
inline uint8_t * c_strdup(const uint8_t * s) { return (uint8_t *) ::strdup((const char *) s); }
inline uint64_t c_strspn(const uint8_t * s, const uint8_t * accept) { return ::strspn((const char *) s, (const char *) accept); }
inline int32_t c_strcoll(const uint8_t * a, const uint8_t * b) { return ::strcoll((const char *) a, (const char *) b); }
inline uint8_t * c_strerror(int32_t errnum) { return (uint8_t *) ::strerror(errnum); }

inline int64_t c_strtol(const uint8_t * s, uint8_t ** end, int32_t base) { return ::strtol((const char *) s, (char **) end, base); }
inline uint64_t c_strtoul(const uint8_t * s, uint8_t ** end, int32_t base) { return ::strtoul((const char *) s, (char **) end, base); }
inline int64_t c_strtoll(const uint8_t * s, uint8_t ** end, int32_t base) { return ::strtoll((const char *) s, (char **) end, base); }
inline uint64_t c_strtoull(const uint8_t * s, uint8_t ** end, int32_t base) { return ::strtoull((const char *) s, (char **) end, base); }
inline double c_strtod(const uint8_t * s, uint8_t ** end) { return ::strtod((const char *) s, (char **) end); }
inline int32_t c_atoi(const uint8_t * s) { return ::atoi((const char *) s); }
inline int64_t c_atol(const uint8_t * s) { return ::atol((const char *) s); }
inline double c_atof(const uint8_t * s) { return ::atof((const char *) s); }

// C's `strtol`, `strtoul` and `atol` where the dialect's `long` is 32 bits (msvc): the host's
// 64-bit parse, then C11 7.22.1.4's range rule at 32 bits, LONG_MAX, LONG_MIN or ULONG_MAX with
// `errno` ERANGE; `errno` is left as it was when the value is in range
inline int32_t c_strtol32(const uint8_t * s, uint8_t ** end, int32_t base) {
    int saved = errno;
    errno = 0;
    long long v = ::strtoll((const char *) s, (char **) end, base);
    if (errno == 0) errno = saved;
    if (v > INT32_MAX) { errno = ERANGE; return INT32_MAX; }
    if (v < INT32_MIN) { errno = ERANGE; return INT32_MIN; }
    return int32_t(v);
}
// a negative subject is its magnitude negated in `unsigned long`, the magnitude range-checked
inline uint32_t c_strtoul32(const uint8_t * s, uint8_t ** end, int32_t base) {
    const char * at = (const char *) s;
    while (isspace((unsigned char) *at)) at++;
    bool negative = *at == '-';
    int saved = errno;
    errno = 0;
    unsigned long long v = ::strtoull((const char *) s, (char **) end, base);
    bool over = errno == ERANGE;
    if (!over) errno = saved;
    unsigned long long magnitude = negative ? 0ull - v : v;
    if (over || magnitude > UINT32_MAX) { errno = ERANGE; return UINT32_MAX; }
    return negative ? 0u - uint32_t(magnitude) : uint32_t(magnitude);
}
// msvc documents LONG_MAX and LONG_MIN with ERANGE for an `atol` out of range
inline int32_t c_atol32(const uint8_t * s) { return c_strtol32(s, nullptr, 10); }
inline int32_t c_abs(int32_t v) { return ::abs(v); }
inline int64_t c_llabs(int64_t v) { return ::llabs(v); }

inline uint8_t * c_getenv(const uint8_t * name) { return (uint8_t *) ::getenv((const char *) name); }
inline int32_t c_rand() { return ::rand(); }
inline void c_srand(uint32_t seed) { ::srand(seed); }

// the host's SIG_IGN (`ignore`) or SIG_DFL for signal `sig`: the dialect's `signal` applies those
// two for real and keeps a converted handler without installing it
inline void c_signal_host(int32_t sig, bool ignore) { ::signal(sig, ignore ? SIG_IGN : SIG_DFL); }

inline int32_t c_errno() { return errno; }
inline void c_set_errno(int32_t value) { errno = value; }
inline int32_t * c_errno_location() { return &errno; }

//! volatile access: one read or write through a `volatile` pointer each call, which neither the JIT
//! (an extern call) nor clang++ under AOT (a volatile access survives inlining) folds or hoists.
inline int8_t c_volatile_load_i8(const int8_t * p) { return *(const volatile int8_t *) p; }
inline uint8_t c_volatile_load_u8(const uint8_t * p) { return *(const volatile uint8_t *) p; }
inline int16_t c_volatile_load_i16(const int16_t * p) { return *(const volatile int16_t *) p; }
inline uint16_t c_volatile_load_u16(const uint16_t * p) { return *(const volatile uint16_t *) p; }
inline int32_t c_volatile_load_i32(const int32_t * p) { return *(const volatile int32_t *) p; }
inline uint32_t c_volatile_load_u32(const uint32_t * p) { return *(const volatile uint32_t *) p; }
inline int64_t c_volatile_load_i64(const int64_t * p) { return *(const volatile int64_t *) p; }
inline uint64_t c_volatile_load_u64(const uint64_t * p) { return *(const volatile uint64_t *) p; }
inline float c_volatile_load_f32(const float * p) { return *(const volatile float *) p; }
inline double c_volatile_load_f64(const double * p) { return *(const volatile double *) p; }
inline void c_volatile_store_i8(int8_t * p, int8_t v) { *(volatile int8_t *) p = v; }
inline void c_volatile_store_u8(uint8_t * p, uint8_t v) { *(volatile uint8_t *) p = v; }
inline void c_volatile_store_i16(int16_t * p, int16_t v) { *(volatile int16_t *) p = v; }
inline void c_volatile_store_u16(uint16_t * p, uint16_t v) { *(volatile uint16_t *) p = v; }
inline void c_volatile_store_i32(int32_t * p, int32_t v) { *(volatile int32_t *) p = v; }
inline void c_volatile_store_u32(uint32_t * p, uint32_t v) { *(volatile uint32_t *) p = v; }
inline void c_volatile_store_i64(int64_t * p, int64_t v) { *(volatile int64_t *) p = v; }
inline void c_volatile_store_u64(uint64_t * p, uint64_t v) { *(volatile uint64_t *) p = v; }
inline void c_volatile_store_f32(float * p, float v) { *(volatile float *) p = v; }
inline void c_volatile_store_f64(double * p, double v) { *(volatile double *) p = v; }

inline int64_t c_time(int64_t * t) { return int64_t(::time((time_t *) t)); }
inline int64_t c_clock() { return int64_t(::clock()); }
//! the steady clock's nanoseconds: the wall clock the perf harness's dasProfile method times by,
//! std::chrono::steady_clock as dasProfile's C++ harness reads it
inline int64_t c_monotonic_ns() { return int64_t(std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch()).count()); }
//! POSIX `clock_gettime` over the two clocks a program reads, by glibc's ids: CLOCK_REALTIME (0),
//! std::chrono::system_clock, and CLOCK_MONOTONIC (1), the steady clock `c_monotonic_ns` reads;
//! any other id returns -1 with errno EINVAL. The `struct timespec *` is a `void *` the converted
//! program lays out as the host's `<time.h>` does (glibc: two 64-bit words).
inline int32_t c_clock_gettime(int32_t clock_id, void * ts) {
    int64_t ns = 0;
    if (clock_id == 0) {
        ns = int64_t(std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::system_clock::now().time_since_epoch()).count());
    } else if (clock_id == 1) {
        ns = c_monotonic_ns();
    } else {
        errno = EINVAL;
        return -1;
    }
    ((struct timespec *) ts)->tv_sec = time_t(ns / 1000000000);
    ((struct timespec *) ts)->tv_nsec = long(ns % 1000000000);
    return 0;
}
inline double c_difftime(int64_t a, int64_t b) { return ::difftime(time_t(a), time_t(b)); }
//! A `struct tm *` and a `struct lconv *` are `void *`: the converted program lays the record out
//! itself and converts the pointer at the call site.
inline int64_t c_mktime(void * tm) { return int64_t(::mktime((struct tm *) tm)); }
inline void * c_localtime(const int64_t * t) { return ::localtime((const time_t *) t); }
inline void * c_gmtime(const int64_t * t) { return ::gmtime((const time_t *) t); }
inline uint64_t c_strftime(uint8_t * buf, uint64_t size, const uint8_t * fmt, const void * tm) { return ::strftime((char *) buf, size_t(size), (const char *) fmt, (const struct tm *) tm); }

inline uint8_t * c_setlocale(int32_t category, const uint8_t * locale) { return (uint8_t *) ::setlocale(category, (const char *) locale); }
inline void * c_localeconv() { return ::localeconv(); }

//! stdio: a `FILE *` is `void *`, opaque on both sides.
inline void * c_stdin() { return stdin; }
inline void * c_stdout() { return stdout; }
inline void * c_stderr() { return stderr; }
inline void * c_fopen(const uint8_t * name, const uint8_t * mode) { return ::fopen((const char *) name, (const char *) mode); }
inline void * c_freopen(const uint8_t * name, const uint8_t * mode, void * f) { return ::freopen((const char *) name, (const char *) mode, (FILE *) f); }
inline int32_t c_fclose(void * f) { return ::fclose((FILE *) f); }
//! POSIX `mkdir`; `mode_t` is `unsigned int` on Linux
inline int32_t c_mkdir(const uint8_t * name, uint32_t mode) { return ::mkdir((const char *) name, mode_t(mode)); }
inline uint64_t c_fread(void * data, uint64_t size, uint64_t n, void * f) { return ::fread(data, size_t(size), size_t(n), (FILE *) f); }
inline uint64_t c_fwrite(const void * data, uint64_t size, uint64_t n, void * f) { return ::fwrite(data, size_t(size), size_t(n), (FILE *) f); }
inline uint8_t * c_fgets(uint8_t * buf, int32_t n, void * f) { return (uint8_t *) ::fgets((char *) buf, n, (FILE *) f); }
inline int32_t c_fputs(const uint8_t * s, void * f) { return ::fputs((const char *) s, (FILE *) f); }
inline int32_t c_getc(void * f) { return ::getc((FILE *) f); }
inline int32_t c_fgetc(void * f) { return ::fgetc((FILE *) f); }
inline int32_t c_fputc(int32_t c, void * f) { return ::fputc(c, (FILE *) f); }
inline int32_t c_ungetc(int32_t c, void * f) { return ::ungetc(c, (FILE *) f); }
inline int32_t c_feof(void * f) { return ::feof((FILE *) f); }
inline int32_t c_ferror(void * f) { return ::ferror((FILE *) f); }
inline void c_clearerr(void * f) { ::clearerr((FILE *) f); }
inline int32_t c_fflush(void * f) { return ::fflush((FILE *) f); }
inline int32_t c_fseek(void * f, int64_t offset, int32_t whence) { return ::fseek((FILE *) f, long(offset), whence); }
inline int64_t c_ftell(void * f) { return int64_t(::ftell((FILE *) f)); }
// C's `ftell` where `long` is 32 bits: a position past LONG_MAX is the failure C11 7.21.9.4 names,
// -1 with a positive `errno` (ERANGE)
inline int32_t c_ftell32(void * f) {
    long long v = ::ftell((FILE *) f);
    if (v > INT32_MAX) { errno = ERANGE; return -1; }
    return int32_t(v);
}
inline int32_t c_setvbuf(void * f, uint8_t * buf, int32_t mode, uint64_t size) { return ::setvbuf((FILE *) f, (char *) buf, mode, size_t(size)); }
inline void * c_tmpfile() { return ::tmpfile(); }
#if defined(__GNUC__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
#endif
inline uint8_t * c_tmpnam(uint8_t * buf) { return (uint8_t *) ::tmpnam((char *) buf); }
#if defined(__GNUC__)
#pragma GCC diagnostic pop
#endif
inline int32_t c_remove(const uint8_t * name) { return ::remove((const char *) name); }
inline int32_t c_rename(const uint8_t * from, const uint8_t * to) { return ::rename((const char *) from, (const char *) to); }
inline int32_t c_system(const uint8_t * command) { return ::system((const char *) command); }

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
inline int32_t c_isgraph(int32_t c) { return ::isgraph(c); }
inline int32_t c_toupper(int32_t c) { return ::toupper(c); }
inline int32_t c_tolower(int32_t c) { return ::tolower(c); }

inline uint64_t c_fwrite_stdout(const void * data, uint64_t n) { return ::fwrite(data, 1, size_t(n), stdout); }
inline int32_t c_fflush_stdout() { return ::fflush(stdout); }

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
//! sscanf, one directive and a trailing `%n` per call, the out-pointer passed as the program gave it.
inline int32_t c_sscanf_one(const uint8_t * src, const uint8_t * fmt, void * out, int32_t * consumed) { return ::sscanf((const char *) src, (const char *) fmt, out, consumed); }
inline int32_t c_sscanf_none(const uint8_t * src, const uint8_t * fmt, int32_t * consumed) { return ::sscanf((const char *) src, (const char *) fmt, consumed); }
//! fscanf the same way over a `FILE *`, the stream moved by what the CRT consumed.
inline int32_t c_fscanf_one(void * f, const uint8_t * fmt, void * out, int32_t * consumed) { return ::fscanf((FILE *) f, (const char *) fmt, out, consumed); }
inline int32_t c_fscanf_none(void * f, const uint8_t * fmt, int32_t * consumed) { return ::fscanf((FILE *) f, (const char *) fmt, consumed); }
#if defined(__GNUC__)
#pragma GCC diagnostic pop
#endif

} // namespace crt
