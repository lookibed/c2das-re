options gen2

module macro_sites public

require strings
require math
require daslib/strings_boost
require daslib/fio
require daslib/json_boost
require cir

//! The function-like macro expansions of a clang JSON dump, found by the spelling of their nodes
//! against the `#define` text (`ARCHITECTURE_DUMPER.md#fn-macros`): which node is a whole
//! expansion of which macro, and which nodes are copies of which argument.

let private TOK_IDENT = 0
let private TOK_NUMBER = 1
let private TOK_QUOTED = 2
let private TOK_PUNCT = 3

let private PUNCT3 <- {"<<=", ">>=", "..."}
let private PUNCT2 <- {"++", "--", "->", "<<", ">>", "<=", ">=", "==", "!=", "&&", "||", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "##"}

// the nodes a dump wraps around an operand with the operand's own range
let private WRAPPER_KINDS <- {"ImplicitCastExpr", "ConstantExpr"}

// nesting deeper than this resolves nothing: a macro body is never that deep, a cycle would be
let private MAX_DEPTH = 64

//! One preprocessing token of a file's text: its bytes `[at, stop)`, its kind, and its spelling for
//! an identifier or a punctuator.
struct MTok {
    at : int
    stop : int
    kind : int
    word : string
}

//! A `#define` libclang processed: `file` canonical, `given_file` as clang names it, `at` the
//! offset of the macro's name; the rest is read from the text on first use (`parsed` 1, or -1 for
//! a macro this pass does not follow: variadic, `#` or `##` in the body).
struct MacroDef {
    name : string
    file : string
    given_file : string
    line : int
    at : int
    fn_like : bool
    parsed : int
    params : array<string>
    body : array<MTok>
    text : string
    uses : array<int>
    uses_state : int
    // the parameters in the order the full expansion holds their tokens (`seq_state` 2), through
    // the macros the body calls; -1 when a call goes through a macro this pass does not follow
    seq : array<int>
    seq_state : int
    cir_index : int = -1
}

// a token range `[lo, hi)` of a macro's body (`src` its index) or of the outermost call's text
// (`src` -1), whose parameters resolve in context `ctx` (-1: none)
struct private MSpan {
    src : int
    lo : int
    hi : int
    ctx : int
}

// one expansion being resolved: the macro and its arguments' spans
struct private MCtx {
    mac : int
    args : array<MSpan>
    parent : int
}

// a byte of a file: where a token of an expansion is spelled; `at` -1 for none
struct private SpellPos {
    file : string
    at : int
}

// the calls a body or an argument writes: a macro and the token ranges of its arguments
struct private MCall {
    mac : int
    args : array<MSpan>
}

//! What libclang's preprocessing record gives (`defs`, `expansion_at` keyed `file:offset` of the
//! expansion's name) and what the pass finds: the marks on JSON nodes by address and the C-IR
//! `macros` table.
struct MacroIndex {
    defs : array<MacroDef>
    def_at : table<string; int>
    by_name : table<string; array<int>>
    expansion_at : table<string; int>
    expansion_offsets : table<int64>
    // the function-like macros of system headers, by name: never marked, and a body calling one is
    // followed no further
    system_fn : table<string>
    texts : table<string; string>
    fn_marks : table<uint64; array<CirMacroUse>>
    arg_marks : table<uint64; array<CirMacroArg>>
    macros : array<CirMacro>
    sites : int
    // per site id: the canonical file and the offset of its outermost call's name
    site_places : array<tuple<file : string; at : int>>
    // per outermost expansion: its call's tokens and file, the contexts, the nodes each macro took
    site_toks : array<MTok>
    site_file : string
    ctxs : array<MCtx>
    claimed : table<string>
    done : table<string>
}

//! The index of the definition libclang names at canonical `file`, offset `at`, added when new.
def macro_def_index(var ix : MacroIndex; name, file, given_file : string; line, at : int; fn_like : bool) : int {
    let key = "{file}:{at}"
    let known = ix.def_at?[key] ?? -1
    if (known >= 0) {
        return known
    }
    let idx = length(ix.defs)
    ix.defs |> emplace(MacroDef(name = name, file = file, given_file = given_file, line = line, at = at, fn_like = fn_like))
    ix.def_at[key] = idx
    if (!key_exists(ix.by_name, name)) {
        ix.by_name[name] <- array<int>()
    }
    ix.by_name[name] |> push(idx)
    return idx
}

//! Records that a system header defines function-like macro `name`.
def system_macro(var ix : MacroIndex; name : string) {
    ix.system_fn |> insert(name)
}

// whether token `k` of `toks` before `hi` calls a system header's function-like macro no program
// macro of the name hides
def private calls_system(ix : MacroIndex; toks : array<MTok>; k, hi : int) : bool =>
    toks[k].kind == TOK_IDENT && key_exists(ix.system_fn, toks[k].word) && !key_exists(ix.by_name, toks[k].word) && k + 1 < hi && is_punct(toks[k + 1], "(")

//! Records that the macro at `mac` expands at canonical `file`, offset `at`.
def macro_expansion_at(var ix : MacroIndex; file : string; at : int; mac : int) {
    ix.expansion_at["{file}:{at}"] = mac
    ix.expansion_offsets |> insert(int64(at))
}

def private is_ident_start(c : int) : bool => is_alpha(c) || c == '_'

def private is_ident_char(c : int) : bool => is_alnum(c) || c == '_'

// the token of `t` at or after `from` before `stop`; `at` -1 at the end. Blanks, comments and line
// continuations separate tokens; a newline ends the scan when `one_line`
def private next_tok(t : array<uint8>#; from, stop : int; one_line : bool) : MTok {
    var i = from
    while (i < stop) {
        let c = int(t[i])
        if (c == ' ' || c == '\t' || c == '\r' || c == '\f' || c == '\v') {
            i++
        } elif (c == '\n') {
            if (one_line) {
                return MTok(at = -1)
            }
            i++
        } elif (c == '\\' && i + 1 < stop && (int(t[i + 1]) == '\n' || int(t[i + 1]) == '\r')) {
            i += int(t[i + 1]) == '\r' && i + 2 < stop && int(t[i + 2]) == '\n' ? 3 : 2
        } elif (c == '/' && i + 1 < stop && int(t[i + 1]) == '*') {
            i += 2
            while (i + 1 < stop && !(int(t[i]) == '*' && int(t[i + 1]) == '/')) {
                i++
            }
            i = min(i + 2, stop)
        } elif (c == '/' && i + 1 < stop && int(t[i + 1]) == '/') {
            while (i < stop && int(t[i]) != '\n') {
                i++
            }
        } else {
            return tok_at(t, i, stop)
        }
    }
    return MTok(at = -1)
}

// the token starting at `i`, a non-blank byte
def private tok_at(t : array<uint8>#; i, stop : int) : MTok {
    let c = int(t[i])
    var j = i + 1
    if (is_ident_start(c)) {
        while (j < stop && is_ident_char(int(t[j]))) {
            j++
        }
        return MTok(at = i, stop = j, kind = TOK_IDENT, word = slice_bytes(t, i, j))
    }
    if (is_number(c) || (c == '.' && j < stop && is_number(int(t[j])))) {
        while (j < stop) {
            let n = int(t[j])
            if ((n == '+' || n == '-') && (int(t[j - 1]) == 'e' || int(t[j - 1]) == 'E' || int(t[j - 1]) == 'p' || int(t[j - 1]) == 'P')) {
                j++
            } elif (is_ident_char(n) || n == '.') {
                j++
            } else {
                break
            }
        }
        return MTok(at = i, stop = j, kind = TOK_NUMBER)
    }
    if (c == '"' || c == '\'') {
        while (j < stop && int(t[j]) != c && int(t[j]) != '\n') {
            j += int(t[j]) == '\\' ? 2 : 1
        }
        return MTok(at = i, stop = min(j + 1, stop), kind = TOK_QUOTED)
    }
    for (n in fixed_array(3, 2)) {
        if (i + n <= stop) {
            let word = slice_bytes(t, i, i + n)
            if (n == 3 ? key_exists(PUNCT3, word) : key_exists(PUNCT2, word)) {
                return MTok(at = i, stop = i + n, kind = TOK_PUNCT, word = word)
            }
        }
    }
    return MTok(at = i, stop = j, kind = TOK_PUNCT, word = slice_bytes(t, i, j))
}

def private slice_bytes(t : array<uint8>#; lo, hi : int) : string {
    var bytes : array<uint8>
    bytes |> reserve(hi - lo)
    for (i in range(lo, hi)) {
        bytes |> push(t[i])
    }
    return string(bytes)
}

def private is_punct(tok : MTok; word : string) : bool => tok.kind == TOK_PUNCT && tok.word == word

def private file_text(var ix : MacroIndex; file : string) : string {
    if (!key_exists(ix.texts, file)) {
        ix.texts[file] = stat(file).is_reg ? fread(file) : ""
    }
    return ix.texts?[file] ?? ""
}

// reads definition `idx` from its text once: the parameters, the body tokens, the one-line text
def private parse_def(var ix : MacroIndex; idx : int) : bool {
    if (ix.defs[idx].parsed != 0) {
        return ix.defs[idx].parsed > 0
    }
    ix.defs[idx].parsed = -1
    var toks : array<MTok>
    let text = file_text(ix, ix.defs[idx].file)
    peek_data(text) $(t) {
        var i = ix.defs[idx].at
        while (i >= 0 && i < length(t)) {
            let tok = next_tok(t, i, length(t), true)
            if (tok.at < 0) {
                break
            }
            toks |> push(tok)
            i = tok.stop
        }
    }
    if (empty(toks) || toks[0].word != ix.defs[idx].name) {
        return false
    }
    var at = 1
    var params : array<string>
    if (ix.defs[idx].fn_like) {
        if (length(toks) < 3 || !is_punct(toks[1], "(") || toks[1].at != toks[0].stop) {
            return false
        }
        at = 2
        while (at < length(toks) && !is_punct(toks[at], ")")) {
            if (toks[at].kind != TOK_IDENT) {
                return false
            }
            params |> push(toks[at].word)
            at++
            if (at < length(toks) && is_punct(toks[at], ",")) {
                at++
            }
        }
        if (at >= length(toks)) {
            return false
        }
        at++
    }
    let text_out = build_string() $(var w) {
        w |> write("#define")
        peek_data(text) $(t) {
            for (k in range(length(toks))) {
                w |> write(k == 0 || toks[k].at > toks[k - 1].stop ? " " : "")
                w |> write(slice_bytes(t, toks[k].at, toks[k].stop))
            }
        }
    }
    ix.defs[idx].body |> reserve(length(toks) - at)
    for (k in range(at, length(toks))) {
        let tok = toks[k]
        if (is_punct(tok, "#") || is_punct(tok, "##") || tok.word == "__VA_ARGS__") {
            return false
        }
        ix.defs[idx].body |> push(tok)
    }
    delete ix.defs[idx].params
    ix.defs[idx].params <- params
    ix.defs[idx].text = text_out
    ix.defs[idx].parsed = 1
    return true
}

def private param_index(mac : MacroDef; word : string) : int {
    for (k in range(length(mac.params))) {
        if (mac.params[k] == word) {
            return k
        }
    }
    return -1
}

// the index of the `)` closing the `(` at `open` in `toks` before `hi`, -1 when unbalanced
def private close_of(toks : array<MTok>; open, hi : int) : int {
    var depth = 0
    for (k in range(open, hi)) {
        if (is_punct(toks[k], "(")) {
            depth++
        } elif (is_punct(toks[k], ")")) {
            depth--
            if (depth == 0) {
                return k
            }
        }
    }
    return -1
}

// the argument spans of the call whose `(` is at `open` and `)` at `close`
def private split_args(toks : array<MTok>; src, open, close, ctx : int) : array<MSpan> {
    var args : array<MSpan>
    var depth = 0
    var lo = open + 1
    for (k in range(open + 1, close)) {
        if (is_punct(toks[k], "(")) {
            depth++
        } elif (is_punct(toks[k], ")")) {
            depth--
        } elif (depth == 0 && is_punct(toks[k], ",")) {
            args |> push(MSpan(src = src, lo = lo, hi = k, ctx = ctx))
            lo = k + 1
        }
    }
    args |> push(MSpan(src = src, lo = lo, hi = close, ctx = ctx))
    return <- args
}

// whether context `ctx` or one enclosing it expands definition `mac`: C rescans no such name
def private in_chain(ix : MacroIndex; ctx : int; mac : int) : bool {
    var c = ctx
    var depth = 0
    while (c >= 0 && depth < MAX_DEPTH) {
        if (ix.ctxs[c].mac == mac) {
            return true
        }
        c = ix.ctxs[c].parent
        depth++
    }
    return depth >= MAX_DEPTH
}

// the macro token `k` of span `sp` names, -1 for none: the expansion libclang recorded there in the
// call's text, the one processed definition of the name in a body
def private macro_of(var ix : MacroIndex; sp : MSpan; k : int) : int {
    let tok = sp.src < 0 ? ix.site_toks[k] : ix.defs[sp.src].body[k]
    if (tok.kind != TOK_IDENT) {
        return -1
    }
    if (sp.src < 0) {
        return ix.expansion_at?["{ix.site_file}:{tok.at}"] ?? -1
    }
    if (sp.ctx >= 0 && param_index(ix.defs[ix.ctxs[sp.ctx].mac], tok.word) >= 0) {
        return -1
    }
    var found = -1
    get(ix.by_name, tok.word) $(defs) {
        if (length(defs) == 1) {
            found = defs[0]
        }
    }
    return found >= 0 && !in_chain(ix, sp.ctx, found) && parse_def(ix, found) ? found : -1
}

// the argument spans of a call whose name is token `k` of `toks`, when a `(` follows that closes
// before `hi`
def private open_call(toks : array<MTok>; src, k, hi, ctx : int; var args : array<MSpan>) : bool {
    if (!is_punct(toks[k + 1], "(")) {
        return false
    }
    let close = close_of(toks, k + 1, hi)
    if (close <= k + 1) {
        return false
    }
    delete args
    args <- split_args(toks, src, k + 1, close, ctx)
    return true
}

// the context of a call of macro `mac` at token `k` of span `sp` (its `(` at `k + 1`), -1 when it
// does not close inside the span or its argument count is not the macro's
def private call_ctx(var ix : MacroIndex; sp : MSpan; k, mac : int) : int {
    var args : array<MSpan>
    var ok = false
    let src = sp.src
    let hi = sp.hi
    let ctx = sp.ctx
    if (k + 1 < hi) {
        if (src < 0) {
            ok = open_call(ix.site_toks, src, k, hi, ctx, args)
        } else {
            ok = open_call(ix.defs[src].body, src, k, hi, ctx, args)
        }
    }
    if (!ok || !ix.defs[mac].fn_like || (length(args) != length(ix.defs[mac].params) && !(empty(ix.defs[mac].params) && length(args) == 1 && args[0].lo == args[0].hi))) {
        return -1
    }
    if (empty(ix.defs[mac].params)) {
        args |> clear()
    }
    ix.ctxs |> emplace(MCtx(mac = mac, args <- args, parent = ctx))
    return length(ix.ctxs) - 1
}

// where the last token of span `sp`, a `)`, is spelled: the end of the body of the macro the
// group calls, the `)` itself after anything else
def private spelled_close(var ix : MacroIndex; sp : MSpan; depth : int) : SpellPos {
    let src = sp.src
    let file = src < 0 ? ix.site_file : ix.defs[src].file
    let close = src < 0 ? ix.site_toks[sp.hi - 1] : ix.defs[src].body[sp.hi - 1]
    var depth_p = 0
    var open = -1
    for (j in range(sp.hi - sp.lo)) {
        let at = sp.hi - 1 - j
        let tj = src < 0 ? ix.site_toks[at] : ix.defs[src].body[at]
        if (is_punct(tj, ")")) {
            depth_p++
        } elif (is_punct(tj, "(")) {
            depth_p--
            if (depth_p == 0) {
                open = at
                break
            }
        }
    }
    if (open - 1 < sp.lo) {
        return SpellPos(file = file, at = close.at)
    }
    let k = open - 1
    let tok = src < 0 ? ix.site_toks[k] : ix.defs[src].body[k]
    let system = src < 0 ? calls_system(ix, ix.site_toks, k, sp.hi) : calls_system(ix, ix.defs[src].body, k, sp.hi)
    if (system || (src >= 0 && sp.ctx >= 0 && tok.kind == TOK_IDENT && param_index(ix.defs[ix.ctxs[sp.ctx].mac], tok.word) >= 0)) {
        return SpellPos(at = -1)
    }
    let mac = macro_of(ix, sp, k)
    if (mac < 0 || !ix.defs[mac].fn_like) {
        return SpellPos(file = file, at = close.at)
    }
    let ctx = call_ctx(ix, MSpan(src = src, lo = k, hi = sp.hi, ctx = sp.ctx), k, mac)
    return ctx < 0 ? SpellPos(at = -1) : spelled_end(ix, MSpan(src = mac, lo = 0, hi = length(ix.defs[mac].body), ctx = ctx), true, depth + 1)
}

// where the first (`last` false) or the last token of span `sp` is spelled once every macro and
// parameter in the way is expanded
[arch(at="ARCHITECTURE_DUMPER_MACROS.md#fn-macros")]
def private spelled_end(var ix : MacroIndex; sp : MSpan; last : bool; depth : int) : SpellPos {
    if (sp.lo >= sp.hi || depth > MAX_DEPTH) {
        return SpellPos(at = -1)
    }
    let src = sp.src
    let k = last ? sp.hi - 1 : sp.lo
    let file = src < 0 ? ix.site_file : ix.defs[src].file
    let tok = src < 0 ? ix.site_toks[k] : ix.defs[src].body[k]
    if (last && is_punct(tok, ")")) {
        return spelled_close(ix, sp, depth)
    }
    if (tok.kind != TOK_IDENT) {
        return SpellPos(file = file, at = tok.at)
    }
    if (src >= 0 && sp.ctx >= 0) {
        let p = param_index(ix.defs[ix.ctxs[sp.ctx].mac], tok.word)
        // a parameter called (`fop(L, a, b)`) expands what its argument names, which this pass
        // does not follow
        if (p >= 0 && !last && k + 1 < sp.hi && is_punct(ix.defs[src].body[k + 1], "(")) {
            return SpellPos(at = -1)
        }
        if (p >= 0) {
            let arg = ix.ctxs[sp.ctx].args[p]
            return spelled_end(ix, arg, last, depth + 1)
        }
    }
    if (!last && (src < 0 ? calls_system(ix, ix.site_toks, k, sp.hi) : calls_system(ix, ix.defs[src].body, k, sp.hi))) {
        return SpellPos(at = -1)
    }
    let mac = macro_of(ix, sp, k)
    if (mac < 0 || !parse_def(ix, mac)) {
        return SpellPos(file = file, at = tok.at)
    }
    if (!ix.defs[mac].fn_like) {
        ix.ctxs |> emplace(MCtx(mac = mac, parent = sp.ctx))
        let ctx = length(ix.ctxs) - 1
        return spelled_end(ix, MSpan(src = mac, lo = 0, hi = length(ix.defs[mac].body), ctx = ctx), last, depth + 1)
    }
    if (last) {
        return SpellPos(file = file, at = tok.at)
    }
    let ctx = call_ctx(ix, sp, k, mac)
    if (ctx < 0) {
        let opens = k + 1 < sp.hi && is_punct(src < 0 ? ix.site_toks[k + 1] : ix.defs[src].body[k + 1], "(")
        return opens ? SpellPos(at = -1) : SpellPos(file = file, at = tok.at)
    }
    return spelled_end(ix, MSpan(src = mac, lo = 0, hi = length(ix.defs[mac].body), ctx = ctx), false, depth + 1)
}

// the calls of function-like macros span `sp` writes, nested ones included, in text order
def private calls_in(var ix : MacroIndex; sp : MSpan) : array<MCall> {
    var calls : array<MCall>
    for (k in range(sp.lo, sp.hi)) {
        let mac = macro_of(ix, sp, k)
        if (mac >= 0 && ix.defs[mac].fn_like && ix.defs[mac].parsed > 0) {
            let ctx = call_ctx(ix, sp, k, mac)
            if (ctx >= 0) {
                calls |> emplace(MCall(mac = mac, args := ix.ctxs[ctx].args))
                ix.ctxs |> pop()
            }
        }
    }
    return <- calls
}

// how many times the expansion of definition `mac` holds each parameter's tokens, through the
// macros its body calls; -1 where a call goes through a macro this pass does not follow
def private uses_of(var ix : MacroIndex; mac : int) {
    if (ix.defs[mac].uses_state != 0) {
        return
    }
    ix.defs[mac].uses_state = 1
    let body_len = length(ix.defs[mac].body)
    var uses <- [for (p in range(length(ix.defs[mac].params))); occurrences(ix, mac, 0, body_len, p)]
    delete ix.defs[mac].uses
    ix.defs[mac].uses <- uses
    ix.defs[mac].uses_state = 2
}

// the times parameter `p` of `mac` appears in the expansion of body tokens `[lo, hi)`
def private occurrences(var ix : MacroIndex; mac, lo, hi, p : int) : int {
    var total = 0
    var k = lo
    while (k < hi) {
        let tok = ix.defs[mac].body[k]
        let called = tok.kind == TOK_IDENT && k + 1 < hi && is_punct(ix.defs[mac].body[k + 1], "(")
        if (called && param_index(ix.defs[mac], tok.word) >= 0) {
            // a called parameter's argument names a function or a macro, no expression, and what
            // it expands to decides how often its arguments are used
            let close = close_of(ix.defs[mac].body, k + 1, hi)
            if (close < 0 || tok.word == ix.defs[mac].params[p] || occurrences(ix, mac, k + 2, close, p) != 0) {
                return -1
            }
            k = close + 1
            continue
        }
        if (tok.kind == TOK_IDENT && tok.word == ix.defs[mac].params[p]) {
            total++
            k++
            continue
        }
        if (calls_system(ix, ix.defs[mac].body, k, hi)) {
            return -1
        }
        var callee = -1
        if (tok.kind == TOK_IDENT && param_index(ix.defs[mac], tok.word) < 0 && k + 1 < hi && is_punct(ix.defs[mac].body[k + 1], "(")) {
            get(ix.by_name, tok.word) $(defs) {
                callee = length(defs) == 1 ? defs[0] : -2
            }
        }
        if (callee == -1 || (callee >= 0 && !ix.defs[callee].fn_like) || callee == mac) {
            k++
            continue
        }
        let close = close_of(ix.defs[mac].body, k + 1, hi)
        if (close < 0) {
            return -1
        }
        var inscope args <- split_args(ix.defs[mac].body, mac, k + 1, close, -1)
        var known = callee >= 0 && parse_def(ix, callee)
        if (known) {
            uses_of(ix, callee)
            known = ix.defs[callee].uses_state == 2 && length(ix.defs[callee].params) == length(args)
        }
        for (a in range(length(args))) {
            let n = occurrences(ix, mac, args[a].lo, args[a].hi, p)
            if (n < 0) {
                return -1
            }
            if (n > 0) {
                if (!known || ix.defs[callee].uses[a] < 0) {
                    return -1
                }
                total += n * ix.defs[callee].uses[a]
            }
        }
        k = close + 1
    }
    return total
}

// appends to `seq` the parameters of `mac` in the order the expansion of its body tokens `[lo, hi)`
// holds their tokens, through the macros the body calls; false where a call goes through a macro
// this pass does not follow or a parameter is called
def private param_seq(var ix : MacroIndex; mac, lo, hi, depth : int; var seq : array<int>) : bool {
    if (depth > MAX_DEPTH) {
        return false
    }
    var k = lo
    while (k < hi) {
        let tok = ix.defs[mac].body[k]
        let called = tok.kind == TOK_IDENT && k + 1 < hi && is_punct(ix.defs[mac].body[k + 1], "(")
        let p = tok.kind == TOK_IDENT ? param_index(ix.defs[mac], tok.word) : -1
        if (p >= 0 && called) {
            return false
        }
        if (p >= 0) {
            seq |> push(p)
            k++
            continue
        }
        if (calls_system(ix, ix.defs[mac].body, k, hi)) {
            return false
        }
        var callee = -1
        if (called) {
            get(ix.by_name, tok.word) $(defs) {
                callee = length(defs) == 1 ? defs[0] : -2
            }
        }
        if (callee == -1 || (callee >= 0 && !ix.defs[callee].fn_like) || callee == mac) {
            k++
            continue
        }
        let close = close_of(ix.defs[mac].body, k + 1, hi)
        if (close < 0) {
            return false
        }
        var inscope args <- split_args(ix.defs[mac].body, mac, k + 1, close, -1)
        if (callee < 0 || !parse_def(ix, callee) || !macro_seq(ix, callee, depth + 1)) {
            // a call this pass does not follow keeps the order only when no argument holds a parameter
            for (a in args) {
                var inscope inner : array<int>
                if (!param_seq(ix, mac, a.lo, a.hi, depth + 1, inner) || !empty(inner)) {
                    return false
                }
            }
        } else {
            for (q in ix.defs[callee].seq) {
                if (q >= length(args) || !param_seq(ix, mac, args[q].lo, args[q].hi, depth + 1, seq)) {
                    return false
                }
            }
        }
        k = close + 1
    }
    return true
}

// whether the order of the parameters in the expansion of definition `mac` is known, read once
def private macro_seq(var ix : MacroIndex; mac, depth : int) : bool {
    if (ix.defs[mac].seq_state == 0) {
        ix.defs[mac].seq_state = 1
        var seq : array<int>
        let ok = param_seq(ix, mac, 0, length(ix.defs[mac].body), depth, seq)
        delete ix.defs[mac].seq
        ix.defs[mac].seq <- seq
        ix.defs[mac].seq_state = ok ? 2 : -1
    }
    return ix.defs[mac].seq_state == 2
}

def private node_key(js : JsonValue const?) : uint64 => unsafe(reinterpret<uint64>(js))

def private kind_of(js : JsonValue const?) : string => js?["kind"] ?? ""

def private kids_of(js : JsonValue const?) : int {
    let kids = js?["inner"]
    return kids != null && kids is _array ? length(kids as _array) : 0
}

def private kid(js : JsonValue const?; k : int) : JsonValue const? => (js?["inner"] as _array)[k]

def private is_expr_kind(kind : string) : bool => kind |> ends_with("Expr") || kind |> ends_with("Operator") || kind |> ends_with("Literal")

// the spelling of one end of a node's range: its own location where no macro made it
def private end_spelling(var canon : table<string; string>; js : JsonValue const?; which : string) : SpellPos =>
    spelling_of(canon, js?["range"]?[which])

// where location `at` is spelled: the location itself where no macro made it
def private spelling_of(var canon : table<string; string>; at : JsonValue const?) : SpellPos {
    let spelled = at?["spellingLoc"]
    return spelled != null ? position(canon, spelled) : position(canon, at)
}

def private position(var canon : table<string; string>; at : JsonValue const?) : SpellPos =>
    SpellPos(file = canonical_name(canon, at?["file"] ?? ""), at = int(at?["offset"] ?? -1l))

//! `name` made canonical through the dumper's cache.
def canonical_name(var canon : table<string; string>; name : string) : string {
    if (empty(name) || name |> starts_with("<")) {
        return ""
    }
    var full = canon?[name] ?? ""
    if (empty(full)) {
        full = get_full_file_name(name)
        canon[name] = full
    }
    return full
}

def private spells(var canon : table<string; string>; js : JsonValue const?; first, last : SpellPos) : bool {
    let b = end_spelling(canon, js, "begin")
    if (b.at != first.at || b.file != first.file) {
        return false
    }
    let e = end_spelling(canon, js, "end")
    return e.at == last.at && e.file == last.file
}

// every node below and at `js` that is no wrapper and is spelled from `first` to `last`, in
// preorder; `stmts` admits statements
def private spelled_nodes(var canon : table<string; string>; js : JsonValue const?; first, last : SpellPos; var out : array<JsonValue const?>) {
    if (!(WRAPPER_KINDS |> key_exists(kind_of(js))) && spells(canon, js, first, last)) {
        out |> push(js)
    }
    for (k in range(kids_of(js))) {
        spelled_nodes(canon, kid(js, k), first, last, out)
    }
}

// whether `js` is a copy of an argument spelled from `first` to `last`; node `whole`, an expansion
// whose argument is another expansion of the same body (`SQ(SQ(x))`), is never its own copy
def private is_copy(var canon : table<string; string>; js, whole : JsonValue const?; first, last : SpellPos) : bool {
    let kind = kind_of(js)
    return js != whole && !(WRAPPER_KINDS |> key_exists(kind)) && is_expr_kind(kind) && spells(canon, js, first, last)
}

// node `js`, the whole expansion of macro `mac`, when it spells the argument `first` to `last` too
// and is no identity (`#define ID(x) x`), whose node is its argument's copy
def private self_spelled(ix : MacroIndex; var canon : table<string; string>; js : JsonValue const?; mac : int; first, last : SpellPos) : JsonValue const? =>
    length(ix.defs[mac].body) > 1 && spells(canon, js, first, last) ? js : null

// the topmost copies below or at `js` of the arguments spelled `firsts[a]` to `lasts[a]`, each as
// its argument's index, in preorder: the order of their tokens
def private copy_order(var canon : table<string; string>; js, whole : JsonValue const?; firsts, lasts : array<SpellPos>; var order : array<int>) {
    for (a in range(length(firsts))) {
        if (firsts[a].at >= 0 && lasts[a].at >= 0 && is_copy(canon, js, whole, firsts[a], lasts[a])) {
            order |> push(a)
            return
        }
    }
    for (j in range(kids_of(js))) {
        copy_order(canon, kid(js, j), whole, firsts, lasts, order)
    }
}

// the tokens the expansion holds whose node, if any, is a leaf (a name or a literal), as a count by
// `file:offset` of where each is spelled
struct private Leaves {
    known : bool
    counts : table<string; int>
    // the numbers among them, which always have a node of their own
    numbers : table<string>
    budget : int
}

// a cap on the tokens one expansion's leaves walk visits: past it the leaves are unknown
let private LEAF_BUDGET = 20000

// adds to `lv` the leaves of span `sp` once every macro and parameter in it is expanded; unknown
// where a parameter is called, a system header's macro is called, or the budget runs out
def private span_leaves(var ix : MacroIndex; sp : MSpan; depth : int; var lv : Leaves) {
    var k = sp.lo
    while (k < sp.hi && lv.known) {
        lv.budget--
        if (lv.budget < 0 || depth > MAX_DEPTH) {
            lv.known = false
            return
        }
        let src = sp.src
        let tok = src < 0 ? ix.site_toks[k] : ix.defs[src].body[k]
        let opens = k + 1 < sp.hi && is_punct(src < 0 ? ix.site_toks[k + 1] : ix.defs[src].body[k + 1], "(")
        if (src >= 0 && sp.ctx >= 0 && tok.kind == TOK_IDENT && param_index(ix.defs[ix.ctxs[sp.ctx].mac], tok.word) >= 0) {
            if (opens) {
                lv.known = false
                return
            }
            span_leaves(ix, ix.ctxs[sp.ctx].args[param_index(ix.defs[ix.ctxs[sp.ctx].mac], tok.word)], depth + 1, lv)
            k++
            continue
        }
        if (src < 0 ? calls_system(ix, ix.site_toks, k, sp.hi) : calls_system(ix, ix.defs[src].body, k, sp.hi)) {
            lv.known = false
            return
        }
        let mac = macro_of(ix, sp, k)
        if (mac >= 0 && !ix.defs[mac].fn_like) {
            ix.ctxs |> emplace(MCtx(mac = mac, parent = sp.ctx))
            span_leaves(ix, MSpan(src = mac, lo = 0, hi = length(ix.defs[mac].body), ctx = length(ix.ctxs) - 1), depth + 1, lv)
            k++
            continue
        }
        if (mac >= 0 && opens) {
            let ctx = call_ctx(ix, sp, k, mac)
            let close = src < 0 ? close_of(ix.site_toks, k + 1, sp.hi) : close_of(ix.defs[src].body, k + 1, sp.hi)
            if (ctx < 0 || close < 0) {
                lv.known = false
                return
            }
            span_leaves(ix, MSpan(src = mac, lo = 0, hi = length(ix.defs[mac].body), ctx = ctx), depth + 1, lv)
            k = close + 1
            continue
        }
        if (tok.kind != TOK_PUNCT) {
            let key = "{src < 0 ? ix.site_file : ix.defs[src].file}:{tok.at}"
            lv.counts[key] = (lv.counts?[key] ?? 0) + 1
            if (tok.kind == TOK_NUMBER) {
                lv.numbers |> insert(key)
            }
        }
        k++
    }
}

// the leaves of the expansion of context `ctx`
def private expansion_leaves(var ix : MacroIndex; ctx : int) : Leaves {
    var lv = Leaves(known = true, budget = LEAF_BUDGET)
    let mac = ix.ctxs[ctx].mac
    span_leaves(ix, MSpan(src = mac, lo = 0, hi = length(ix.defs[mac].body), ctx = ctx), 0, lv)
    return <- lv
}

def private is_leaf_kind(kind : string) : bool => kind == "DeclRefExpr" || kind |> ends_with("Literal")

// the leaves below or at `js`, counted by `file:offset` of where each is spelled
def private node_leaves(var canon : table<string; string>; js : JsonValue const?; var out : table<string; int>) {
    if (is_leaf_kind(kind_of(js))) {
        let sp = end_spelling(canon, js, "begin")
        let key = "{sp.file}:{sp.at}"
        out[key] = (out?[key] ?? 0) + 1
    }
    for (j in range(kids_of(js))) {
        node_leaves(canon, kid(js, j), out)
    }
}

// whether `node` holds the leaves `lv` the expansion holds: each of its leaves as many times as the
// expansion holds that token, and every number. Two expansions side by side (`ADD1(x) + ADD1(0)`),
// an expansion inside a body's own (`ADD1(x)` of `S3(x)`), another call of the body
// (`tonumberns(v2, n2)` for `tonumberns(v1, n1)`) and a body naming another constant (`ttisfloat(o)`
// for `ttisinteger(o)`) each hold other leaves
def private holds_leaves(var canon : table<string; string>; node : JsonValue const?; lv : Leaves) : bool {
    if (!lv.known) {
        return true
    }
    var seen : table<string; int>
    node_leaves(canon, node, seen)
    for (key, n in keys(seen), values(seen)) {
        if ((lv.counts?[key] ?? 0) != n) {
            return false
        }
    }
    for (key in keys(lv.numbers)) {
        if ((seen?[key] ?? 0) != (lv.counts?[key] ?? 0)) {
            return false
        }
    }
    return true
}

// whether `node` holds the expansion's leaves (`holds_leaves`) and the arguments of context `ctx` as
// its macro's expansion does: each copied argument's copies in the order the expansion holds the
// parameters, or, where that order is unknown, as many times as the macro uses it
def private fits_call(var ix : MacroIndex; var canon : table<string; string>; node : JsonValue const?; ctx : int; lv : Leaves) : bool {
    let mac = ix.ctxs[ctx].mac
    let nargs = length(ix.ctxs[ctx].args)
    var firsts, lasts : array<SpellPos>
    firsts |> reserve(nargs)
    lasts |> reserve(nargs)
    for (a in range(nargs)) {
        firsts |> push(spelled_end(ix, ix.ctxs[ctx].args[a], false, 0))
        lasts |> push(spelled_end(ix, ix.ctxs[ctx].args[a], true, 0))
    }
    if (!holds_leaves(canon, node, lv)) {
        return false
    }
    var order : array<int>
    copy_order(canon, node, length(ix.defs[mac].body) > 1 ? node : null, firsts, lasts, order)
    if (macro_seq(ix, mac, 0)) {
        // an argument with no copy at all (a type, an operator, one the body's precedence splits)
        // is left to the backend, which counts the copies against `uses`
        var copied : table<int>
        for (o in order) {
            copied |> insert(o)
        }
        let want <- [for (q in ix.defs[mac].seq); q; where key_exists(copied, q)]
        if (length(want) != length(order)) {
            return false
        }
        for (w, o in want, order) {
            if (w != o) {
                return false
            }
        }
        return true
    }
    uses_of(ix, mac)
    for (a in range(nargs)) {
        let uses = ix.defs[mac].uses_state == 2 ? ix.defs[mac].uses[a] : -1
        let copies = length([for (o in order); o; where o == a])
        if (uses >= 0 && copies > 0 && copies != uses) {
            return false
        }
    }
    return true
}

// marks every topmost expression below or at `js` spelled from `first` to `last` a copy of
// argument `k` of expansion `site`
def private mark_copies(var ix : MacroIndex; var canon : table<string; string>; js, whole : JsonValue const?; first, last : SpellPos; site, k : int) {
    if (is_copy(canon, js, whole, first, last)) {
        let key = node_key(js)
        if (!key_exists(ix.arg_marks, key)) {
            ix.arg_marks[key] <- array<CirMacroArg>()
        }
        ix.arg_marks[key] |> push(CirMacroArg(site = site, k = k))
        return
    }
    for (j in range(kids_of(js))) {
        mark_copies(ix, canon, kid(js, j), whole, first, last, site, k)
    }
}

def private cir_macro(var ix : MacroIndex; mac : int) : int {
    if (ix.defs[mac].cir_index < 0) {
        uses_of(ix, mac)
        let known = ix.defs[mac].uses_state == 2
        var uses <- [for (p in range(length(ix.defs[mac].params))); known ? ix.defs[mac].uses[p] : -1]
        ix.defs[mac].cir_index = length(ix.macros)
        ix.macros |> emplace(CirMacro(name = ix.defs[mac].name, params := ix.defs[mac].params, file = ix.defs[mac].given_file, line = ix.defs[mac].line, text = ix.defs[mac].text, uses <- uses))
    }
    return ix.defs[mac].cir_index
}

// the text of span `sp` as its file writes it, from its first token to its last
def private span_text(var ix : MacroIndex; sp : MSpan) : string {
    if (sp.lo >= sp.hi) {
        return ""
    }
    let first = sp.src < 0 ? ix.site_toks[sp.lo] : ix.defs[sp.src].body[sp.lo]
    let last = sp.src < 0 ? ix.site_toks[sp.hi - 1] : ix.defs[sp.src].body[sp.hi - 1]
    var out = ""
    peek_data(file_text(ix, sp.src < 0 ? ix.site_file : ix.defs[sp.src].file)) $(t) {
        if (last.stop <= length(t)) {
            out = slice_bytes(t, first.at, last.stop)
        }
    }
    return out
}

// node `js` is the whole expansion of context `ctx`: marks it, its argument copies, and the
// expansions its macro's body calls
[arch(at="ARCHITECTURE_DUMPER_MACROS.md#fn-macros")]
def private take_site(var ix : MacroIndex; var canon : table<string; string>; js : JsonValue const?; ctx : int; depth : int) : bool {
    let mac = ix.ctxs[ctx].mac
    let nargs = length(ix.ctxs[ctx].args)
    var firsts, lasts : array<SpellPos>
    firsts |> reserve(nargs)
    lasts |> reserve(nargs)
    for (a in range(nargs)) {
        let arg = ix.ctxs[ctx].args[a]
        firsts |> push(spelled_end(ix, arg, false, 0))
        lasts |> push(spelled_end(ix, arg, true, 0))
        for (b in range(a)) {
            if (firsts[a].at >= 0 && firsts[a].at == firsts[b].at && firsts[a].file == firsts[b].file && lasts[a].at == lasts[b].at && lasts[a].file == lasts[b].file) {
                return false
            }
        }
    }
    let site = ix.sites
    ix.sites++
    ix.site_places |> push((file = ix.site_file, at = ix.site_toks[0].at))
    let key = node_key(js)
    if (!key_exists(ix.fn_marks, key)) {
        ix.fn_marks[key] <- array<CirMacroUse>()
    }
    var texts <- [for (a in range(nargs)); span_text(ix, ix.ctxs[ctx].args[a])]
    let m = cir_macro(ix, mac)
    ix.fn_marks[key] |> emplace(CirMacroUse(m = m, site = site, args <- texts))
    for (a in range(nargs)) {
        if (firsts[a].at >= 0 && lasts[a].at >= 0) {
            mark_copies(ix, canon, js, self_spelled(ix, canon, js, mac, firsts[a], lasts[a]), firsts[a], lasts[a], site, a)
        }
    }
    if (depth < MAX_DEPTH) {
        var calls <- calls_in(ix, MSpan(src = mac, lo = 0, hi = length(ix.defs[mac].body), ctx = ctx))
        for (call in calls) {
            nested_site(ix, canon, js, call, ctx, depth + 1)
        }
    }
    return true
}

// the expansion of `call`, written in the text context `parent` expands, among the nodes below
// `scope`: each one no expansion of the macro took that holds every argument as often as the
// macro uses it
def private nested_site(var ix : MacroIndex; var canon : table<string; string>; scope : JsonValue const?; call : MCall; parent : int; depth : int) {
    ix.ctxs |> emplace(MCtx(mac = call.mac, args := call.args, parent = parent))
    let ctx = length(ix.ctxs) - 1
    let body = MSpan(src = call.mac, lo = 0, hi = length(ix.defs[call.mac].body), ctx = ctx)
    let first = spelled_end(ix, body, false, 0)
    let last = spelled_end(ix, body, true, 0)
    if (first.at < 0 || last.at < 0) {
        return
    }
    uses_of(ix, call.mac)
    // a call whose every argument the expansion holds has no known spelling tells no candidate
    // apart (`APPLY2(f, x)` of `ADD1(f(x))`)
    var held, known = 0
    for (a in range(length(ix.ctxs[ctx].args))) {
        if (ix.defs[call.mac].uses_state != 2 || ix.defs[call.mac].uses[a] != 0) {
            held++
            known += spelled_end(ix, ix.ctxs[ctx].args[a], false, 0).at >= 0 && spelled_end(ix, ix.ctxs[ctx].args[a], true, 0).at >= 0 ? 1 : 0
        }
    }
    if (held > 0 && known == 0) {
        return
    }
    let lv <- expansion_leaves(ix, ctx)
    var nodes : array<JsonValue const?>
    spelled_nodes(canon, scope, first, last, nodes)
    for (node in nodes) {
        let claim = "{node_key(node)}/{call.mac}"
        if (key_exists(ix.claimed, claim)) {
            continue
        }
        // two expansions side by side can spell one body's first and last token, and one body can
        // call a macro twice with other arguments: the node holds the body's tokens and the
        // arguments as the expansion does; a call written once in an argument the enclosing body
        // uses twice expands twice
        if (fits_call(ix, canon, node, ctx, lv)) {
            ix.claimed |> insert(claim)
            take_site(ix, canon, node, ctx, depth)
        }
    }
}

// the expansion at canonical `file`, offset `at`, whose range node `js` spans: the call's tokens,
// the whole node (the first below `js` spelled over the body), its marks
def private outermost_site(var ix : MacroIndex; var canon : table<string; string>; js : JsonValue const?; file : string; at, mac : int) {
    if (!parse_def(ix, mac) || !ix.defs[mac].fn_like) {
        return
    }
    ix.site_toks |> clear()
    ix.ctxs |> clear()
    ix.claimed |> clear()
    ix.site_file = file
    let text = file_text(ix, file)
    peek_data(text) $(t) {
        var depth = 0
        var i = at
        while (i < length(t)) {
            let tok = next_tok(t, i, length(t), false)
            if (tok.at < 0) {
                break
            }
            ix.site_toks |> push(tok)
            i = tok.stop
            if (is_punct(tok, "(")) {
                depth++
            } elif (is_punct(tok, ")")) {
                depth--
                if (depth == 0) {
                    break
                }
            } elif (length(ix.site_toks) == 2) {
                break
            }
        }
    }
    let n = length(ix.site_toks)
    if (n < 3 || ix.site_toks[0].word != ix.defs[mac].name || !is_punct(ix.site_toks[1], "(") || !is_punct(ix.site_toks[n - 1], ")")) {
        return
    }
    let ctx = call_ctx(ix, MSpan(src = -1, lo = 0, hi = n, ctx = -1), 0, mac)
    if (ctx < 0) {
        return
    }
    let body = MSpan(src = mac, lo = 0, hi = length(ix.defs[mac].body), ctx = ctx)
    let first = spelled_end(ix, body, false, 0)
    let last = spelled_end(ix, body, true, 0)
    if (first.at < 0 || last.at < 0) {
        return
    }
    let lv <- expansion_leaves(ix, ctx)
    var nodes : array<JsonValue const?>
    spelled_nodes(canon, js, first, last, nodes)
    // the topmost node that holds the body's tokens and the arguments as the expansion does
    // (`MUL2(i + 1)` of `x * 2` has none: the body's precedence splits the argument, nor has `S3(i) *
    // 3` of `ADD1(x) + ADD1(0)`)
    var whole : JsonValue const?
    for (node in nodes) {
        if (whole == null && fits_call(ix, canon, node, ctx, lv)) {
            whole = node
        }
    }
    if (whole == null || !take_site(ix, canon, whole, ctx, 0)) {
        return
    }
    ix.claimed |> insert("{node_key(whole)}/{mac}")
    var calls <- calls_in(ix, MSpan(src = -1, lo = 2, hi = n - 1, ctx = -1))
    for (call in calls) {
        nested_site(ix, canon, whole, call, -1, 1)
    }
}

//! Walks dump `js` (its locations completed) for the expansions `ix` holds and marks them.
[arch(at="ARCHITECTURE_DUMPER_MACROS.md#fn-macros")]
def find_macro_sites(var ix : MacroIndex; var canon : table<string; string>; js : JsonValue const?) {
    let b = js?["range"]?["begin"]?["expansionLoc"]
    let e = js?["range"]?["end"]?["expansionLoc"]
    if (b != null && e != null) {
        let at = b?["offset"] ?? -1l
        if (at >= 0l && at == (e?["offset"] ?? -2l) && key_exists(ix.expansion_offsets, at)) {
            let file = canonical_name(canon, b?["file"] ?? "")
            let key = "{file}:{at}"
            let mac = ix.expansion_at?[key] ?? -1
            if (mac >= 0 && !key_exists(ix.done, key)) {
                ix.done |> insert(key)
                outermost_site(ix, canon, js, file, int(at), mac)
            }
        }
    }
    for (k in range(kids_of(js))) {
        find_macro_sites(ix, canon, kid(js, k))
    }
}
