options gen2
require dastest/testing_boost public
require strings
require daslib/strings_boost
require c_runtime/printf
require crt
require ../../probes/_daslang_child.das

struct Case {
    fmt : string
    c_args : string
    va : CVaList
}

def cstr(s : string) : uint8? => unsafe(reinterpret<uint8?>(s))

def iv(v : int64) : CVal => CVal(i = v)

def dv(v : double) : CVal => CVal(d = v)

def sv(s : string) : CVal => CVal(p = unsafe(reinterpret<void?>(s)))

//! The conversion battery: one line per case, the C argument list spelled for clang and the
//! same values as a CVaList for the das side.
def battery : array<Case> {
    return <- [
        Case(fmt = "%d|%5d|%-5d|%05d|%+d|% d|%i", c_args = "42, 42, 42, 42, 42, 42, -7", va <- [iv(42l), iv(42l), iv(42l), iv(42l), iv(42l), iv(42l), iv(-7l)]),
        Case(fmt = "%u|%o|%x|%X|%#x|%#o|%08x", c_args = "3000000000u, 8u, 255u, 255u, 255u, 8u, 48879u", va <- [iv(3000000000l), iv(8l), iv(255l), iv(255l), iv(255l), iv(8l), iv(48879l)]),
        Case(fmt = "%lld|%llu|%zu|%hd|%hhd|%hu|%c", c_args = "-5000000000LL, 18446744073709551615ULL, (size_t)123456789012ULL, (short)-3, (signed char)-2, (unsigned short)65535, 'Q'", va <- [iv(-5000000000l), iv(-1l), iv(123456789012l), iv(-3l), iv(-2l), iv(65535l), iv(81l)]),
        Case(fmt = "%f|%.2f|%10.3f|%-10.1f|%e|%E|%g|%G|%.0f|%#.0f", c_args = "3.14159, 3.14159, 3.14159, 3.14159, 12345.678, 12345.678, 0.0001, 1e20, 2.5, 2.5", va <- [dv(3.14159lf), dv(3.14159lf), dv(3.14159lf), dv(3.14159lf), dv(12345.678lf), dv(12345.678lf), dv(0.0001lf), dv(1e20lf), dv(2.5lf), dv(2.5lf)]),
        Case(fmt = "%s|%10s|%-10s|%.2s|%%|%5.1s|", c_args = "\"hello\", \"hi\", \"hi\", \"hello\", \"xyz\"", va <- [sv("hello"), sv("hi"), sv("hi"), sv("hello"), sv("xyz")]),
        Case(fmt = "%*d|%-*d|%.*f|%*.*f", c_args = "6, 42, 6, 42, 3, 2.0, 8, 2, 2.0", va <- [iv(6l), iv(42l), iv(6l), iv(42l), iv(3l), dv(2.0lf), iv(8l), iv(2l), dv(2.0lf)]),
        Case(fmt = "%a|%A|%ld|%lu|%lx", c_args = "1.0, 0.5, (long)-9, (unsigned long)9, (unsigned long)255", va <- [dv(1.0lf), dv(0.5lf), iv(-9l), iv(9l), iv(255l)]),
        // the dialect's `long double` is a `double`: the C side passes a `long double`, the
        // converted side the `double` it lowers to
        Case(fmt = "%Lf|%.3Le|%Lg", c_args = "2.5L, 12345.678L, 0.25L", va <- [dv(2.5lf), dv(12345.678lf), dv(0.25lf)])
    ]
}

def c_escaped(s : string) : string =>
    s |> replace("\\", "\\\\") |> replace("\"", "\\\"") |> replace("\n", "\\n")

def native_output(cases : array<Case>) : string {
    let body = build_string() $(var w) {
        w |> write("#include <stdio.h>\nint main(void) \{\n")
        for (c in cases) {
            w |> write("    printf(\"{c_escaped(c.fmt)}\\n\", {c.c_args});\n")
        }
        w |> write("    return 0;\n\}\n")
    }
    let no_flags : array<string>
    return native_battery("c2das_printf_battery", no_flags, body)
}

def das_output(cases : array<Case>) : string {
    return build_string() $(var w) {
        for (c in cases) {
            w |> write(string(c_vformat(cstr(c.fmt), c.va)))
            w |> write("\n")
        }
    }
}

[test]
def test_printf(t : T?) {
    t |> run("the conversion battery renders byte for byte as the native printf") @(t : T?) {
        let cases <- battery()
        let native = native_output(cases)
        let ours = das_output(cases)
        t |> equal(ours, native)
        t |> equal(native |> find("3.14") >= 0, true, native)
    }
    t |> run("snprintf truncates with a NUL and reports the full length; sprintf has no bound") @(t : T?) {
        var buf : uint8[8]
        unsafe {
            var p = addr(buf[0])
            t |> equal(snprintf(p, 4ul, cstr("%d-%d"), 123, 456), 7)
            t |> equal(reinterpret<string>(p), "123")
            t |> equal(sprintf(p, cstr("%s!"), cstr("hey")), 4)
            t |> equal(reinterpret<string>(p), "hey!")
            t |> equal(snprintf(p, 0ul, cstr("x")), 1)
            t |> equal(reinterpret<string>(p), "hey!")
        }
    }
    t |> run("an `l` conversion has the dialect's `long` width whatever the host's: 32 bits under msvc, 64 under linux") @(t : T?) {
        let saved = c_long_bits
        let lst <- [CVal(i = -1l), CVal(i = -5l), CVal(i = -1l), CVal(i = 4294967303l), CVal(i = -1l)]
        c_long_bits = 32
        let msvc = string(c_vformat(cstr("%lx|%ld|%lu|%ld|%Lx"), lst))
        c_long_bits = 64
        let linux = string(c_vformat(cstr("%lx|%ld|%lu|%ld|%Lx"), lst))
        c_long_bits = 32
        var wide_caught = false
        try {
            c_vformat(cstr("%lc"), lst)
        } recover {
            wide_caught = true
        }
        c_long_bits = saved
        t |> equal(msvc, "ffffffff|-5|4294967295|7|ffffffffffffffff")
        t |> equal(linux, "ffffffffffffffff|-5|18446744073709551615|4294967303|ffffffffffffffff")
        t |> equal(wide_caught, crt::LONG_BITS != 32)
    }
    t |> run("a printf `*` takes the width's place, so `%*5d` is no directive printf knows") @(t : T?) {
        var caught = false
        try {
            c_vformat(cstr("%*5d"), [CVal(i = 1l), CVal(i = 2l)])
        } recover {
            caught = true
        }
        t |> equal(caught, true)
    }
    t |> run("the CVaList fronts take a forwarded va_list: c_vsprintf and c_vsnprintf over va_rest of a cursor") @(t : T?) {
        var buf : uint8[16]
        let lst <- [CVal(i = 9l), CVal(i = 42l), CVal(p = unsafe(reinterpret<void?>("go")))]
        var v = va_begin(lst)
        va_i(v)
        unsafe {
            var p = addr(buf[0])
            t |> equal(c_vsprintf(p, cstr("%d-%s"), va_rest(v)), 5)
            t |> equal(reinterpret<string>(p), "42-go")
            t |> equal(c_vsnprintf(p, 3ul, cstr("%d-%s"), va_rest(v)), 5)
            t |> equal(reinterpret<string>(p), "42")
        }
    }
    t |> run("printf writes the bytes to the CRT stdout and returns their count") @(t : T?) {
        t |> equal(printf(cstr("ok\n")), 3)
        t |> equal(printf(cstr("%d%s"), 5, cstr("\n")), 2)
        t |> equal(printf(null), 0)
    }
    t |> run("a directive whose argument has the wrong class panics, the C undefined behavior made visible") @(t : T?) {
        var buf : uint8[8]
        var caught = false
        var p = unsafe(addr(buf[0]))
        try {
            snprintf(p, 8ul, cstr("%d"), 1.5lf)
        } recover {
            caught = true
        }
        t |> equal(caught, true)
    }
}

[test]
def test_fprintf(t : T?) {
    t |> run("fprintf writes the bytes to a CRT stream, a FILE * as void?, and returns their count") @(t : T?) {
        unsafe {
            var f = crt::tmpfile()
            t |> equal(fprintf(f, cstr("%d-%s"), 42, cstr("go")), 5)
            t |> equal(fprintf(f, cstr("!")), 1)
            crt::fseek(f, 0l, 0)
            var back : uint8[8]
            t |> equal(crt::fread(addr<void?>(back[0]), 1ul, 8ul, f), 6ul)
            t |> equal(reinterpret<string>(addr(back[0])), "42-go!")
            crt::fclose(f)
            t |> equal(fprintf(crt::c_stdout(), cstr("ok\n")), 3)
        }
    }
}
