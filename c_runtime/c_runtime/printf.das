options gen2

module printf public

require strings
require math
require daslib/strings_boost
require crt
require c_runtime/variadic public

//! The printf family over a `CVaList`: the C format is split at its directives and every
//! directive is rendered by the CRT's own `snprintf` with one argument of its C type, so the
//! bytes are the CRT's byte for byte and no conversion engine lives in das. `c_vformat` is the
//! splitter, `c_vsnprintf`, `c_vsprintf` and `c_vprintf` its `CVaList` fronts (a forwarded
//! `va_list` arrives as `va_rest` of its cursor), `c_vfprintf` the front onto a CRT stream, and
//! `printf`, `fprintf`, `sprintf` and `snprintf` are `[variadic]` over them.

//! The width in bits of the dialect's `long`, which a `l` length modifier names: 64 under
//! `linux`, 32 under `msvc`. A converted module sets it before `main` (`c2das_dialect`); the
//! default is the host CRT's own.
var c_long_bits = crt::LONG_BITS

//! The C `EOF`, which the scanf family returns when the input ends before the first conversion.
let C_EOF = -1

//! One `%` directive of a C format, shared by the printf and the scanf families: its text with
//! `*` kept, its conversion, its length modifier, whether a `*` leads it (a width for printf, a
//! suppressed assignment for scanf), whether one stands for the precision, and the index just
//! past it. A scanf set (`%[^,]`) runs to its closing `]`.
struct CFormatDirective {
    spec : string
    conv : int
    length_mod : string
    leading_star : bool
    star_precision : bool
    end : int
}

def private is_flag(b : int) : bool => b == '-' || b == '+' || b == ' ' || b == '#' || b == '0'

def private is_length(b : int) : bool => b == 'h' || b == 'l' || b == 'j' || b == 'z' || b == 't' || b == 'L'

//! The directive starting at fmt[at] == '%'; under `scanf` a `*` is followed by the width, where
//! a printf `*` takes the width's place.
def c_parse_directive(fmt : uint8?; at : int; scanf : bool = false) : CFormatDirective {
    var d : CFormatDirective
    var idx = at + 1
    unsafe {
        while (is_flag(int(deref(fmt + idx)))) {
            idx++
        }
        if (int(deref(fmt + idx)) == '*') {
            d.leading_star = true
            idx++
        }
        if (scanf || !d.leading_star) {
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
        if (d.conv == '[') {
            // the set runs to the first `]` past a leading `^` and a leading `]`
            idx++
            if (int(deref(fmt + idx)) == '^') {
                idx++
            }
            if (int(deref(fmt + idx)) == ']') {
                idx++
            }
            while (int(deref(fmt + idx)) != 0 && int(deref(fmt + idx)) != ']') {
                idx++
            }
        }
        if (int(deref(fmt + idx)) == 0) {
            // a format ending inside the directive: the directive stops at the NUL
            idx--
        }
        d.end = idx + 1
        d.spec = unsafe(reinterpret<string>(fmt + at)) |> slice(0, d.end - at)
    }
    return d
}

//! Whether a directive converts an integer (`%n` included, which stores one).
def c_is_int_conversion(d : CFormatDirective) : bool {
    let c = d.conv
    return c == 'd' || c == 'i' || c == 'u' || c == 'o' || c == 'x' || c == 'X' || c == 'n'
}

def private is_signed_conv(d : CFormatDirective) : bool => d.conv == 'd' || d.conv == 'i' || d.conv == 'c'

//! Whether a length modifier names a 64-bit integer: `l` where the dialect's `long` is one,
//! and `L`, which glibc takes as `ll` on an integer conversion.
def c_is_wide_length(mod : string) : bool =>
    mod == "ll" || mod == "L" || mod == "j" || mod == "z" || mod == "t" || (mod == "l" && c_long_bits == 64)

//! Whether a directive converts a floating value.
def c_is_float_conversion(d : CFormatDirective) : bool {
    let c = d.conv
    return c == 'f' || c == 'F' || c == 'e' || c == 'E' || c == 'g' || c == 'G' || c == 'a' || c == 'A'
}

//! A directive's text `spec` as the host CRT must read it, so its `long` never matters: an
//! integer `l` is the dialect's width (none for 32 bits, `ll` for 64), an integer `L` is `ll`,
//! a floating `L` is `l` (the dialect's `long double` is a `double`). A wide `%lc`, `%ls` or
//! `%l[` panics where the dialect's `wchar_t` is not the host's, which is where its `long` is
//! not (msvc's 2-byte `wchar_t`, linux's 4).
def c_dialect_spec(d : CFormatDirective; spec : string) : string {
    let m = d.length_mod
    if (m != "l" && m != "L") {
        return spec
    }
    let conv_at = d.conv == '[' ? find(spec, "[") : length(spec) - 1
    let head = slice(spec, 0, conv_at - length(m))
    let tail = slice(spec, conv_at)
    if (d.conv == 'c' || d.conv == 's' || d.conv == '[') {
        if (m == "l" && c_long_bits != crt::LONG_BITS) {
            panic("`{spec}`: a wide character directive under a dialect whose wchar_t is not the host's is not supported")
        }
        return spec
    }
    if (c_is_float_conversion(d)) {
        return m == "L" ? "{head}l{tail}" : spec
    }
    if (c_is_int_conversion(d)) {
        return c_is_wide_length(m) ? "{head}ll{tail}" : "{head}{tail}"
    }
    return spec
}

// `spec` with each `*` replaced by the value it consumed, so the CRT sees a literal directive
def private resolve_stars(d : CFormatDirective; var v : CVaCursor) : string {
    if (!d.leading_star && !d.star_precision) {
        return d.spec
    }
    var width = 0l
    var precision = 0l
    if (d.leading_star) {
        width = va_i(v)
    }
    if (d.star_precision) {
        precision = va_i(v)
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

// one directive's argument popped and rendered into `buf` by the CRT call its conversion and
// length name; the rendered length, as `snprintf` reports it
def private render_into(d : CFormatDirective; var v : CVaCursor; buf : uint8?; cap : uint64; fmt : uint8?) : int {
    unsafe {
        if (d.conv == '%') {
            return crt::snprintf_none(buf, cap, fmt)
        } elif (c_is_int_conversion(d) || d.conv == 'c') {
            let n = va_i(v)
            if (c_is_wide_length(d.length_mod)) {
                return is_signed_conv(d) ? crt::snprintf_int64(buf, cap, fmt, n) : crt::snprintf_uint64(buf, cap, fmt, uint64(n))
            }
            return is_signed_conv(d) ? crt::snprintf_int(buf, cap, fmt, int(n)) : crt::snprintf_uint(buf, cap, fmt, uint(n))
        } elif (c_is_float_conversion(d)) {
            return crt::snprintf_double(buf, cap, fmt, va_d(v))
        } elif (d.conv == 's') {
            return crt::snprintf_str(buf, cap, fmt, reinterpret<uint8?>(va_p(v)))
        } elif (d.conv == 'p') {
            return crt::snprintf_ptr(buf, cap, fmt, va_p(v))
        }
    }
    panic("printf: conversion `{d.spec}` is not supported")
    return -1
}

// one directive rendered into `out`, retried into a CRT buffer from the same argument when the
// 512-byte scratch is short
def private render(d : CFormatDirective; var v : CVaCursor; var out : array<uint8>) {
    if (d.conv == 'n') {
        panic("printf: `%n` is not supported")
    }
    let spec = c_dialect_spec(d, resolve_stars(d, v))
    let fmt = unsafe(reinterpret<uint8?>(spec))
    let at = v.at
    var tmp : uint8[512]
    let cap = uint64(typeinfo dim(tmp))
    var n = render_into(d, v, unsafe(addr(tmp[0])), cap, fmt)
    if (n < 0) {
        panic("printf: the CRT rejected `{spec}`")
    }
    out |> reserve(length(out) + n)
    if (uint64(n) < cap) {
        for (idx in range(n)) {
            out |> push(tmp[idx])
        }
        return
    }
    unsafe {
        var big = reinterpret<uint8?>(crt::malloc(uint64(n) + 1ul))
        v.at = at
        n = render_into(d, v, big, uint64(n) + 1ul, fmt)
        for (idx in range(n)) {
            out |> push(deref(big + idx))
        }
        crt::free(big)
    }
}

//! The rendered bytes of `fmt` over `va`, no NUL: the splitter every front shares.
def c_vformat(fmt : uint8?; va : CVaList) : array<uint8> {
    var out : array<uint8>
    if (fmt == null) {
        return <- out
    }
    var v = va_begin(va)
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
        let d = c_parse_directive(fmt, idx)
        render(d, v, out)
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

//! C `vsprintf`: `c_vsnprintf` with no bound, the caller's buffer taken to be large enough.
def c_vsprintf(var buf : uint8?; fmt : uint8?; va : CVaList) : int => c_vsnprintf(buf, 0xFFFFFFFFul, fmt, va)

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

//! C `vfprintf`: the bytes go through the CRT's `fwrite` to `f`, a `FILE *` as `void?`, so they
//! interleave with every other bound write to the stream in order.
def c_vfprintf(var f : void?; fmt : uint8?; va : CVaList) : int {
    let bytes <- c_vformat(fmt, va)
    if (!empty(bytes)) {
        unsafe {
            crt::fwrite(addr(bytes[0]), 1ul, uint64(long_length(bytes)), f)
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
    return c_vsprintf(buf, fmt, va)
}

[variadic]
def snprintf(var buf : uint8?; size : uint64; fmt : uint8?; va : va_args) : int {
    return c_vsnprintf(buf, size, fmt, va)
}

[variadic]
def fprintf(var f : void?; fmt : uint8?; va : va_args) : int {
    return c_vfprintf(f, fmt, va)
}
