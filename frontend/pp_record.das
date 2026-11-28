options gen2
options indenting = 4

module pp_record public

require strings
require pp_expand public

//! The expansion record's readers (`ARCHITECTURE_EXPAND.md#pp-record`): what a token, a call, an
//! argument and a macro tell Dumper C about the expansions of a unit. None allocates for a token or
//! a call; a text is appended to the caller's buffer.

//! The expansion location of a token of call `call` (-1: a token of the source): the place of the
//! outermost call's name, as clang's `SourceManager` gives it; `own` for a token of the source.
[arch(at="ARCHITECTURE_EXPAND.md#pp-places")]
def pp_expansion_place(pp : Preprocessor; call : int; own : PpToken) : PpPlace {
    if (call < 0) {
        return PpPlace(file = own.file, offset = own.offset, line = own.line, col = own.col)
    }
    let top & = unsafe(pp.expansion.calls[pp.expansion.calls[call].outer].name)
    return PpPlace(file = top.file, offset = top.offset, line = top.line, col = top.col)
}

//! The expansion location of the handed-out token `t`.
def pp_expansion_place(pp : Preprocessor; t : PpOutToken) : PpPlace => pp_expansion_place(pp, t.call, t.tok)

//! The spelling location of the handed-out token `t`: where its spelling was written, a macro
//! body's token in its `#define`.
def pp_spelling_place(t : PpOutToken) : PpPlace => PpPlace(file = t.tok.file, offset = t.tok.offset, line = t.tok.line, col = t.tok.col)

//! Each argument copy `copy` (a token's `copy`) is in, the latest substitution first: `blk` gets
//! the call and the parameter index. `#define A(x) B(x)` makes a token of `A(t)` a copy of `B`'s
//! argument 0, then of `A`'s; `A(B(t))` makes `t` a copy of `A`'s argument 0, then of `B`'s.
[arch(at="ARCHITECTURE_EXPAND.md#pp-copies")]
def pp_each_copy(pp : Preprocessor; copy : int; blk : block<(call : int; k : int) : void>) {
    var at = copy
    while (at > 0) {
        let c & = unsafe(pp.expansion.copies[at])
        invoke(blk, c.call, c.k)
        at = c.outer
    }
}

//! Whether the token whose `copy` is `copy` is in a copy of argument `k` of call `call`.
def pp_is_copy_of(pp : Preprocessor; copy, call, k : int) : bool {
    var at = copy
    while (at > 0) {
        let c & = unsafe(pp.expansion.copies[at])
        return true if (c.call == call && c.k == k)
        at = c.outer
    }
    return false
}

//! The bytes of argument `k` of call `call` as written, when they are one stretch of a file, valid
//! for the whole unit; null data for any other argument, whose text `pp_call_arg_text` appends,
//! and length 0 for an empty one.
[arch(at="ARCHITECTURE_EXPAND.md#pp-record")]
def pp_call_arg_view(pp : Preprocessor; call, k : int) : tuple<data : uint8 const?; len : int> {
    let arg & = unsafe(pp.expansion.call_args[pp.expansion.calls[call].first_arg + k])
    if (arg.text == PpArgText.source) {
        return (data = unsafe(pp.buffer_data[arg.buffer] + arg.at), len = arg.len)
    }
    return (data = null, len = 0)
}

//! The text of argument `k` of call `call` as written, appended to `out`: a stretch of a file as the
//! file spells it, line splices removed; an argument written in a `#define` or not one stretch,
//! its tokens with a blank where one had space, as the C-IR's `text` rule joins them.
[arch(at="ARCHITECTURE_EXPAND.md#pp-record")]
def pp_call_arg_text(pp : Preprocessor; call, k : int; var out : array<uint8>) {
    let arg & = unsafe(pp.expansion.call_args[pp.expansion.calls[call].first_arg + k])
    if (arg.text == PpArgText.body) {
        for (j in range(arg.at, arg.at + arg.len)) {
            let h & = unsafe(pp.macro_body[j])
            if (j > arg.at && h.has_space) {
                out |> push(' 'u8)
            }
            out |> reserve(length(out) + h.len)
            for (b in range(h.at, h.at + h.len)) {
                out |> push(pp.macro_text[b])
            }
        }
        return
    } elif (arg.text == PpArgText.pooled) {
        out |> reserve(length(out) + arg.len)
        for (b in range(arg.at, arg.at + arg.len)) {
            out |> push(pp.expansion.arg_text[b])
        }
        return
    }
    let view = pp_call_arg_view(pp, call, k)
    out |> reserve(length(out) + view.len)
    for (i in range(view.len)) {
        out |> push(unsafe(view.data[i]))
    }
}

//! Whether macro `m` is one the C-IR marks (`docs/c-ir-spec.md` section 6.3): function-like, not
//! variadic, no `#` or `##` in its body.
def pp_macro_markable(pp : Preprocessor; m : int) : bool {
    let mac & = unsafe(pp.macros[m])
    return false if (!mac.function_like || mac.variadic)
    for (j in range(mac.first, mac.first + mac.count)) {
        let kind = pp.macro_body[j].kind
        return false if (kind == int(PpTok.HASH) || kind == int(PpTok.HASHHASH))
    }
    return true
}

//! The `#define` of macro `m` on one line, appended to `out`: `#define`, then its tokens from the
//! name on as its line spells them, continuations joined, each comment and run of blanks one
//! blank between the tokens it separated (the C-IR's `text`).
[arch(at="ARCHITECTURE_EXPAND.md#pp-macro-facts")]
def pp_macro_text(pp : Preprocessor; m : int; var out : array<uint8>) {
    let mac & = unsafe(pp.macros[m])
    let data = pp.buffer_data[mac.buffer]
    peek_data("#define ") $(head) {
        for (c in head) {
            out |> push(c)
        }
    }
    var gap = false
    var i = mac.at
    while (i < mac.stop) {
        let c = int(unsafe(data[i]))
        let next = i + 1 < mac.stop ? int(unsafe(data[i + 1])) : 0
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f') {
            gap = true
            i++
            continue
        }
        if (c == '/' && next == '*') {
            i += 2
            while (i + 1 < mac.stop && !(unsafe(data[i]) == '*'u8 && unsafe(data[i + 1]) == '/'u8)) {
                i++
            }
            i += 2
            gap = true
            continue
        }
        if (gap) {
            out |> push(' 'u8)
            gap = false
        }
        if (c == '"' || c == '\'') {
            out |> push(uint8(c))
            i++
            while (i < mac.stop && int(unsafe(data[i])) != c) {
                if (unsafe(data[i]) == '\\'u8 && i + 1 < mac.stop) {
                    out |> push(unsafe(data[i]))
                    i++
                }
                out |> push(unsafe(data[i]))
                i++
            }
            if (i < mac.stop) {
                out |> push(unsafe(data[i]))
                i++
            }
            continue
        }
        out |> push(uint8(c))
        i++
    }
}

//! How many times the full expansion of macro `m` holds the tokens of argument `k` (the C-IR's
//! `uses[k]`): its parameter's uses in the body, each argument of a macro the body calls counted
//! as often as that macro uses it; -1 when it cannot be told - `m` variadic, the parameter an
//! operand of `#` or `##` or called as a function, a call of a macro whose use of the argument is
//! not known or whose name has two definitions. Computed once per macro, so it is read once the
//! unit is preprocessed: a body's call resolves among every definition the unit made.
[arch(at="ARCHITECTURE_EXPAND.md#pp-macro-facts")]
def pp_macro_uses(var pp : Preprocessor; m, k : int) : int {
    var ex = pp.expansion
    if (m >= length(ex.uses_at)) {
        let was = length(ex.uses_at)
        ex.uses_at |> resize(length(pp.macros))
        for (i in range(was, length(ex.uses_at))) {
            ex.uses_at[i] = -1
        }
    }
    if (ex.uses_at[m] == -1) {
        ex.uses_at[m] = -2
        let n = length(pp.macros[m].params)
        let at = length(ex.uses)
        ex.uses |> resize(at + n)
        for (p in range(n)) {
            ex.uses[at + p] = pp.macros[m].variadic ? -1 : param_uses(pp, m, p, pp.macros[m].first, pp.macros[m].first + pp.macros[m].count)
        }
        ex.uses_at[m] = at
    }
    return ex.uses_at[m] == -2 ? -1 : ex.uses[ex.uses_at[m] + k]
}

// the one definition of the name `sym` a body calls, -1 for none, -2 when the unit has two that differ
def private called_definition(var pp : Preprocessor; sym : int) : int {
    var ex = pp.expansion
    if (empty(ex.called_def)) {
        for (i in range(length(pp.macros))) {
            let name = pp.macros[i].name
            let known = ex.called_def?[name] ?? -1
            if (known == -1) {
                ex.called_def[name] = i
            } elif (known >= 0 && !pp_same_definition(pp, pp.macros[known], pp.macros[i])) {
                ex.called_def[name] = -2
            }
        }
    }
    return ex.called_def?[sym] ?? -1
}

// the index of parameter `sym` of macro `m`, -1 when it names none
def private param_index(pp : Preprocessor; m, sym : int) : int {
    let params & = unsafe(pp.macros[m].params)
    for (i in range(length(params))) {
        return i if (params[i] == sym)
    }
    return -1
}

// the index of the `)` closing the `(` at body index `open`, -1 when none does before `hi`
def private close_of(pp : Preprocessor; open, hi : int) : int {
    var nest = 0
    for (i in range(open, hi)) {
        let kind = pp.macro_body[i].kind
        if (kind == int(PpTok.LPAREN)) {
            nest++
        } elif (kind == int(PpTok.RPAREN)) {
            nest--
            return i if (nest == 0)
        }
    }
    return -1
}

// the times parameter `p` of `m` is held by the expansion of body indices `lo .. hi`
def private param_uses(var pp : Preprocessor; m, p, lo, hi : int) : int {
    let sym = pp.macros[m].params[p]
    var total = 0
    var j = lo
    while (j < hi) {
        let h = pp.macro_body[j]
        if (h.kind == int(PpTok.HASH) || h.kind == int(PpTok.HASHHASH)) {
            return -1 if (j + 1 < hi && pp.macro_body[j + 1].sym == sym || h.kind == int(PpTok.HASHHASH) && j > lo && pp.macro_body[j - 1].sym == sym)
            j++
            continue
        }
        let called = h.kind == int(PpTok.IDENTIFIER) && j + 1 < hi && pp.macro_body[j + 1].kind == int(PpTok.LPAREN)
        if (h.kind == int(PpTok.IDENTIFIER) && h.sym == sym) {
            return -1 if (called)
            total++
            j++
            continue
        }
        if (called && param_index(pp, m, h.sym) >= 0) {
            let close = close_of(pp, j + 1, hi)
            return -1 if (close < 0 || param_uses(pp, m, p, j + 2, close) != 0)
            j = close + 1
            continue
        }
        let callee = called ? called_definition(pp, h.sym) : -1
        if (callee == -1 || (callee >= 0 && !pp.macros[callee].function_like) || callee == m) {
            j++
            continue
        }
        let close = close_of(pp, j + 1, hi)
        return -1 if (close < 0)
        var a = j + 2
        var k = 0
        while (true) {
            let end = arg_end(pp, a, close)
            let n = param_uses(pp, m, p, a, end)
            return -1 if (n < 0)
            if (n > 0) {
                return -1 if (callee < 0 || k >= length(pp.macros[callee].params))
                let u = pp_macro_uses(pp, callee, k)
                return -1 if (u < 0)
                total += n * u
            }
            k++
            break if (end >= close)
            a = end + 1
        }
        j = close + 1
    }
    return total
}

// the end of the argument from body index `from` before `close`: its comma at the top level, or `close`
def private arg_end(pp : Preprocessor; from, close : int) : int {
    var nest = 0
    for (i in range(from, close)) {
        let kind = pp.macro_body[i].kind
        if (kind == int(PpTok.LPAREN)) {
            nest++
        } elif (kind == int(PpTok.RPAREN)) {
            nest--
        } elif (kind == int(PpTok.COMMA) && nest == 0) {
            return i
        }
    }
    return close
}
