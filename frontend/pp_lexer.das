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

let private COMMENT_COND = 2

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
    condition("COMMENT", exclusive) {
        rule("\\*/") {
            comment_closed(lx)
            lx |> begin("INITIAL")
        }
        rule("[^*]+") {
        }
        rule("\\*") {
        }
    }
    rule("[ \\t\\v\\f\\r\\n]+") {
    }
    rule("//[^\\n]*") {
    }
    rule("/\\*") {
        comment_opened(lx)
        lx |> begin("COMMENT")
    }
    rule("(?:[a-zA-Z_$\\u00A8\\u00AA\\u00AD\\u00AF\\u00B2-\\u00B5\\u00B7-\\u00BA\\u00BC-\\u00BE\\u00C0-\\u00D6\\u00D8-\\u00F6\\u00F8-\\u00FF\\u0100-\\u02FF\\u0370-\\u167F\\u1681-\\u180D\\u180F-\\u1DBF\\u1E00-\\u1FFF\\u200B-\\u200D\\u202A-\\u202E\\u203F-\\u2040\\u2054\\u2060-\\u206F\\u2070-\\u20CF\\u2100-\\u218F\\u2460-\\u24FF\\u2776-\\u2793\\u2C00-\\u2DFF\\u2E80-\\u2FFF\\u3004-\\u3007\\u3021-\\u302F\\u3031-\\u303F\\u3040-\\uD7FF\\uF900-\\uFD3D\\uFD40-\\uFDCF\\uFDF0-\\uFE1F\\uFE30-\\uFE44\\uFE47-\\uFFFD\\U00010000-\\U0001FFFD\\U00020000-\\U0002FFFD\\U00030000-\\U0003FFFD\\U00040000-\\U0004FFFD\\U00050000-\\U0005FFFD\\U00060000-\\U0006FFFD\\U00070000-\\U0007FFFD\\U00080000-\\U0008FFFD\\U00090000-\\U0009FFFD\\U000A0000-\\U000AFFFD\\U000B0000-\\U000BFFFD\\U000C0000-\\U000CFFFD\\U000D0000-\\U000DFFFD\\U000E0000-\\U000EFFFD]|\\\\u[0-9a-fA-F]\{4\}|\\\\U[0-9a-fA-F]\{8\})(?:[a-zA-Z_$0-9\\u00A8\\u00AA\\u00AD\\u00AF\\u00B2-\\u00B5\\u00B7-\\u00BA\\u00BC-\\u00BE\\u00C0-\\u00D6\\u00D8-\\u00F6\\u00F8-\\u00FF\\u0100-\\u167F\\u1681-\\u180D\\u180F-\\u1FFF\\u200B-\\u200D\\u202A-\\u202E\\u203F-\\u2040\\u2054\\u2060-\\u206F\\u2070-\\u218F\\u2460-\\u24FF\\u2776-\\u2793\\u2C00-\\u2DFF\\u2E80-\\u2FFF\\u3004-\\u3007\\u3021-\\u302F\\u3031-\\u303F\\u3040-\\uD7FF\\uF900-\\uFD3D\\uFD40-\\uFDCF\\uFDF0-\\uFE44\\uFE47-\\uFFFD\\U00010000-\\U0001FFFD\\U00020000-\\U0002FFFD\\U00030000-\\U0003FFFD\\U00040000-\\U0004FFFD\\U00050000-\\U0005FFFD\\U00060000-\\U0006FFFD\\U00070000-\\U0007FFFD\\U00080000-\\U0008FFFD\\U00090000-\\U0009FFFD\\U000A0000-\\U000AFFFD\\U000B0000-\\U000BFFFD\\U000C0000-\\U000CFFFD\\U000D0000-\\U000DFFFD\\U000E0000-\\U000EFFFD]|\\\\u[0-9a-fA-F]\{4\}|\\\\U[0-9a-fA-F]\{8\})*") {
        intern(lx)
        lx |> emit(PpTok.IDENTIFIER)
    }
    rule("\\.?[0-9](?:[0-9a-zA-Z_.\\u00A8\\u00AA\\u00AD\\u00AF\\u00B2-\\u00B5\\u00B7-\\u00BA\\u00BC-\\u00BE\\u00C0-\\u00D6\\u00D8-\\u00F6\\u00F8-\\u00FF\\u0100-\\u167F\\u1681-\\u180D\\u180F-\\u1FFF\\u200B-\\u200D\\u202A-\\u202E\\u203F-\\u2040\\u2054\\u2060-\\u206F\\u2070-\\u218F\\u2460-\\u24FF\\u2776-\\u2793\\u2C00-\\u2DFF\\u2E80-\\u2FFF\\u3004-\\u3007\\u3021-\\u302F\\u3031-\\u303F\\u3040-\\uD7FF\\uF900-\\uFD3D\\uFD40-\\uFDCF\\uFDF0-\\uFE44\\uFE47-\\uFFFD\\U00010000-\\U0001FFFD\\U00020000-\\U0002FFFD\\U00030000-\\U0003FFFD\\U00040000-\\U0004FFFD\\U00050000-\\U0005FFFD\\U00060000-\\U0006FFFD\\U00070000-\\U0007FFFD\\U00080000-\\U0008FFFD\\U00090000-\\U0009FFFD\\U000A0000-\\U000AFFFD\\U000B0000-\\U000BFFFD\\U000C0000-\\U000CFFFD\\U000D0000-\\U000DFFFD\\U000E0000-\\U000EFFFD]|\\\\u[0-9a-fA-F]\{4\}|\\\\U[0-9a-fA-F]\{8\}|[eEpP][+\\-])*") {
        lx |> emit(PpTok.PP_NUMBER)
    }
    rule("[uUL]?'(?:[^'\\\\\\n]|\\\\[^\\n])*'") {
        lx |> emit(PpTok.CHAR_CONSTANT)
    }
    rule("(?:u8|[uUL])?\"(?:[^\"\\\\\\n]|\\\\[^\\n])*\"") {
        lx |> emit(PpTok.STRING_LITERAL)
    }
    rule("[uUL]?'(?:[^'\\\\\\n]|\\\\[^\\n])*|(?:u8|[uUL])?\"(?:[^\"\\\\\\n]|\\\\[^\\n])*") {
        lx |> emit(PpTok.OTHER)
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
        lx |> emit(PpTok.OTHER)
    }
    rule("[\\x80-\\xFF]") {
        lx |> emit(PpTok.INVALID_BYTE)
    }
}

//! the `/*` rule: the line the comment opens on taken off `prev_end_line`, for `comment_closed` to
//! add the line it closes on
[arch(at="ARCHITECTURE.md#pp-flags")]
def private comment_opened(var lx : FlexLexer) {
    lx.prev_end_line -= lx.tok.line
}

//! the `*/` rule: `prev_end_line` moved by the lines the comment spans, so the comment is one space
[arch(at="ARCHITECTURE.md#pp-flags")]
def private comment_closed(var lx : FlexLexer) {
    lx.prev_end_line += lx.tok.line
}

//! the length of the line splice whose backslash is at `at` - the backslash, horizontal blanks,
//! then a newline (`\n` or `\r\n`) - or 0 when none is there; blanks between the two are clang's and
//! gcc's extension
def private splice_length(bytes : array<uint8>; at, len : int) : int {
    var i = at + 1
    while (i < len && (bytes[i] == ' 'u8 || bytes[i] == '\t'u8 || bytes[i] == '\f'u8 || bytes[i] == '\v'u8)) {
        i++
    }
    if (i < len && bytes[i] == '\r'u8 && i + 1 < len && bytes[i + 1] == '\n'u8) {
        i++
    }
    return i < len && bytes[i] == '\n'u8 ? i + 1 - at : 0
}

//! `bytes` with every line splice removed into a new buffer, and the table mapping it back to the
//! file; called only when `first` is the backslash of a splice
[arch(at="ARCHITECTURE.md#pp-phases")]
def private removed_splices(bytes : array<uint8>; len, first : int; var splices : array<PpSplice>) : array<uint8> {
    var out : array<uint8>
    out |> reserve(len + 1)
    var copied = 0
    var at = first
    while (at >= 0 && at < len) {
        let n = splice_length(bytes, at, len)
        if (n > 0) {
            for (i in range(copied, at)) {
                out |> push(bytes[i])
            }
            copied = at + n
            splices |> push(PpSplice(at = length(out), from = at, orig = copied))
        }
        at = find(bytes, '\\', at + 1)
    }
    for (i in range(copied, len)) {
        out |> push(bytes[i])
    }
    return <- out
}

//! the first line splice of `bytes[0 .. len)`: the offset of its backslash, or -1
def private first_splice(bytes : array<uint8>; len : int) : int {
    var at = find(bytes, '\\', 0)
    while (at >= 0 && at < len) {
        return at if (splice_length(bytes, at, len) > 0)
        at = find(bytes, '\\', at + 1)
    }
    return -1
}

def private has_bom(bytes : array<uint8>) : bool {
    return length(bytes) >= 3 && bytes[0] == 0xEFu8 && bytes[1] == 0xBBu8 && bytes[2] == 0xBFu8
}

//! Open the file `file` (an id the caller numbers) for lexing; `bytes` is the file as read, taken
//! over without a copy when it holds no line splice - one byte of spare capacity past its end (as
//! `pp_read_file` leaves) keeps the scanner's end zero from reallocating it. Translation phases 1
//! and 2 happen here: a UTF-8 byte order mark is skipped and the line splices are removed into a
//! working buffer. The interner and the diagnostics stay from the previous file.
[arch(at="ARCHITECTURE.md#pp-phases")]
def pp_open(var lx : PpLexer; var bytes : array<uint8>; file : int; name : string = "") {
    flex_open(lx.flex, "", name)
    lx.file = file
    lx.tok = PpToken(sym = -1)
    lx.applied = 0
    lx.splices |> clear()
    let len = length(bytes)
    let first = first_splice(bytes, len)
    if (first < 0) {
        lx.flex.bytes <- bytes
    } else {
        lx.flex.bytes <- removed_splices(bytes, len, first, lx.splices)
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

//! the diagnostic `what` at the current token
def private diagnose(var lx : PpLexer; what : string) {
    lx.diags |> push(PpDiag(file = lx.file, offset = lx.tok.offset, line = lx.tok.line, col = lx.tok.col, what = what))
}

//! Read the next token into `lx.tok`; false at the end of the file, `lx.tok.kind` then EOF.
[arch(at="ARCHITECTURE.md#pp-lexer")]
def pp_next(var lx : PpLexer) : bool {
    if (!pp_scan(lx.flex)) {
        if (lx.flex.cond == COMMENT_COND) {
            lx.tok.offset = lx.flex.len
            diagnose(lx, "unterminated /* comment")
            lx.flex.cond = 0
        }
        lx.tok.kind = int(PpTok.EOF)
        lx.tok.sym = -1
        return false
    }
    let t & = unsafe(lx.flex.tok)
    lx.tok.kind = t.kind
    lx.tok.file = lx.file
    lx.tok.sym = t.sym
    lx.tok.has_space = t.has_space
    lx.tok.at_bol = t.at_bol
    if (empty(lx.splices)) {
        lx.tok.offset = t.start
        lx.tok.len = t.len
        lx.tok.line = t.line
        lx.tok.col = t.col
    } else {
        placed(lx, t)
    }
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
    if (lx.flex.cond == HEADER_COND) {
        lx.flex.cond = 0
    }
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
