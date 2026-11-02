options gen2
require dastest/testing_boost public
require crt
require math
require daslib/fio

def cstr(s : string) : uint8? => unsafe(reinterpret<uint8?>(s))

def as_string(p : uint8?) : string => unsafe(reinterpret<string>(p))

[test]
def test_crt_memory(t : T?) {
    t |> run("malloc, memset, memcpy, memcmp, memchr, realloc, calloc, free") @(t : T?) {
        unsafe {
            var p = reinterpret<uint8?>(crt::malloc(16ul))
            t |> equal(p != null, true)
            crt::memset(p, 'A', 4ul)
            deref(p + 4) = uint8(0)
            t |> equal(as_string(p), "AAAA")
            var q = reinterpret<uint8?>(crt::calloc(4ul, 4ul))
            t |> equal(int(deref(q + 15)), 0)
            crt::memcpy(q, p, 5ul)
            t |> equal(crt::memcmp(p, q, 5ul), 0)
            deref(q + 2) = uint8('B')
            t |> equal(crt::memcmp(p, q, 5ul) < 0, true)
            t |> equal(reinterpret<uint8?>(crt::memchr(q, 'B', 5ul)) == q + 2, true)
            t |> equal(crt::memchr(q, 'Z', 5ul) == null, true)
            crt::memmove(q + 1, q, 3ul)
            t |> equal(as_string(q), "AAAB")
            q = reinterpret<uint8?>(crt::realloc(q, 64ul))
            t |> equal(as_string(q), "AAAB")
            crt::free(p)
            crt::free(q)
        }
    }
}

[test]
def test_crt_strings(t : T?) {
    t |> run("string.h over uint8 bytes") @(t : T?) {
        unsafe {
            var buf : uint8[32]
            t |> equal(crt::strlen(cstr("hello")), 5ul)
            crt::strcpy(addr(buf[0]), cstr("hello"))
            crt::strcat(addr(buf[0]), cstr(" world"))
            t |> equal(as_string(addr(buf[0])), "hello world")
            crt::strncpy(addr(buf[0]), cstr("HE"), 2ul)
            t |> equal(as_string(addr(buf[0])), "HEllo world")
            crt::strncat(addr(buf[0]), cstr("!!!"), 1ul)
            t |> equal(as_string(addr(buf[0])), "HEllo world!")
            t |> equal(crt::strcmp(cstr("abc"), cstr("abd")) < 0, true)
            t |> equal(crt::strcmp(cstr("abc"), cstr("abc")), 0)
            t |> equal(crt::strncmp(cstr("abc"), cstr("abd"), 2ul), 0)
            let s = cstr("a.b.c")
            t |> equal(crt::strchr(s, '.') == s + 1, true)
            t |> equal(crt::strrchr(s, '.') == s + 3, true)
            t |> equal(crt::strchr(s, 'z') == null, true)
            t |> equal(crt::strstr(s, cstr("b.c")) == s + 2, true)
            t |> equal(crt::strpbrk(s, cstr("c.")) == s + 1, true)
            t |> equal(crt::strpbrk(s, cstr("xyz")) == null, true)
            t |> equal(crt::strspn(s, cstr("a.")), 2ul)
            // the C locale a program starts in collates by byte value
            t |> equal(crt::strcoll(cstr("abc"), cstr("abd")) < 0, true)
            t |> equal(crt::strcoll(cstr("abc"), cstr("abc")), 0)
            t |> equal(crt::strlen(crt::strerror(crt::ERANGE)) > 0ul, true)
        }
    }
}

[test]
def test_crt_conversions(t : T?) {
    t |> run("strtol family reports the end pointer and ERANGE through errno") @(t : T?) {
        unsafe {
            let s = cstr("123abc")
            var end : uint8?
            t |> equal(crt::strtol(s, addr(end), 10), 123l)
            t |> equal(end == s + 3, true)
            t |> equal(crt::strtoul(cstr("ff"), null, 16), 255ul)
            t |> equal(crt::strtoll(cstr("-9223372036854775808"), null, 10), -9223372036854775807l - 1l)
            t |> equal(crt::strtoull(cstr("18446744073709551615"), null, 10), 18446744073709551615ul)
            t |> equal(crt::strtod(cstr("2.5e1x"), addr(end)), 25.0lf)
            t |> equal(int(deref(end)), 'x')
            crt::c_set_errno(0)
            crt::strtol(cstr("99999999999999999999"), null, 10)
            t |> equal(crt::c_errno(), crt::ERANGE)
            crt::c_set_errno(0)
            t |> equal(crt::c_errno(), 0)
            crt::strtol(cstr("1"), null, 1)
            t |> equal(crt::c_errno(), crt::EINVAL)
            crt::c_set_errno(crt::EDOM)
            t |> equal(crt::c_errno(), crt::EDOM)
            // glibc's `errno` is `*__errno_location()`: a store through the address is errno
            deref(crt::c_errno_location()) = crt::ERANGE
            t |> equal(crt::c_errno(), crt::ERANGE)
            crt::c_set_errno(crt::EDOM)
            t |> equal(crt::EDOM != crt::ERANGE && crt::ERANGE != crt::EINVAL, true)
            crt::c_set_errno(0)
            t |> equal(crt::atoi(cstr("-42")), -42)
            t |> equal(crt::atol(cstr("4000000000")), 4000000000l)
            t |> equal(crt::atof(cstr("0.5")), 0.5lf)
            t |> equal(crt::abs(-3), 3)
            t |> equal(crt::llabs(-3l), 3l)
        }
    }
    t |> run("the 32-bit `long` forwarders range a parse at 32 bits: LONG_MAX, LONG_MIN or ULONG_MAX with ERANGE, errno untouched in range") @(t : T?) {
        unsafe {
            var end : uint8?
            let s = cstr(" 3000000000x")
            crt::c_set_errno(0)
            t |> equal(crt::c_strtol32(s, addr(end), 10), 2147483647)
            t |> equal(crt::c_errno(), crt::ERANGE)
            t |> equal(int(deref(end)), 'x')
            crt::c_set_errno(0)
            t |> equal(crt::c_strtol32(cstr("-3000000000"), null, 10), -2147483647 - 1)
            t |> equal(crt::c_errno(), crt::ERANGE)
            crt::c_set_errno(crt::EDOM)
            t |> equal(crt::c_strtol32(cstr("-2147483648"), null, 10), -2147483647 - 1)
            t |> equal(crt::c_strtol32(cstr("7fffffff"), null, 16), 2147483647)
            t |> equal(crt::c_errno(), crt::EDOM)
            crt::c_set_errno(0)
            t |> equal(crt::c_strtoul32(cstr("4294967296"), null, 10), 4294967295u)
            t |> equal(crt::c_errno(), crt::ERANGE)
            crt::c_set_errno(0)
            // a negative subject is its magnitude negated in `unsigned long`
            t |> equal(crt::c_strtoul32(cstr("  -1"), null, 10), 4294967295u)
            t |> equal(crt::c_strtoul32(cstr("-4294967295"), null, 10), 1u)
            t |> equal(crt::c_errno(), 0)
            t |> equal(crt::c_strtoul32(cstr("-4294967296"), null, 10), 4294967295u)
            t |> equal(crt::c_errno(), crt::ERANGE)
            crt::c_set_errno(0)
            t |> equal(crt::c_strtoul32(cstr("-99999999999999999999"), null, 10), 4294967295u)
            t |> equal(crt::c_errno(), crt::ERANGE)
            crt::c_set_errno(0)
            t |> equal(crt::c_atol32(cstr("3000000000")), 2147483647)
            t |> equal(crt::c_errno(), crt::ERANGE)
            crt::c_set_errno(0)
            t |> equal(crt::c_atol32(cstr("-12")), -12)
            t |> equal(crt::c_errno(), 0)
            var f = crt::tmpfile()
            t |> equal(crt::fwrite(cstr("abc"), 1ul, 3ul, f), 3ul)
            t |> equal(crt::c_ftell32(f), 3)
            // a position past LONG_MAX is ftell's failure, -1 with ERANGE
            t |> equal(crt::fseek(f, 3000000000l, 0), 0)
            t |> equal(crt::c_ftell32(f), -1)
            t |> equal(crt::c_errno(), crt::ERANGE)
            t |> equal(crt::fclose(f), 0)
            crt::c_set_errno(0)
        }
    }
}

[test]
def test_crt_environment(t : T?) {
    t |> run("getenv, rand, srand, time, clock") @(t : T?) {
        unsafe {
            t |> equal(crt::getenv(cstr("PATH")) != null, true)
            t |> equal(crt::getenv(cstr("C2DAS_NO_SUCH_VARIABLE")) == null, true)
        }
        crt::srand(7u)
        let first = crt::rand()
        let second = crt::rand()
        crt::srand(7u)
        t |> equal(crt::rand(), first)
        t |> equal(crt::rand(), second)
        t |> equal(first >= 0 && first <= crt::RAND_MAX, true)
        var now = 0l
        t |> equal(unsafe(crt::time(null)) > 1700000000l, true)
        t |> equal(unsafe(crt::time(unsafe(addr(now)))) == now, true)
        t |> equal(crt::difftime(now + 60l, now), 60.0lf)
        t |> equal(crt::clock() >= 0l, true)
        // the steady clock advances over a busy wait of two milliseconds of processor time
        let before = crt::c_monotonic_ns()
        let started = crt::clock()
        while (crt::clock() - started < crt::CLOCKS_PER_SEC / 500l) {
            pass
        }
        t |> success(before > 0l && crt::c_monotonic_ns() - before >= 1000000l, "the steady clock did not advance a millisecond")
        // clock_gettime: glibc's CLOCK_REALTIME (0) and CLOCK_MONOTONIC (1) into glibc's timespec,
        // the monotonic one the steady clock's, an unknown id refused
        var ts = CTimespec()
        unsafe {
            t |> equal(crt::clock_gettime(1, addr<void?>(ts)), 0)
            t |> success(ts.tv_nsec >= 0l && ts.tv_nsec < 1000000000l && ts.tv_sec * 1000000000l + ts.tv_nsec <= crt::c_monotonic_ns(), "monotonic {ts.tv_sec}.{ts.tv_nsec}")
            t |> equal(crt::clock_gettime(0, addr<void?>(ts)), 0)
            t |> success(ts.tv_sec > 1700000000l && ts.tv_nsec < 1000000000l, "realtime {ts.tv_sec}.{ts.tv_nsec}")
            crt::c_set_errno(0)
            t |> equal(crt::clock_gettime(12345, addr<void?>(ts)), -1)
            t |> equal(crt::c_errno(), crt::EINVAL)
        }
        t |> equal(crt::CLOCKS_PER_SEC > 0l, true)
        t |> equal(crt::LONG_BITS == 32 || crt::LONG_BITS == 64, true)
        t |> equal(crt::fflush_stdout(), 0)
        t |> equal(unsafe(crt::fwrite_stdout(cstr(""), 0ul)), 0ul)
    }
}

[test]
def test_crt_math(t : T?) {
    t |> run("math.h exotica") @(t : T?) {
        t |> equal(crt::fmod(7.5lf, 2.0lf), 1.5lf)
        t |> equal(crt::fmodf(7.5f, 2.0f), 1.5f)
        // HUGE_VAL is positive and above every finite double (C 7.12p3; IEC 60559 makes it +inf)
        t |> equal(crt::HUGE_VAL > 1.7976931348623157e308lf, true)
        var e = 0
        var mant = 0.0lf
        unsafe {
            mant = crt::frexp(8.0lf, addr(e))
        }
        t |> equal(mant, 0.5lf)
        t |> equal(e, 4)
        t |> equal(crt::ldexp(0.5lf, 4), 8.0lf)
        var ip = 0.0lf
        var frac = 0.0lf
        unsafe {
            frac = crt::modf(3.25lf, addr(ip))
        }
        t |> equal(frac, 0.25lf)
        t |> equal(ip, 3.0lf)
        t |> equal(crt::nextafter(1.0lf, 2.0lf) > 1.0lf, true)
        t |> equal(crt::hypot(3.0lf, 4.0lf), 5.0lf)
        t |> equal(abs(crt::cbrt(27.0lf) - 3.0lf) < 1e-12lf, true)
        t |> equal(crt::expm1(0.0lf), 0.0lf)
        t |> equal(crt::log1p(0.0lf), 0.0lf)
        t |> equal(crt::copysign(2.0lf, -1.0lf), -2.0lf)
        t |> equal(crt::remainder(7.0lf, 2.0lf), -1.0lf)
        t |> equal(crt::trunc(-2.7lf), -2.0lf)
        t |> equal(crt::round(2.5lf), 3.0lf)
        t |> equal(crt::erf(0.0lf), 0.0lf)
        t |> equal(crt::erfc(0.0lf), 1.0lf)
        t |> equal(crt::tgamma(5.0lf), 24.0lf)
        t |> equal(crt::lgamma(1.0lf), 0.0lf)
        t |> equal(crt::fma(2.0lf, 3.0lf, 1.0lf), 7.0lf)
    }
    t |> run("c_signal_host installs the host's SIG_IGN: a signal the process ignores leaves it running") @(t : T?) {
        // SIGUSR1 (10) from a shell whose parent is this process
        crt::c_signal_host(10, true)
        t |> equal(unsafe(crt::system(cstr("kill -USR1 $PPID"))), 0)
        crt::c_signal_host(10, false)
    }
    t |> run("a libm entry that sets errno runs though its result is discarded") @(t : T?) {
        let zero = 0.0lf
        crt::c_set_errno(0)
        let _rem = crt::fmod(1.0lf, zero)
        t |> equal(crt::c_errno(), crt::EDOM)
        crt::c_set_errno(0)
        let _big = crt::ldexp(1.0lf, 5000)
        t |> equal(crt::c_errno(), crt::ERANGE)
        crt::c_set_errno(0)
    }
}

[test]
def test_crt_ctype(t : T?) {
    t |> run("ctype.h") @(t : T?) {
        t |> equal(crt::isalpha('a') != 0, true)
        t |> equal(crt::isalpha('1') != 0, false)
        t |> equal(crt::isdigit('7') != 0, true)
        t |> equal(crt::isalnum('_') != 0, false)
        t |> equal(crt::isspace(' ') != 0, true)
        t |> equal(crt::isupper('Q') != 0, true)
        t |> equal(crt::islower('Q') != 0, false)
        t |> equal(crt::isxdigit('f') != 0, true)
        t |> equal(crt::ispunct('!') != 0, true)
        t |> equal(crt::isprint(' ') != 0, true)
        t |> equal(crt::iscntrl(7) != 0, true)
        t |> equal(crt::isgraph('!') != 0, true)
        t |> equal(crt::isgraph(' ') != 0, false)
        t |> equal(crt::toupper('a'), 'A')
        t |> equal(crt::tolower('A'), 'a')
    }
}

[test]
def test_crt_snprintf(t : T?) {
    t |> run("snprintf renders one directive per call, byte-exact with the CRT") @(t : T?) {
        unsafe {
            var buf : uint8[64]
            let b = addr(buf[0])
            t |> equal(crt::snprintf_none(b, 64ul, cstr("100%%")), 4)
            t |> equal(as_string(b), "100%")
            t |> equal(crt::snprintf_int(b, 64ul, cstr("%05d"), 42), 5)
            t |> equal(as_string(b), "00042")
            crt::snprintf_uint(b, 64ul, cstr("%x"), 0xBEEF)
            t |> equal(as_string(b), "beef")
            crt::snprintf_int64(b, 64ul, cstr("%lld"), -5000000000l)
            t |> equal(as_string(b), "-5000000000")
            crt::snprintf_uint64(b, 64ul, cstr("%llu"), 18446744073709551615ul)
            t |> equal(as_string(b), "18446744073709551615")
            crt::snprintf_double(b, 64ul, cstr("%.3f"), 3.14159lf)
            t |> equal(as_string(b), "3.142")
            crt::snprintf_double(b, 64ul, cstr("%g"), 1e20lf)
            t |> equal(as_string(b), "1e+20")
            crt::snprintf_str(b, 64ul, cstr("[%-4s]"), cstr("hi"))
            t |> equal(as_string(b), "[hi  ]")
            crt::snprintf_ptr(b, 64ul, cstr("%p"), null)
            t |> equal(empty(as_string(b)), false)
            t |> equal(crt::snprintf_int(b, 3ul, cstr("%d"), 12345), 5)
            t |> equal(as_string(b), "12")
        }
    }
}

[test]
def test_crt_sscanf(t : T?) {
    t |> run("sscanf reads one directive per call through the C out-pointer, %n giving the bytes consumed") @(t : T?) {
        unsafe {
            var n = 0
            var consumed = -1
            t |> equal(crt::sscanf_one(cstr("  -42xyz"), cstr("%d%n"), addr<void?>(n), addr(consumed)), 1)
            t |> equal(n, -42)
            t |> equal(consumed, 5)
            var d = 0.0lf
            consumed = -1
            t |> equal(crt::sscanf_one(cstr("2.5e1"), cstr("%lf%n"), addr<void?>(d), addr(consumed)), 1)
            t |> equal(d, 25.0lf)
            t |> equal(consumed, 5)
            consumed = -1
            t |> equal(crt::sscanf_one(cstr("abc"), cstr("%d%n"), addr<void?>(n), addr(consumed)), 0)
            t |> equal(consumed, -1)
            // das's "" is a null pointer (docs/probe-findings.md F10): the empty input is a NUL byte
            var nul : uint8[1]
            // C fixes an input failure's result only as EOF, a negative value
            t |> equal(crt::sscanf_one(addr(nul[0]), cstr("%d%n"), addr<void?>(n), addr(consumed)) < 0, true)
            consumed = -1
            t |> equal(crt::sscanf_none(cstr(" 77 rest"), cstr("%*d%n"), addr(consumed)), 0)
            t |> equal(consumed, 3)
        }
    }
}

// glibc's `struct timespec` on x86_64: the seconds and the nanoseconds, a word each
struct CTimespec {
    tv_sec : int64
    tv_nsec : int64
}

// `struct tm` as C names its first nine members, which glibc lays out in this order; the tail
// (`tm_gmtoff`, `tm_zone`) is room the CRT may write
struct CTm {
    tm_sec, tm_min, tm_hour, tm_mday, tm_mon, tm_year, tm_wday, tm_yday, tm_isdst : int
    tail : int64[2]
}

[test]
def test_crt_time_locale(t : T?) {
    t |> run("mktime normalizes, localtime and gmtime convert back, strftime formats, the C locale's point") @(t : T?) {
        unsafe {
            // C fixes mktime's normalization: the 32nd of January is the 1st of February
            var tm = CTm(tm_mday = 32, tm_mon = 0, tm_year = 100, tm_hour = 12, tm_isdst = -1)
            var when = crt::mktime(addr<void?>(tm))
            t |> equal(when != -1l, true)
            t |> equal(tm.tm_mon, 1)
            t |> equal(tm.tm_mday, 1)
            let local = reinterpret<CTm?>(crt::localtime(addr(when)))
            t |> equal(local.tm_mon == 1 && local.tm_mday == 1 && local.tm_year == 100, true)
            t |> equal(crt::gmtime(addr(when)) != null, true)
            var buf : uint8[16]
            t |> equal(crt::strftime(addr(buf[0]), 16ul, cstr("%Y-%m-%d"), addr<void?>(tm)), 10ul)
            t |> equal(as_string(addr(buf[0])), "2000-02-01")
            // the C locale is every program's at startup; a null locale queries it
            t |> equal(as_string(crt::setlocale(0, null)), "C")
            // `decimal_point`, the member C lists first and glibc lays out first, is "." in the C locale
            t |> equal(as_string(deref(reinterpret<uint8 ??>(crt::localeconv()))), ".")
        }
    }
}

[test]
def test_crt_stdio(t : T?) {
    t |> run("a FILE as void?: writes, reads, positions, errors and the standard streams") @(t : T?) {
        unsafe {
            t |> equal(crt::c_stdin() != null && crt::c_stdout() != null && crt::c_stderr() != null, true)
            t |> equal(crt::fflush(crt::c_stderr()), 0)
            var f = crt::tmpfile()
            t |> equal(f != null, true)
            t |> equal(crt::fputs(cstr("ab\n"), f) >= 0, true)
            t |> equal(crt::fwrite(cstr("cde"), 1ul, 3ul, f), 3ul)
            t |> equal(crt::fflush(f), 0)
            t |> equal(crt::ftell(f), 6l)
            // SEEK_SET, which glibc and every POSIX system spell 0
            t |> equal(crt::fseek(f, 0l, 0), 0)
            t |> equal(crt::getc(f), 'a')
            t |> equal(crt::ungetc('A', f), 'A')
            var line : uint8[8]
            t |> equal(crt::fgets(addr(line[0]), 8, f) == addr(line[0]), true)
            t |> equal(as_string(addr(line[0])), "Ab\n")
            var rest : uint8[8]
            t |> equal(crt::fread(addr<void?>(rest[0]), 1ul, 8ul, f), 3ul)
            t |> equal(crt::feof(f) != 0, true)
            t |> equal(crt::ferror(f), 0)
            crt::clearerr(f)
            t |> equal(crt::feof(f), 0)
            t |> equal(crt::setvbuf(f, null, 2, 0ul), 0)
            t |> equal(crt::fclose(f), 0)
        }
    }
    t |> run("named files: fopen, freopen, rename, remove, tmpnam, system") @(t : T?) {
        var dir_error : string
        let dir = create_temp_directory("c2das_crt", dir_error)
        t |> equal(dir_error, "")
        let first = path_join(dir, "first.txt")
        let second = path_join(dir, "second.txt")
        unsafe {
            var f = crt::fopen(cstr(first), cstr("w"))
            t |> equal(f != null, true)
            t |> equal(crt::fputs(cstr("x"), f) >= 0, true)
            f = crt::freopen(cstr(first), cstr("r"), f)
            t |> equal(crt::getc(f), 'x')
            t |> equal(crt::fclose(f), 0)
            t |> equal(crt::rename(cstr(first), cstr(second)), 0)
            t |> equal(crt::fopen(cstr(first), cstr("r")) == null, true)
            t |> equal(crt::remove(cstr(second)), 0)
            t |> equal(crt::remove(cstr(second)) != 0, true)
            var name : uint8[4096]
            t |> equal(crt::tmpnam(addr(name[0])) == addr(name[0]), true)
            // a null command asks whether a command processor exists
            t |> equal(crt::system(null) != 0, true)
        }
        rmdir_rec(dir)
    }
}

[test]
def test_crt_volatile(t : T?) {
    t |> run("each volatile forwarder reads or writes its width once through the pointer it is given") @(t : T?) {
        var i8 = int8(-5)
        var u8 = 250u8
        var i16 = int16(-300)
        var u16 = uint16(60000)
        var i32 = -70000
        var u32 = 4000000000u
        var i64 = -5000000000l
        var u64 = 18000000000000000000ul
        var f32 = 1.5f
        var f64 = -2.25lf
        unsafe {
            crt::c_volatile_store_i8(addr(i8), int8(int(crt::c_volatile_load_i8(addr(i8))) - 1))
            crt::c_volatile_store_u8(addr(u8), uint8(int(crt::c_volatile_load_u8(addr(u8))) + 1))
            crt::c_volatile_store_i16(addr(i16), int16(int(crt::c_volatile_load_i16(addr(i16))) - 1))
            crt::c_volatile_store_u16(addr(u16), uint16(int(crt::c_volatile_load_u16(addr(u16))) + 1))
            crt::c_volatile_store_i32(addr(i32), crt::c_volatile_load_i32(addr(i32)) - 1)
            crt::c_volatile_store_u32(addr(u32), crt::c_volatile_load_u32(addr(u32)) + 1u)
            crt::c_volatile_store_i64(addr(i64), crt::c_volatile_load_i64(addr(i64)) - 1l)
            crt::c_volatile_store_u64(addr(u64), crt::c_volatile_load_u64(addr(u64)) + 1ul)
            crt::c_volatile_store_f32(addr(f32), crt::c_volatile_load_f32(addr(f32)) * 2.0f)
            crt::c_volatile_store_f64(addr(f64), crt::c_volatile_load_f64(addr(f64)) * 2.0lf)
        }
        t |> equal(i8, int8(-6))
        t |> equal(u8, 251u8)
        t |> equal(i16, int16(-301))
        t |> equal(u16, uint16(60001))
        t |> equal(i32, -70001)
        t |> equal(u32, 4000000001u)
        t |> equal(i64, -5000000001l)
        t |> equal(u64, 18000000000000000001ul)
        t |> equal(f32, 3.0f)
        t |> equal(f64, -4.5lf)
    }
}
