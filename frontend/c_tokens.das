options gen2
options indenting = 4

module c_tokens public

require strings
require math
require daslib/strings_boost
require pp_directives public
require pp_expand

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

//! One C token: its kind and symbol, where its spelling lies - `spelled`, `buffer`, `at` and `len`
//! as the preprocessor's `PpOutToken` has them, but a `scratch` spelling (a pasted or stringified
//! token, or one spelled by its symbol) is `len` bytes at `at` of the unit's own `pool` - and its
//! presumed place: `file` an index
//! of the preprocessor's `names`, `line` and `col`, of the outermost macro name for a token of an
//! expansion; `expanded` marks a token a macro expansion made.
struct CToken {
    kind : int
    sym : int       //!< the interned name of an IDENTIFIER or a keyword; -1 for every other kind
    spelled : PpSpelled
    buffer : int
    at : int
    len : int
    file : int      //!< 0 the unit's own name, then each name a file, `#line` or a line marker gives, in order of first sight
    line : int
    col : int
    expanded : bool
}

//! A unit's C tokens, an EOF token last, and what reading them needs: the preprocessor that hands
//! out its tokens (and holds the interner, the files and their names), the spellings of pasted and
//! stringified tokens, and the keyword kind of each interned symbol.
struct CUnit {
    pp : Preprocessor
    toks : array<CToken>
    pool : array<uint8>     //!< the `scratch` spellings of `toks`, copied before the next token is read
    splits : array<int>     //!< per `::` read as two `:` tokens, its index among the preprocessor's tokens
    kind_of_sym : array<int> //!< per symbol, its C kind once known: a keyword's kind or IDENTIFIER; 0 before
    err : string            //!< the first error, `file:line:col: what`; "" when the tokens are clean
}

//! The bytes of token `t`'s spelling, valid while the unit is.
def c_span(unit : CUnit; t : int) : tuple<data : uint8 const?; len : int> {
    let tok = unit.toks[t]
    if (tok.spelled == PpSpelled.scratch) {
        return (data = unsafe(addr(unit.pool[tok.at])), len = tok.len)
    } elif (tok.spelled == PpSpelled.body) {
        return (data = unsafe(addr(unit.pp.macro_text[tok.at])), len = tok.len)
    }
    return (data = unsafe(pp_buffer_data(unit.pp, tok.buffer) + tok.at), len = tok.len)
}

//! Byte `i` of token `t`'s spelling.
def c_byte(unit : CUnit; t, i : int) : int => int(unsafe(c_span(unit, t).data[i]))

//! The spelling of token `t`.
def c_spelling(unit : CUnit; t : int) : string {
    if (unit.toks[t].len == 0) {
        return ""
    }
    let span = c_span(unit, t)
    return build_string() $(var out) {
        for (i in range(span.len)) {
            out |> write_char(int(unsafe(span.data[i])))
        }
    }
}

// whether token `t` follows token `t - 1` in one file's bytes with nothing but blanks between them:
// both read from the file, no expansion's, and no directive, skipped group or comment in between
def private follows(unit : CUnit; data : uint8 const?; t : int) : bool {
    let tok = unit.toks[t]
    let prev = unit.toks[t - 1]
    return false if (tok.spelled != PpSpelled.source || tok.expanded || tok.buffer != prev.buffer || tok.at < prev.at + prev.len)
    for (i in range(prev.at + prev.len, tok.at)) {
        let b = int(unsafe(data[i]))
        return false if (b != ' ' && b != '\t' && b != '\n' && b != '\r' && b != '\v' && b != '\f')
    }
    return true
}

//! The text of tokens `first` to `last`: the bytes between them as written when the tokens cover
//! them, each read from one file with nothing but blanks between, else their spellings with a blank
//! between each two.
[arch(at="ARCHITECTURE_PARSER.md#c-tokens")]
def c_range_text(unit : CUnit; first, last : int) : string {
    let head = unit.toks[first]
    let data = head.spelled == PpSpelled.source ? pp_buffer_data(unit.pp, head.buffer) : null
    var in_place = head.spelled == PpSpelled.source && !head.expanded
    for (t in range(first + 1, last + 1)) {
        in_place = in_place && follows(unit, data, t)
    }
    if (!in_place) {
        return join([for (t in range(first, last + 1)); c_spelling(unit, t)], " ")
    }
    let stop = unit.toks[last].at + unit.toks[last].len
    return build_string() $(var out) {
        for (i in range(head.at, stop)) {
            out |> write_char(int(unsafe(data[i])))
        }
    }
}

//! The name of file `file`.
def c_file_name(unit : CUnit; file : int) : string => unit.pp.names[file]

//! `file:line:col` of token `t`.
def c_where(unit : CUnit; t : int) : string {
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
def c_symbol(var unit : CUnit; name : string) : int => intern_name(unit.pp.lx.flex.syms, name)

//! The text of symbol `sym`.
def c_symbol_text(var unit : CUnit; sym : int) : string => pp_symbol_text(unit.pp.lx, sym)

def private byte_of(data : uint8 const?; i : int) : int => int(unsafe(data[i]))

def private is_digit(b : int) : bool => is_number(b)

def private is_hex_digit(b : int) : bool => is_digit(b) || (b >= 'a' && b <= 'f') || (b >= 'A' && b <= 'F')

//! the first byte at or after `at` and before `stop` that `digit` does not take
def private digits_end(data : uint8 const?; at, stop : int; hex : bool) : int {
    var i = at
    while (i < stop && (hex ? is_hex_digit(byte_of(data, i)) : is_digit(byte_of(data, i)))) {
        i++
    }
    return i
}

//! an integer suffix spans `[at, stop)`: `u` and `l`, `ll` (one case) in either order, each once
def private is_int_suffix(data : uint8 const?; at, stop : int) : bool {
    var i = at
    var u = false
    var l = false
    while (i < stop) {
        let b = byte_of(data, i)
        if ((b == 'u' || b == 'U') && !u) {
            u = true
            i++
        } elif ((b == 'l' || b == 'L') && !l) {
            l = true
            i += i + 1 < stop && byte_of(data, i + 1) == b ? 2 : 1
        } else {
            return false
        }
    }
    return true
}

//! a floating suffix spans `[at, stop)`: none, or one of `f`, `F`, `l`, `L`
def private is_float_suffix(data : uint8 const?; at, stop : int) : bool =>
    at == stop || (at + 1 == stop && (byte_of(data, at) == 'f' || byte_of(data, at) == 'F' || byte_of(data, at) == 'l' || byte_of(data, at) == 'L'))

//! after a mantissa ending at `at`: an exponent `e`/`p` (`binary` picks), its sign and digits, then
//! a floating suffix, up to `stop`
def private is_float_tail(data : uint8 const?; at, stop : int; binary : bool) : bool {
    var i = at
    let b = i < stop ? byte_of(data, i) : 0
    if (binary ? (b == 'p' || b == 'P') : (b == 'e' || b == 'E')) {
        i++
        if (i < stop && (byte_of(data, i) == '+' || byte_of(data, i) == '-')) {
            i++
        }
        let digits = digits_end(data, i, stop, false)
        return false if (digits == i)
        i = digits
    }
    return is_float_suffix(data, i, stop)
}

//! The constant kind of the pp-number spelled by the `len` bytes at `data` (C11 6.4.4.1, 6.4.4.2,
//! binary `0b` as GNU C has it): INT_CONSTANT, FLOAT_CONSTANT, or EOF when it is no constant. Its
//! value is not read here.
[arch(at="ARCHITECTURE_PARSER.md#c-tokens")]
def private number_kind(data : uint8 const?; len : int) : int {
    let stop = len
    let second = len > 1 ? byte_of(data, 1) : 0
    let lead_zero = byte_of(data, 0) == '0'
    if (lead_zero && (second == 'x' || second == 'X')) {
        let whole = digits_end(data, 2, stop, true)
        var i = whole
        var frac = whole
        if (i < stop && byte_of(data, i) == '.') {
            frac = digits_end(data, i + 1, stop, true)
            i = frac
        }
        let has_digits = whole > 2 || frac > whole + 1
        if (has_digits && i < stop && (byte_of(data, i) == 'p' || byte_of(data, i) == 'P')) {
            return int(is_float_tail(data, i, stop, true) ? CTok.FLOAT_CONSTANT : CTok.EOF)
        }
        return int(whole > 2 && whole == i && is_int_suffix(data, i, stop) ? CTok.INT_CONSTANT : CTok.EOF)
    }
    if (lead_zero && (second == 'b' || second == 'B')) {
        var i = 2
        while (i < stop && (byte_of(data, i) == '0' || byte_of(data, i) == '1')) {
            i++
        }
        return int(i > 2 && is_int_suffix(data, i, stop) ? CTok.INT_CONSTANT : CTok.EOF)
    }
    let whole = digits_end(data, 0, stop, false)
    var i = whole
    let b = i < stop ? byte_of(data, i) : 0
    if (b == '.' || b == 'e' || b == 'E') {
        if (b == '.') {
            i = digits_end(data, i + 1, stop, false)
        }
        return int(is_float_tail(data, i, stop, false) ? CTok.FLOAT_CONSTANT : CTok.EOF)
    }
    if (lead_zero) {
        for (k in range(whole)) {
            return int(CTok.EOF) if (byte_of(data, k) > '7')
        }
    }
    return int(is_int_suffix(data, whole, stop) ? CTok.INT_CONSTANT : CTok.EOF)
}

def private hex_value(b : int) : int => b <= '9' ? b - '0' : (b | 0x20) - 'a' + 10

//! the identifier spelled by the `len` bytes at `data` holds a universal character name C11
//! 6.4.3p2 forbids: one naming a character below U+00A0 other than `$`, `@` and a backquote, a
//! surrogate, or a code point past U+10FFFF; the pp-lexer takes only well-formed UCNs into an
//! identifier
[arch(at="ARCHITECTURE_PARSER.md#c-tokens")]
def private names_basic_character(data : uint8 const?; len : int) : bool {
    var i = 0
    while (i < len) {
        if (byte_of(data, i) != '\\') {
            i++
            continue
        }
        let digits = byte_of(data, i + 1) == 'u' ? 4 : 8
        var value = 0l
        for (d in range(digits)) {
            value = value * 16l + int64(hex_value(byte_of(data, i + 2 + d)))
        }
        let basic = value < int64(0xA0) && value != int64(0x24) && value != int64(0x40) && value != int64(0x60)
        return true if (basic || (value >= int64(0xD800) && value <= int64(0xDFFF)) || value > int64(0x10FFFF))
        i += 2 + digits
    }
    return false
}

//! the provider of one file in memory, the bytes of a preprocessed unit: read once, the bytes
//! moved to the lexer
class private TextProvider : PpFileProvider {
    path : string
    bytes : array<uint8>
    def override exists(path : string) : bool => path == self.path
    def override read(path : string; var bytes : array<uint8>) : bool {
        return false if (path != self.path)
        delete bytes
        bytes <- self.bytes
        return true
    }
    def override identity(path : string) : string => path
}

//! a fresh preprocessor for the unit, the interner of the last one kept so a symbol keeps its id
def private reset(var unit : CUnit) {
    flex_symbols_detach(unit.pp.lx.flex.syms)
    var syms <- unit.pp.lx.flex.syms
    unsafe {
        delete unit.pp
    }
    unit.pp <- Preprocessor()
    unit.pp.lx.flex.syms <- syms
    unit.err = ""
    unit.toks |> clear()
    unit.pool |> clear()
    unit.splits |> clear()
}

//! the keyword spellings interned once, so a token's kind is one index by its symbol
def private keywords(var unit : CUnit) {
    var syms <- [for (kw in KEYWORDS); c_symbol(unit, kw._0)]
    unit.kind_of_sym |> clear()
    unit.kind_of_sym |> resize(symbol_count(unit.pp.lx.flex.syms))
    for (sym, kw in syms, KEYWORDS) {
        unit.kind_of_sym[sym] = int(kw._1)
    }
}

//! Open the unit over `bytes`, the text of a preprocessed translation unit, named `name`: the
//! directive layer reads it, so its line markers place the tokens, and expands no macro.
[arch(at="ARCHITECTURE_PARSER.md#c-tokens")]
def c_tokens_open(var unit : CUnit; var bytes : array<uint8>; name : string) {
    reset(unit)
    var provider = new TextProvider(path = normalized_path(name))
    provider.bytes <- bytes
    let none : array<string>
    pp_start(unit.pp, provider, name, none, none)
    keywords(unit)
}

//! Open the unit over the C source `main` read through `provider`, preprocessed with macro
//! expansion as `pp_expand_start` does it.
[arch(at="ARCHITECTURE_PARSER.md#c-tokens")]
def c_tokens_expand_open(var unit : CUnit; var provider : PpFileProvider?; main : string; predefines : array<string>;
                         search : array<string>; epoch : int64 = -1l) {
    reset(unit)
    pp_expand_start(unit.pp, provider, main, predefines, search, epoch)
    keywords(unit)
}

//! the C token kind of the preprocessor's token, or EOF when it is no C token
def private c_kind_of(var unit : CUnit) : int {
    let k = unit.pp.tok.tok.kind
    if (k == int(PpTok.IDENTIFIER)) {
        let sym = unit.pp.tok.tok.sym
        return unit.kind_of_sym[sym] if (sym < length(unit.kind_of_sym) && unit.kind_of_sym[sym] != 0)
        let span = pp_token_span(unit.pp)
        return int(CTok.EOF) if (names_basic_character(span.data, span.len))
        if (sym >= length(unit.kind_of_sym)) {
            unit.kind_of_sym |> resize(max(sym + 1, 2 * length(unit.kind_of_sym)))
        }
        unit.kind_of_sym[sym] = int(CTok.IDENTIFIER)
        return int(CTok.IDENTIFIER)
    } elif (k == int(PpTok.PP_NUMBER)) {
        let span = pp_token_span(unit.pp)
        return number_kind(span.data, span.len)
    } elif (k == int(PpTok.CHAR_CONSTANT)) {
        return int(CTok.CHAR_CONSTANT)
    } elif (k == int(PpTok.STRING_LITERAL)) {
        return int(CTok.STRING_LITERAL)
    } elif ((k > 0 && k < 256 && k != int(PpTok.HASH)) || (k >= int(PpTok.ELLIPSIS) && k <= int(PpTok.OR_ASSIGN))) {
        return k
    }
    return int(CTok.EOF)
}

//! the preprocessor's token as a C token of kind `kind`: placed at its presumed line and file, and
//! at the column of the outermost macro name when an expansion made it; a `scratch` or `symbol`
//! spelling copied into the unit's pool
[arch(at="ARCHITECTURE_PARSER.md#c-tokens")]
def private kept(var unit : CUnit; kind : int) : CToken {
    let out & = unsafe(unit.pp.tok)
    var call = out.call
    var col = out.tok.col
    if (call >= 0) {
        let calls & = unsafe(unit.pp.expansion.calls)
        while (calls[call].parent >= 0) {
            call = calls[call].parent
        }
        col = calls[call].name.col
    }
    var tok = CToken(kind = kind, sym = out.tok.sym, spelled = out.spelled, buffer = out.buffer, at = out.at, len = out.len,
                     file = out.pname, line = int(out.pline), col = col, expanded = out.call >= 0)
    if (out.spelled == PpSpelled.scratch || out.spelled == PpSpelled.symbol) {
        let span = pp_token_span(unit.pp)
        tok.spelled = PpSpelled.scratch
        tok.at = length(unit.pool)
        unit.pool |> resize(tok.at + span.len)
        for (i in range(span.len)) {
            unit.pool[tok.at + i] = unsafe(span.data[i])
        }
    }
    return tok
}

//! The pragmas the C-IR may pass by, as the text after `pragma` starts: a diagnostic's, a message's
//! and a warning's, which change no C-IR; `#ident` too. Any other pragma the preprocessor records is
//! refused, `pack` until the record layout reads `pp.packs`.
let PASSED_PRAGMAS <- fixed_array("GCC diagnostic", "clang diagnostic", "message", "GCC warning")

//! the two diagnostics the preprocessor places at a construct's start but meets at its file's end
let private MET_AT_END <- fixed_array("unterminated function-like macro invocation", "unterminated conditional directive")

//! how far the read took each record the preprocessor fills
struct private ReadMarks {
    diags : int
    lexer : int
    pragmas : int
    packs : int
}

//! an error the read met: where it met it in the file as read, and its text
struct private Met {
    file : int
    line : int
    col : int
    at_end : bool       //!< placed at its construct, met at its file's end
    text : string
}

// the presumed name and line of physical line `line` of file `file`: by the `#line` state of its
// inclusion while it is read, else as its path names it
def private presumed(unit : CUnit; file, line : int) : tuple<name : int; line : int> {
    if (unit.pp.state.file == file) {
        return (name = unit.pp.state.pname, line = int(uint(line) + unit.pp.state.line_delta))
    }
    for (k in range(length(unit.pp.frames))) {
        let st & = unsafe(unit.pp.frames[length(unit.pp.frames) - 1 - k].state)
        return (name = st.pname, line = int(uint(line) + st.line_delta)) if (st.file == file)
    }
    return (name = unit.pp.files[file].name, line = line)
}

// `what` placed at physical `line`:`col` of file `file`
def private met_at(unit : CUnit; file, line, col : int; what : string) : Met {
    let at = presumed(unit, file, line)
    return Met(file = file, line = line, col = col, text = "{unit.pp.names[at.name]}:{at.line}:{col}: {what}")
}

// `m` in `best` when the read met it first: of one file, the earlier place, a construct met at the
// file's end after every place; of two files, the one recorded first
def private earliest(var best : Met; m : Met) {
    if (empty(best.text)) {
        best = m
    } elif (m.file == best.file && (m.at_end != best.at_end ? best.at_end : m.line < best.line || (m.line == best.line && m.col < best.col))) {
        best = m
    }
}

// why pragma `pr` is refused, "" when the C-IR may pass it by
def private pragma_refusal(pr : PpPragma) : string {
    return "" if (pr.ident)
    for (passed in PASSED_PRAGMAS) {
        return "" if (pr.text == passed || starts_with(pr.text, "{passed} ") || starts_with(pr.text, "{passed}("))
    }
    return starts_with(pr.text, "GCC error") ? "#pragma {pr.text}" : "the pragma '#pragma {pr.text}' is not parsed"
}

//! the first error the read met past `marks`, into `unit.err`: the preprocessor's (a warning is
//! none), the lexer's, a pragma's the C-IR does not pass by
[arch(at="ARCHITECTURE_PARSER.md#c-tokens")]
def private diagnosed(var unit : CUnit; var marks : ReadMarks&) : bool {
    var best : Met
    for (k in range(marks.diags, length(unit.pp.diags))) {
        let d & = unsafe(unit.pp.diags[k])
        continue if (d.severity == PpSeverity.warning)
        if (d.line == 0) {
            earliest(best, Met(file = -1, text = d.what))
        } else {
            earliest(best, Met(file = d.file, line = d.line, col = d.col, at_end = has_value(MET_AT_END, d.what),
                               text = "{unit.pp.names[d.pname]}:{int(d.pline)}:{d.col}: {d.what}"))
        }
    }
    for (k in range(marks.lexer, length(unit.pp.lx.diags))) {
        let d & = unsafe(unit.pp.lx.diags[k])
        earliest(best, met_at(unit, d.file, d.line, d.col, d.what))
    }
    for (k in range(marks.pragmas, length(unit.pp.pragmas))) {
        let pr & = unsafe(unit.pp.pragmas[k])
        let why = pragma_refusal(pr)
        if (!empty(why)) {
            earliest(best, Met(file = pr.file, line = pr.line, col = pr.col, text = "{unit.pp.names[pr.pname]}:{int(pr.pline)}:{pr.col}: {why}"))
        }
    }
    for (k in range(marks.packs, length(unit.pp.packs))) {
        let pk & = unsafe(unit.pp.packs[k])
        earliest(best, met_at(unit, pk.file, pk.line, pk.col, "the pragma '#pragma pack' is not parsed (the record layout does not read it yet)"))
    }
    marks = ReadMarks(diags = length(unit.pp.diags), lexer = length(unit.pp.lx.diags), pragmas = length(unit.pp.pragmas), packs = length(unit.pp.packs))
    unit.err = best.text
    return !empty(unit.err)
}

//! The index in the unit's tokens of the preprocessor's token `emitted` (its count of the tokens
//! before it, as a pragma's `emitted` gives it): past one more for each `::` split before it.
def c_token_index(unit : CUnit; emitted : int) : int {
    var at = emitted
    for (k in unit.splits) {
        at += k < emitted ? 1 : 0
    }
    return at
}

//! Read the unit's tokens to its end, as the preprocessor hands them out: identifiers become
//! keywords by their symbol, pp-numbers integer or floating constants. False after the first
//! error, the preprocessor's or a token's, which `unit.err` holds with its place; the tokens end
//! with EOF either way.
[arch(at="ARCHITECTURE_PARSER.md#c-tokens")]
def c_tokens_read(var unit : CUnit) : bool {
    var marks : ReadMarks
    while (true) {
        let more = pp_next_token(unit.pp)
        break if (diagnosed(unit, marks) || !more)
        let pk = unit.pp.tok.tok.kind
        let kind = c_kind_of(unit)
        if (pk == int(PpTok.COLONCOLON)) {
            var colon = kept(unit, int(CTok.COLON))
            colon.len = 1
            unit.splits |> push(unit.pp.emitted - 1)
            unit.toks |> push(colon) // nolint:STYLE012 - the colons append to the unit's tokens
            unit.toks |> push(CToken(kind = colon.kind, sym = -1, spelled = colon.spelled, buffer = colon.buffer, at = colon.at + 1, len = 1,
                                     file = colon.file, line = colon.line, col = colon.expanded ? colon.col : colon.col + 1, expanded = colon.expanded))
            continue
        } elif (kind == int(CTok.EOF)) {
            let what = pk == int(PpTok.PP_NUMBER) ? "invalid numeric constant" : pk == int(PpTok.IDENTIFIER) ? "invalid universal character name in" : "stray"
            let at = kept(unit, kind)
            unit.err = "{c_file_name(unit, at.file)}:{at.line}:{at.col}: {what} '{pp_token_spelling(unit.pp)}'"
            break
        }
        unit.toks |> push(kept(unit, kind))
    }
    var end = CToken(kind = int(CTok.EOF), sym = -1, file = 0, line = 1, col = 1)
    if (!empty(unit.toks)) {
        let last = unit.toks[length(unit.toks) - 1]
        end.file = last.file
        end.line = last.line
        end.col = last.col + last.len
        if (last.expanded) {
            // after the call's `)`, the last token the main file's lexer read
            end.file = unit.pp.state.pname
            end.line = int(uint(unit.pp.lx.tok.line) + unit.pp.state.line_delta)
            end.col = unit.pp.lx.tok.col + unit.pp.lx.tok.len
        }
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

//! `c_tokens_expand_open` and `c_tokens_read`.
def c_tokens_expand(var unit : CUnit; var provider : PpFileProvider?; main : string; predefines : array<string>;
                    search : array<string>; epoch : int64 = -1l) : bool {
    c_tokens_expand_open(unit, provider, main, predefines, search, epoch)
    return c_tokens_read(unit)
}
