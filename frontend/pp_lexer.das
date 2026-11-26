options gen2
options indenting = 4

module pp_lexer public

require strings
require daslib/fio
require flex/flex_macro public

//! The kind of a preprocessing token (C11 6.4). A one-byte punctuator's kind is its byte; a digraph
//! has the kind of the punctuator it spells (`<:` is LBRACKET).
enum PpTok {
    EOF = 0
    IDENTIFIER = 256
    PP_NUMBER = 257
    CHAR_CONSTANT = 258
    STRING_LITERAL = 259
    HEADER_NAME = 260
    OTHER = 261
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
    HASHHASH = 284
    INVALID_BYTE = 285      //!< the scanner's kind of a byte that starts no UTF-8 character; `pp_next` hands it out as OTHER
    COLONCOLON = 286
    EXCLAIM = 33
    HASH = 35
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
}

//! One preprocessing token, placed in its original file: `offset` and `len` are bytes of the file as
//! read, a line splice inside the token counted in `len`.
struct PpToken {
    kind : int
    file : int
    offset : int
    len : int
    line : int
    col : int
    sym : int           //!< the interned name of an IDENTIFIER; -1 for every other kind
    has_space : bool    //!< whitespace or a comment lies between the previous token and this one
    at_bol : bool       //!< the first token of its line, a comment counting as one space (C11 6.10p2)
}

//! A line splice removed in translation phase 2: its backslash is at `from` in the file, and the
//! working buffer's bytes from `at` on start at `orig`, the first byte after the removed newline.
struct PpSplice {
    at : int
    from : int
    orig : int
}

//! A malformed span the lexer met and took as tokens all the same, placed in the original file.
struct PpDiag {
    file : int
    offset : int
    line : int
    col : int
    what : string
}

//! The lexer over one file at a time: `pp_open` hands it the file's bytes, `pp_next` reads one token
//! into `tok`. Its interner `flex.syms` outlives a reopen, so a name has one symbol across files.
struct PpLexer {
    flex : FlexLexer
    tok : PpToken
    file : int
    splices : array<PpSplice>   //!< empty when the file holds no line splice: the scanner reads the file's own bytes
    applied : int               //!< the splices that lie before `tok`
    diags : array<PpDiag>
}

let private HEADER_COND = 1

//! the scanner of preprocessing tokens over a buffer past translation phase 2; a header name only in
//! the HEADER condition, which `pp_next_header_name` switches on for one token
[arch(at="ARCHITECTURE.md#pp-tokens"), flex(flags = true)]
def private pp_scan(var lx : FlexLexer) : bool {  // nolint:STYLE038 - a rule list is one function by construction
    condition("HEADER", inclusive) {
        rule("<[^>\\n]+>") {
            lx |> emit(PpTok.HEADER_NAME)
        }
        rule("\"[^\"\\n]*\"") {
            lx |> emit(PpTok.HEADER_NAME)
        }
    }
    rule("[ \\t\\v\\f\\r\\n\\x00]+") {
    }
    rule("//[^\\n]*") {
    }
    rule("/\\*") {
        skip_comment(lx)
    }
    rule("(?:[a-zA-Z_$\\u00A8\\u00AA\\u00AD\\u00AF\\u00B2-\\u00B5\\u00B7-\\u00BA\\u00BC-\\u00BE\\u00C0-\\u00D6\\u00D8-\\u00F6\\u00F8-\\u00FF\\u0100-\\u02FF\\u0370-\\u167F\\u1681-\\u180D\\u180F-\\u1DBF\\u1E00-\\u1FFF\\u200B-\\u200D\\u202A-\\u202E\\u203F-\\u2040\\u2054\\u2060-\\u206F\\u2070-\\u20CF\\u2100-\\u218F\\u2460-\\u24FF\\u2776-\\u2793\\u2C00-\\u2DFF\\u2E80-\\u2FFF\\u3004-\\u3007\\u3021-\\u302F\\u3031-\\u303F\\u3040-\\uD7FF\\uF900-\\uFD3D\\uFD40-\\uFDCF\\uFDF0-\\uFE1F\\uFE30-\\uFE44\\uFE47-\\uFFFD\\U00010000-\\U0001FFFD\\U00020000-\\U0002FFFD\\U00030000-\\U0003FFFD\\U00040000-\\U0004FFFD\\U00050000-\\U0005FFFD\\U00060000-\\U0006FFFD\\U00070000-\\U0007FFFD\\U00080000-\\U0008FFFD\\U00090000-\\U0009FFFD\\U000A0000-\\U000AFFFD\\U000B0000-\\U000BFFFD\\U000C0000-\\U000CFFFD\\U000D0000-\\U000DFFFD\\U000E0000-\\U000EFFFD]|\\\\u[0-9a-fA-F]\{4\}|\\\\U[0-9a-fA-F]\{8\})(?:[a-zA-Z_$0-9\\u00A8\\u00AA\\u00AD\\u00AF\\u00B2-\\u00B5\\u00B7-\\u00BA\\u00BC-\\u00BE\\u00C0-\\u00D6\\u00D8-\\u00F6\\u00F8-\\u00FF\\u0100-\\u167F\\u1681-\\u180D\\u180F-\\u1FFF\\u200B-\\u200D\\u202A-\\u202E\\u203F-\\u2040\\u2054\\u2060-\\u206F\\u2070-\\u218F\\u2460-\\u24FF\\u2776-\\u2793\\u2C00-\\u2DFF\\u2E80-\\u2FFF\\u3004-\\u3007\\u3021-\\u302F\\u3031-\\u303F\\u3040-\\uD7FF\\uF900-\\uFD3D\\uFD40-\\uFDCF\\uFDF0-\\uFE44\\uFE47-\\uFFFD\\U00010000-\\U0001FFFD\\U00020000-\\U0002FFFD\\U00030000-\\U0003FFFD\\U00040000-\\U0004FFFD\\U00050000-\\U0005FFFD\\U00060000-\\U0006FFFD\\U00070000-\\U0007FFFD\\U00080000-\\U0008FFFD\\U00090000-\\U0009FFFD\\U000A0000-\\U000AFFFD\\U000B0000-\\U000BFFFD\\U000C0000-\\U000CFFFD\\U000D0000-\\U000DFFFD\\U000E0000-\\U000EFFFD]|\\\\u[0-9a-fA-F]\{4\}|\\\\U[0-9a-fA-F]\{8\})*") {
        intern(lx)
        lx |> emit(PpTok.IDENTIFIER)
    }
    rule("\\.?[0-9](?:[0-9a-zA-Z_.\\u00A8\\u00AA\\u00AD\\u00AF\\u00B2-\\u00B5\\u00B7-\\u00BA\\u00BC-\\u00BE\\u00C0-\\u00D6\\u00D8-\\u00F6\\u00F8-\\u00FF\\u0100-\\u167F\\u1681-\\u180D\\u180F-\\u1FFF\\u200B-\\u200D\\u202A-\\u202E\\u203F-\\u2040\\u2054\\u2060-\\u206F\\u2070-\\u218F\\u2460-\\u24FF\\u2776-\\u2793\\u2C00-\\u2DFF\\u2E80-\\u2FFF\\u3004-\\u3007\\u3021-\\u302F\\u3031-\\u303F\\u3040-\\uD7FF\\uF900-\\uFD3D\\uFD40-\\uFDCF\\uFDF0-\\uFE44\\uFE47-\\uFFFD\\U00010000-\\U0001FFFD\\U00020000-\\U0002FFFD\\U00030000-\\U0003FFFD\\U00040000-\\U0004FFFD\\U00050000-\\U0005FFFD\\U00060000-\\U0006FFFD\\U00070000-\\U0007FFFD\\U00080000-\\U0008FFFD\\U00090000-\\U0009FFFD\\U000A0000-\\U000AFFFD\\U000B0000-\\U000BFFFD\\U000C0000-\\U000CFFFD\\U000D0000-\\U000DFFFD\\U000E0000-\\U000EFFFD]|\\\\u[0-9a-fA-F]\{4\}|\\\\U[0-9a-fA-F]\{8\}|[eEpP][+\\-])*") {
        lx |> emit(PpTok.PP_NUMBER)
    }
    rule("[uUL]?'(?:[^'\\\\\\n]|\\\\[^\\n])+'") {
        lx |> emit(PpTok.CHAR_CONSTANT)
    }
    rule("(?:u8|[uUL])?\"(?:[^\"\\\\\\n]|\\\\[^\\n])*\"") {
        lx |> emit(PpTok.STRING_LITERAL)
    }
    rule("[uUL]?'(?:[^'\\\\\\n]|\\\\[^\\n])*\\\\?|(?:u8|[uUL])?\"(?:[^\"\\\\\\n]|\\\\[^\\n])*\\\\?|[uUL]?''") {
        lx |> emit(PpTok.OTHER)
    }
    rule("(?:u8|[uUL])?R\"") {
        lx |> emit(raw_string(lx))
    }
    rule("\\.\\.\\.") {
        lx |> emit(PpTok.ELLIPSIS)
    }
    rule("->") {
        lx |> emit(PpTok.ARROW)
    }
    rule("\\+\\+") {
        lx |> emit(PpTok.INC)
    }
    rule("--") {
        lx |> emit(PpTok.DEC)
    }
    rule("<<") {
        lx |> emit(PpTok.SHL)
    }
    rule(">>") {
        lx |> emit(PpTok.SHR)
    }
    rule("<=") {
        lx |> emit(PpTok.LE)
    }
    rule(">=") {
        lx |> emit(PpTok.GE)
    }
    rule("==") {
        lx |> emit(PpTok.EQ)
    }
    rule("!=") {
        lx |> emit(PpTok.NE)
    }
    rule("&&") {
        lx |> emit(PpTok.AND_AND)
    }
    rule("\\|\\|") {
        lx |> emit(PpTok.OR_OR)
    }
    rule("\\*=") {
        lx |> emit(PpTok.MUL_ASSIGN)
    }
    rule("/=") {
        lx |> emit(PpTok.DIV_ASSIGN)
    }
    rule("%=") {
        lx |> emit(PpTok.MOD_ASSIGN)
    }
    rule("\\+=") {
        lx |> emit(PpTok.ADD_ASSIGN)
    }
    rule("-=") {
        lx |> emit(PpTok.SUB_ASSIGN)
    }
    rule("<<=") {
        lx |> emit(PpTok.SHL_ASSIGN)
    }
    rule(">>=") {
        lx |> emit(PpTok.SHR_ASSIGN)
    }
    rule("&=") {
        lx |> emit(PpTok.AND_ASSIGN)
    }
    rule("\\^=") {
        lx |> emit(PpTok.XOR_ASSIGN)
    }
    rule("\\|=") {
        lx |> emit(PpTok.OR_ASSIGN)
    }
    rule("::") {
        lx |> emit(PpTok.COLONCOLON)
    }
    rule("##|%:%:") {
        lx |> emit(PpTok.HASHHASH)
    }
    rule("<:") {
        lx |> emit(PpTok.LBRACKET)
    }
    rule(":>") {
        lx |> emit(PpTok.RBRACKET)
    }
    rule("<%") {
        lx |> emit(PpTok.LBRACE)
    }
    rule("%>") {
        lx |> emit(PpTok.RBRACE)
    }
    rule("%:") {
        lx |> emit(PpTok.HASH)
    }
    rule("[\\[\\]()\{\}.&*+\\-~!/%<>^|?:;=,#]") {
        lx |> emit(int(unsafe(lx.data[lx.tok.start])))
    }
    rule(".") {
        lx |> emit(utf8_checked(lx))
    }
    rule("[\\x80-\\xFF]") {
        lx |> emit(PpTok.INVALID_BYTE)
    }
}

//! the cursor moved on to `stop`, line and column following the newlines it passes
def private advance(var lx : FlexLexer; stop : int) {
    for (i in range(lx.pos, stop)) {
        if (unsafe(lx.data[i]) == '\n'u8) {
            lx.line++
            lx.col = 1
        } else {
            lx.col++
        }
    }
    lx.pos = stop
}

//! the `/*` rule: the comment skipped to its `*/`, `prev_end_line` moved by the lines it spans so
//! it is one space; with no `*/` the scanner stops at the file's end as failed, `tok` still the `/*`
[arch(at="ARCHITECTURE.md#pp-flags")]
def private skip_comment(var lx : FlexLexer) {
    let close = find(lx.bytes, "*/", lx.pos)
    if (close < 0) {
        lx.pos = lx.len
        lx.failed = true
        lx.err = "unterminated /* comment"
        return
    }
    let line = lx.line
    advance(lx, close + 2)
    lx.prev_end_line += lx.line - line
}

//! a raw string delimiter's character: a printable ASCII byte but a blank, `(`, `)` and `\\`
def private is_raw_delimiter_byte(b : int) : bool => b > ' ' && b < 127 && b != '(' && b != ')' && b != '\\'

//! the `R"` rule: the token run on to the end of its raw string - STRING_LITERAL past its `)delim"`,
//! OTHER past the next `"` when the delimiter is malformed or to the file's end when nothing closes it
[arch(at="ARCHITECTURE.md#pp-tokens")]
def private raw_string(var lx : FlexLexer) : int {
    let open = lx.pos
    var paren = open
    while (paren < lx.len && paren - open < 16 && is_raw_delimiter_byte(int(unsafe(lx.data[paren])))) {
        paren++
    }
    var kind = int(PpTok.OTHER)
    var stop = lx.len
    if (paren < lx.len && unsafe(lx.data[paren]) == '('u8) {
        let delim = paren - open
        var close = find(lx.bytes, ')', paren + 1)
        while (close >= 0 && close + delim < lx.len) {
            if (unsafe(lx.data[close + delim + 1]) == '"'u8 && same_bytes(lx, open, close + 1, delim)) {
                kind = int(PpTok.STRING_LITERAL)
                stop = close + delim + 2
                break
            }
            close = find(lx.bytes, ')', close + 1)
        }
    } else {
        let quote = find(lx.bytes, '"', open)
        stop = quote >= 0 && quote < lx.len ? quote + 1 : lx.len
    }
    advance(lx, stop)
    lx.tok.len = stop - lx.tok.start
    return kind
}

//! the `count` bytes at `a` equal those at `b`
def private same_bytes(lx : FlexLexer; a, b, count : int) : bool {
    for (i in range(count)) {
        return false if (unsafe(lx.data[a + i]) != unsafe(lx.data[b + i]))
    }
    return true
}

//! the `.` rule: OTHER, or INVALID_BYTE with the token cut back to its first byte when that byte and
//! the next make a surrogate, an overlong form or a code point past U+10FFFF, which `.` admits
[arch(at="ARCHITECTURE.md#pp-tokens")]
def private utf8_checked(var lx : FlexLexer) : int {
    let lead = int(unsafe(lx.data[lx.tok.start]))
    return int(PpTok.OTHER) if (lead < 0xE0)
    let next = int(unsafe(lx.data[lx.tok.start + 1]))
    let valid = ((lead != 0xE0 || next >= 0xA0) && (lead != 0xED || next < 0xA0)
        && (lead != 0xF0 || next >= 0x90) && (lead != 0xF4 || next < 0x90))
    return int(PpTok.OTHER) if (valid)
    lx.pos = lx.tok.start + 1
    lx.col = lx.tok.col + 1
    lx.tok.len = 1
    return int(PpTok.INVALID_BYTE)
}

//! the length of the line splice whose backslash is at `at` - the backslash, horizontal blanks,
//! then a newline (`\n`, `\r\n` or a lone `\r`) - or 0 when none is there; blanks between the two
//! are clang's and gcc's extension
def private splice_length(bytes : array<uint8>; at, len : int) : int {
    var i = at + 1
    while (i < len && (bytes[i] == ' 'u8 || bytes[i] == '\t'u8 || bytes[i] == '\f'u8 || bytes[i] == '\v'u8)) {
        i++
    }
    if (i < len && bytes[i] == '\r'u8) {
        return (i + 1 < len && bytes[i + 1] == '\n'u8 ? i + 2 : i + 1) - at
    }
    return i < len && bytes[i] == '\n'u8 ? i + 1 - at : 0
}

//! the byte at `at` is a `\r` no `\n` follows, a newline to clang
def private is_lone_cr(bytes : array<uint8>; at, len : int) : bool =>
    bytes[at] == '\r'u8 && (at + 1 >= len || bytes[at + 1] != '\n'u8)

//! `bytes` past translation phases 1 and 2 in a new buffer - every line splice removed, every lone
//! `\r` a `\n` - and the table mapping it back to the file; `first` is the first byte they change
[arch(at="ARCHITECTURE.md#pp-phases")]
def private rewritten(bytes : array<uint8>; len, first : int; var splices : array<PpSplice>) : array<uint8> {
    var out : array<uint8>
    out |> reserve(len + 1)
    for (i in range(first)) {
        out |> push(bytes[i])
    }
    var at = first
    while (at < len) {
        let n = bytes[at] == '\\'u8 ? splice_length(bytes, at, len) : 0
        if (n > 0) {
            splices |> push(PpSplice(at = length(out), from = at, orig = at + n))
            at += n
        } else {
            out |> push(is_lone_cr(bytes, at, len) ? '\n'u8 : bytes[at])
            at++
        }
    }
    return <- out
}

//! the first byte of `bytes[0 .. len)` translation phases 1 and 2 change - the backslash of a line
//! splice or a lone `\r` - or -1 when they change none
def private first_rewrite(bytes : array<uint8>; len : int) : int {
    var first = -1
    var at = find(bytes, '\\', 0)
    while (at >= 0 && at < len) {
        if (splice_length(bytes, at, len) > 0) {
            first = at
            break
        }
        at = find(bytes, '\\', at + 1)
    }
    at = find(bytes, '\r', 0)
    while (at >= 0 && at < len && (first < 0 || at < first)) {
        return at if (is_lone_cr(bytes, at, len))
        at = find(bytes, '\r', at + 1)
    }
    return first
}

def private has_bom(bytes : array<uint8>) : bool =>
    length(bytes) >= 3 && bytes[0] == 0xEFu8 && bytes[1] == 0xBBu8 && bytes[2] == 0xBFu8

//! Open the file `file` (an id the caller numbers) for lexing; `bytes` is the file as read, taken
//! over without a copy when it holds no line splice and no lone `\r` - one byte of spare capacity past its end (as
//! `pp_read_file` leaves) keeps the scanner's end zero from reallocating it. Translation phases 1
//! and 2 happen here: a UTF-8 byte order mark is skipped and the line splices are removed into a
//! working buffer, a lone `\r` turned into the newline it is. The interner and the diagnostics stay
//! from the previous file.
[arch(at="ARCHITECTURE.md#pp-phases")]
def pp_open(var lx : PpLexer; var bytes : array<uint8>; file : int; name : string = "") {
    flex_open(lx.flex, "", name)
    lx.file = file
    lx.tok = PpToken(sym = -1)
    lx.applied = 0
    lx.splices |> clear()
    let len = length(bytes)
    let first = first_rewrite(bytes, len)
    if (first < 0) {
        lx.flex.bytes <- bytes
    } else {
        lx.flex.bytes <- rewritten(bytes, len, first, lx.splices)
    }
    lx.flex.len = length(lx.flex.bytes)
    lx.flex.bytes |> push(0u8)
    lx.flex.data = unsafe(addr(lx.flex.bytes[0]))
    if (has_bom(lx.flex.bytes)) {
        lx.flex.pos = 3
        lx.flex.col = 4
        lx.flex.prev_end = 3
    }
}

//! `pp_open` over the bytes of `text`, copied once.
def pp_open_text(var lx : PpLexer; text : string; file : int; name : string = "") {
    var bytes : array<uint8>
    bytes |> reserve(length(text) + 1)
    peek_data(text) $(chars) {
        for (c in chars) {
            bytes |> push(c)
        }
    }
    pp_open(lx, bytes, file, name)
}

//! The bytes of the file at `path`, with the spare byte `pp_open` wants; false when it cannot be read.
def pp_read_file(path : string; var bytes : array<uint8>) : bool {
    var ok = false
    fopen(path, "rb") $(f) {
        return if (f == null)
        let size = int(fstat(f).size)
        bytes |> reserve(size + 1)
        bytes |> resize(size)
        ok = size == 0 || fread(f, bytes) == size
    }
    return ok
}

//! the original offset, line and column of the working-buffer token `t`, and its length in the file;
//! a token right after a splice starts at that splice's backslash, as clang places it
[arch(at="ARCHITECTURE.md#pp-phases")]
def private placed(var lx : PpLexer; t : FlexToken) {
    let count = length(lx.splices)
    while (lx.applied < count && lx.splices[lx.applied].at < t.start) {
        lx.applied++
    }
    var end_k = lx.applied
    let stop = t.start + t.len
    while (end_k < count && lx.splices[end_k].at < stop) {
        end_k++
    }
    let k = lx.applied
    let at_splice = k < count && lx.splices[k].at == t.start
    let shift = k > 0 ? lx.splices[k - 1].orig - lx.splices[k - 1].at : 0
    lx.tok.offset = at_splice ? lx.splices[k].from : t.start + shift
    lx.tok.len = stop + (end_k > 0 ? lx.splices[end_k - 1].orig - lx.splices[end_k - 1].at : 0) - lx.tok.offset
    lx.tok.line = t.line + k
    let line_start = t.start - (t.col - 1)
    lx.tok.col = k > 0 && lx.splices[k - 1].at >= line_start ? lx.tok.offset - lx.splices[k - 1].orig + 1 : t.col
}

//! `lx.tok` placed where the scanner's token `t` lies in the file
def private place(var lx : PpLexer; t : FlexToken) {
    if (empty(lx.splices)) {
        lx.tok.offset = t.start
        lx.tok.len = t.len
        lx.tok.line = t.line
        lx.tok.col = t.col
    } else {
        placed(lx, t)
    }
}

//! the diagnostic `what` at the current token
def private diagnose(var lx : PpLexer; what : string) {
    lx.diags |> push(PpDiag(file = lx.file, offset = lx.tok.offset, line = lx.tok.line, col = lx.tok.col, what = what))
}

//! Read the next token into `lx.tok`; false at the end of the file, `lx.tok.kind` then EOF.
[arch(at="ARCHITECTURE.md#pp-lexer")]
def pp_next(var lx : PpLexer) : bool {
    let t & = unsafe(lx.flex.tok)
    if (!pp_scan(lx.flex)) {
        if (lx.flex.failed) {
            place(lx, t)
            diagnose(lx, lx.flex.err)
            lx.flex.failed = false
        }
        lx.tok.kind = int(PpTok.EOF)
        lx.tok.sym = -1
        return false
    }
    lx.tok.kind = t.kind
    lx.tok.file = lx.file
    lx.tok.sym = t.sym
    lx.tok.has_space = t.has_space
    lx.tok.at_bol = t.at_bol
    place(lx, t)
    if (t.kind == int(PpTok.INVALID_BYTE)) {
        lx.tok.kind = int(PpTok.OTHER)
        diagnose(lx, "invalid UTF-8: byte {int(lx.flex.bytes[t.start])}")
    }
    return true
}

//! `pp_next` with a header name allowed (C11 6.4.7): `<...>` or `"..."` is one HEADER_NAME token;
//! PP.2 calls it for the token after `#include`.
[arch(at="ARCHITECTURE.md#pp-lexer")]
def pp_next_header_name(var lx : PpLexer) : bool {
    lx.flex.cond = HEADER_COND
    let got = pp_next(lx)
    lx.flex.cond = 0
    return got
}

//! The current token's bytes, line splices removed: a new string on each call.
def pp_spelling(lx : PpLexer) : string {
    let t & = unsafe(lx.flex.tok)
    return slice(lx.flex.bytes, t.start, t.start + t.len)
}

//! The current token's bytes, line splices removed, equal `s`; nothing allocated.
def pp_spelling_is(lx : PpLexer; s : string) : bool => text_is(lx.flex, s)

//! The name of symbol `sym`, built on the first call and kept.
def pp_symbol_text(var lx : PpLexer; sym : int) : string => symbol_text(lx.flex.syms, sym)
