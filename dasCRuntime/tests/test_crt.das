options gen2
require dastest/testing_boost public
require crt
require math

def cstr(s : string) : uint8? {
    return unsafe(reinterpret<uint8?>(s))
}

def as_string(p : uint8?) : string {
    return unsafe(reinterpret<string>(p))
}

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
            t |> equal(crt::EDOM != crt::ERANGE && crt::ERANGE != crt::EINVAL, true)
            crt::c_set_errno(0)
            t |> equal(crt::atoi(cstr("-42")), -42)
            t |> equal(crt::atol(cstr("4000000000")), 4000000000l)
            t |> equal(crt::atof(cstr("0.5")), 0.5lf)
            t |> equal(crt::abs(-3), 3)
            t |> equal(crt::llabs(-3l), 3l)
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
        t |> equal(crt::time() > 1700000000l, true)
        t |> equal(crt::clock() >= 0l, true)
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
