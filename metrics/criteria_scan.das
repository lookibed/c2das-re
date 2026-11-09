options gen2

module criteria_scan public

require strings
require math
require daslib/strings_boost

//! The text scanners of the readability criteria (`metrics/ARCHITECTURE_CRITERIA.md`): one lexer
//! for C and das text, the facts a C source and an emitted module hold, and the raw counts of one
//! converted input from both sides.

//! A token kind.
enum TokKind {
    ident
    number
    str
    chr
    punct
}

//! One token: its kind, its spelling (a string's or a character's whole literal) and its line.
struct Tok {
    kind : TokKind
    text : string
    line : int
}

//! A text lexed: its tokens, and per line (from 0) its comment text, normalized, whether it is a
//! C preprocessor directive, and its length in bytes.
struct Lexed {
    toks : array<Tok>
    comments : array<string>
    directive : array<bool>
    lengths : array<int>
}

let private PUNCT3 <- ["<<=", ">>=", "||=", "&&=", "^^=", "..."]
let private PUNCT2 <- ["<<", ">>", "<=", ">=", "==", "!=", "&&", "||", "^^", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "->", "::", "++", "--", "=>", "@@", "##"]

def private is_ident_start(c : int) : bool => is_alpha(c) || c == '_'
def private is_ident_char(c : int) : bool => is_alnum(c) || c == '_'

// a comment's text on one line: whitespace collapsed, the decoration of `/** ... */` lines gone
def private normalized_comment(text : string) : string {
    let words <- [for (w in split(replace(replace(text, "\t", " "), "\r", " "), " ")); w; where !empty(w)]
    let joined = join(words, " ")
    var first = 0
    var last = 0
    peek_data(joined) $(b) {
        last = length(b)
        while (first < last && (int(b[first]) == '*' || int(b[first]) == '/' || int(b[first]) == ' ')) {
            first++
        }
        while (last > first && (int(b[last - 1]) == '*' || int(b[last - 1]) == '/' || int(b[last - 1]) == ' ')) {
            last--
        }
    }
    return slice(joined, first, last)
}

// the length of the literal quoted by `quote` starting at `at`, its closing quote included
def private quoted_length(b : array<uint8> const implicit; at, quote : int) : int {
    let n = length(b)
    var i = at + 1
    while (i < n && int(b[i]) != quote && int(b[i]) != '\n') {
        i += int(b[i]) == '\\' && i + 1 < n ? 2 : 1
    }
    return min(i + 1, n) - at
}

// the length of the number starting at `at`: digits, letters, `.`, `_` and an exponent's sign
def private number_length(b : array<uint8> const implicit; at : int) : int {
    let n = length(b)
    var i = at
    while (i < n) {
        let c = int(b[i])
        let hex = at + 1 < n && int(b[at]) == '0' && (int(b[at + 1]) | 32) == 'x'
        let exponent_sign = (c == '+' || c == '-') && i > at && (int(b[i - 1]) | 32) == (hex ? 'p' : 'e')
        if (!(is_ident_char(c) || c == '.' || exponent_sign)) {
            break
        }
        i++
    }
    return i - at
}

// the punctuation token at `at`: the longest of the multi-character ones, else one character
def private punct_length(b : array<uint8> const implicit; at : int) : int {
    for (p in PUNCT3) {
        if (starts_with(b, at, p)) {
            return 3
        }
    }
    for (p in PUNCT2) {
        if (starts_with(b, at, p)) {
            return 2
        }
    }
    return 1
}

// the token starting at `at`: its length, its kind in `kind`
def private token_length(b : array<uint8> const implicit; at : int; var kind : TokKind&) : int {
    let c = int(b[at])
    let n = length(b)
    if (is_ident_start(c)) {
        var len = 0
        while (at + len < n && is_ident_char(int(b[at + len]))) {
            len++
        }
        kind = TokKind.ident
        return len
    } elif (is_number(c) || (c == '.' && at + 1 < n && is_number(int(b[at + 1])))) {
        kind = TokKind.number
        return number_length(b, at)
    } elif (c == '"' || c == '\'') {
        kind = c == '"' ? TokKind.str : TokKind.chr
        return quoted_length(b, at, c)
    }
    kind = TokKind.punct
    return punct_length(b, at)
}

//! `text` lexed as C (`c_mode`: a line whose first token is `#` is a directive, continued past a
//! trailing backslash) or as das; `//` and `/* */` comments, string and character literals with
//! their escapes.
def lex(text : string; c_mode : bool) : Lexed {
    var out : Lexed
    var spans : array<tuple<line : int; a : int; b : int>>
    var line = 0
    out.directive |> push(false)
    out.lengths |> push(0)
    var line_start = 0
    var line_has_token = false
    var in_directive = false
    peek_data(text) $(b) {
        let n = length(b)
        var i = 0
        while (i < n) {
            let c = int(b[i])
            if (c == '\n') {
                out.lengths[line] = i - line_start
                in_directive = in_directive && i > 0 && int(b[i - 1]) == '\\'
                line++
                line_start = i + 1
                line_has_token = false
                out.directive |> push(in_directive)
                out.lengths |> push(0)
                i++
            } elif (is_white_space(c)) {
                i++
            } elif (c == '/' && i + 1 < n && int(b[i + 1]) == '/') {
                var e = i
                while (e < n && int(b[e]) != '\n') {
                    e++
                }
                spans |> push((line = line, a = i + 2, b = e))
                i = e
            } elif (c == '/' && i + 1 < n && int(b[i + 1]) == '*') {
                var a = i + 2
                var e = a
                while (e < n && !(int(b[e]) == '*' && e + 1 < n && int(b[e + 1]) == '/')) {
                    if (int(b[e]) == '\n') {
                        spans |> push((line = line, a = a, b = e))
                        out.lengths[line] = e - line_start
                        line++
                        line_start = e + 1
                        out.directive |> push(in_directive)
                        out.lengths |> push(0)
                        a = e + 1
                    }
                    e++
                }
                spans |> push((line = line, a = a, b = e))
                i = min(e + 2, n)
            } else {
                var kind = TokKind.punct
                let len = token_length(b, i, kind)
                if (c_mode && c == '#' && !line_has_token) {
                    in_directive = true
                    out.directive[line] = true
                }
                line_has_token = true
                out.toks |> push(Tok(kind = kind, text = slice(b, i, i + len), line = line))
                i += len
            }
        }
        out.lengths[line] = n - line_start
        out.comments |> resize(line + 1)
        for (s in spans) {
            let piece = normalized_comment(slice(b, s.a, s.b))
            if (!empty(piece)) {
                out.comments[s.line] = empty(out.comments[s.line]) ? piece : "{out.comments[s.line]} {piece}"
            }
        }
    }
    out.comments |> resize(line + 1)
    return <- out
}

//! The tokens of `lx` grouped by line, a directive's lines empty when `skip_directives`.
def tokens_by_line(lx : Lexed; skip_directives : bool) : array<array<Tok>> {
    var lines : array<array<Tok>>
    lines |> resize(length(lx.lengths))
    for (t in lx.toks) {
        if (!(skip_directives && lx.directive[t.line])) {
            lines[t.line] |> push(t)
        }
    }
    return <- lines
}

//! A line's tokens as text, one space between tokens: the normalized code line.
def line_text(toks : array<Tok>) : string => join([for (t in toks); t.text], " ")

//! One function definition: its name and its first and last lines.
struct FnExtent {
    name : string
    first : int
    last : int
}

//! A C source's facts: comment lines and their texts, character literals by spelling, string
//! literals, `#include` lines and the quoted ones, `switch` statements, the names its `#define`s
//! give, identifier uses outside directives and the ones a `(` follows (a call or a function-like
//! macro's use), its function definitions and its code lines.
struct CSource {
    comment_lines : int
    comment_texts : array<string>
    chars : table<string; int>
    strings : int
    includes : int
    quoted_includes : array<string>
    switches : int
    defined : array<string>
    idents : table<string; int>
    calls : table<string; int>
    functions : array<FnExtent>
    code : array<array<Tok>>
}

// the index of the token closing the bracket opened at `at` (`(` or `{`), or the last index
def private closing(toks : array<Tok>; at : int) : int {
    let open = toks[at].text
    let close = open == "(" ? ")" : open == "[" ? "]" : "\}"
    var depth = 0
    for (i in range(at, length(toks))) {
        if (toks[i].text == open) {
            depth++
        } elif (toks[i].text == close) {
            depth--
            if (depth == 0) {
                return i
            }
        }
    }
    return length(toks) - 1
}

// the index of the token opening the bracket closed at `at`
def private opening(toks : array<Tok>; at, floor : int) : int {
    var depth = 0
    var i = at
    while (i >= floor) {
        if (toks[i].text == ")") {
            depth++
        } elif (toks[i].text == "(") {
            depth--
            if (depth == 0) {
                return i
            }
        }
        i--
    }
    return -1
}

let private RECORD_HEADS <- ["struct", "union", "enum", "typedef"]

// the function definitions of C code tokens: a `{` at file level after a head ending in `)` with
// no `=`, named by the identifier before that parenthesis
def private c_functions(code : array<Tok>) : array<FnExtent> {
    var fns : array<FnExtent>
    var head = 0
    var i = 0
    while (i < length(code)) {
        let t = code[i].text
        if (t == ";" || t == "\}") {
            head = i + 1
        } elif (t == "\{") {
            let close = closing(code, i)
            if (i > head && code[i - 1].text == ")" && !has_value(RECORD_HEADS, code[head].text)) {
                let open = opening(code, i - 1, head)
                let assigned = !empty([for (k in range(head, i)); k; where code[k].text == "="])
                if (open > head && code[open - 1].kind == TokKind.ident && !assigned) {
                    fns |> push(FnExtent(name = code[open - 1].text, first = code[open - 1].line, last = code[close].line))
                }
            }
            i = close
            head = close + 1
        }
        i++
    }
    return <- fns
}

// the branch after the directive on line `head` up to line `last` marked inactive when the
// preprocessor emitted none of its lines
def private close_branch(head, last : int; emitted : array<bool>; var inactive : array<bool>) {
    var live = false
    for (l in range(head + 1, last + 1)) {
        live = live || (l < length(emitted) && emitted[l])
    }
    if (!live) {
        for (l in range(head + 1, last + 1)) {
            inactive[l] = true
        }
    }
}

// the lines inside a conditional branch (`#if`, `#ifdef`, `#ifndef`, `#elif`, `#else`) none of
// whose lines the preprocessor emitted, nested branches included
def private inactive_lines(lx : Lexed; emitted : array<bool>) : array<bool> {
    var inactive : array<bool>
    inactive |> resize(length(lx.lengths))
    var heads : array<int>
    for (i, t in count(), lx.toks) {
        if (!(t.text == "#" && lx.directive[t.line] && i + 1 < length(lx.toks) && lx.toks[i + 1].line == t.line)) {
            continue
        }
        let what = lx.toks[i + 1].text
        if (what == "if" || what == "ifdef" || what == "ifndef") {
            heads |> push(t.line)
        } elif (!empty(heads) && (what == "elif" || what == "else" || what == "endif")) {
            close_branch(heads[length(heads) - 1], t.line - 1, emitted, inactive)
            heads |> pop()
            if (what != "endif") {
                heads |> push(t.line)
            }
        }
    }
    return <- inactive
}

//! The facts of one C source text; `emitted`, when not empty, marks by line (from 0) the lines the
//! preprocessor emitted, and a conditional branch none of whose lines it emitted is left out.
[arch(at="ARCHITECTURE_CRITERIA.md#constants")]
def scan_c(text : string; emitted : array<bool>) : CSource {
    var cs : CSource
    var lx <- lex(text, true)
    if (!empty(emitted)) {
        let inactive <- inactive_lines(lx, emitted)
        lx.toks <- [for (t in lx.toks); t; where !inactive[t.line] || lx.directive[t.line]]
        for (l in range(length(lx.comments))) {
            if (inactive[l]) {
                lx.comments[l] = ""
            }
        }
    }
    for (c in lx.comments) {
        if (!empty(c)) {
            cs.comment_lines++
            cs.comment_texts |> push(c)
        }
    }
    var code : array<Tok>
    for (i, t in count(), lx.toks) {
        if (lx.directive[t.line]) {
            if (t.text == "#" && i + 2 < length(lx.toks) && lx.toks[i + 1].line == t.line) {
                let what = lx.toks[i + 1].text
                if (what == "include") {
                    cs.includes++
                    if (lx.toks[i + 2].kind == TokKind.str) {
                        cs.quoted_includes |> push(replace(lx.toks[i + 2].text, "\"", ""))
                    }
                } elif (what == "define" && lx.toks[i + 2].kind == TokKind.ident) {
                    cs.defined |> push(lx.toks[i + 2].text)
                }
            }
            continue
        }
        code |> push(t)
        if (t.kind == TokKind.chr) {
            cs.chars[t.text]++
        } elif (t.kind == TokKind.str) {
            cs.strings++
        } elif (t.kind == TokKind.ident) {
            cs.idents[t.text]++
            if (t.text == "switch") {
                cs.switches++
            } elif (i + 1 < length(lx.toks) && lx.toks[i + 1].text == "(") {
                cs.calls[t.text]++
            }
        }
    }
    cs.functions <- c_functions(code)
    cs.code <- tokens_by_line(lx, true)
    return <- cs
}

//! An emitted module or cluster fragment: its stem (`lvm`, `llex_h` for `llex_h.das.inc`), its
//! tokens by line, its comments and line lengths, its `require` lines and its functions.
struct DasModule {
    stem : string
    fragment : bool
    code : array<array<Tok>>
    comments : array<string>
    lengths : array<int>
    requires : int
    functions : array<FnExtent>
}

//! The facts of one emitted das text named `stem`; `fragment` for a `.das.inc` fragment.
def scan_das(text, stem : string; fragment : bool) : DasModule {
    var dm = DasModule(stem = stem, fragment = fragment)
    let lx <- lex(text, false)
    dm.comments := lx.comments
    dm.lengths := lx.lengths
    dm.code <- tokens_by_line(lx, false)
    var open = -1
    var name = ""
    for (i, toks in count(), dm.code) {
        if (!empty(toks) && toks[0].text == "require") {
            dm.requires++
        }
        if (open < 0 && !empty(toks) && toks[0].text == "def" && toks[length(toks) - 1].text == "\{") {
            var inscope named <- [for (t in toks); t.text; where t.kind == TokKind.ident && t.text != "def" && t.text != "private" && t.text != "static"]
            if (!empty(named)) {
                open = i
                name = named[0]
            }
        } elif (open >= 0 && length(toks) == 1 && toks[0].text == "\}" && lx.lengths[i] == 1) {
            dm.functions |> push(FnExtent(name = name, first = open, last = i))
            open = -1
        }
    }
    return <- dm
}
