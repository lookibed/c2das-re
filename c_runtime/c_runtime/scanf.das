options gen2

module scanf public

require crt
require strings
require c_runtime/variadic public
require c_runtime/printf public

//! The scanf family over a `CVaList`, the printf family's split run backwards: the C format is
//! read directive by directive (`c_parse_directive`, shared with printf), and every conversion
//! is the CRT's own `sscanf` over that one directive and a trailing `%n`, writing through the
//! C program's out-pointer at the width the directive names and reporting the bytes it took,
//! so the input moves on by exactly what the CRT consumed. Whitespace and ordinary characters
//! of the format match in das, as C defines them. `c_vsscanf` is the splitter, `sscanf` the
//! `[variadic]` front; `c_vfscanf` and `fscanf` the same over a stream, each piece the CRT's
//! `fscanf`.

// `%n`: the bytes consumed so far, stored at the width its length modifier names
def private store_percent_n(d : CFormatDirective; var out : void?; consumed : int) {
    unsafe {
        let m = d.length_mod
        if (m == "hh") {
            deref(reinterpret<int8?>(out)) = int8(consumed)
        } elif (m == "h") {
            deref(reinterpret<int16?>(out)) = int16(consumed)
        } elif (c_is_wide_length(m)) {
            deref(reinterpret<int64?>(out)) = int64(consumed)
        } else {
            deref(reinterpret<int?>(out)) = consumed
        }
    }
}

def private crt_piece(d : CFormatDirective) : string => "{c_dialect_spec(d, d.spec)}%n"

// the conversions C's scanf defines; a glibc extension (`%m`, `%q`, `%1$d`) is not one
def private is_scanf_conversion(d : CFormatDirective) : bool =>
    c_is_int_conversion(d) || c_is_float_conversion(d) || d.conv == 's' || d.conv == 'c' || d.conv == '[' || d.conv == 'p' || d.conv == '%'

//! C `vsscanf`: the count of assignments made, or `C_EOF` when the input ends before the
//! first conversion; a directive that does not match stops the scan. A null format reads
//! nothing.
def c_vsscanf(src : uint8?; fmt : uint8?; va : CVaList) : int {
    if (fmt == null) {
        return 0
    }
    if (src == null) {
        panic("sscanf: the input is a null pointer")
    }
    var v = va_begin(va)
    var count = 0
    var pos = 0
    var idx = 0
    unsafe {
        while (true) {
            let b = int(deref(fmt + idx))
            if (b == 0) {
                break
            }
            if (crt::isspace(b) != 0) {
                // a whitespace directive takes any run of input whitespace, none included
                while (crt::isspace(int(deref(fmt + idx))) != 0) {
                    idx++
                }
                while (crt::isspace(int(deref(src + pos))) != 0) {
                    pos++
                }
                continue
            }
            if (b != '%') {
                let c = int(deref(src + pos))
                if (c == 0) {
                    return count == 0 ? C_EOF : count
                }
                if (c != b) {
                    return count
                }
                pos++
                idx++
                continue
            }
            let d = c_parse_directive(fmt, idx, true)
            idx = d.end
            if (!is_scanf_conversion(d)) {
                panic("sscanf: directive `{d.spec}` is not supported")
            }
            if (d.conv == 'n') {
                if (!d.leading_star) {
                    store_percent_n(d, va_p(v), pos)
                }
                continue
            }
            let assigns = !d.leading_star && d.conv != '%'
            let piece = crt_piece(d)
            var consumed = -1
            let r = assigns ? crt::sscanf_one(src + pos, reinterpret<uint8?>(piece), va_p(v), addr(consumed)) : crt::sscanf_none(src + pos, reinterpret<uint8?>(piece), addr(consumed))
            if (r < 0) {
                return count == 0 ? C_EOF : count
            }
            if (consumed < 0) {
                return count
            }
            pos += consumed
            if (assigns) {
                count++
            }
        }
    }
    return count
}

[variadic]
def sscanf(src : uint8?; fmt : uint8?; va : va_args) : int {
    return c_vsscanf(src, fmt, va)
}

// one piece of a format over stream `f`: the CRT's `fscanf` of `piece` (ending in `%n`), through
// `out` when it assigns; the CRT's result, `consumed` the bytes it took or -1 when it stopped short
def private fscanf_piece(var f : void?; piece : string; assigns : bool; var out : void?; var consumed : int&) : int {
    consumed = -1
    unsafe {
        return assigns ? crt::fscanf_one(f, reinterpret<uint8?>(piece), out, addr(consumed)) : crt::fscanf_none(f, reinterpret<uint8?>(piece), addr(consumed))
    }
}

// the result of a piece that matched nothing, below every byte count and apart from `C_EOF`
let private FSCANF_MISMATCH = -2

// a piece of the format that assigns nothing over `f` (a whitespace run `" %n"`, an ordinary
// character `"x%n"`): the bytes it consumed, `FSCANF_MISMATCH` when the character did not match,
// `C_EOF` when the input ended first
def private fscanf_literal(var f : void?; piece : string) : int {
    var consumed = -1
    var none : void?
    if (fscanf_piece(f, piece, false, none, consumed) < 0) {
        return C_EOF
    }
    return consumed < 0 ? FSCANF_MISMATCH : consumed
}

//! C `vfscanf` over a `FILE *` as `void?`: `c_vsscanf`'s split, each piece the CRT's `fscanf`
//! over the stream: a whitespace run, an ordinary character, or one directive, each with a
//! trailing `%n`, so the stream moves by exactly what the CRT consumed. The count of assignments,
//! or `C_EOF` when the input ends before the first conversion.
def c_vfscanf(var f : void?; fmt : uint8?; va : CVaList) : int {
    if (fmt == null) {
        return 0
    }
    var v = va_begin(va)
    var count = 0
    var pos = 0
    var idx = 0
    unsafe {
        while (true) {
            let b = int(deref(fmt + idx))
            if (b == 0) {
                break
            }
            if (b != '%') {
                let ws = crt::isspace(b) != 0
                while (ws && crt::isspace(int(deref(fmt + idx))) != 0) {
                    idx++
                }
                let took = fscanf_literal(f, ws ? " %n" : "{to_char(b)}%n")
                if (took == C_EOF) {
                    return count == 0 ? C_EOF : count
                }
                if (took == FSCANF_MISMATCH) {
                    return count
                }
                pos += took
                idx += ws ? 0 : 1
                continue
            }
            let d = c_parse_directive(fmt, idx, true)
            idx = d.end
            if (!is_scanf_conversion(d)) {
                panic("fscanf: directive `{d.spec}` is not supported")
            }
            if (d.conv == 'n') {
                if (!d.leading_star) {
                    store_percent_n(d, va_p(v), pos)
                }
                continue
            }
            let assigns = !d.leading_star && d.conv != '%'
            var none : void?
            var out = assigns ? va_p(v) : none
            var consumed = -1
            let r = fscanf_piece(f, crt_piece(d), assigns, out, consumed)
            if (r < 0) {
                return count == 0 ? C_EOF : count
            }
            if (consumed < 0) {
                return count
            }
            pos += consumed
            count += assigns ? 1 : 0
        }
    }
    return count
}

[variadic]
def fscanf(var f : void?; fmt : uint8?; va : va_args) : int {
    return c_vfscanf(f, fmt, va)
}
