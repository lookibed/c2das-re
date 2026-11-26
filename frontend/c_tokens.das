options gen2
options indenting = 4

module c_tokens public

require strings
require pp_lexer public

//! The kind of a C token (C11 6.4, translation phase 7). A punctuator keeps the value `PpTok`
//! gives it; a keyword's kind is 300 and up, grouped so a class of keywords is one range.
enum CTok {
    EOF = 0
    IDENTIFIER = 256
    INT_CONSTANT = 257
    FLOAT_CONSTANT = 258
    CHAR_CONSTANT = 259
    STRING_LITERAL = 260
    ELLIPSIS = 262
    ARROW = 263
    INC = 264
    DEC = 265
    SHL = 266
    SHR = 267
    LE = 268
    GE = 269
    EQ = 270
    NE = 271
    AND_AND = 272
    OR_OR = 273
    MUL_ASSIGN = 274
    DIV_ASSIGN = 275
    MOD_ASSIGN = 276
    ADD_ASSIGN = 277
    SUB_ASSIGN = 278
    SHL_ASSIGN = 279
    SHR_ASSIGN = 280
    AND_ASSIGN = 281
    XOR_ASSIGN = 282
    OR_ASSIGN = 283
    EXCLAIM = 33
    PERCENT = 37
    AMP = 38
    LPAREN = 40
    RPAREN = 41
    STAR = 42
    PLUS = 43
    COMMA = 44
    MINUS = 45
    PERIOD = 46
    SLASH = 47
    COLON = 58
    SEMI = 59
    LESS = 60
    ASSIGN = 61
    GREATER = 62
    QUESTION = 63
    LBRACKET = 91
    RBRACKET = 93
    CARET = 94
    LBRACE = 123
    PIPE = 124
    RBRACE = 125
    TILDE = 126
    VOID = 300
    CHAR = 301
    SHORT = 302
    INT = 303
    LONG = 304
    FLOAT = 305
    DOUBLE = 306
    SIGNED = 307
    UNSIGNED = 308
    BOOL = 309
    COMPLEX = 310
    CONST = 320
    VOLATILE = 321
    RESTRICT = 322
    ATOMIC = 323
    TYPEDEF = 330
    EXTERN = 331
    STATIC = 332
    AUTO = 333
    REGISTER = 334
    THREAD_LOCAL = 335
    INLINE = 336
    NORETURN = 337
    STRUCT = 340
    UNION = 341
    ENUM = 342
    BREAK = 350
    CASE = 351
    CONTINUE = 352
    DEFAULT = 353
    DO = 354
    ELSE = 355
    FOR = 356
    GOTO = 357
    IF = 358
    RETURN = 359
    SWITCH = 360
    WHILE = 361
    SIZEOF = 370
    ALIGNOF = 371
    GNU_ALIGNOF = 372
    ALIGNAS = 373
    STATIC_ASSERT = 374
    ATTRIBUTE = 375
    ASM = 376
    EXTENSION = 377
    TYPEOF = 378
    VA_ARG = 379
    OFFSETOF = 380
    TYPES_COMPATIBLE = 381
    FUNC_NAME = 382
    GENERIC = 390
    IMAGINARY = 391
    INT128 = 392
    AUTO_TYPE = 393
    LOCAL_LABEL = 394
    REAL_PART = 395
    IMAG_PART = 396
}

//! Every spelling that is a keyword under gnu17, GNU alternates included, beside its kind; the
//! first spelling of a kind names it in messages.
let KEYWORDS <- fixed_array(
    ("void", CTok.VOID), ("char", CTok.CHAR), ("short", CTok.SHORT), ("int", CTok.INT),
    ("long", CTok.LONG), ("float", CTok.FLOAT), ("double", CTok.DOUBLE), ("signed", CTok.SIGNED),
    ("__signed", CTok.SIGNED), ("__signed__", CTok.SIGNED), ("unsigned", CTok.UNSIGNED),
    ("_Bool", CTok.BOOL), ("_Complex", CTok.COMPLEX), ("__complex", CTok.COMPLEX), ("__complex__", CTok.COMPLEX),
    ("const", CTok.CONST), ("__const", CTok.CONST), ("__const__", CTok.CONST),
    ("volatile", CTok.VOLATILE), ("__volatile", CTok.VOLATILE), ("__volatile__", CTok.VOLATILE),
    ("restrict", CTok.RESTRICT), ("__restrict", CTok.RESTRICT), ("__restrict__", CTok.RESTRICT),
    ("_Atomic", CTok.ATOMIC), ("typedef", CTok.TYPEDEF), ("extern", CTok.EXTERN), ("static", CTok.STATIC),
    ("auto", CTok.AUTO), ("register", CTok.REGISTER), ("_Thread_local", CTok.THREAD_LOCAL),
    ("__thread", CTok.THREAD_LOCAL), ("inline", CTok.INLINE), ("__inline", CTok.INLINE),
    ("__inline__", CTok.INLINE), ("_Noreturn", CTok.NORETURN), ("struct", CTok.STRUCT),
    ("union", CTok.UNION), ("enum", CTok.ENUM), ("break", CTok.BREAK), ("case", CTok.CASE),
    ("continue", CTok.CONTINUE), ("default", CTok.DEFAULT), ("do", CTok.DO), ("else", CTok.ELSE),
    ("for", CTok.FOR), ("goto", CTok.GOTO), ("if", CTok.IF), ("return", CTok.RETURN),
    ("switch", CTok.SWITCH), ("while", CTok.WHILE), ("sizeof", CTok.SIZEOF), ("_Alignof", CTok.ALIGNOF),
    ("__alignof__", CTok.GNU_ALIGNOF), ("__alignof", CTok.GNU_ALIGNOF), ("_Alignas", CTok.ALIGNAS),
    ("_Static_assert", CTok.STATIC_ASSERT), ("__attribute__", CTok.ATTRIBUTE),
    ("__attribute", CTok.ATTRIBUTE), ("asm", CTok.ASM), ("__asm", CTok.ASM), ("__asm__", CTok.ASM),
    ("__extension__", CTok.EXTENSION), ("typeof", CTok.TYPEOF), ("__typeof", CTok.TYPEOF),
    ("__typeof__", CTok.TYPEOF), ("__builtin_va_arg", CTok.VA_ARG), ("__builtin_offsetof", CTok.OFFSETOF),
    ("__builtin_types_compatible_p", CTok.TYPES_COMPATIBLE), ("__func__", CTok.FUNC_NAME),
    ("__FUNCTION__", CTok.FUNC_NAME), ("__PRETTY_FUNCTION__", CTok.FUNC_NAME), ("_Generic", CTok.GENERIC),
    ("_Imaginary", CTok.IMAGINARY), ("__int128", CTok.INT128), ("__auto_type", CTok.AUTO_TYPE),
    ("__label__", CTok.LOCAL_LABEL), ("__real__", CTok.REAL_PART), ("__real", CTok.REAL_PART),
    ("__imag__", CTok.IMAG_PART), ("__imag", CTok.IMAG_PART))

//! One C token: `start` and `len` are bytes of the unit's text past translation phase 2 (the
//! lexer's working buffer); `file`, `line` and `col` place it as the line markers before it say.
struct CToken {
    kind : int
    sym : int       //!< the interned name of an IDENTIFIER or a keyword; -1 for every other kind
    start : int
    len : int
    file : int      //!< 0 the unit's own name, then each file a line marker names, in order of first sight
    line : int
    col : int
}

//! A unit's C tokens, an EOF token last, and what reading them needs: the lexer (its bytes and its
//! interner), the files the line markers name, and the keyword kind of each interned symbol.
struct CUnit {
    lx : PpLexer
    toks : array<CToken>
    name : string           //!< the name of file 0
    file_syms : array<int>  //!< per file past 0, the interned bytes of its name between the quotes
    keyword_of : array<int> //!< per symbol interned before the first token, its keyword kind or 0
    err : string            //!< the first error, `file:line:col: what`; "" when the tokens are clean
}

//! the bytes `[start, start + len)` of the unit's text as a string, for a message or a dump
def c_text(unit : CUnit; start, len : int) : string => slice(unit.lx.flex.bytes, start, start + len)

//! The spelling of token `t`.
def c_spelling(unit : CUnit; t : int) : string => c_text(unit, unit.toks[t].start, unit.toks[t].len)

//! The name of file `file`.
def c_file_name(var unit : CUnit; file : int) : string =>
    file == 0 ? unit.name : pp_symbol_text(unit.lx, unit.file_syms[file - 1])

//! `file:line:col` of token `t`.
def c_where(var unit : CUnit; t : int) : string {
    let tok = unit.toks[t]
    return "{c_file_name(unit, tok.file)}:{tok.line}:{tok.col}"
}

//! The name of token kind `k` as a message spells it: a punctuator or a keyword's first spelling;
//! any other kind by its number.
def c_kind_name(k : int) : string {
    return to_char(k) if (k > 0 && k < 256)
    let puncts = fixed_array("...", "->", "++", "--", "<<", ">>", "<=", ">=", "==", "!=", "&&", "||", "*=", "/=", "%=", "+=", "-=", "<<=", ">>=", "&=", "^=", "|=")
    return puncts[k - int(CTok.ELLIPSIS)] if (k >= int(CTok.ELLIPSIS) && k <= int(CTok.OR_ASSIGN))
    for (kw in KEYWORDS) {
        return kw._0 if (int(kw._1) == k)
    }
    return "token kind {k}"
}

//! The symbol of `name` in the unit's interner, interned when new.
def c_symbol(var unit : CUnit; name : string) : int => intern_name(unit.lx.flex.syms, name)

def private byte_at(unit : CUnit; at : int) : int => int(unsafe(unit.lx.flex.data[at]))

def private is_digit(b : int) : bool => is_number(b)

def private is_hex_digit(b : int) : bool => is_digit(b) || (b >= 'a' && b <= 'f') || (b >= 'A' && b <= 'F')

//! the first byte at or after `at` and before `stop` that `digit` does not take
def private digits_end(unit : CUnit; at, stop : int; hex : bool) : int {
    var i = at
    while (i < stop && (hex ? is_hex_digit(byte_at(unit, i)) : is_digit(byte_at(unit, i)))) {
        i++
    }
    return i
}

//! an integer suffix spans `[at, stop)`: `u` and `l`, `ll` (one case) in either order, each once
def private is_int_suffix(unit : CUnit; at, stop : int) : bool {
    var i = at
    var u = false
    var l = false
    while (i < stop) {
        let b = byte_at(unit, i)
        if ((b == 'u' || b == 'U') && !u) {
            u = true
            i++
        } elif ((b == 'l' || b == 'L') && !l) {
            l = true
            i += i + 1 < stop && byte_at(unit, i + 1) == b ? 2 : 1
        } else {
            return false
        }
    }
    return true
}

//! a floating suffix spans `[at, stop)`: none, or one of `f`, `F`, `l`, `L`
def private is_float_suffix(unit : CUnit; at, stop : int) : bool =>
    at == stop || (at + 1 == stop && (byte_at(unit, at) == 'f' || byte_at(unit, at) == 'F' || byte_at(unit, at) == 'l' || byte_at(unit, at) == 'L'))

//! after a mantissa ending at `at`: an exponent `e`/`p` (`binary` picks), its sign and digits, then
//! a floating suffix, up to `stop`; `needed` when a hexadecimal mantissa makes the exponent required
def private is_float_tail(unit : CUnit; at, stop : int; binary, needed : bool) : bool {
    var i = at
    let b = i < stop ? byte_at(unit, i) : 0
    if (binary ? (b == 'p' || b == 'P') : (b == 'e' || b == 'E')) {
        i++
        if (i < stop && (byte_at(unit, i) == '+' || byte_at(unit, i) == '-')) {
            i++
        }
        let digits = digits_end(unit, i, stop, false)
        return false if (digits == i)
        i = digits
    } elif (needed) {
        return false
    }
    return is_float_suffix(unit, i, stop)
}

//! The constant kind of the pp-number at `[start, start + len)` (C11 6.4.4.1, 6.4.4.2, binary
//! `0b` as GNU C has it): INT_CONSTANT, FLOAT_CONSTANT, or EOF when it is no constant. Its value is
//! not read here.
[arch(at="ARCHITECTURE_PARSER.md#c-tokens")]
def private number_kind(unit : CUnit; start, len : int) : int {
    let stop = start + len
    let second = len > 1 ? byte_at(unit, start + 1) : 0
    let lead_zero = byte_at(unit, start) == '0'
    if (lead_zero && (second == 'x' || second == 'X')) {
        let whole = digits_end(unit, start + 2, stop, true)
        var i = whole
        var frac = whole
        if (i < stop && byte_at(unit, i) == '.') {
            frac = digits_end(unit, i + 1, stop, true)
            i = frac
        }
        let has_digits = whole > start + 2 || frac > whole + 1
        if (has_digits && i < stop && (byte_at(unit, i) == 'p' || byte_at(unit, i) == 'P')) {
            return int(is_float_tail(unit, i, stop, true, true) ? CTok.FLOAT_CONSTANT : CTok.EOF)
        }
        return int(whole > start + 2 && whole == i && is_int_suffix(unit, i, stop) ? CTok.INT_CONSTANT : CTok.EOF)
    }
    if (lead_zero && (second == 'b' || second == 'B')) {
        var i = start + 2
        while (i < stop && (byte_at(unit, i) == '0' || byte_at(unit, i) == '1')) {
            i++
        }
        return int(i > start + 2 && is_int_suffix(unit, i, stop) ? CTok.INT_CONSTANT : CTok.EOF)
    }
    let whole = digits_end(unit, start, stop, false)
    var i = whole
    let b = i < stop ? byte_at(unit, i) : 0
    if (b == '.' || b == 'e' || b == 'E') {
        if (b == '.') {
            i = digits_end(unit, i + 1, stop, false)
        }
        let has_digits = whole > start || i > whole + 1
        return int(has_digits && is_float_tail(unit, i, stop, false, false) ? CTok.FLOAT_CONSTANT : CTok.EOF)
    }
    if (lead_zero) {
        for (k in range(start, whole)) {
            return int(CTok.EOF) if (byte_at(unit, k) > '7')
        }
    }
    return int(is_int_suffix(unit, whole, stop) ? CTok.INT_CONSTANT : CTok.EOF)
}

//! the decimal value of the pp-number token in the lexer, -1 when it holds any other byte
def private decimal_value(unit : CUnit) : int {
    let t & = unsafe(unit.lx.flex.tok)
    var value = 0
    for (i in range(t.start, t.start + t.len)) {
        let b = byte_at(unit, i)
        return -1 if (!is_digit(b) || value > 100000000)
        value = value * 10 + b - '0'
    }
    return value
}

//! the first error of the unit, at the lexer's token
def private token_error(var unit : CUnit; file, line_delta : int; what : string) {
    if (empty(unit.err)) {
        unit.err = "{c_file_name(unit, file)}:{unit.lx.tok.line + line_delta}:{unit.lx.tok.col}: {what}"
    }
}

//! the file id of the line marker's name in the lexer's string-literal token, added when new
def private marker_file(var unit : CUnit) : int {
    let t & = unsafe(unit.lx.flex.tok)
    let sym = intern(unit.lx.flex.syms, unit.lx.flex.data, t.start + 1, t.len - 2)
    for (k in range(length(unit.file_syms))) {
        return k + 1 if (unit.file_syms[k] == sym)
    }
    unit.file_syms |> push(sym)
    return length(unit.file_syms)
}

//! Open the unit over `bytes`, the text of a preprocessed translation unit, named `name`: the
//! keyword spellings are interned once, so a token's kind is one index by its symbol.
def c_tokens_open(var unit : CUnit; var bytes : array<uint8>; name : string) {
    unit.name = name
    unit.err = ""
    unit.toks |> clear()
    unit.file_syms |> clear()
    pp_open(unit.lx, bytes, 0, name)
    var syms <- [for (kw in KEYWORDS); c_symbol(unit, kw._0)]
    unit.keyword_of |> resize(symbol_count(unit.lx.flex.syms))
    for (sym, kw in syms, KEYWORDS) {
        unit.keyword_of[sym] = int(kw._1)
    }
}

//! the C token kind of the pp-token in the lexer, or EOF when it is no C token
def private c_kind_of(unit : CUnit) : int {
    let k = unit.lx.tok.kind
    if (k == int(PpTok.IDENTIFIER)) {
        let sym = unit.lx.tok.sym
        let kw = sym < length(unit.keyword_of) ? unit.keyword_of[sym] : 0
        return kw != 0 ? kw : int(CTok.IDENTIFIER)
    } elif (k == int(PpTok.PP_NUMBER)) {
        let t & = unsafe(unit.lx.flex.tok)
        return number_kind(unit, t.start, t.len)
    } elif (k == int(PpTok.CHAR_CONSTANT)) {
        return int(CTok.CHAR_CONSTANT)
    } elif (k == int(PpTok.STRING_LITERAL)) {
        return int(CTok.STRING_LITERAL)
    } elif ((k > 0 && k < 256 && k != int(PpTok.HASH)) || (k >= int(PpTok.ELLIPSIS) && k <= int(PpTok.OR_ASSIGN))) {
        return k
    }
    return int(CTok.EOF)
}

//! the line marker or directive whose `#` the lexer holds, read to the end of its line: a marker
//! `# <line> "<file>" <flags>` (or `#line`) moves the place of the lines after it; any other
//! directive is an error. False after an error; `more` answers whether a token follows the line.
[arch(at="ARCHITECTURE_PARSER.md#c-tokens")]
def private line_marker(var unit : CUnit; var file, line_delta : int&; var more : bool&) : bool {
    let hash_line = unit.lx.tok.line
    more = pp_next(unit.lx)
    if (more && !unit.lx.tok.at_bol && unit.lx.tok.kind == int(PpTok.IDENTIFIER) && pp_spelling_is(unit.lx, "line")) {
        more = pp_next(unit.lx)
    }
    let value = more && !unit.lx.tok.at_bol && unit.lx.tok.kind == int(PpTok.PP_NUMBER) ? decimal_value(unit) : -1
    if (value < 0) {
        let what = more && !unit.lx.tok.at_bol ? "the directive '#{pp_spelling(unit.lx)}'" : "an empty directive '#'"
        token_error(unit, file, line_delta, "{what} is not parsed")
        return false
    }
    var new_file = file
    more = pp_next(unit.lx)
    if (more && !unit.lx.tok.at_bol && unit.lx.tok.kind == int(PpTok.STRING_LITERAL)) {
        new_file = marker_file(unit)
        more = pp_next(unit.lx)
    }
    while (more && !unit.lx.tok.at_bol) {
        more = pp_next(unit.lx)
    }
    file = new_file
    line_delta = value - hash_line - 1
    return true
}

//! Read the unit's tokens to its end: identifiers become keywords by their symbol, pp-numbers
//! integer or floating constants, line markers move the place of the tokens after them. False
//! after the first error, which `unit.err` holds with its place; the tokens end with EOF either way.
[arch(at="ARCHITECTURE_PARSER.md#c-tokens")]
def c_tokens_read(var unit : CUnit) : bool {
    var file = 0
    var line_delta = 0
    var more = pp_next(unit.lx)
    while (more && empty(unit.err)) {
        if (unit.lx.tok.kind == int(PpTok.HASH) && unit.lx.tok.at_bol) {
            line_marker(unit, file, line_delta, more)
            continue
        }
        let kind = c_kind_of(unit)
        if (kind == int(CTok.EOF)) {
            let what = unit.lx.tok.kind == int(PpTok.PP_NUMBER) ? "invalid numeric constant" : "stray"
            token_error(unit, file, line_delta, "{what} '{pp_spelling(unit.lx)}'")
            break
        }
        let t & = unsafe(unit.lx.flex.tok)
        unit.toks |> push(CToken(kind = kind, sym = unit.lx.tok.sym, start = t.start, len = t.len,
                                 file = file, line = unit.lx.tok.line + line_delta, col = unit.lx.tok.col))
        more = pp_next(unit.lx)
    }
    if (empty(unit.err) && !empty(unit.lx.diags)) {
        let d = unit.lx.diags[0]
        unit.err = "{c_file_name(unit, file)}:{d.line + line_delta}:{d.col}: {d.what}"
    }
    var end = CToken(kind = int(CTok.EOF), sym = -1, start = unit.lx.flex.len, file = file, line = 1, col = 1)
    if (!empty(unit.toks)) {
        let last = unit.toks[length(unit.toks) - 1]
        end.file = last.file
        end.line = last.line
        end.col = last.col + last.len
    }
    unit.toks |> push(end)
    return empty(unit.err)
}

//! `c_tokens_open` and `c_tokens_read` over the bytes of `text`, copied once.
def c_tokens_of_text(var unit : CUnit; text : string; name : string) : bool {
    var bytes : array<uint8>
    bytes |> reserve(length(text) + 1)
    peek_data(text) $(chars) {
        for (c in chars) {
            bytes |> push(c)
        }
    }
    c_tokens_open(unit, bytes, name)
    return c_tokens_read(unit)
}
