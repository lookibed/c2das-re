options gen2
options indenting = 4

module pp_eval public

require strings
require daslib/strings_boost
require daslib/fio
require pp_lexer
require c_defines

//! A token of an `#if` line as the evaluator reads it: its kind, its symbol (an identifier's) and its
//! spelling, `len` bytes from `at` of the line's text.
struct PpEvalToken {
    kind : int
    sym : int
    at : int
    len : int
}

//! The facts of the target a character constant's value depends on, read off the dialect's
//! predefined macros (`__CHAR_UNSIGNED__`, `__WCHAR_UNSIGNED__`, `__WCHAR_WIDTH__`, `__INT_WIDTH__`).
struct PpEvalTarget {
    char_unsigned : bool
    wchar_unsigned : bool
    wchar_width : int
    int_width : int
}

//! What the evaluator asks the directive layer: whether a name is defined (a macro or a builtin
//! name), whether a query's name is still the builtin (an `#undef` removes it), and whether
//! `__has_include`, `__has_include_next` or `__has_embed` find their file.
enum PpEvalAsk {
    defined
    builtin
    has_include
    has_include_next
    has_embed
}

//! A diagnostic of the evaluator at token `token` of the line, -1 for the directive itself.
struct PpEvalDiag {
    error : bool
    token : int
    what : string
}

//! The answers of the feature queries of one dialect (`__has_builtin`, `__has_attribute`, ...), as
//! the pinned clang gives them: `"<query> <operand>"` to the value; a query not listed answers 0.
struct PpFeatures {
    answers : table<string; int64>
}

//! The evaluator's state: the line it reads, the diagnostics of its last run, the target and the
//! dialect's feature table. The directive layer fills `toks` and `text` before each run.
struct PpEval {
    toks : array<PpEvalToken>
    text : array<uint8>
    diags : array<PpEvalDiag>
    target : PpEvalTarget
    features : PpFeatures
    pos : int
}

//! The answer of one `#if` or `#elif`: its value, and `failed` when an error makes clang skip the
//! group whatever the value.
struct PpEvalResult {
    value : bool
    failed : bool
}

// an intmax_t or uintmax_t value: the 64 bits and the signedness
struct private PpValue {
    bits : uint64
    unsigned : bool
}

let private SIGN_BIT = 0x8000000000000000ul

let private FEATURE_EXT = "_features.defs"

//! The file of the feature-query table of `dialect`, beside its predefined-macro table.
def features_path(dialect : string) : string => path_join(dir_name(predefined_path(dialect)), dialect + FEATURE_EXT)

//! The table text `text` read: a line `<query> <operand> <value>`, an empty line and a line starting
//! with `#` skipped. `error` names `path` and the first line that is no entry, or that repeats one.
[arch(at="ARCHITECTURE_EVAL.md#pp-eval-features")]
def parse_features(text, path : string; var error : string&) : PpFeatures {
    var features : PpFeatures
    for (line, line_no in split(text, "\n"), count(1)) {
        if (empty(line) || line |> starts_with("#")) {
            continue
        }
        var inscope parts <- split(line, " ")
        var value = 0l
        let ok = length(parts) == 3 && !empty(parts[0]) && !empty(parts[1]) && is_integer(parts[2])
        if (ok) {
            value = to_int64(parts[2])
        }
        let key = "{parts[0]} {length(parts) > 1 ? parts[1] : ""}"
        if (!ok || key_exists(features.answers, key)) {
            error = "{path}:{line_no}: `{line}` is no entry `<query> <operand> <value>`, or repeats one"
            return <- features
        }
        features.answers |> insert(key, value)
    }
    return <- features
}

def private is_integer(s : string) : bool {
    for (c, i in s, count()) {
        return false if (!(is_number(c) || (i == 0 && c == '-' && length(s) > 1)))
    }
    return !empty(s)
}

//! The feature table file `path` (`parse_features`); `error` names a missing file.
def read_features(path : string; var error : string&) : PpFeatures {
    if (!fexist(path)) {
        error = "{path}: no such feature-query table"
        return <- PpFeatures()
    }
    return <- parse_features(fread(path), path, error)
}

//! The target facts the predefined entries state (`parse_define`'s); an entry missing leaves the
//! default, the x86-64 Linux one with a signed `char`.
def pp_eval_target(predefines : array<string>) : PpEvalTarget {
    var target = PpEvalTarget(wchar_width = 32, int_width = 32)
    var parsed : Define
    for (entry in predefines) {
        if (!parse_define(entry, parsed)) {
            continue
        }
        if (parsed.name == "__CHAR_UNSIGNED__") {
            target.char_unsigned = true
        } elif (parsed.name == "__WCHAR_UNSIGNED__") {
            target.wchar_unsigned = true
        } elif (parsed.name == "__WCHAR_WIDTH__") {
            target.wchar_width = to_int(parsed.value)
        } elif (parsed.name == "__INT_WIDTH__") {
            target.int_width = to_int(parsed.value)
        }
    }
    return target
}

// Reading the line

def private at_end(ev : PpEval) : bool => ev.pos >= length(ev.toks)

def private peek_kind(ev : PpEval) : int => ev.pos < length(ev.toks) ? ev.toks[ev.pos].kind : int(PpTok.EOF)

def private spelling(ev : PpEval; i : int) : string => slice_bytes(ev, ev.toks[i].at, ev.toks[i].len)

def private slice_bytes(ev : PpEval; at, len : int) : string {
    return build_string() $(var out) {
        for (j in range(at, at + len)) {
            out |> write_char(int(ev.text[j]))
        }
    }
}

def private spelled_is(ev : PpEval; i : int; s : string) : bool {
    let t & = unsafe(ev.toks[i])
    return false if (t.len != length(s))
    var same = true
    peek_data(s) $(chars) {
        for (j in range(t.len)) {
            same = same && ev.text[t.at + j] == chars[j]
        }
    }
    return same
}

def private byte_at(ev : PpEval; i, j : int) : int => j < ev.toks[i].len ? int(ev.text[ev.toks[i].at + j]) : 0

def private fail(var ev : PpEval; token : int; what : string) : bool {
    ev.diags |> push(PpEvalDiag(error = true, token = token, what = what))
    return false
}

def private warn(var ev : PpEval; token : int; what : string) {
    ev.diags |> push(PpEvalDiag(error = false, token = token, what = what))
}

def private here(ev : PpEval) : int => ev.pos < length(ev.toks) ? ev.pos : -1

def private signed_value(v : int64) : PpValue => PpValue(bits = uint64(v), unsigned = false)

def private is_negative(v : PpValue) : bool => !v.unsigned && (v.bits & SIGN_BIT) != 0ul

def private as_signed(v : PpValue) : int64 => int64(v.bits)

// `u` in decimal digits: a uint64 interpolates as hex
def private decimal(u : uint64) : string {
    var digits : array<int>
    var rest = u
    while (true) {
        digits |> push(int(rest % 10ul) + '0')
        rest /= 10ul
        break if (rest == 0ul)
    }
    return build_string() $(var out) {
        for (i in range(length(digits))) {
            out |> write_char(digits[length(digits) - 1 - i])
        }
    }
}

def private value_text(v : PpValue) : string => v.unsigned ? decimal(v.bits) : "{int64(v.bits)}"

// Integer constants

def private digit_value(c : int) : int {
    return c - '0' if (is_number(c))
    return c - 'a' + 10 if (c >= 'a' && c <= 'f')
    return c - 'A' + 10 if (c >= 'A' && c <= 'F')
    return 99
}

// the integer suffix from byte `from` of token `i`: whether it is valid, and whether it makes the
// constant unsigned; `u`, `l` and `ll` in either case and order, `lL` and `Ll` not
def private read_suffix(ev : PpEval; i, from : int) : tuple<ok : bool; unsigned : bool> {
    let n = ev.toks[i].len
    var j = from
    var saw_u = false
    var saw_l = false
    while (j < n) {
        let c = byte_at(ev, i, j)
        if ((c == 'u' || c == 'U') && !saw_u) {
            saw_u = true
            j++
        } elif ((c == 'l' || c == 'L') && !saw_l) {
            saw_l = true
            j += byte_at(ev, i, j + 1) == c ? 2 : 1
        } else {
            return (ok = false, unsigned = false)
        }
    }
    return (ok = true, unsigned = saw_u)
}

// a pp-number as clang's NumericLiteralParser reads an integer constant (C11 6.4.4.1): decimal,
// octal, hex and the binary `0b` clang takes under gnu17; a floating constant is an error
[arch(at="ARCHITECTURE_EVAL.md#pp-eval-literals")]
def private number_value(var ev : PpEval; i : int; var v : PpValue) : bool {
    let n = ev.toks[i].len
    var radix = 10
    var j = 0
    let c0 = byte_at(ev, i, 0)
    let c1 = byte_at(ev, i, 1)
    if (c0 == '0' && (c1 == 'x' || c1 == 'X') && (digit_value(byte_at(ev, i, 2)) < 16 || byte_at(ev, i, 2) == '.')) {
        radix = 16
        j = 2
    } elif (c0 == '0' && (c1 == 'b' || c1 == 'B') && digit_value(byte_at(ev, i, 2)) < 10) {
        radix = 2
        j = 2
    } elif (c0 == '0') {
        radix = 8
    }
    let digits_from = j
    while (j < n && digit_value(byte_at(ev, i, j)) < (radix == 16 ? 16 : 10)) {
        j++
    }
    let c = byte_at(ev, i, j)
    let exp = radix == 16 ? (c == 'p' || c == 'P') : (c == 'e' || c == 'E')
    if (j < n && (c == '.' || exp)) {
        return fail(ev, i, "floating point literal in preprocessor expression")
    }
    let digits_end = j
    var value = 0ul
    var too_large = false
    for (k in range(digits_from, digits_end)) {
        let d = digit_value(byte_at(ev, i, k))
        if (d >= radix) {
            let kind = radix == 2 ? "binary" : "octal"
            return fail(ev, i, "invalid digit '{to_char(byte_at(ev, i, k))}' in {kind} constant")
        }
        let next = value * uint64(radix) + uint64(d)
        too_large ||= (next - uint64(d)) / uint64(radix) != value
        value = next
    }
    let suffix = read_suffix(ev, i, digits_end)
    if (!suffix.ok) {
        let last = byte_at(ev, i, n - 1)
        if (last == 'i' || last == 'j') {
            return fail(ev, i, "floating point literal in preprocessor expression")
        }
        return fail(ev, i, "invalid suffix '{slice_bytes(ev, ev.toks[i].at + digits_end, n - digits_end)}' on integer constant")
    }
    if (too_large) {
        ev.diags |> push(PpEvalDiag(error = true, token = i, what = "integer literal is too large to be represented in any integer type"))
    }
    v = PpValue(bits = value, unsigned = suffix.unsigned || too_large)
    if (!v.unsigned && (value & SIGN_BIT) != 0ul) {
        if (radix == 10) {
            warn(ev, i, "integer literal is too large to be represented in a signed integer type, interpreting as unsigned")
        }
        v.unsigned = true
    }
    return true
}

// Character constants

// one code point of the literal's bytes from `j`, UTF-8 decoded: the value and the next byte
def private utf8_at(ev : PpEval; i, j : int) : int2 {
    let b = byte_at(ev, i, j)
    return int2(b, j + 1) if (b < 0x80)
    let count = b >= 0xF0 ? 3 : b >= 0xE0 ? 2 : 1
    var cp = b & (0x3F >> count)
    for (k in range(1, count + 1)) {
        cp = (cp << 6) | (byte_at(ev, i, j + k) & 0x3F)
    }
    return int2(cp, j + count + 1)
}

// a delimited escape `\x{...}`, `\o{...}` or `\u{...}` from its first digit at byte `from`, clang's
// extension under C17: the digits to the `}` in base 16, or 8 for `\o`; a `\u` past the type fails
def private delimited_escape(var ev : PpEval; i, from, e : int; ordinary : bool; mask : uint64) : tuple<ok : bool; value : uint64; next : int> {
    let n = ev.toks[i].len
    let radix = e == 'o' ? 8 : 16
    var j = from
    var c = 0ul
    var over = false
    while (j < n - 1 && digit_value(byte_at(ev, i, j)) < radix) {
        over ||= (c >> 60ul) != 0ul
        c = c * uint64(radix) + uint64(digit_value(byte_at(ev, i, j)))
        j++
    }
    if (j == from || byte_at(ev, i, j) != '}') {
        return (ok = fail(ev, i, "delimited escape sequence is malformed"), value = 0ul, next = j)
    }
    j++
    if (e == 'u' && ((ordinary && c >= 0x80ul) || c > mask || over)) {
        return (ok = fail(ev, i, "character too large for enclosing character literal type"), value = 0ul, next = j)
    }
    if (e != 'u' && (over || (c & ~mask) != 0ul)) {
        ev.diags |> push(PpEvalDiag(error = true, token = i, what = "{e == 'o' ? "octal" : "hex"} escape sequence out of range"))
    }
    return (ok = true, value = c, next = j)
}

// the escape sequence at byte `j` of the character constant `i` (C11 6.4.4.4): its value and the
// byte after it; an octal or hex escape past the type is clang's error and keeps its low bits, a
// UCN past it fails the constant
def private read_escape(var ev : PpEval; i, at : int; ordinary : bool; mask : uint64) : tuple<ok : bool; value : uint64; next : int> {
    let n = ev.toks[i].len
    let e = byte_at(ev, i, at + 1)
    var j = at + 2
    var c = 0ul
    if ((e == 'x' || e == 'o' || e == 'u') && byte_at(ev, i, j) == '{') {
        return delimited_escape(ev, i, j + 1, e, ordinary, mask)
    } elif (e == 'N' && byte_at(ev, i, j) == '{') {
        return (ok = fail(ev, i, "named universal character escapes are not read"), value = 0ul, next = j)
    } elif (e >= '0' && e <= '7') {
        c = uint64(e - '0')
        var k = 1
        while (k < 3 && byte_at(ev, i, j) >= '0' && byte_at(ev, i, j) <= '7' && j < n - 1) {
            c = c * 8ul + uint64(byte_at(ev, i, j) - '0')
            j++
            k++
        }
        if ((c & ~mask) != 0ul) {
            ev.diags |> push(PpEvalDiag(error = true, token = i, what = "octal escape sequence out of range"))
        }
    } elif (e == 'x') {
        var any = false
        var over = false
        while (j < n - 1 && digit_value(byte_at(ev, i, j)) < 16) {
            over ||= (c >> 60ul) != 0ul
            c = (c << 4ul) | uint64(digit_value(byte_at(ev, i, j)))
            j++
            any = true
        }
        if (!any) {
            return (ok = fail(ev, i, "\\x used with no following hex digits"), value = 0ul, next = j)
        }
        if (over || (c & ~mask) != 0ul) {
            ev.diags |> push(PpEvalDiag(error = true, token = i, what = "hex escape sequence out of range"))
        }
    } elif (e == 'u' || e == 'U') {
        for (_k in range(e == 'u' ? 4 : 8)) {
            let d = digit_value(byte_at(ev, i, j))
            if (j >= n - 1 || d >= 16) {
                return (ok = fail(ev, i, "incomplete universal character name"), value = 0ul, next = j)
            }
            c = (c << 4ul) | uint64(d)
            j++
        }
        if ((ordinary && c >= 0x80ul) || c > mask) {
            return (ok = fail(ev, i, "character too large for enclosing character literal type"), value = 0ul, next = j)
        }
    } else {
        let simple = escape_value(e)
        if (simple < 0) {
            warn(ev, i, "unknown escape sequence '\\{to_char(e)}'")
        }
        c = uint64(simple < 0 ? e : simple)
    }
    return (ok = true, value = c, next = j)
}

// a character constant as clang's CharLiteralParser reads it (C11 6.4.4.4), then its type's
// width and signedness and the conversion to intmax_t as clang's evaluator gives them
[arch(at="ARCHITECTURE_EVAL.md#pp-eval-literals")]
def private char_value(var ev : PpEval; i : int; var v : PpValue) : bool {
    let n = ev.toks[i].len
    let p = byte_at(ev, i, 0)
    let wide = p == 'L'
    let utf16 = p == 'u'
    let utf32 = p == 'U'
    let ordinary = !wide && !utf16 && !utf32
    let width = ordinary ? 8 : wide ? ev.target.wchar_width : utf16 ? 16 : 32
    let mask = width >= 64 ? 0xFFFFFFFFFFFFFFFFul : (1ul << uint64(width)) - 1ul
    var j = ordinary ? 1 : 2
    var count = 0
    var acc = 0ul
    var too_long = false
    var first = 0ul
    while (j < n - 1) {
        var c = 0ul
        var escaped = false
        let b = byte_at(ev, i, j)
        if (b != '\\') {
            let cp = utf8_at(ev, i, j)
            j = cp.y
            if (ordinary && cp.x >= 0x80) {
                return fail(ev, i, "character too large for enclosing character literal type")
            }
            c = uint64(cp.x)
        } else {
            escaped = true
            let esc = read_escape(ev, i, j, ordinary, mask)
            return false if (!esc.ok)
            c = esc.value
            j = esc.next
        }
        if (!ordinary && !escaped && c > mask) {
            return fail(ev, i, "character too large for enclosing character literal type")
        }
        if (count == 0) {
            first = c & mask
        }
        too_long ||= (acc >> 24ul) != 0ul
        acc = ((acc << 8ul) | (c & 0xFFul)) & 0xFFFFFFFFul
        count++
    }
    if (count > 1 && !ordinary) {
        return fail(ev, i, "wide character literals may not contain multiple characters")
    }
    var bits = 0ul
    var unsigned = false
    var vwidth = width
    if (count > 1) {
        warn(ev, i, too_long ? "character constant too long for its type" : "multi-character character constant")
        bits = acc
        vwidth = ev.target.int_width
        unsigned = ev.target.char_unsigned
    } else {
        bits = first
        unsigned = ordinary ? ev.target.char_unsigned : wide ? ev.target.wchar_unsigned : true
    }
    let vmask = vwidth >= 64 ? 0xFFFFFFFFFFFFFFFFul : (1ul << uint64(vwidth)) - 1ul
    bits &= vmask
    if (!unsigned && vwidth < 64 && (bits & (1ul << uint64(vwidth - 1))) != 0ul) {
        bits |= ~vmask
    }
    v = PpValue(bits = bits, unsigned = unsigned)
    return true
}

// the value of a simple escape `\e`, -1 for an unknown one
def private escape_value(e : int) : int {
    if (e == 'n') {
        return 10
    } elif (e == 't') {
        return 9
    } elif (e == 'r') {
        return 13
    } elif (e == 'a') {
        return 7
    } elif (e == 'b') {
        return 8
    } elif (e == 'f') {
        return 12
    } elif (e == 'v') {
        return 11
    } elif (e == 'e' || e == 'E') {
        return 27
    } elif (e == '\\' || e == '\'' || e == '"' || e == '?') {
        return e
    }
    return -1
}

// Queries

// which builtin query a name spells; "" for none. `__has_cpp_attribute` is C++'s alone: clang
// under C has no such builtin, so it reads as a name
let private QUERIES <- ["__has_feature", "__has_extension", "__has_builtin", "__has_constexpr_builtin", "__has_attribute",
                        "__has_c_attribute", "__has_declspec_attribute", "__has_warning", "__has_include", "__has_include_next",
                        "__has_embed", "__is_identifier", "__is_target_arch", "__is_target_vendor", "__is_target_os",
                        "__is_target_environment", "__is_target_variant_os", "__is_target_variant_environment", "__building_module"]

def private query_of(ev : PpEval; i : int) : string {
    return "" if (ev.toks[i].len < 10 || byte_at(ev, i, 0) != '_' || byte_at(ev, i, 1) != '_')
    for (q in QUERIES) {
        return q if (spelled_is(ev, i, q))
    }
    return ""
}

// `__foo__` read as `foo`, as clang normalizes a feature or attribute name
def private normalized(name : string) : string {
    if (length(name) >= 5 && starts_with(name, "__") && ends_with(name, "__")) {
        return slice(name, 2, length(name) - 2)
    }
    return name
}

// `__has_include ( "name" )` or `( < ... > )`, and `__has_embed`'s same operand: the
// directive layer searches the file
[arch(at="ARCHITECTURE_EVAL.md#pp-eval-queries")]
def private include_query(var ev : PpEval; q : string; name_at : int; var v : PpValue;
                          ask : block<(what : PpEvalAsk; sym, first, last : int) : int>) : bool {
    if (peek_kind(ev) != int(PpTok.LPAREN)) {
        return fail(ev, name_at, "missing '(' after '{q}'")
    }
    ev.pos++
    let first = ev.pos
    var last = -1
    if (peek_kind(ev) == int(PpTok.STRING_LITERAL) && byte_at(ev, ev.pos, 0) == '"') {
        last = ev.pos
        ev.pos++
    } elif (peek_kind(ev) == int(PpTok.LESS)) {
        var k = ev.pos + 1
        while (k < length(ev.toks) && ev.toks[k].kind != int(PpTok.GREATER)) {
            k++
        }
        if (k == length(ev.toks)) {
            return fail(ev, first, "expected '>'")
        }
        last = k
        ev.pos = k + 1
    } else {
        return fail(ev, here(ev), "expected \"FILENAME\" or <FILENAME>")
    }
    if (peek_kind(ev) != int(PpTok.RPAREN)) {
        if (q == "__has_embed" && !at_end(ev)) {
            return fail(ev, here(ev), "__has_embed parameters are not read")
        }
        return fail(ev, here(ev), "missing ')' after '{q}'")
    }
    ev.pos++
    let what = q == "__has_include" ? PpEvalAsk.has_include : q == "__has_include_next" ? PpEvalAsk.has_include_next : PpEvalAsk.has_embed
    v = signed_value(int64(invoke(ask, what, -1, first, last)))
    return true
}

// a feature-like query `q ( name )`, `__has_c_attribute` also `( scope :: name )`, and
// `__has_warning ( "-Wname" )`: the answer of the dialect's table
[arch(at="ARCHITECTURE_EVAL.md#pp-eval-queries")]
def private feature_query(var ev : PpEval; q : string; name_at : int; var v : PpValue) : bool {
    if (peek_kind(ev) != int(PpTok.LPAREN)) {
        return fail(ev, name_at, "missing '(' after '{q}'")
    }
    ev.pos++
    if (at_end(ev)) {
        return fail(ev, name_at, "unterminated function-like macro invocation")
    }
    var name = ""
    if (q == "__has_warning") {
        if (peek_kind(ev) != int(PpTok.STRING_LITERAL) || byte_at(ev, ev.pos, 0) != '"') {
            return fail(ev, here(ev), "expected string literal in '__has_warning'")
        }
        name = slice_bytes(ev, ev.toks[ev.pos].at + 1, ev.toks[ev.pos].len - 2)
        ev.pos++
    } else {
        if (peek_kind(ev) != int(PpTok.IDENTIFIER)) {
            return fail(ev, here(ev), "builtin feature check macro requires a parenthesized identifier")
        }
        name = spelling(ev, ev.pos)
        ev.pos++
        if (q == "__has_c_attribute" && peek_kind(ev) == int(PpTok.COLONCOLON) && ev.pos + 1 < length(ev.toks)
                && ev.toks[ev.pos + 1].kind == int(PpTok.IDENTIFIER)) {
            name = "{normalized(name)}::{normalized(spelling(ev, ev.pos + 1))}"
            ev.pos += 2
        } elif (q == "__has_feature" || q == "__has_extension" || q == "__has_attribute" || q == "__has_c_attribute"
                || q == "__has_declspec_attribute") {
            name = normalized(name)
        }
    }
    if (peek_kind(ev) != int(PpTok.RPAREN)) {
        if (at_end(ev)) {
            return fail(ev, name_at, "unterminated function-like macro invocation")
        }
        return fail(ev, here(ev), "missing ')' after '{spelling(ev, ev.pos - 1)}'")
    }
    ev.pos++
    if (q == "__has_warning" && !starts_with(name, "-W")) {
        warn(ev, name_at, "__has_warning expected option name (e.g. \"-Wundef\")")
    }
    let fallback = q == "__is_identifier" ? 1l : 0l
    v = signed_value(q == "__building_module" ? 0l : (ev.features.answers?["{q} {name}"] ?? fallback))
    return true
}

// `defined X` or `defined ( X )`
def private defined_value(var ev : PpEval; var v : PpValue; ask : block<(what : PpEvalAsk; sym, first, last : int) : int>) : bool {
    let paren = peek_kind(ev) == int(PpTok.LPAREN)
    if (paren) {
        ev.pos++
    }
    if (at_end(ev)) {
        return fail(ev, -1, "macro name missing")
    }
    if (peek_kind(ev) != int(PpTok.IDENTIFIER)) {
        return fail(ev, ev.pos, "macro name must be an identifier")
    }
    v = signed_value(int64(invoke(ask, PpEvalAsk.defined, ev.toks[ev.pos].sym, ev.pos, ev.pos)))
    ev.pos++
    if (paren) {
        if (peek_kind(ev) != int(PpTok.RPAREN)) {
            return fail(ev, here(ev), "missing ')' after 'defined'")
        }
        ev.pos++
    }
    return true
}

// The expression

// clang's precedence of a binary operator token, 0 for a token that ends an operand list (the
// line's end, `)`, `:`), -1 for a token that is no binary operator
def private precedence(kind : int) : int {
    if (kind == int(PpTok.EOF) || kind == int(PpTok.RPAREN) || kind == int(PpTok.COLON)) {
        return 0
    } elif (kind == int(PpTok.COMMA)) {
        return 1
    } elif (kind == int(PpTok.QUESTION)) {
        return 2
    } elif (kind == int(PpTok.OR_OR)) {
        return 3
    } elif (kind == int(PpTok.AND_AND)) {
        return 4
    } elif (kind == int(PpTok.PIPE)) {
        return 5
    } elif (kind == int(PpTok.CARET)) {
        return 6
    } elif (kind == int(PpTok.AMP)) {
        return 7
    } elif (kind == int(PpTok.EQ) || kind == int(PpTok.NE)) {
        return 8
    } elif (kind == int(PpTok.LESS) || kind == int(PpTok.GREATER) || kind == int(PpTok.LE) || kind == int(PpTok.GE)) {
        return 9
    } elif (kind == int(PpTok.SHL) || kind == int(PpTok.SHR)) {
        return 10
    } elif (kind == int(PpTok.PLUS) || kind == int(PpTok.MINUS)) {
        return 11
    } elif (kind == int(PpTok.STAR) || kind == int(PpTok.SLASH) || kind == int(PpTok.PERCENT)) {
        return 12
    }
    return -1
}

// one operand: a constant, a name, `defined`, a query, a unary operator and its operand, or a
// parenthesized expression
[arch(at="ARCHITECTURE_EVAL.md#pp-eval-grammar")]
def private eval_value(var ev : PpEval; var v : PpValue; live : bool; ask : block<(what : PpEvalAsk; sym, first, last : int) : int>) : bool {
    if (at_end(ev)) {
        return fail(ev, -1, "expected value in expression")
    }
    let i = ev.pos
    let kind = ev.toks[i].kind
    ev.pos++
    if (kind == int(PpTok.IDENTIFIER)) {
        if (spelled_is(ev, i, "defined")) {
            return defined_value(ev, v, ask)
        }
        var q = query_of(ev, i)
        if (!empty(q) && invoke(ask, PpEvalAsk.builtin, ev.toks[i].sym, i, i) == 0) {
            q = ""
        }
        if (q == "__has_include" || q == "__has_include_next" || q == "__has_embed") {
            return include_query(ev, q, i, v, ask)
        } elif (!empty(q)) {
            return feature_query(ev, q, i, v)
        }
        v = signed_value(0l)
        if (peek_kind(ev) == int(PpTok.LPAREN)) {
            return fail(ev, i, "function-like macro '{spelling(ev, i)}' is not defined")
        }
        return true
    } elif (kind == int(PpTok.PP_NUMBER)) {
        return number_value(ev, i, v)
    } elif (kind == int(PpTok.CHAR_CONSTANT)) {
        return char_value(ev, i, v)
    } elif (kind == int(PpTok.LPAREN)) {
        return false if (!eval_value(ev, v, live, ask) || !sub_expr(ev, v, 1, live, ask))
        if (peek_kind(ev) != int(PpTok.RPAREN)) {
            return fail(ev, here(ev), "expected ')' in preprocessor expression")
        }
        ev.pos++
        return true
    } elif (kind == int(PpTok.PLUS) || kind == int(PpTok.MINUS) || kind == int(PpTok.TILDE) || kind == int(PpTok.EXCLAIM)) {
        return false if (!eval_value(ev, v, live, ask))
        if (kind == int(PpTok.MINUS)) {
            if (live && !v.unsigned && v.bits == SIGN_BIT) {
                warn(ev, i, "integer overflow in preprocessor expression")
            }
            v.bits = ~v.bits + 1ul
        } elif (kind == int(PpTok.TILDE)) {
            v.bits = ~v.bits
        } elif (kind == int(PpTok.EXCLAIM)) {
            v = signed_value(v.bits == 0ul ? 1l : 0l)
        }
        return true
    }
    return fail(ev, i, "invalid token at start of a preprocessor expression")
}

// the operators of precedence `min_prec` and above after the operand `lhs`, as clang's
// EvaluateDirectiveSubExpr folds them; `live` is false inside an operand short-circuiting skips
[arch(at="ARCHITECTURE_EVAL.md#pp-eval-grammar")]
def private sub_expr(var ev : PpEval; var lhs : PpValue; min_prec : int; live : bool;
                     ask : block<(what : PpEvalAsk; sym, first, last : int) : int>) : bool {
    var peek = precedence(peek_kind(ev))
    while (true) {
        if (peek < 0) {
            return fail(ev, here(ev), "token is not a valid binary operator in a preprocessor subexpression")
        }
        return true if (peek < min_prec)
        let this_prec = peek
        let op_at = ev.pos
        let op = ev.toks[op_at].kind
        ev.pos++
        var rhs_live = live
        if ((op == int(PpTok.AND_AND) && lhs.bits == 0ul) || (op == int(PpTok.OR_OR) && lhs.bits != 0ul)
                || (op == int(PpTok.QUESTION) && lhs.bits == 0ul)) {
            rhs_live = false
        }
        var rhs : PpValue
        return false if (!eval_value(ev, rhs, rhs_live, ask))
        let rhs_prec = op == int(PpTok.QUESTION) ? 1 : this_prec + 1
        peek = precedence(peek_kind(ev))
        if (peek >= rhs_prec) {
            return false if (!sub_expr(ev, rhs, rhs_prec, rhs_live, ask))
            peek = precedence(peek_kind(ev))
        }
        if (op == int(PpTok.QUESTION)) {
            if (peek_kind(ev) != int(PpTok.COLON)) {
                return fail(ev, here(ev), "expected ':'")
            }
            ev.pos++
            let after_live = live && lhs.bits == 0ul
            var after : PpValue
            return false if (!eval_value(ev, after, after_live, ask) || !sub_expr(ev, after, this_prec, after_live, ask))
            let unsigned = rhs.unsigned || after.unsigned
            lhs = PpValue(bits = lhs.bits != 0ul ? rhs.bits : after.bits, unsigned = unsigned)
            peek = precedence(peek_kind(ev))
            continue
        }
        return false if (!binary(ev, op, op_at, lhs, rhs, live))
    }
    return true
}

// lhs `op` rhs folded into `lhs` in intmax_t, or uintmax_t when either operand is unsigned (C11
// 6.10.1p4, the usual arithmetic conversions); a comparison or a logical operator gives a signed 0 or 1
[arch(at="ARCHITECTURE_EVAL.md#pp-eval-arith")]
def private binary(var ev : PpEval; op, op_at : int; var lhs : PpValue; rhs : PpValue; live : bool) : bool {  // nolint:STYLE037 - one arm per operator
    if (op == int(PpTok.AND_AND) || op == int(PpTok.OR_OR)) {
        let both = op == int(PpTok.AND_AND) ? lhs.bits != 0ul && rhs.bits != 0ul : lhs.bits != 0ul || rhs.bits != 0ul
        lhs = signed_value(both ? 1l : 0l)
        return true
    } elif (op == int(PpTok.COMMA)) {
        lhs = rhs
        return true
    } elif (op == int(PpTok.SHL) || op == int(PpTok.SHR)) {
        shift(ev, op, op_at, lhs, rhs, live)
        return true
    }
    let unsigned = lhs.unsigned || rhs.unsigned
    if (unsigned && live) {
        if (is_negative(lhs)) {
            warn(ev, op_at, "left side of operator converted from negative value to unsigned: {value_text(lhs)} to {decimal(lhs.bits)}")
        }
        if (is_negative(rhs)) {
            warn(ev, op_at, "right side of operator converted from negative value to unsigned: {value_text(rhs)} to {decimal(rhs.bits)}")
        }
    }
    let a = lhs.bits
    let b = rhs.bits
    var overflow = false
    var r = 0ul
    if (op == int(PpTok.PLUS)) {
        r = a + b
        overflow = !unsigned && ((a ^ r) & (b ^ r) & SIGN_BIT) != 0ul
    } elif (op == int(PpTok.MINUS)) {
        r = a - b
        overflow = !unsigned && ((a ^ b) & (a ^ r) & SIGN_BIT) != 0ul
    } elif (op == int(PpTok.STAR)) {
        r = a * b
        if (!unsigned && a != 0ul && b != 0ul) {
            let sa = int64(a)
            let sb = int64(b)
            overflow = (sa == -1l && b == SIGN_BIT) || (sb == -1l && a == SIGN_BIT) || (sb != -1l && int64(r) / sb != sa)
        }
    } elif (op == int(PpTok.SLASH) || op == int(PpTok.PERCENT)) {
        if (b == 0ul) {
            if (!live) {
                lhs = PpValue(bits = 0ul, unsigned = unsigned)
                return true
            }
            return fail(ev, op_at, "division by zero in preprocessor expression")
        }
        if (unsigned) {
            r = op == int(PpTok.SLASH) ? a / b : a % b
        } elif (int64(b) == -1l) {
            overflow = op == int(PpTok.SLASH) && a == SIGN_BIT
            r = op == int(PpTok.SLASH) ? ~a + 1ul : 0ul
        } else {
            r = uint64(op == int(PpTok.SLASH) ? int64(a) / int64(b) : int64(a) % int64(b))
        }
    } elif (op == int(PpTok.AMP)) {
        r = a & b
    } elif (op == int(PpTok.CARET)) {
        r = a ^ b
    } elif (op == int(PpTok.PIPE)) {
        r = a | b
    } else {
        lhs = signed_value(compare(op, a, b, unsigned) ? 1l : 0l)
        return true
    }
    if (overflow && live) {
        warn(ev, op_at, "integer overflow in preprocessor expression")
    }
    lhs = PpValue(bits = r, unsigned = unsigned)
    return true
}

def private compare(op : int; a, b : uint64; unsigned : bool) : bool {
    if (op == int(PpTok.EQ)) {
        return a == b
    } elif (op == int(PpTok.NE)) {
        return a != b
    }
    let less = unsigned ? a < b : int64(a) < int64(b)
    let greater = unsigned ? a > b : int64(a) > int64(b)
    if (op == int(PpTok.LESS)) {
        return less
    } elif (op == int(PpTok.GREATER)) {
        return greater
    } elif (op == int(PpTok.LE)) {
        return !greater
    }
    return !less
}

// `<<` and `>>`: no usual conversion, the result has the left operand's type; a count past the
// width is clang's overflow (`<<` gives 0, `>>` shifts by 63); `<<` that drops a set bit, or the
// sign of a signed value, overflows too
[arch(at="ARCHITECTURE_EVAL.md#pp-eval-arith")]
def private shift(var ev : PpEval; op, op_at : int; var lhs : PpValue; rhs : PpValue; live : bool) {
    let a = lhs.bits
    var overflow = false
    if (op == int(PpTok.SHL)) {
        if (rhs.bits >= 64ul) {
            overflow = true
            lhs.bits = 0ul
        } else {
            let r = a << rhs.bits
            if (lhs.unsigned) {
                overflow = (r >> rhs.bits) != a
            } else {
                overflow = int64(r) >> int64(rhs.bits) != int64(a)
            }
            lhs.bits = r
        }
    } else {
        var count = uint64(uint(rhs.bits & 0xFFFFFFFFul))
        if (count >= 64ul) {
            overflow = true
            count = 63ul
        }
        lhs.bits = lhs.unsigned ? a >> count : uint64(int64(a) >> int64(count))
    }
    if (overflow && live) {
        warn(ev, op_at, "integer overflow in preprocessor expression")
    }
}

//! The `#if` or `#elif` expression in `ev.toks` evaluated (C11 6.10.1), every constant an intmax_t
//! or uintmax_t, as clang 22 evaluates it; `ev.diags` holds its diagnostics. `ask` answers
//! `defined` (by symbol) and the include queries (by the line's tokens `first` to `last` that
//! name the file). An error fails the condition, so its group is skipped, except tokens after a
//! complete expression, which clang reports and then takes the value of.
[arch(at="ARCHITECTURE_EVAL.md#pp-eval")]
def pp_eval_condition(var ev : PpEval; ask : block<(what : PpEvalAsk; sym, first, last : int) : int>) : PpEvalResult {
    ev.diags |> clear()
    ev.pos = 0
    var v : PpValue
    if (!eval_value(ev, v, true, ask) || !sub_expr(ev, v, 2, true, ask)) {
        return PpEvalResult(value = false, failed = true)
    }
    if (!at_end(ev)) {
        ev.diags |> push(PpEvalDiag(error = true, token = ev.pos, what = "expected end of line in preprocessor expression"))
    }
    return PpEvalResult(value = v.bits != 0ul, failed = false)
}
