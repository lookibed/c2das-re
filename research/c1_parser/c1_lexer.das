options gen2
options indenting = 4

module c1_lexer shared public

// The probe's one token source: preprocessed C text (`clang -E` output) into `Source.toks`. Line
// markers (`# 12 "file.c" 1`) set the file and line the next line's tokens carry; `#pragma` and
// `#ident` lines are skipped. A word is interned to its symbol, a keyword (`KEYWORDS`, GNU alternates
// included) lexes as its kind, every other word as IDENTIFIER: the typedef-name decision is each
// parser's own. Nothing is allocated per token but the token's slot in the array.

require strings
require c1_ast public

def private is_ident_start(c : int) : bool => (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || c == '$'

def private is_ident_char(c : int) : bool => is_ident_start(c) || (c >= '0' && c <= '9')

def private is_digit(c : int) : bool => c >= '0' && c <= '9'

//! The kind and length of the punctuator at `at`, (0, 0) when none starts there.
def private punctuator(bytes : array<uint8>; at : int) : int2 {
    let c = int(bytes[at])
    let c1 = int(bytes[at + 1])
    let c2 = int(bytes[at + 2])
    if (c == '-') {
        return c1 == '>' ? int2(int(TK.ARROW), 2) : c1 == '-' ? int2(int(TK.DEC), 2) : c1 == '=' ? int2(int(TK.SUB_ASSIGN), 2) : int2(c, 1)
    } elif (c == '+') {
        return c1 == '+' ? int2(int(TK.INC), 2) : c1 == '=' ? int2(int(TK.ADD_ASSIGN), 2) : int2(c, 1)
    } elif (c == '<') {
        if (c1 == '<') {
            return c2 == '=' ? int2(int(TK.SHL_ASSIGN), 3) : int2(int(TK.SHL), 2)
        }
        return c1 == '=' ? int2(int(TK.LE), 2) : int2(c, 1)
    } elif (c == '>') {
        if (c1 == '>') {
            return c2 == '=' ? int2(int(TK.SHR_ASSIGN), 3) : int2(int(TK.SHR), 2)
        }
        return c1 == '=' ? int2(int(TK.GE), 2) : int2(c, 1)
    } elif (c == '=') {
        return c1 == '=' ? int2(int(TK.EQ), 2) : int2(c, 1)
    } elif (c == '!') {
        return c1 == '=' ? int2(int(TK.NE), 2) : int2(c, 1)
    } elif (c == '&') {
        return c1 == '&' ? int2(int(TK.ANDAND), 2) : c1 == '=' ? int2(int(TK.AND_ASSIGN), 2) : int2(c, 1)
    } elif (c == '|') {
        return c1 == '|' ? int2(int(TK.OROR), 2) : c1 == '=' ? int2(int(TK.OR_ASSIGN), 2) : int2(c, 1)
    } elif (c == '*') {
        return c1 == '=' ? int2(int(TK.MUL_ASSIGN), 2) : int2(c, 1)
    } elif (c == '/') {
        return c1 == '=' ? int2(int(TK.DIV_ASSIGN), 2) : int2(c, 1)
    } elif (c == '%') {
        return c1 == '=' ? int2(int(TK.MOD_ASSIGN), 2) : int2(c, 1)
    } elif (c == '^') {
        return c1 == '=' ? int2(int(TK.XOR_ASSIGN), 2) : int2(c, 1)
    } elif (c == '.') {
        return c1 == '.' && c2 == '.' ? int2(int(TK.ELLIPSIS), 3) : int2(c, 1)
    } elif (c == '(' || c == ')' || c == '[' || c == ']' || c == '{' || c == '}' || c == ',' || c == ';' || c == ':' || c == '?' || c == '~') {
        return int2(c, 1)
    }
    return int2(0, 0)
}

//! The end of the quoted literal whose opening quote `q` is at `at`, -1 when the line ends first.
def private quoted_end(bytes : array<uint8>; at, q : int) : int {
    var i = at + 1
    while (true) {
        let c = int(bytes[i])
        if (c == q) {
            return i + 1
        } elif (c == '\\') {
            i += 2
        } elif (c == '\n' || c == 0) {
            return -1
        } else {
            i++
        }
    }
    return -1
}

//! The end of the pp-number at `at` and whether it is a floating constant.
def private number_end(bytes : array<uint8>; at : int) : int2 {
    let hex = int(bytes[at]) == '0' && (int(bytes[at + 1]) == 'x' || int(bytes[at + 1]) == 'X')
    var is_float = false
    var i = at
    while (true) {
        let c = int(bytes[i])
        if ((c == '+' || c == '-') && i > at) {
            let e = int(bytes[i - 1])
            if ((!hex && (e == 'e' || e == 'E')) || (hex && (e == 'p' || e == 'P'))) {
                i++
                continue
            }
            break
        }
        if (c == '.') {
            is_float = true
        } elif (!hex && (c == 'e' || c == 'E')) {
            is_float = true
        } elif (hex && (c == 'p' || c == 'P')) {
            is_float = true
        } elif (!is_ident_char(c)) {
            break
        }
        i++
    }
    return int2(i, is_float ? 1 : 0)
}

//! The file id of the name `name`, added to `src.files` on first sight.
def private file_id(var src : Source; var ids : table<string; int>; name : string) : int {
    var id = -1
    ids |> get(name) $(v) {
        id = v
    }
    if (id < 0) {
        id = length(src.files)
        src.files |> push(name)
        ids[name] = id
    }
    return id
}

//! Lex the preprocessed text `text` named `name` into `src`; on a byte no token starts with,
//! `src.err` names it and the tokens stop there.
def lex(var src : Source; text : string; name : string) {
    src.bytes <- to_bytes(text)
    let n = length(src.bytes)
    src.bytes |> push(0u8)
    src.bytes |> push(0u8)
    src.bytes |> push(0u8)
    src.names <- keyword_interner()
    src.toks |> reserve(n / 4)
    var ids : table<string; int>
    var file = file_id(src, ids, name)
    let nkw = length(KEYWORDS)
    var line = 1
    var line_start = 0
    var at_bol = true
    var i = 0
    while (i < n) {
        let c = int(src.bytes[i])
        if (c == '\n') {
            i++
            line++
            line_start = i
            at_bol = true
            continue
        }
        if (c == ' ' || c == '\t' || c == '\r' || c == '\f' || c == '\v') {
            i++
            continue
        }
        if (c == '#' && at_bol) {
            // a line marker `# N "file" flags`, or a directive the parser does not read
            var j = i + 1
            while (int(src.bytes[j]) == ' ') {
                j++
            }
            var eol = j
            while (eol < n && int(src.bytes[eol]) != '\n') {
                eol++
            }
            if (is_digit(int(src.bytes[j]))) {
                var num = 0
                while (is_digit(int(src.bytes[j]))) {
                    num = num * 10 + int(src.bytes[j]) - '0'
                    j++
                }
                while (int(src.bytes[j]) == ' ') {
                    j++
                }
                if (int(src.bytes[j]) == '"') {
                    let close = quoted_end(src.bytes, j, '"')
                    if (close > 0) {
                        let fname = build_string() $(var w) {
                            for (k in range(j + 1, close - 1)) {
                                w |> write_char(int(src.bytes[k]))
                            }
                        }
                        file = file_id(src, ids, fname)
                    }
                }
                // the marker names the line after it
                line = num - 1
            }
            i = eol
            continue
        }
        at_bol = false
        let col = i - line_start + 1
        if (is_ident_start(c)) {
            var j = i + 1
            while (is_ident_char(int(src.bytes[j]))) {
                j++
            }
            let q = int(src.bytes[j])
            let is_prefix = (q == '"' || q == '\'') && ((j - i == 1 && (c == 'L' || c == 'u' || c == 'U')) || (j - i == 2 && c == 'u' && int(src.bytes[i + 1]) == '8'))
            if (!is_prefix) {
                let sym = intern(src.names, src.bytes, i, j - i)
                let kind = sym < nkw ? int(KEYWORD_KINDS[sym]) : int(TK.IDENTIFIER)
                src.toks |> push(Tok(kind = kind, start = i, len = j - i, line = line, col = col, file = file, sym = sym))
                i = j
                continue
            }
            let close = quoted_end(src.bytes, j, q)
            if (close < 0) {
                src.err = "{src.files[file]}:{line}:{col}: unterminated literal"
                return
            }
            src.toks |> push(Tok(kind = q == '"' ? int(TK.STRING_LITERAL) : int(TK.C_CONSTANT), start = i, len = close - i, line = line, col = col, file = file, sym = -1))
            i = close
            continue
        }
        if (is_digit(c) || (c == '.' && is_digit(int(src.bytes[i + 1])))) {
            let e = number_end(src.bytes, i)
            src.toks |> push(Tok(kind = e.y == 1 ? int(TK.F_CONSTANT) : int(TK.I_CONSTANT), start = i, len = e.x - i, line = line, col = col, file = file, sym = -1))
            i = e.x
            continue
        }
        if (c == '"' || c == '\'') {
            let close = quoted_end(src.bytes, i, c)
            if (close < 0) {
                src.err = "{src.files[file]}:{line}:{col}: unterminated literal"
                return
            }
            src.toks |> push(Tok(kind = c == '"' ? int(TK.STRING_LITERAL) : int(TK.C_CONSTANT), start = i, len = close - i, line = line, col = col, file = file, sym = -1))
            i = close
            continue
        }
        let p = punctuator(src.bytes, i)
        if (p.y == 0) {
            src.err = "{src.files[file]}:{line}:{col}: stray '{to_char(c)}' in program"
            return
        }
        src.toks |> push(Tok(kind = p.x, start = i, len = p.y, line = line, col = col, file = file, sym = -1))
        i += p.y
    }
    // the end-of-input token carries the last location, so an error at the end has one
    src.toks |> push(Tok(kind = int(TK.EOF), start = n, len = 0, line = line, col = n - line_start + 1, file = file, sym = -1))
}
