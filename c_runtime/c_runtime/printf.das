options gen2

module printf public

require strings
require math
require daslib/strings_boost
require crt
require c_runtime/variadic public

//! The printf family over a `CVaList`: the C format is split at its directives and every
//! directive is rendered by the CRT's own `snprintf` with one argument of its C type, so the
//! bytes are the CRT's byte for byte and no conversion engine lives in das. `c_vsnprintf` is
//! the splitter; `printf`, `sprintf` and `snprintf` are `[variadic]` fronts over it.

struct private Directive {
    spec : string
    conv : int
    length_mod : string
    star_width : bool
    star_precision : bool
    end : int
}

def private is_flag(b : int) : bool {
    return b == '-' || b == '+' || b == ' ' || b == '#' || b == '0'
}

def private is_length(b : int) : bool {
    return b == 'h' || b == 'l' || b == 'j' || b == 'z' || b == 't' || b == 'L'
}

// the directive starting at fmt[at] == '%': its text with `*` kept, its conversion and the
// index just past it
def private parse_directive(fmt : uint8?; at : int) : Directive {
    var d : Directive
    var idx = at + 1
    unsafe {
        while (is_flag(int(deref(fmt + idx)))) {
            idx++
        }
        if (int(deref(fmt + idx)) == '*') {
            d.star_width = true
            idx++
        } else {
            while (crt::isdigit(int(deref(fmt + idx))) != 0) {
                idx++
            }
        }
        if (int(deref(fmt + idx)) == '.') {
            idx++
            if (int(deref(fmt + idx)) == '*') {
                d.star_precision = true
                idx++
            } else {
                while (crt::isdigit(int(deref(fmt + idx))) != 0) {
                    idx++
                }
            }
        }
        let mod_start = idx
        while (is_length(int(deref(fmt + idx)))) {
            idx++
        }
        d.length_mod = unsafe(reinterpret<string>(fmt + mod_start)) |> slice(0, idx - mod_start)
        d.conv = int(deref(fmt + idx))
        d.end = idx + 1
        d.spec = unsafe(reinterpret<string>(fmt + at)) |> slice(0, d.end - at)
    }
    return d
}

def private is_int_class(d : Directive) : bool {
    let c = d.conv
    return c == 'd' || c == 'i' || c == 'u' || c == 'o' || c == 'x' || c == 'X' || c == 'c'
}

def private is_signed_conv(d : Directive) : bool {
    return d.conv == 'd' || d.conv == 'i' || d.conv == 'c'
}

def private is_wide_mod(mod : string) : bool {
    return mod == "ll" || mod == "j" || mod == "z" || mod == "t" || (mod == "l" && crt::LONG_BITS == 64)
}

def private is_float_class(d : Directive) : bool {
    let c = d.conv
    return c == 'f' || c == 'F' || c == 'e' || c == 'E' || c == 'g' || c == 'G' || c == 'a' || c == 'A'
}

def private pop_int(va : CVaList; var cursor : int&; what : string) : int64 {
    if (cursor >= length(va) || !(va[cursor] is i)) {
        panic("printf: {what} expects an integer argument at position {cursor}")
    }
    let v = va[cursor] as i
    cursor++
    return v
}

def private pop_double(va : CVaList; var cursor : int&; what : string) : double {
    if (cursor >= length(va) || !(va[cursor] is d)) {
        panic("printf: {what} expects a floating argument at position {cursor}")
    }
    let v = va[cursor] as d
    cursor++
    return v
}

def private pop_ptr(va : CVaList; var cursor : int&; what : string) : void? {
    if (cursor >= length(va) || !(va[cursor] is p)) {
        panic("printf: {what} expects a pointer argument at position {cursor}")
    }
    let v = va[cursor] as p
    cursor++
    return v
}

// `spec` with each `*` replaced by the value it consumed, so the CRT sees a literal directive
def private resolve_stars(d : Directive; va : CVaList; var cursor : int&) : string {
    if (!d.star_width && !d.star_precision) {
        return d.spec
    }
    var width = 0l
    var precision = 0l
    if (d.star_width) {
        width = pop_int(va, cursor, "a `*` width")
    }
    if (d.star_precision) {
        precision = pop_int(va, cursor, "a `*` precision")
    }
    return build_string() $(var w) {
        var seen_dot = false
        for (ch in d.spec) {
            if (ch == '*') {
                w |> write(seen_dot ? "{precision}" : "{width}")
            } else {
                if (ch == '.') {
                    seen_dot = true
                }
                w |> write(to_char(ch))
            }
        }
    }
}

// one directive rendered into `out` through the CRT call its conversion and length name
def private render(d : Directive; va : CVaList; var cursor : int&; var out : array<uint8>) {
    let spec = resolve_stars(d, va, cursor)
    var tmp : uint8[512]
    var n = 0
    unsafe {
        let buf = addr(tmp[0])
        let cap = uint64(typeinfo dim(tmp))
        let fmt = reinterpret<uint8?>(spec)
        if (d.conv == '%') {
            n = crt::snprintf_none(buf, cap, fmt)
        } elif (is_int_class(d)) {
            let v = pop_int(va, cursor, spec)
            if (is_wide_mod(d.length_mod)) {
                n = is_signed_conv(d) ? crt::snprintf_int64(buf, cap, fmt, v) : crt::snprintf_uint64(buf, cap, fmt, uint64(v))
            } else {
                n = is_signed_conv(d) ? crt::snprintf_int(buf, cap, fmt, int(v)) : crt::snprintf_uint(buf, cap, fmt, uint(v))
            }
        } elif (is_float_class(d)) {
            n = crt::snprintf_double(buf, cap, fmt, pop_double(va, cursor, spec))
        } elif (d.conv == 's') {
            n = crt::snprintf_str(buf, cap, fmt, reinterpret<uint8?>(pop_ptr(va, cursor, spec)))
        } elif (d.conv == 'p') {
            n = crt::snprintf_ptr(buf, cap, fmt, pop_ptr(va, cursor, spec))
        } else {
            panic("printf: conversion `{spec}` is not supported")
        }
        if (n < 0) {
            panic("printf: the CRT rejected `{spec}`")
        }
        if (uint64(n) < cap) {
            out |> reserve(length(out) + n)
            for (idx in range(n)) {
                out |> push(tmp[idx])
            }
        } else {
            var big = reinterpret<uint8?>(crt::malloc(uint64(n) + 1ul))
            if (is_int_class(d)) {
                cursor--
                let v = pop_int(va, cursor, spec)
                if (is_wide_mod(d.length_mod)) {
                    n = is_signed_conv(d) ? crt::snprintf_int64(big, uint64(n) + 1ul, fmt, v) : crt::snprintf_uint64(big, uint64(n) + 1ul, fmt, uint64(v))
                } else {
                    n = is_signed_conv(d) ? crt::snprintf_int(big, uint64(n) + 1ul, fmt, int(v)) : crt::snprintf_uint(big, uint64(n) + 1ul, fmt, uint(v))
                }
            } elif (is_float_class(d)) {
                cursor--
                n = crt::snprintf_double(big, uint64(n) + 1ul, fmt, pop_double(va, cursor, spec))
            } elif (d.conv == 's') {
                cursor--
                n = crt::snprintf_str(big, uint64(n) + 1ul, fmt, reinterpret<uint8?>(pop_ptr(va, cursor, spec)))
            } else {
                cursor--
                n = crt::snprintf_ptr(big, uint64(n) + 1ul, fmt, pop_ptr(va, cursor, spec))
            }
            out |> reserve(length(out) + n)
            for (idx in range(n)) {
                out |> push(deref(big + idx))
            }
            crt::free(big)
        }
    }
}

//! The rendered bytes of `fmt` over `va`, no NUL: the splitter every front shares.
def c_vformat(fmt : uint8?; va : CVaList) : array<uint8> {
    var out : array<uint8>
    if (fmt == null) {
        return <- out
    }
    var cursor = 0
    var idx = 0
    while (true) {
        let at = unsafe(fmt + idx)
        let b = deref(at)
        if (b == uint8(0)) {
            break
        }
        if (int(b) != '%') {
            out |> push(b)
            idx++
            continue
        }
        let d = parse_directive(fmt, idx)
        render(d, va, cursor, out)
        idx = d.end
    }
    return <- out
}

//! C `vsnprintf`: at most `size - 1` bytes plus a NUL into `buf` (nothing when `size` is 0),
//! the full rendered length returned.
def c_vsnprintf(var buf : uint8?; size : uint64; fmt : uint8?; va : CVaList) : int {
    let bytes <- c_vformat(fmt, va)
    let total = length(bytes)
    if (size > 0ul) {
        let room = int(min(uint64(total), size - 1ul))
        unsafe {
            for (idx in range(room)) {
                deref(buf + idx) = bytes[idx]
            }
            deref(buf + room) = uint8(0)
        }
    }
    return total
}

//! C `vprintf`: the bytes go to the CRT's stdout, so they interleave with every bound CRT
//! write in order and `exit_now` flushes them.
def c_vprintf(fmt : uint8?; va : CVaList) : int {
    let bytes <- c_vformat(fmt, va)
    if (!empty(bytes)) {
        unsafe {
            crt::fwrite_stdout(addr(bytes[0]), uint64(long_length(bytes)))
        }
    }
    return length(bytes)
}

[variadic]
def printf(fmt : uint8?; va : va_args) : int {
    return c_vprintf(fmt, va)
}

[variadic]
def sprintf(var buf : uint8?; fmt : uint8?; va : va_args) : int {
    return c_vsnprintf(buf, 0xFFFFFFFFul, fmt, va)
}

[variadic]
def snprintf(var buf : uint8?; size : uint64; fmt : uint8?; va : va_args) : int {
    return c_vsnprintf(buf, size, fmt, va)
}
