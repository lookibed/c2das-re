options gen2
require dastest/testing_boost public
require daslib/regex
require daslib/regex_boost
require daslib/fio
require daslib/strings_boost
require ../converter/tiers.das

// the byte at `i` of literal `p`
def private byte_at(p : uint8?; i : int) : int {
    unsafe {
        return int(deref(p + i))
    }
}

// a child that prints the bytes of literals with escapes the converter writes, past their NULs
let ESCAPE_SOURCE = "options gen2\n\ndef dump(p : uint8?; n : int) \{\n    var s = \"\"\n    unsafe \{\n        for (i in range(n)) \{\n            s += \" \{int(deref(p + i))\}\"\n        \}\n    \}\n    print(\"\{s\}\\n\")\n\}\n\n[export]\ndef main : int \{\n    unsafe \{\n        dump(reinterpret<uint8?>(\"a\\x00b\"), 4)\n        dump(reinterpret<uint8?>(\"\\0a\\x0012\\a\\v\\xff\\x80\"), 10)\n    \}\n    return 0\n\}\n"

let ESCAPE_EXPECTED = " 97 0 98 0\n 0 97 0 49 50 7 11 255 128 0\n"

[test]
def test_strings(t : T?) {
    t |> run("a das literal is a NUL-terminated byte-walkable interned C string") @(t : T?) {
        unsafe {
            let msg = reinterpret<uint8?>("hello")
            var n = 0
            while (deref(msg + n) != uint8(0)) {
                n++
            }
            t |> equal(n, 5)
            t |> equal(int(deref(msg)), 'h')
            let again = reinterpret<uint8?>("hello")
            t |> equal(intptr(msg) == intptr(again), true)
        }
    }
    t |> run("the empty das literal is a null pointer, not a pointer to a NUL") @(t : T?) {
        unsafe {
            t |> equal(reinterpret<uint8?>("") == null, true)
            t |> equal(reinterpret<uint8?>("x") != null, true)
        }
    }
    t |> run("reinterpret<string> bridges a NUL-terminated buffer as an alias") @(t : T?) {
        var buf : uint8[8]
        buf[0] = uint8('a')
        buf[1] = uint8('b')
        buf[2] = uint8('c')
        unsafe {
            let s = reinterpret<string>(addr(buf[0]))
            t |> equal(length(s), 3)
            t |> equal(s == "abc", true)
            buf[1] = uint8('X')
            t |> equal(s == "aXc", true)
        }
    }
    t |> run("a literal keeps the bytes after an interior \\x00, and two literals differing only past it are two pointers") @(t : T?) {
        unsafe {
            let p = reinterpret<uint8?>("a\x00b")
            let q = reinterpret<uint8?>("a\x00c")
            t |> equal(int(deref(p + 1)), 0)
            t |> equal(int(deref(p + 2)), 'b')
            t |> equal(int(deref(p + 3)), 0)
            t |> equal(int(deref(q + 2)), 'c')
            t |> equal(intptr(p) != intptr(q), true)
        }
    }
}

[test]
def test_regex_alternation(t : T?) {
    t |> run("daslib regex: a repeated group whose alternatives share a prefix backtracks into them (F71, fixed upstream); an optional suffix finds it too") @(t : T?) {
        var prefixed <- regex_compile("x(aba|ab|b)*c")
        t |> equal(regex_search(prefixed, "xabac").x, 0, "the quantifier retries the group's other alternatives")
        var alternation <- regex_compile("\\b(__asm__|__asm|asm)(\\s|__volatile__|__volatile|volatile)*\\(")
        t |> equal(regex_search(alternation, "x __asm __volatile__ (").x, 2)
        var optional <- regex_compile("x(ab(a)?|b)*c")
        t |> equal(regex_search(optional, "xabac").x, 0)
        var keyword <- regex_compile("\\b(__asm(__)?|asm)(\\s|__volatile(__)?|volatile)*\\(")
        t |> equal(regex_search(keyword, "x __asm __volatile__ (").x, 2)
    }
}

[test]
def test_c_escapes(t : T?) {
    t |> run("a string literal takes the C escapes: \\0, \\a, \\v, \\?, \\xHH and octal (F94)") @(t : T?) {
        let p = unsafe(reinterpret<uint8?>("\a\v\?\b\f\0"))
        t |> equal(byte_at(p, 0), 7)
        t |> equal(byte_at(p, 1), 11)
        t |> equal(byte_at(p, 2), '?')
        t |> equal(byte_at(p, 3), 8)
        t |> equal(byte_at(p, 4), 12)
        t |> equal(byte_at(p, 5), 0)
    }
    t |> run("\\x takes at most two hex digits, so \\x00 before a digit or a hex letter is one NUL") @(t : T?) {
        let p = unsafe(reinterpret<uint8?>("\x0012\x41BC\x0f"))
        t |> equal(byte_at(p, 0), 0)
        t |> equal(byte_at(p, 1), '1')
        t |> equal(byte_at(p, 2), '2')
        t |> equal(byte_at(p, 3), 'A')
        t |> equal(byte_at(p, 4), 'B')
        t |> equal(byte_at(p, 6), 15)
    }
    t |> run("\\0 before an octal digit is an octal escape: \\012 is a newline, so a NUL before a digit 0-7 is never \\0") @(t : T?) {
        let p = unsafe(reinterpret<uint8?>("\012|\0009|\1012|\4777"))
        t |> equal(byte_at(p, 0), 10, "the control: \\0 then 12 reads as one byte")
        t |> equal(byte_at(p, 2), 0)
        t |> equal(byte_at(p, 3), '9', "8 and 9 are no octal digits")
        t |> equal(byte_at(p, 5), 'A', "an octal escape takes at most three digits")
        t |> equal(byte_at(p, 6), '2')
        t |> equal(byte_at(p, 8), 39, "one starting 4-7 takes at most two")
        t |> equal(byte_at(p, 9), '7')
    }
    t |> run("a byte past 0x7f is \\xHH, a raw UTF-8 byte stays itself, \\u0000 is a NUL") @(t : T?) {
        unsafe {
            let p = reinterpret<uint8?>("\x80\xff\xc3\xa9é")
            t |> equal(byte_at(p, 0), 128)
            t |> equal(byte_at(p, 1), 255)
            t |> equal(byte_at(p, 4), 195)
            t |> equal(byte_at(p, 5), 169)
            let u = reinterpret<uint8?>("a\u0000b")
            t |> equal(byte_at(u, 1), 0)
            t |> equal(byte_at(u, 2), 'b')
        }
    }
    t |> run("an embedded NUL ends the string as a string, the literal's bytes after it stay") @(t : T?) {
        t |> equal(length("a\0b"), 1)
        t |> equal("a\0b" == "a\0c", true)
        let p = unsafe(reinterpret<uint8?>("a\0b"))
        t |> equal(byte_at(p, 1), 0)
        t |> equal(byte_at(p, 2), 'b')
        t |> equal(byte_at(p, 3), 0)
    }
    t |> run("a character literal takes the C escapes too: '\\0' '\\a' '\\v' '\\xHH' octal, all of type int") @(t : T?) {
        t |> equal('\0', 0)
        t |> equal('\a', 7)
        t |> equal('\v', 11)
        t |> equal('\x1b', 27)
        t |> equal('\033', 27)
        t |> equal('\x7f', 127)
        t |> equal('\xff', 255)
        t |> equal(typeinfo typename('\0'), "int const")
    }
    for (tier in fixed_array("interp", "jit", "exe", "aot")) {
        t |> run("under {tier} the bytes after an interior NUL stay, every escape the converter writes reads as under interp") @(t : T?) {
            let work = path_join(test_temp_dir(), "escapes_{tier}")
            mkdir_rec(work)
            let entry = path_join(work, "escapes_probe.das")
            fwrite(entry, ESCAPE_SOURCE)
            var out : string
            t |> equal(run_tier(entry, tier, work, out), 0, out)
            t |> success(out |> contains(ESCAPE_EXPECTED), "{tier}: {out}")
        }
    }
}
