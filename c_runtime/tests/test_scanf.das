options gen2
require dastest/testing_boost public
require strings
require daslib/strings_boost
require c_runtime/scanf
require crt
require c_runtime/printf
require ../../probes/_daslang_child.das

//! The sscanf battery, as-if-converted: each case's out-arguments are pointers into C-shaped
//! storage, filled by `c_vsscanf` (and the `sscanf` front) and rendered by the printf family,
//! byte for byte against the same calls in a native C program.

struct Case {
    input : string
    fmt : string
    // one letter per out-argument: i int, h short, b signed char, l long long, u unsigned,
    // f float, d double, L long double, s char[32]
    kinds : string
}

def cstr(s : string) : uint8? => unsafe(reinterpret<uint8?>(s))

def battery : array<Case> {
    return <- [
        Case(input = "42 -17 0x1f 077", fmt = "%d %i %x %o", kinds = "iiuu"),
        Case(input = "3.5 -2e3 1e-2", fmt = "%f %lf %Lf", kinds = "fdL"),
        Case(input = "hello world", fmt = "%s %3s", kinds = "ss"),
        Case(input = "abc,def", fmt = "%[^,],%s", kinds = "ss"),
        Case(input = "12345678", fmt = "%3d%2d%n%d", kinds = "iiii"),
        Case(input = "x=7;y=8", fmt = "x=%d;y=%d", kinds = "ii"),
        Case(input = "  -5  ", fmt = "%hd%hhd", kinds = "hb"),
        Case(input = "   ", fmt = "%d", kinds = "i"),
        Case(input = "abc", fmt = "%d", kinds = "i"),
        Case(input = "9999999999 -3", fmt = "%lld %ld", kinds = "ll"),
        Case(input = "100%", fmt = "%d%%", kinds = "i"),
        Case(input = "skip 5", fmt = "%*s %d", kinds = "i"),
        Case(input = "xyz", fmt = "%c%2c", kinds = "ss"),
        Case(input = "12abc", fmt = "%d%n%s", kinds = "iis"),
        Case(input = "0x10 010 10", fmt = "%i %i %i", kinds = "iii"),
        Case(input = "1.5 2.5", fmt = "%f,%f", kinds = "ff"),
        Case(input = "7 q", fmt = "%u %hhn%c", kinds = "ubs"),
        Case(input = "ab", fmt = "a%dz", kinds = "i"),
        Case(input = "]x]y", fmt = "%[]x]%[y]", kinds = "ss"),
        Case(input = "12345", fmt = "%*3d%d", kinds = "i"),
        Case(input = "ab]xc", fmt = "%[^]x]%s", kinds = "ss"),
        Case(input = "  ", fmt = " x%d", kinds = "i"),
        Case(input = "7 8", fmt = "%d%*n %d", kinds = "ii")
    ]
}

def c_type(kind : int) : string {
    if (kind == 'i') {
        return "int"
    } elif (kind == 'h') {
        return "short"
    } elif (kind == 'b') {
        return "signed char"
    } elif (kind == 'l') {
        return "long long"
    } elif (kind == 'u') {
        return "unsigned"
    } elif (kind == 'f') {
        return "float"
    } elif (kind == 'd') {
        return "double"
    } elif (kind == 'L') {
        return "long double"
    }
    return "char"
}

// how a slot prints: the same printf format on both sides, the value widened as C's default
// promotions widen it
def render_fmt(kind : int) : string {
    if (kind == 'l') {
        return " %lld"
    } elif (kind == 'u') {
        return " %u"
    } elif (kind == 'f' || kind == 'd' || kind == 'L') {
        return " %.17g"
    } elif (kind == 's') {
        return " [%s]"
    }
    return " %d"
}

def native_output(cases : array<Case>) : string {
    let body = build_string() $(var f) {
        f |> write("#include <stdio.h>\nint main(void) \{\n")
        for (c in cases) {
            f |> write("    \{\n")
            var inscope args : array<string>
            for (k, slot_idx in c.kinds, range(length(c.kinds))) {
                if (k == 's') {
                    f |> write("        char v{slot_idx}[32] = \"~\";\n")
                    args |> push("v{slot_idx}")
                } else {
                    f |> write("        {c_type(k)} v{slot_idx} = -1;\n")
                    args |> push("&v{slot_idx}")
                }
            }
            f |> write("        int r = sscanf(\"{c.input}\", \"{c.fmt}\", {join(args, ", ")});\n")
            f |> write("        printf(\"r=%d\", r);\n")
            for (k, slot_idx in c.kinds, range(length(c.kinds))) {
                let value = k == 'L' ? "(double) v{slot_idx}" : "v{slot_idx}"
                f |> write("        printf(\"{render_fmt(k)}\", {value});\n")
            }
            f |> write("        printf(\"\\n\");\n    \}\n")
        }
        f |> write("    return 0;\n\}\n")
    }
    return native_battery("c2das_scanf_battery", ["-funsigned-char"], body)
}

// one slot's storage: 32 bytes, 8-aligned, holding the C object of the slot's kind
struct Slot {
    words : uint64[4]
}

def preset(var s : Slot; kind : int) {
    unsafe {
        let p = addr(s.words[0])
        if (kind == 's') {
            deref(reinterpret<uint8?>(p)) = uint8('~')
        } elif (kind == 'f') {
            deref(reinterpret<float?>(p)) = -1.0f
        } elif (kind == 'd' || kind == 'L') {
            deref(reinterpret<double?>(p)) = -1.0lf
        } elif (kind == 'l') {
            deref(reinterpret<int64?>(p)) = -1l
        } elif (kind == 'h') {
            deref(reinterpret<int16?>(p)) = int16(-1)
        } elif (kind == 'b') {
            deref(reinterpret<int8?>(p)) = int8(-1)
        } else {
            deref(reinterpret<int?>(p)) = -1
        }
    }
}

// the slot read back as C's default promotions pass it to printf
def promoted(s : Slot; kind : int) : CVal {
    unsafe {
        let p = addr(s.words[0])
        if (kind == 's') {
            return CVal(p = reinterpret<void?>(p))
        } elif (kind == 'f') {
            return CVal(d = double(deref(reinterpret<float?>(p))))
        } elif (kind == 'd' || kind == 'L') {
            return CVal(d = deref(reinterpret<double?>(p)))
        } elif (kind == 'l') {
            return CVal(i = deref(reinterpret<int64?>(p)))
        } elif (kind == 'h') {
            return CVal(i = int64(deref(reinterpret<int16?>(p))))
        } elif (kind == 'b') {
            return CVal(i = int64(deref(reinterpret<int8?>(p))))
        } elif (kind == 'u') {
            return CVal(i = int64(deref(reinterpret<uint?>(p))))
        }
        return CVal(i = int64(deref(reinterpret<int?>(p))))
    }
}

def rendered(fmt : string; v : CVal) : string => string(c_vformat(cstr(fmt), [v]))

def das_output(cases : array<Case>) : string {
    return build_string() $(var w) {
        for (c in cases) {
            var inscope slots : array<Slot>
            slots |> resize(length(c.kinds))
            var inscope lst : CVaList
            for (k, slot_idx in c.kinds, range(length(c.kinds))) {
                preset(slots[slot_idx], k)
                lst |> push(CVal(p = unsafe(addr<void?>(slots[slot_idx].words[0]))))
            }
            let r = c_vsscanf(cstr(c.input), cstr(c.fmt), lst)
            w |> write("r={r}")
            for (k, slot_idx in c.kinds, range(length(c.kinds))) {
                w |> write(rendered(render_fmt(k), promoted(slots[slot_idx], k)))
            }
            w |> write("\n")
        }
    }
}

// a `va_list` forwarded after one pop, as the converter emits `vsscanf(src, fmt, ap)`
[variadic]
def scan_after(src : uint8?; fmt : uint8?; va : va_args) : int {
    var ap : CVaCursor
    ap = va_begin(va)
    let skip = va_i(ap)
    return c_vsscanf(src, fmt, va_rest(ap)) + int(skip) * 100
}

[test]
def test_scanf(t : T?) {
    t |> run("the sscanf battery assigns, counts and stops byte for byte as the native sscanf") @(t : T?) {
        let cases <- battery()
        let native = native_output(cases)
        let ours = das_output(cases)
        t |> equal(ours, native)
        t |> equal(native |> find("r=4 42 -17 31 63") >= 0, true, native)
    }
    t |> run("the sscanf front tuples the out-pointers as C spells the call") @(t : T?) {
        var n = 0
        var d = 0.0lf
        var word : uint8[8]
        unsafe {
            t |> equal(sscanf(cstr("12 2.5 hi"), cstr("%d %lf %7s"), addr(n), addr(d), addr(word[0])), 3)
            t |> equal(reinterpret<string>(addr(word[0])), "hi")
        }
        t |> equal(n, 12)
        t |> equal(d, 2.5lf)
        t |> equal(sscanf(cstr("x"), cstr("x")), 0)
        t |> equal(sscanf(cstr("x"), null), 0)
    }
    t |> run("an out-argument that is not a pointer panics, the C undefined behavior made visible") @(t : T?) {
        var caught = false
        try {
            sscanf(cstr("5"), cstr("%d"), 5)
        } recover {
            caught = true
        }
        t |> equal(caught, true)
    }
}

[test]
def test_fscanf(t : T?) {
    t |> run("fscanf reads a stream directive by directive as Quake's savegame lines: an int, a word, floats, a literal, and stops at a mismatch or the end") @(t : T?) {
        unsafe {
            var f = crt::tmpfile()
            crt::fputs(cstr("5\nstart\n1.5\n-2.25\nkey=9 tail\n"), f)
            crt::fseek(f, 0l, 0)
            var version = 0
            var word : uint8[16]
            var a = 0.0
            var b = 0.0
            var key = 0
            t |> equal(fscanf(f, cstr("%i\n"), addr(version)), 1)
            t |> equal(fscanf(f, cstr("%s\n"), addr(word[0])), 1)
            t |> equal(fscanf(f, cstr("%f\n%f\n"), addr(a), addr(b)), 2)
            t |> equal(fscanf(f, cstr("key=%d"), addr(key)), 1)
            t |> equal("{version} {reinterpret<string>(addr(word[0]))} {a} {b} {key}", "5 start 1.5 -2.25 9")
            // `t` does not match `x`: nothing assigned; the input then ends before a conversion
            t |> equal(fscanf(f, cstr(" x%d"), addr(key)), 0)
            t |> equal(fscanf(f, cstr("tail%d"), addr(key)), C_EOF)
            crt::fclose(f)
        }
    }
}

[test]
def test_scanf_widths(t : T?) {
    t |> run("an `l` conversion stores the dialect's `long`: 4 bytes under msvc, the next word untouched") @(t : T?) {
        let saved = c_long_bits
        c_long_bits = 32
        var words : int[6]
        for (w in words) {
            w = 77
        }
        var r = 0
        unsafe {
            r = c_vsscanf(cstr("-5 4294967295 ab"), cstr("%ld %lu %ln"), [CVal(p = addr<void?>(words[0])), CVal(p = addr<void?>(words[2])), CVal(p = addr<void?>(words[4]))])
        }
        c_long_bits = saved
        t |> equal(r, 2)
        t |> equal(words[0], -5)
        t |> equal(words[1], 77)
        t |> equal(words[2], -1)
        t |> equal(words[3], 77)
        t |> equal(words[4], 14)
        t |> equal(words[5], 77)
    }
    t |> run("a forwarded va_list scans from where the cursor stands") @(t : T?) {
        var n = 0
        t |> equal(scan_after(cstr("41"), cstr("%d"), 9, unsafe(addr(n))), 901)
        t |> equal(n, 41)
    }
    t |> run("a directive C's scanf does not define panics before it takes an argument") @(t : T?) {
        // the directive the message names runs to the conversion it does not know
        for (fmt, shown in ["%qd", "%1$d", "%ms", "%"], ["%q", "%1$", "%m", "%"]) {
            // no out-argument at all: a directive that took one first would report the list's end
            let src = "options gen2\nrequire c_runtime/scanf\n[export]\ndef main \{\n    unsafe \{\n        sscanf(reinterpret<uint8?>(\"5\"), reinterpret<uint8?>(\"{fmt}\"))\n    \}\n\}\n"
            let r = runtime_child("scanf_unknown", src, false)
            t |> equal(r.rc != 0, true, r.out)
            t |> equal(r.out |> find("sscanf: directive `{shown}` is not supported") >= 0, true, r.out)
        }
    }
    t |> run("`%n` stores at its length modifier's width, the bytes beside it untouched; `%*n` stores nothing") @(t : T?) {
        let saved = c_long_bits
        c_long_bits = 64
        var bytes : uint8[48]
        for (b in bytes) {
            b = uint8(238)
        }
        var r = 0
        unsafe {
            let at = addr(bytes[0])
            r = c_vsscanf(cstr("abc"), cstr("a%hhnb%hnc%ln%lln%jn%*n"), [CVal(p = reinterpret<void?>(at)), CVal(p = reinterpret<void?>(at + 8)), CVal(p = reinterpret<void?>(at + 16)), CVal(p = reinterpret<void?>(at + 24)), CVal(p = reinterpret<void?>(at + 32))])
        }
        c_long_bits = saved
        t |> equal(r, 0)
        // %hhn: 1 byte of 1; %hn: 2 bytes of 2; %ln, %lln, %jn: 8 bytes of 3
        t |> equal(int(bytes[0]), 1)
        t |> equal(int(bytes[1]), 238)
        t |> equal(int(bytes[8]) + int(bytes[9]) * 256, 2)
        t |> equal(int(bytes[10]), 238)
        for (base in [16, 24, 32]) {
            t |> equal(int(bytes[base]), 3)
            for (k in range(1, 8)) {
                t |> equal(int(bytes[base + k]), 0)
            }
        }
        t |> equal(int(bytes[40]), 238)
    }
}

[test]
def test_scanf_directives(t : T?) {
    t |> run("an unterminated set reads no byte past the format's end") @(t : T?) {
        var word : uint8[8]
        let d = c_parse_directive(cstr("%[abc"), 0, true)
        t |> equal(d.end, 5)
        t |> equal(d.spec, "%[abc")
        t |> equal(c_vsscanf(cstr("abcd"), cstr("%[abc"), [CVal(p = unsafe(addr<void?>(word[0])))]) <= 1, true)
        let star = c_parse_directive(cstr("%*3d"), 0, true)
        t |> equal(star.leading_star, true)
        t |> equal(star.conv, 'd')
        let negated = c_parse_directive(cstr("%[^]x]z"), 0, true)
        t |> equal(negated.spec, "%[^]x]")
    }
    t |> run("a null input panics with its own message") @(t : T?) {
        let src = "options gen2\nrequire c_runtime/scanf\n[export]\ndef main \{\n    var n = 0\n    unsafe \{\n        sscanf(null, reinterpret<uint8?>(\"%d\"), addr(n))\n    \}\n\}\n"
        let r = runtime_child("scanf_null", src, false)
        t |> equal(r.out |> find("sscanf: the input is a null pointer") >= 0, true, r.out)
    }
}
