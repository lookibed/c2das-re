options gen2
options indenting = 4

module pp_expand public

require strings
require daslib/strings_boost
require pp_directives public

//! A token list the expander rescans: a macro's replacement, a pushed-back token, an argument
//! being pre-expanded or a directive's line. `macro` (an index of `Preprocessor.macros`, -1 for
//! none) is disabled while the context is on the stack; reading past the end of a `barrier`
//! context is the end of the input, not a read of the context below.
struct PpContext {
    toks : array<PpOutToken>
    pos : int
    macro : int
    barrier : bool
}

//! The arguments of one function-like call, a slot per nesting depth, reused: argument `i` is
//! `raw[raw_at[i] .. raw_at[i + 1])` as written and `exp[exp_at[i].x .. exp_at[i].y)` macro-expanded,
//! `exp_at[i].x` -1 until it is asked for; `elided` when the call wrote no variadic argument.
struct PpInvocation {
    raw : array<PpOutToken>
    raw_at : array<int>
    exp : array<PpOutToken>
    exp_at : array<int2>
    elided : bool
}

//! A name the preprocessor itself answers.
enum PpBuiltin {
    none
    file
    line
    counter
    date
    time
    timestamp
    include_level
    base_file
    file_name
    pragma
    evaluated       //!< clang's `__has_*` family and the like: the `#if` evaluator's, handed out as a name
}

//! How a function-like macro's call ended: replaced, refused with clang's error, or unterminated.
enum private PpCallRead {
    expanded
    refused
    unterminated
}

//! How a `_Pragma` read ended: done (or kept for the rescan, the operand given back), a token to
//! hand out in its place, or the end of the input.
enum private PragmaRead {
    done
    token
    end
}

//! The kind of the placemarker of an empty operand of `##` (C11 6.10.3.3p2), never handed out.
let private PLACEMARKER = -1

//! The macro expansion of `ARCHITECTURE_EXPAND.md` over the directive layer: the context
//! stack, the macros it disables, and the state of a read in progress.
class PpExpander : PpExpansion {
    ctx : array<PpContext>
    spare : array<array<PpOutToken>>
    inv : array<PpInvocation>
    depth : int                         //!< the invocation slots in use
    disabled : array<int>               //!< per macro index: the contexts on the stack expanding it
    ahead : PpOutToken                  //!< a source token read past and given back
    has_ahead : bool
    carry_bol : bool                    //!< an empty expansion's place, given to the next token
    carry_space : bool
    condition : bool                    //!< expanding an `#if` line: `defined`'s operand stays
    defined_state : int                 //!< 1 after `defined`, 2 after `defined (`; 3 after `__has_include`, 4 after its `(`, 5 in its `< ... >`; 6 after a query whose operand stays, 7 in its `( ... )`
    pre_expanding : int                 //!< the arguments being macro-expanded (C11 6.10.3.1): a `_Pragma` read then is done at the rescan
    counter : int
    epoch : int64                       //!< the seconds since 1970 `__DATE__`, `__TIME__` and `__TIMESTAMP__` show, in UTC
    scratch : PpLexer                   //!< re-lexes a pasted spelling and a `_Pragma` operand
    builtin_of : table<int; PpBuiltin>

    def override next_token(var pp : Preprocessor) : bool {
        while (!empty(self.ctx) && !self.ctx[length(self.ctx) - 1].barrier
                && self.ctx[length(self.ctx) - 1].pos >= length(self.ctx[length(self.ctx) - 1].toks)) {
            pop_context(self)
        }
        if (empty(self.ctx) && self.depth == 0 && !self.has_ahead) {
            self.text |> clear()
        }
        var t : PpOutToken
        return false if (!next_expanded(self, pp, t))
        pp.tok = t
        return true
    }

    def override expand_line(var pp : Preprocessor; condition : bool) : void {
        expand_held_line(self, pp, condition)
    }

    def override macro_changed(var pp : Preprocessor; name : PpToken; undef : bool) : void {
        builtin_changed(self, pp, name, undef)
    }
    def override is_builtin(pp : Preprocessor; sym : int) : bool => key_exists(builtin_of, sym)
}

def private diag(var pp : Preprocessor; severity : PpSeverity; t : PpOutToken; what : string) {
    pp.diags |> push(PpDiagnostic(severity = severity, file = t.tok.file, offset = t.tok.offset, line = t.tok.line, col = t.tok.col,
                                  pname = t.pname, pline = t.pline, what = what, raised = pp_reader_place(pp.lx)))
}

// Spellings

//! the bytes of `t`'s spelling appended to `dst`
def private put_spelling(ex : PpExpander; var pp : Preprocessor; t : PpOutToken; var dst : array<uint8>) {
    if (t.spelled == PpSpelled.source) {
        let data = pp_buffer_data(pp, t.buffer)
        dst |> reserve(length(dst) + t.len)
        for (i in range(t.at, t.at + t.len)) {
            dst |> push(unsafe(data[i]))
        }
    } elif (t.spelled == PpSpelled.body) {
        dst |> reserve(length(dst) + t.len)
        for (i in range(t.at, t.at + t.len)) {
            dst |> push(pp.macro_text[i])
        }
    } elif (t.spelled == PpSpelled.scratch) {
        dst |> reserve(length(dst) + t.len)
        for (i in range(t.at, t.at + t.len)) {
            dst |> push(ex.text[i])
        }
    } else {
        peek_data(pp_name(pp, t.tok.sym)) $(chars) {
            for (c in chars) {
                dst |> push(c)
            }
        }
    }
}

//! a token of kind `kind` spelled by the text pool from `at` to its end, at the place of `place`
def private pooled_token(ex : PpExpander; kind, at : int; place : PpOutToken) : PpOutToken {
    var t = place
    t.tok.kind = kind
    t.tok.sym = -1
    t.painted = false
    t.spelled = PpSpelled.scratch
    t.at = at
    t.len = length(ex.text) - at
    return t
}

// The context stack

def private buffer(var ex : PpExpander) : array<PpOutToken> {
    var b : array<PpOutToken>
    if (!empty(ex.spare)) {
        b <- ex.spare[length(ex.spare) - 1]
        ex.spare |> pop()
    }
    return <- b
}

def private recycle(var ex : PpExpander; var b : array<PpOutToken>) {
    b |> clear()
    ex.spare |> emplace(b)
}

def private disabled(ex : PpExpander; m : int) : bool => m < length(ex.disabled) && ex.disabled[m] > 0

def private push_context(var ex : PpExpander; var toks : array<PpOutToken>; macro : int; barrier : bool) {
    if (macro >= 0) {
        if (macro >= length(ex.disabled)) {
            ex.disabled |> resize(macro + 1)
        }
        ex.disabled[macro]++
    }
    ex.ctx |> emplace(PpContext(toks <- toks, macro = macro, barrier = barrier))
}

//! the top context removed and its macro enabled again
[arch(at="ARCHITECTURE_EXPAND.md#pp-context")]
def private pop_context(var ex : PpExpander) {
    let top = length(ex.ctx) - 1
    if (ex.ctx[top].macro >= 0) {
        ex.disabled[ex.ctx[top].macro]--
    }
    var toks <- ex.ctx[top].toks
    ex.ctx |> pop()
    recycle(ex, toks)
}

//! the next token, unexpanded: of the top context, past the end of exhausted contexts (each popped,
//! its macro enabled again), else of the source; the index of the context it came from, -1 for the
//! source, -2 at a barrier's end or the end of the unit
[arch(at="ARCHITECTURE_EXPAND.md#pp-context")]
def private read_raw(var ex : PpExpander; var pp : Preprocessor; var t : PpOutToken) : int {
    while (!empty(ex.ctx)) {
        let top = length(ex.ctx) - 1
        if (ex.ctx[top].pos < length(ex.ctx[top].toks)) {
            t = ex.ctx[top].toks[ex.ctx[top].pos]
            ex.ctx[top].pos++
            return top
        }
        return -2 if (ex.ctx[top].barrier)
        pop_context(ex)
    }
    if (ex.has_ahead) {
        ex.has_ahead = false
        t = ex.ahead
        return -1
    }
    return -2 if (!pp_next_directive_token(pp))
    t = pp.tok
    return -1
}

//! whether a `(` comes next, read past when it does; any other token, or one of the source read past a
//! directive line, is given back
[arch(at="ARCHITECTURE_EXPAND.md#pp-context")]
def private next_is_lparen(var ex : PpExpander; var pp : Preprocessor) : bool {
    var n : PpOutToken
    let directives = pp.directives_read
    let from = read_raw(ex, pp, n)
    return false if (from == -2)
    return true if (n.tok.kind == int(PpTok.LPAREN) && (from >= 0 || pp.directives_read == directives))
    if (from >= 0) {
        ex.ctx[from].pos--
    } else {
        ex.ahead = n
        ex.has_ahead = true
    }
    return false
}

// Reading with expansion

//! Read the next fully expanded token into `t`; false at a barrier's end or the end of the unit.
[arch(at="ARCHITECTURE_EXPAND.md#pp-context")]
def private next_expanded(var ex : PpExpander; var pp : Preprocessor; var t : PpOutToken) : bool {
    while (true) {
        let from = read_raw(ex, pp, t)
        if (from == -2) {
            ex.carry_bol = false
            ex.carry_space = false
            return false
        }
        if (ex.carry_bol || ex.carry_space) {
            t.tok.at_bol = t.tok.at_bol || ex.carry_bol
            t.tok.has_space = t.tok.has_space || ex.carry_space
            ex.carry_bol = false
            ex.carry_space = false
        }
        return true if ((ex.condition && defined_operand(ex, pp, t)) || t.tok.kind != int(PpTok.IDENTIFIER) || t.painted)
        let m = pp.macro_of?[t.tok.sym] ?? -1
        if (m < 0) {
            let builtin = ex.builtin_of?[t.tok.sym] ?? PpBuiltin.none
            return true if (builtin == PpBuiltin.none || builtin == PpBuiltin.evaluated)
            if (builtin == PpBuiltin.pragma) {
                let done = do_pragma_operator(ex, pp, t)
                return done == PragmaRead.token if (done != PragmaRead.done)
                continue
            }
            t = builtin_token(ex, pp, builtin, t)
            return true
        }
        if (disabled(ex, m)) {
            t.painted = true
            return true
        }
        if (pp.macros[m].function_like) {
            return true if (!next_is_lparen(ex, pp))
            let called = call_function_like(ex, pp, m, t)
            return true if (called == PpCallRead.refused)
            continue
        }
        expand_macro(ex, pp, m, t, -1, t)
    }
    return false
}

//! in an `#if` line, `defined X`, `defined ( X )` and the `< ... >` of `__has_include ( < ... > )`
//! and `__has_include_next`: whether `t` is `defined` or a part of an operand that is not expanded
[arch(at="ARCHITECTURE_EXPAND.md#pp-expand-line")]
def private defined_operand(var ex : PpExpander; pp : Preprocessor; t : PpOutToken) : bool {
    let kind = t.tok.kind
    if (ex.defined_state == 1) {
        ex.defined_state = kind == int(PpTok.LPAREN) ? 2 : 0
        return true
    }
    if (ex.defined_state == 2) {
        ex.defined_state = 0
        return true
    }
    if (ex.defined_state == 3 || ex.defined_state == 4) {
        let opens = ex.defined_state == 3 ? kind == int(PpTok.LPAREN) : kind == int(PpTok.LESS)
        ex.defined_state = opens ? ex.defined_state + 1 : 0
        return opens
    }
    if (ex.defined_state == 5) {
        ex.defined_state = kind == int(PpTok.GREATER) ? 0 : 5
        return true
    }
    if (ex.defined_state == 6) {
        ex.defined_state = kind == int(PpTok.LPAREN) ? 7 : 0
        return kind == int(PpTok.LPAREN)
    }
    if (ex.defined_state == 7) {
        ex.defined_state = kind == int(PpTok.RPAREN) ? 0 : 7
        return true
    }
    return false if (kind != int(PpTok.IDENTIFIER))
    if (t.tok.sym == pp.sym_defined) {
        ex.defined_state = 1
        return true
    }
    if (t.tok.sym == pp.sym_has_include || t.tok.sym == pp.sym_has_include_next || t.tok.sym == pp.sym_has_embed) {
        ex.defined_state = 3
        return true
    }
    if (key_exists(pp.unexpanded_query, t.tok.sym)) {
        ex.defined_state = 6
        return true
    }
    return false
}

// Calls

//! the arguments of a call of `m` after its `(`, into the invocation slot `d`, up to the matching
//! `)` read into `rparen`; false at the end of the input first. A name of a macro disabled when it
//! is read is painted (C11 6.10.3.4p2): reading on can leave that macro's context.
[arch(at="ARCHITECTURE_EXPAND.md#pp-calls")]
def private collect_args(var ex : PpExpander; var pp : Preprocessor; m, d : int; var rparen : PpOutToken) : bool {
    ex.inv[d].raw |> clear()
    ex.inv[d].raw_at |> clear()
    ex.inv[d].exp |> clear()
    ex.inv[d].exp_at |> clear()
    ex.inv[d].raw_at |> push(0)
    let nparams = length(pp.macros[m].params)
    let variadic = pp.macros[m].variadic
    var nest = 0
    var t : PpOutToken
    while (true) {
        return false if (read_raw(ex, pp, t) == -2)
        if (t.tok.at_bol) {
            t.tok.at_bol = false
            t.tok.has_space = true
        }
        let kind = t.tok.kind
        if (kind == int(PpTok.IDENTIFIER) && !t.painted) {
            let named = pp.macro_of?[t.tok.sym] ?? -1
            t.painted = named >= 0 && disabled(ex, named)
        }
        if (kind == int(PpTok.LPAREN)) {
            nest++
        } elif (kind == int(PpTok.RPAREN)) {
            if (nest == 0) {
                rparen = t
                ex.inv[d].raw_at |> push(length(ex.inv[d].raw))
                return true
            }
            nest--
        } elif (kind == int(PpTok.COMMA) && nest == 0 && !(variadic && length(ex.inv[d].raw_at) >= nparams)) {
            ex.inv[d].raw_at |> push(length(ex.inv[d].raw))
            continue
        }
        ex.inv[d].raw |> push(t)
    }
    return false
}

//! whether the arguments of slot `d` fit `m` (C11 6.10.3p4 and p12, clang's GNU reading): a
//! missing variadic argument is an empty one, marked elided; false with clang's error
[arch(at="ARCHITECTURE_EXPAND.md#pp-calls")]
def private arguments_fit(var ex : PpExpander; var pp : Preprocessor; m, d : int; name : PpOutToken) : bool {
    let nparams = length(pp.macros[m].params)
    var k = length(ex.inv[d].raw_at) - 1
    let empty_call = k == 1 && ex.inv[d].raw_at[1] == 0
    ex.inv[d].elided = false
    if (nparams == 0) {
        if (!empty_call) {
            diag(pp, PpSeverity.error, name, "too many arguments provided to function-like macro invocation")
            return false
        }
        ex.inv[d].raw_at |> resize(1)
        k = 0
    } elif (pp.macros[m].variadic) {
        let named = nparams - 1
        if (k < named) {
            diag(pp, PpSeverity.error, name, "too few arguments provided to function-like macro invocation")
            return false
        }
        if (k == named) {
            ex.inv[d].raw_at |> push(length(ex.inv[d].raw))
            k++
            ex.inv[d].elided = true
        } elif (named == 0 && empty_call) {
            ex.inv[d].elided = true
        }
    } elif (k != nparams) {
        diag(pp, PpSeverity.error, name, k > nparams ? "too many arguments provided to function-like macro invocation" : "too few arguments provided to function-like macro invocation")
        return false
    }
    ex.inv[d].exp_at |> resize(k)
    for (i in range(k)) {
        ex.inv[d].exp_at[i] = int2(-1, -1)
    }
    return true
}

//! a call of the function-like `m` whose name `name` is read and whose `(` is next: its arguments
//! collected and the replacement pushed; on clang's error the name is handed out as it is
//! (`refused`), or with the call at the end of the input nothing is (`unterminated`)
[arch(at="ARCHITECTURE_EXPAND.md#pp-calls")]
def private call_function_like(var ex : PpExpander; var pp : Preprocessor; m : int; name : PpOutToken) : PpCallRead {
    let d = ex.depth
    if (d >= length(ex.inv)) {
        ex.inv |> resize(d + 1)
    }
    ex.depth++
    var rparen : PpOutToken
    var read = PpCallRead.expanded
    if (!collect_args(ex, pp, m, d, rparen)) {
        diag(pp, PpSeverity.error, name, "unterminated function-like macro invocation")
        read = PpCallRead.unterminated
    } elif (!arguments_fit(ex, pp, m, d, name)) {
        read = PpCallRead.refused
    } else {
        expand_macro(ex, pp, m, name, d, rparen)
    }
    ex.depth--
    return read
}

//! the call of `m` recorded: its name, the outermost name's presumed place, the presumed line of
//! `last` (the `)`, or the name) and the spans of the arguments of slot `d` (none when -1)
[arch(at="ARCHITECTURE_EXPAND.md#pp-record")]
def private record_call(var ex : PpExpander; m, d : int; name, last : PpOutToken) : int {
    let outer = name.call >= 0
    var call = PpCall(macro = m, name = name.tok, parent = name.call, pline = outer ? ex.calls[name.call].pline : name.pline,
                      pname = outer ? ex.calls[name.call].pname : name.pname,
                      end_pline = last.call >= 0 ? ex.calls[last.call].end_pline : last.pline, first_arg = length(ex.call_args))
    if (d >= 0) {
        call.arg_count = length(ex.inv[d].raw_at) - 1
        for (i in range(call.arg_count)) {
            let lo = ex.inv[d].raw_at[i]
            let hi = ex.inv[d].raw_at[i + 1]
            var arg = PpCallArg(file = -1, from = -1, to = -1)
            if (hi > lo) {
                let a & = unsafe(ex.inv[d].raw[lo].tok)
                let b & = unsafe(ex.inv[d].raw[hi - 1].tok)
                if (ex.inv[d].raw[lo].call < 0 && ex.inv[d].raw[hi - 1].call < 0 && a.file == b.file && b.offset >= a.offset) {
                    arg = PpCallArg(file = a.file, from = a.offset, to = b.offset + b.len)
                }
            }
            ex.call_args |> push(arg)  // nolint:PERF006 - an exact reserve per call reallocates the record every call
        }
    }
    ex.calls |> push(call)
    return length(ex.calls) - 1
}

//! the replacement of `m` called by `name` (arguments in slot `d`, -1 for an object-like macro;
//! `last` its end) pushed as a context that disables `m`; the first token takes the name's place on
//! its line, and an empty replacement gives it to the next token
[arch(at="ARCHITECTURE_EXPAND.md#pp-substitute")]
def private expand_macro(var ex : PpExpander; var pp : Preprocessor; m : int; name : PpOutToken; d : int; last : PpOutToken) {
    let call = record_call(ex, m, d, name, last)
    var out <- buffer(ex)
    let first = pp.macros[m].first
    substitute(ex, pp, m, d, first, first + pp.macros[m].count, out)
    drop_placemarkers(out)

    for (o in out) {
        o.call = call
        o.pline = ex.calls[call].pline
        o.pname = ex.calls[call].pname
    }
    if (empty(out)) {
        ex.carry_bol = ex.carry_bol || name.tok.at_bol
        ex.carry_space = ex.carry_space || name.tok.has_space
        recycle(ex, out)
        return
    }
    out[0].tok.at_bol = name.tok.at_bol
    out[0].tok.has_space = name.tok.has_space
    push_context(ex, out, m, false)
}

// Substitution

//! the placemarkers of a finished replacement dropped (C11 6.10.3.3p3)
def private drop_placemarkers(var toks : array<PpOutToken>) {
    var n = 0
    for (i in range(length(toks))) {  // nolint:PERF018 - compacts in place, writing behind the read
        if (toks[i].tok.kind != PLACEMARKER) {
            toks[n] = toks[i]
            n++
        }
    }
    toks |> resize(n)
}

//! the parameter of `m` that `h` names, -1 when none
def private param_of(pp : Preprocessor; m : int; h : PpHeld) : int {
    return -1 if (h.kind != int(PpTok.IDENTIFIER) || !pp.macros[m].function_like)
    let params & = unsafe(pp.macros[m].params)
    for (i in range(length(params))) {
        return i if (params[i] == h.sym)
    }
    return -1
}

//! a body token as a token of the replacement
def private body_token(h : PpHeld) : PpOutToken {
    return PpOutToken(tok = PpToken(kind = h.kind, file = h.file, offset = h.offset, len = h.len, line = h.line, col = h.col, sym = h.sym,
                                    has_space = h.has_space), spelled = PpSpelled.body, at = h.at, len = h.len, call = -1)
}

//! the index of the `)` closing the `(` at body index `open`, `hi` when none does
def private closing_paren(pp : Preprocessor; open, hi : int) : int {
    var nest = 0
    for (i in range(open, hi)) {
        if (pp.macro_body[i].kind == int(PpTok.LPAREN)) {
            nest++
        } elif (pp.macro_body[i].kind == int(PpTok.RPAREN)) {
            nest--
            return i if (nest == 0)
        }
    }
    return hi
}

//! whether body index `i` of `m` starts `__VA_OPT__ (`: in a function-like macro that is not variadic
//! it is clang's warning at the `#define`, and empty
def private va_opt_at(pp : Preprocessor; m, i, hi : int) : bool {
    return (pp.macros[m].function_like && pp.macro_body[i].sym == pp.sym_va_opt && i + 1 < hi
        && pp.macro_body[i + 1].kind == int(PpTok.LPAREN))
}

//! argument `p` of slot `d` macro-expanded, once, as a context of its own whose end ends the
//! input (C11 6.10.3.1), as clang does in an `#if` line too: `defined`'s operand is expanded there;
//! its range in the slot's `exp`
[arch(at="ARCHITECTURE_EXPAND.md#pp-substitute")]
def private expanded_arg(var ex : PpExpander; var pp : Preprocessor; d, p : int) : int2 {
    return ex.inv[d].exp_at[p] if (ex.inv[d].exp_at[p].x >= 0)
    var toks <- buffer(ex)
    toks |> reserve(ex.inv[d].raw_at[p + 1] - ex.inv[d].raw_at[p])
    for (i in range(ex.inv[d].raw_at[p], ex.inv[d].raw_at[p + 1])) {
        toks |> push(ex.inv[d].raw[i])
    }
    push_context(ex, toks, -1, true)
    let bol = ex.carry_bol
    let space = ex.carry_space
    let state = ex.defined_state
    let condition = ex.condition
    ex.carry_bol = false
    ex.carry_space = false
    ex.defined_state = 0
    ex.condition = false
    ex.pre_expanding++
    let start = length(ex.inv[d].exp)
    var t : PpOutToken
    while (next_expanded(ex, pp, t)) {
        ex.inv[d].exp |> push(t)
    }
    pop_context(ex)
    ex.pre_expanding--
    ex.carry_bol = bol
    ex.carry_space = space
    ex.defined_state = state
    ex.condition = condition
    ex.inv[d].exp_at[p] = int2(start, length(ex.inv[d].exp))
    return ex.inv[d].exp_at[p]
}

//! `lhs ## rhs` (C11 6.10.3.3): the joined spelling, one token by the pp lexer's rules, in the
//! place of `lhs`; with clang's error, and both tokens kept, when it is no single token
[arch(at="ARCHITECTURE_EXPAND.md#pp-paste")]
def private paste(var ex : PpExpander; var pp : Preprocessor; var out : array<PpOutToken>; rhs : PpOutToken) {
    let last = length(out) - 1
    let lhs = out[last]
    let at = length(ex.text)
    put_spelling(ex, pp, lhs, ex.text)
    put_spelling(ex, pp, rhs, ex.text)
    let kind = pasted_kind(ex, at)
    if (kind < 0) {
        diag(pp, PpSeverity.error, lhs, "pasting formed '{slice(ex.text, at, length(ex.text))}', an invalid preprocessing token")
        ex.text |> resize(at)
        out |> push(rhs)
        return
    }
    var t = lhs
    t.tok.kind = kind
    t.tok.sym = -1
    t.painted = false
    t.at = at
    t.len = length(ex.text) - at
    t.spelled = PpSpelled.scratch
    if (kind == int(PpTok.IDENTIFIER)) {
        t.tok.sym = interned_bytes(pp, ex.text, at)
        t.spelled = PpSpelled.symbol
        ex.text |> resize(at)
        if (pp_poisoned(pp, t.tok.sym)) {
            diag(pp, PpSeverity.error, lhs, "attempt to use a poisoned identifier")
        }
    }
    out[last] = t
}

//! the symbol of the name `bytes` spell from `at` to their end; the bytes are read in place, and
//! copied only for a name the interner has not seen
def private interned_bytes(var pp : Preprocessor; var bytes : array<uint8>; at : int) : int {
    let len = length(bytes) - at
    bytes |> push(0u8)
    let view = unsafe(reinterpret<string>(unsafe(addr(bytes[at]))))
    let known = symbol_count(pp.lx.flex.syms)
    let id = intern_name(pp.lx.flex.syms, view)
    if (id == known) {
        pp.lx.flex.syms.names[id] = clone_string(view)
    }
    bytes |> resize(at + len)
    return id
}

//! the kind of the one pp-token the text pool spells from `at` to its end, -1 when it is none or
//! more than one: a run of letters, digits and `_` is a name or a number without a lexer; anything
//! else is lexed from the scratch lexer's own buffer
[arch(at="ARCHITECTURE_EXPAND.md#pp-paste")]
def private pasted_kind(var ex : PpExpander; at : int) : int {
    var simple = true
    for (i in range(at, length(ex.text))) {
        let c = int(ex.text[i])
        simple = simple && (is_alpha(c) || is_number(c) || c == '_')
    }
    if (simple) {
        return int(is_number(int(ex.text[at])) ? PpTok.PP_NUMBER : PpTok.IDENTIFIER)
    }
    var bytes <- ex.scratch.flex.bytes
    bytes |> clear()
    bytes |> reserve(length(ex.text) - at + 1)
    for (i in range(at, length(ex.text))) {
        bytes |> push(ex.text[i])
    }
    pp_open(ex.scratch, bytes, -1)
    return -1 if (!pp_next(ex.scratch) || ex.scratch.tok.offset != 0 || ex.scratch.tok.len != length(ex.text) - at)
    let kind = ex.scratch.tok.kind
    return -1 if (kind == int(PpTok.OTHER) || pp_next(ex.scratch))
    return kind
}

//! the tokens `src[lo .. hi)` appended to `out` as an operand: pasted onto the last token when
//! `paste_before`, a placemarker for an empty operand that `##` follows; the first token takes
//! `space` when it is not pasted
[arch(at="ARCHITECTURE_EXPAND.md#pp-paste")]
def private append_operand(var ex : PpExpander; var pp : Preprocessor; var out : array<PpOutToken>; src : array<PpOutToken>; lo, hi : int;
                           paste_before, paste_after, space : bool) {
    if (hi == lo) {
        if (!paste_before && paste_after) {
            out |> push(PpOutToken(tok = PpToken(kind = PLACEMARKER)))
        }
        return
    }
    var start = lo
    out |> reserve(length(out) + hi - lo)
    if (paste_before && !empty(out)) {
        if (out[length(out) - 1].tok.kind == PLACEMARKER) {
            out |> pop()
        } else {
            paste(ex, pp, out, src[lo])
            start++
        }
    }
    for (i in range(start, hi)) {
        out |> push(src[i])
        if (i == lo) {
            out[length(out) - 1].tok.has_space = out[length(out) - 1].tok.has_space || space
        }
    }
}

//! one token appended to `out`, pasted onto the last token when `paste_before`
[arch(at="ARCHITECTURE_EXPAND.md#pp-paste")]
def private append_token(var ex : PpExpander; var pp : Preprocessor; var out : array<PpOutToken>; t : PpOutToken; paste_before : bool) {
    if (paste_before && !empty(out)) {
        if (out[length(out) - 1].tok.kind != PLACEMARKER) {
            paste(ex, pp, out, t)
            return
        }
        out |> pop()
    }
    out |> push(t)
}

//! the replacement of body indices `lo .. hi` of `m` into `out` (C11 6.10.3.1-3): `#` stringifies
//! an argument as written, an operand of `##` is its argument as written, any other parameter its
//! argument expanded, and `__VA_OPT__ ( ... )` its content when the variadic argument expands to
//! a token; clang's leading-space rule throughout
[arch(at="ARCHITECTURE_EXPAND.md#pp-substitute")]
def private substitute(var ex : PpExpander; var pp : Preprocessor; m, d, lo, hi : int; var out : array<PpOutToken>) {
    var space = false
    var i = lo
    while (i < hi) {
        let b = pp.macro_body[i]
        if (b.kind == int(PpTok.HASHHASH)) {
            i++
            continue
        }
        let paste_before = i > lo && pp.macro_body[i - 1].kind == int(PpTok.HASHHASH)
        if (i > lo && !paste_before && b.has_space) {
            space = true
        }
        if (b.kind == int(PpTok.HASH) && pp.macros[m].function_like && i + 1 < hi) {
            var s : PpOutToken
            var next = i + 2
            let p = param_of(pp, m, pp.macro_body[i + 1])
            if (p >= 0) {
                s = stringified(ex, pp, ex.inv[d].raw, ex.inv[d].raw_at[p], ex.inv[d].raw_at[p + 1], body_token(b))
            } elif (va_opt_at(pp, m, i + 1, hi)) {
                let close = closing_paren(pp, i + 2, hi)
                var content <- va_opt_content(ex, pp, m, d, i + 3, close)
                s = stringified(ex, pp, content, 0, length(content), body_token(b))
                recycle(ex, content)
                next = close + 1
            } else {
                next = -1
            }
            if (next >= 0) {
                s.tok.has_space = b.has_space || space
                space = false
                append_token(ex, pp, out, s, paste_before)
                i = next
                continue
            }
        }
        if (va_opt_at(pp, m, i, hi)) {
            let close = closing_paren(pp, i + 1, hi)
            var content <- va_opt_content(ex, pp, m, d, i + 2, close)
            i = close + 1
            append_operand(ex, pp, out, content, 0, length(content), paste_before, i < hi && pp.macro_body[i].kind == int(PpTok.HASHHASH), space && !paste_before)
            space = space && empty(content)
            recycle(ex, content)
            continue
        }
        let p = param_of(pp, m, b)
        if (p < 0) {
            var t = body_token(b)
            t.tok.has_space = t.tok.has_space || space
            space = false
            append_token(ex, pp, out, t, paste_before)
            i++
            continue
        }
        let paste_after = i + 1 < hi && pp.macro_body[i + 1].kind == int(PpTok.HASHHASH)
        i++
        let lo_raw = ex.inv[d].raw_at[p]
        let hi_raw = ex.inv[d].raw_at[p + 1]
        let gnu_comma = (paste_before && pp.macros[m].variadic && p == length(pp.macros[m].params) - 1 && !empty(out)
            && out[length(out) - 1].tok.kind == int(PpTok.COMMA))
        if (gnu_comma && ex.inv[d].elided) {
            out |> pop()
        } elif (gnu_comma) {
            append_operand(ex, pp, out, ex.inv[d].raw, lo_raw, hi_raw, false, paste_after, false)
        } elif (paste_before || paste_after) {
            append_operand(ex, pp, out, ex.inv[d].raw, lo_raw, hi_raw, paste_before, paste_after, space && !paste_before)
        } else {
            let r = expanded_arg(ex, pp, d, p)
            append_operand(ex, pp, out, ex.inv[d].exp, r.x, r.y, false, false, false)
            if (r.y > r.x) {
                out[length(out) - (r.y - r.x)].tok.has_space = space
            }
        }
        space = space && hi_raw == lo_raw
    }
}

//! the content of `__VA_OPT__ ( ... )`, body indices `lo .. hi` of `m`, replaced when the
//! variadic argument of slot `d` expands to at least one token, else empty
[arch(at="ARCHITECTURE_EXPAND.md#pp-substitute")]
def private va_opt_content(var ex : PpExpander; var pp : Preprocessor; m, d, lo, hi : int) : array<PpOutToken> {
    var content <- buffer(ex)
    return <- content if (!pp.macros[m].variadic)
    let r = expanded_arg(ex, pp, d, length(pp.macros[m].params) - 1)
    if (r.y > r.x) {
        substitute(ex, pp, m, d, lo, hi, content)
        drop_placemarkers(content)
    }
    return <- content
}

//! `# arg` (C11 6.10.3.2): the tokens `src[lo .. hi)` spelled in a string literal, one blank where
//! a token has space before it, `\` and `"` escaped in string and character literals, a final
//! unescaped `\` dropped with clang's warning; at `at`
[arch(at="ARCHITECTURE_EXPAND.md#pp-stringify")]
def private stringified(var ex : PpExpander; var pp : Preprocessor; src : array<PpOutToken>; lo, hi : int; at : PpOutToken) : PpOutToken {
    var t = at
    t.tok.kind = int(PpTok.STRING_LITERAL)
    t.tok.sym = -1
    t.painted = false
    t.spelled = PpSpelled.scratch
    t.at = length(ex.text)
    ex.text |> push('"'u8)
    for (i in range(lo, hi)) {
        let k = src[i].tok.kind
        if (i > lo && src[i].tok.has_space) {
            ex.text |> push(' 'u8)
        }
        let from = length(ex.text)
        put_spelling(ex, pp, src[i], ex.text)
        if (k == int(PpTok.STRING_LITERAL) || k == int(PpTok.CHAR_CONSTANT)) {
            escape_from(ex, from)
        }
    }
    var backslashes = 0
    while (length(ex.text) - backslashes - 1 > t.at && ex.text[length(ex.text) - backslashes - 1] == '\\'u8) {
        backslashes++
    }
    if (backslashes % 2 == 1) {
        ex.text |> pop()
        diag(pp, PpSeverity.warning, src[hi - 1], "invalid string literal, ignoring final '\\'")
    }
    ex.text |> push('"'u8)
    t.len = length(ex.text) - t.at
    return t
}

//! the bytes of the text pool from `from` on with `\` and `"` escaped
def private escape_from(var ex : PpExpander; from : int) {
    var extra = 0
    for (i in range(from, length(ex.text))) {
        extra += ex.text[i] == '\\'u8 || ex.text[i] == '"'u8 ? 1 : 0
    }
    return if (extra == 0)
    var j = length(ex.text) - 1
    ex.text |> resize(length(ex.text) + extra)
    var k = length(ex.text) - 1
    while (j >= from) {
        let c = ex.text[j]
        ex.text[k] = c
        k--
        if (c == '\\'u8 || c == '"'u8) {
            ex.text[k] = '\\'u8
            k--
        }
        j--
    }
}

// Builtins

let private MONTHS <- ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

let private WEEKDAYS <- ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

//! the UTC calendar of `epoch` seconds: year, month (1-12), day, hours, minutes, seconds, weekday
//! (0 Sunday), by days-from-civil's inverse
def private civil(epoch : int64) : tuple<y : int; mo : int; d : int; h : int; mi : int; s : int; wd : int> {
    let days = int(epoch >= 0l ? epoch / 86400l : (epoch - 86399l) / 86400l)
    let secs = int(epoch - int64(days) * 86400l)
    let z = days + 719468
    let era = (z >= 0 ? z : z - 146096) / 146097
    let doe = z - era * 146097
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    let mp = (5 * doy + 2) / 153
    let day = doy - (153 * mp + 2) / 5 + 1
    let month = mp < 10 ? mp + 3 : mp - 9
    let year = yoe + era * 400 + (month <= 2 ? 1 : 0)
    let wd = (days % 7 + 11) % 7
    return (y = year, mo = month, d = day, h = secs / 3600, mi = secs / 60 % 60, s = secs % 60, wd = wd)
}

//! the decimal digits of `n` appended to the text pool
def private put_number(var ex : PpExpander; n : int64) {
    let at = length(ex.text)
    var v = n
    while (true) {
        ex.text |> push(uint8('0' + int(v % 10l)))
        v /= 10l
        break if (v == 0l)
    }
    var lo = at
    var hi = length(ex.text) - 1
    while (lo < hi) {
        let c = ex.text[lo]
        ex.text[lo] = ex.text[hi]
        ex.text[hi] = c
        lo++
        hi--
    }
}

//! `n`, 0 to 99, as two characters appended to the text pool, `pad` before a single digit
def private put_two(var ex : PpExpander; n : int; pad : uint8) {
    ex.text |> push(n < 10 ? pad : uint8('0' + n / 10))  // nolint:STYLE012 - appends to the pool
    ex.text |> push(uint8('0' + n % 10))
}

//! the bytes of `s` past its last `/` when `last_component`, appended to the text pool with `\` and
//! `"` escaped when `escaped`
def private put_text(var ex : PpExpander; s : string; escaped, last_component : bool) {
    peek_data(s) $(chars) {
        var from = 0
        if (last_component) {
            for (c, i in chars, count()) {
                if (c == '/'u8) {
                    from = i + 1
                }
            }
        }
        for (i in range(from, length(chars))) {
            let c = chars[i]
            if (escaped && (c == '\\'u8 || c == '"'u8)) {
                ex.text |> push('\\'u8)
            }
            ex.text |> push(c)
        }
    }
}

//! the token a builtin name `t` stands for (C11 6.10.8, clang's extensions): its place, its value
//! spelled in the text pool, no string made
[arch(at="ARCHITECTURE_EXPAND.md#pp-builtins")]
def private builtin_token(var ex : PpExpander; pp : Preprocessor; b : PpBuiltin; t : PpOutToken) : PpOutToken {
    let from_source = t.call < 0
    let pname = from_source ? t.pname : ex.calls[t.call].pname
    let at = length(ex.text)
    if (b == PpBuiltin.line) {
        put_number(ex, int64(from_source ? t.pline : ex.calls[t.call].end_pline))
        return pooled_token(ex, int(PpTok.PP_NUMBER), at, t)
    } elif (b == PpBuiltin.counter) {
        put_number(ex, int64(ex.counter))
        ex.counter++
        return pooled_token(ex, int(PpTok.PP_NUMBER), at, t)
    } elif (b == PpBuiltin.include_level) {
        put_number(ex, long_length(pp.frames))
        return pooled_token(ex, int(PpTok.PP_NUMBER), at, t)
    }
    ex.text |> push('"'u8)
    if (b == PpBuiltin.file || b == PpBuiltin.file_name) {
        put_text(ex, pp.names[pname], true, b == PpBuiltin.file_name)
    } elif (b == PpBuiltin.base_file) {
        put_text(ex, pp.files[0].path, true, false)
    } else {
        let c = civil(ex.epoch)
        if (b == PpBuiltin.timestamp) {
            put_text(ex, WEEKDAYS[c.wd], false, false)
            ex.text |> push(' 'u8)
        }
        if (b != PpBuiltin.time) {
            put_text(ex, MONTHS[c.mo - 1], false, false)
            ex.text |> push(' 'u8)
            put_two(ex, c.d, ' 'u8)
            ex.text |> push(' 'u8)
        }
        if (b == PpBuiltin.date) {
            put_number(ex, int64(c.y))
        } else {
            put_two(ex, c.h, '0'u8)
            ex.text |> push(':'u8)
            put_two(ex, c.mi, '0'u8)
            ex.text |> push(':'u8)
            put_two(ex, c.s, '0'u8)
        }
        if (b == PpBuiltin.timestamp) {
            ex.text |> push(' 'u8)
            put_number(ex, int64(c.y))
        }
    }
    ex.text |> push('"'u8)
    return pooled_token(ex, int(PpTok.STRING_LITERAL), at, t)
}

//! a `#define` (`undef` false) or an `#undef` of `name`: of a builtin name no macro defines, clang's
//! warning; an `#undef` removes the builtin for the rest of the unit, as clang does
[arch(at="ARCHITECTURE_EXPAND.md#pp-builtins")]
def private builtin_changed(var ex : PpExpander; var pp : Preprocessor; name : PpToken; undef : bool) {
    return if (!key_exists(ex.builtin_of, name.sym))
    if (!pp_defined(pp, name.sym)) {
        diag(pp, PpSeverity.warning, PpOutToken(tok = name, pname = pp.state.pname, pline = uint(name.line) + pp.state.line_delta),
             undef ? "undefining builtin macro" : "redefining builtin macro")
    }
    if (undef) {
        ex.builtin_of |> erase(name.sym)
    }
}

//! the text of the `_Pragma` string literal `str` (C11 6.10.9) as the scratch lexer's input: the
//! prefix and the quotes off, `\"` and `\\` read as one character each
def private open_destringized(var ex : PpExpander; var pp : Preprocessor; str : PpOutToken) {
    let span = pp_span_of(pp, str)
    var bytes <- ex.scratch.flex.bytes
    bytes |> clear()
    var open = 0
    while (unsafe(span.data[open]) != '"'u8) {
        open++
    }
    var i = open + 1
    while (i < span.len - 1) {
        let c = unsafe(span.data[i])
        if (c == '\\'u8 && i + 1 < span.len - 1 && (unsafe(span.data[i + 1]) == '\\'u8 || unsafe(span.data[i + 1]) == '"'u8)) {
            i++
        }
        bytes |> push(unsafe(span.data[i]))
        i++
    }
    pp_open(ex.scratch, bytes, str.tok.file)
}

//! `_Pragma ( string-literal )` read after the name `t` (C11 6.10.9), its operand read with
//! expansion as clang reads it. In an argument being macro-expanded the operand is given back and
//! `_Pragma` handed out, to be done at the rescan (6.10.3.4p3); else the destringized text is lexed
//! and done as a `#pragma` line, and the next token starts a line, as after the directive.
//! Malformed, it is clang's error, and the token read where another was expected is handed out in
//! `t`, as clang recovers
[arch(at="ARCHITECTURE_EXPAND.md#pp-builtins")]
def private do_pragma_operator(var ex : PpExpander; var pp : Preprocessor; var t : PpOutToken) : PragmaRead {
    let name = t
    let malformed = "_Pragma takes a parenthesized string literal"
    var lp, str, rp : PpOutToken
    if (!next_expanded(ex, pp, lp)) {
        diag(pp, PpSeverity.error, name, malformed)
        return PragmaRead.end
    }
    if (lp.tok.kind != int(PpTok.LPAREN)) {
        diag(pp, PpSeverity.error, name, malformed)
        t = lp
        return PragmaRead.token
    }
    if (!next_expanded(ex, pp, str)) {
        diag(pp, PpSeverity.error, name, malformed)
        return PragmaRead.end
    }
    if (str.tok.kind != int(PpTok.STRING_LITERAL)) {
        diag(pp, PpSeverity.error, name, malformed)
        t = str
        var more = t.tok.kind == int(PpTok.RPAREN) || next_expanded(ex, pp, t)
        while (more && t.tok.kind != int(PpTok.RPAREN) && !t.tok.at_bol) {
            more = next_expanded(ex, pp, t)
        }
        if (more && t.tok.kind == int(PpTok.RPAREN)) {
            more = next_expanded(ex, pp, t)
        }
        return more ? PragmaRead.token : PragmaRead.end
    }
    if (!next_expanded(ex, pp, rp)) {
        diag(pp, PpSeverity.error, name, malformed)
        return PragmaRead.end
    }
    if (rp.tok.kind != int(PpTok.RPAREN)) {
        diag(pp, PpSeverity.error, name, malformed)
        t = rp
        return PragmaRead.token
    }
    if (ex.pre_expanding > 0) {
        var operand <- buffer(ex)
        operand |> push(lp)
        operand |> push(str)
        operand |> push(rp)
        push_context(ex, operand, -1, false)
        return PragmaRead.token
    }
    pp.line |> clear()
    pp.line_text |> clear()
    open_destringized(ex, pp, str)
    while (pp_next(ex.scratch)) {
        let at = length(pp.line_text)
        let span = pp_token_range(ex.scratch)
        pp.line_text |> reserve(at + span.len)
        for (i in range(span.start, span.start + span.len)) {
            pp.line_text |> push(ex.scratch.flex.bytes[i])
        }
        let st & = unsafe(ex.scratch.tok)
        let sym = st.kind == int(PpTok.IDENTIFIER) ? interned_bytes(pp, pp.line_text, at) : -1
        pp.line |> push(PpHeld(kind = st.kind, sym = sym, file = name.tok.file, offset = name.tok.offset, line = name.tok.line, col = name.tok.col,
                               at = at, len = span.len, has_space = st.has_space))
    }
    pp_pragma_line(pp, name.tok)
    ex.carry_bol = true
    return PragmaRead.done
}

// Directive lines

//! `pp.line` macro-expanded in place: its tokens a barrier context, read with expansion, written
//! back with their spellings; in a `condition`, `defined`'s operands stay as written
[arch(at="ARCHITECTURE_EXPAND.md#pp-expand-line")]
def private expand_held_line(var ex : PpExpander; var pp : Preprocessor; condition : bool) {
    var toks <- buffer(ex)
    toks |> reserve(length(pp.line))
    for (h in pp.line) {
        var t = PpOutToken(tok = PpToken(kind = h.kind, file = h.file, offset = h.offset, len = h.len, line = h.line, col = h.col, sym = h.sym,
                                         has_space = h.has_space), pline = uint(h.line) + pp.state.line_delta, pname = pp.state.pname, call = -1)
        if (h.kind == int(PpTok.IDENTIFIER)) {
            t.spelled = PpSpelled.symbol
        } else {
            t.spelled = PpSpelled.scratch
            t.at = length(ex.text)
            ex.text |> reserve(length(ex.text) + h.len)
            for (i in range(h.at, h.at + h.len)) {
                ex.text |> push(pp.line_text[i])
            }
            t.len = h.len
        }
        toks |> push(t)
    }
    push_context(ex, toks, -1, true)
    let was_condition = ex.condition
    ex.condition = condition
    ex.defined_state = 0
    var out <- buffer(ex)
    var t : PpOutToken
    while (next_expanded(ex, pp, t)) {
        out |> push(t)
    }
    pop_context(ex)
    ex.condition = was_condition
    ex.defined_state = 0
    pp.line |> clear()
    pp.line_text |> clear()
    pp.line |> reserve(length(out))
    for (o in out) {
        let at = length(pp.line_text)
        put_spelling(ex, pp, o, pp.line_text)
        pp.line |> push(PpHeld(kind = o.tok.kind, sym = o.tok.sym, file = o.tok.file, offset = o.tok.offset, line = o.tok.line, col = o.tok.col,
                               at = at, len = length(pp.line_text) - at, has_space = o.tok.has_space))
    }
    recycle(ex, out)
}

// Starting

//! Start preprocessing `main` as `pp_start` does, with macro expansion: `pp_next_token` hands out
//! the expanded tokens, and the macros of `#include`, `#line` and `#if` lines are expanded.
//! `epoch` is the time `__DATE__`, `__TIME__` and `__TIMESTAMP__` show, seconds since 1970 in
//! UTC; -1 for now.
[arch(at="ARCHITECTURE_EXPAND.md#pp-expansion")]
def pp_expand_start(var pp : Preprocessor; var provider : PpFileProvider?; main : string; predefines : array<string>;
                    search : array<string>; epoch : int64 = -1l) : bool {
    let ok = pp_start(pp, provider, main, predefines, search)
    var ex = new PpExpander()
    ex.epoch = epoch >= 0l ? epoch : int64(get_clock())
    ex.inv |> resize(16)
    let names <- [("__FILE__", PpBuiltin.file), ("__LINE__", PpBuiltin.line), ("__COUNTER__", PpBuiltin.counter),
                  ("__DATE__", PpBuiltin.date), ("__TIME__", PpBuiltin.time), ("__TIMESTAMP__", PpBuiltin.timestamp),
                  ("__INCLUDE_LEVEL__", PpBuiltin.include_level), ("__BASE_FILE__", PpBuiltin.base_file),
                  ("__FILE_NAME__", PpBuiltin.file_name), ("_Pragma", PpBuiltin.pragma)]
    for (entry in names) {
        ex.builtin_of |> insert(intern_name(pp.lx.flex.syms, entry._0), entry._1)
    }
    for (name in PP_QUERIES) {
        ex.builtin_of |> insert(intern_name(pp.lx.flex.syms, name), PpBuiltin.evaluated)
    }
    pp.expansion = ex
    return ok
}
