options gen2

module criteria_count public

require strings
require math
require daslib/strings_boost
require criteria_scan
require criteria_file

//! The raw counts of one converted input (`metrics/ARCHITECTURE_CRITERIA.md`, the criteria): what
//! the C sources hold, what the emitted modules spell, each das function's lines per C line and
//! the das functions' lengths.

//! The lines a function's body may stretch to before it counts as blown up: das lines per C line.
let BLOWUP_LIMIT = 1.5

//! The prefix of the functions the converter adds to a module (the layout check, the globals'
//! init, the dialect): in no length distribution.
let CONVERTER_FUNCTION_PREFIX = "c2das_"

//! The type names whose call is a cast: the numeric types, the pointer-sized integers and the
//! `c_runtime` enum cast. A cast of a bare number literal (`uint8(7)`, a table entry or a typed
//! zero) is a `literal_cast_lines` line, not a `cast` site: a table of a thousand entries is a few
//! lines a reader skips, and the literal's own spelling is what a suffix would replace.
let CAST_NAMES <- ["int", "uint", "int8", "uint8", "int16", "uint16", "int64", "uint64", "float", "double", "intptr", "uintptr", "enum_from_int"]

//! A line longer than this many bytes is a long line.
let LONG_LINE = 160

//! The lines of a repeated block: a window of this many consecutive code lines seen twice.
let REPEAT_WINDOW = 4

// a line holding only braces, `else`, `break` or `pass`, which a repeated block does not count
def private trivial_line(toks : array<Tok>) : bool {
    for (t in toks) {
        if (!(t.text == "\{" || t.text == "\}" || t.text == ";" || t.text == "else" || t.text == "break" || t.text == "pass")) {
            return false
        }
    }
    return true
}

//! The code lines inside a repeated block: the non-trivial lines in order, each covered by a
//! window of `REPEAT_WINDOW` consecutive ones whose text occurs at least twice.
def repeated_lines(lines : array<string>) : int {
    var seen : table<string; int>
    let windows = length(lines) - REPEAT_WINDOW + 1
    for (i in range(max(windows, 0))) {
        seen[join([for (k in range(i, i + REPEAT_WINDOW)); lines[k]], "\n")]++
    }
    var covered : array<bool>
    covered |> resize(length(lines))
    for (i in range(max(windows, 0))) {
        if ((seen?[join([for (k in range(i, i + REPEAT_WINDOW)); lines[k]], "\n")] ?? 0) > 1) {
            for (k in range(i, i + REPEAT_WINDOW)) {
                covered[k] = true
            }
        }
    }
    return length([for (c in covered); c; where c])
}

// the non-trivial code lines of token lines, as text
def private code_lines(code : array<array<Tok>>) : array<string> => <- [for (toks in code); line_text(toks); where !empty(toks) && !trivial_line(toks)]

// whether `name` is `stem` followed by digits only, none at all included
def private is_numbered(name, stem : string) : bool {
    if (!(name |> starts_with(stem))) {
        return false
    }
    var digits = true
    peek_data(name) $(b) {
        for (i in range(length(stem), length(b))) {
            digits = digits && is_number(int(b[i]))
        }
    }
    return digits
}

def private is_temp_name(name : string) : bool => length(name) > 2 && is_numbered(name, "_t")

def private is_operand(t : Tok) : bool => t.kind != TokKind.punct || t.text == ")" || t.text == "]"

let private ADDITIVE <- ["+", "-"]
let private BITWISE <- ["&", "|", "^"]
let private SHIFTS <- ["<<", ">>"]
let private ARITH_OPS <- ["+", "-", "*", "/", "%", "<<", ">>", "&", "|", "^"]
let private SEGMENT_ENDS <- [",", "=", "?", ":", "\{", "\}", ";", "||", "&&", "==", "!=", "<=", ">=", "+=", "-=", "*=", "/=", "|=", "&=", "^=", "<<=", ">>=", "||=", "&&=", "=>", "return"]

let private SEEN_SHIFT = 1
let private SEEN_OTHER = 2

// one parenthesis level's operators: a site when it saw both a shift and another operator
def private mixed(level : int) : int => level == (SEEN_SHIFT | SEEN_OTHER) ? 1 : 0

//! The expressions of one line where a shift meets an additive or bitwise operator at one
//! parenthesis level with no parentheses saying which binds first (`1 << b - 1`).
def lost_parens(toks : array<Tok>) : int {
    var sites = 0
    var inscope levels <- [0]
    for (i, t in count(), toks) {
        let top = length(levels) - 1
        let binary = i > 0 && is_operand(toks[i - 1])
        if (t.text == "(" || t.text == "[") {
            levels |> push(0)
        } elif ((t.text == ")" || t.text == "]") && top > 0) {
            sites += mixed(levels[top])
            levels |> pop()
        } elif (has_value(SEGMENT_ENDS, t.text)) {
            sites += mixed(levels[top])
            levels[top] = 0
        } elif (binary && has_value(SHIFTS, t.text) && i + 1 < length(toks) && (is_operand(toks[i + 1]) || toks[i + 1].text == "(" || toks[i + 1].text == "~")) {
            levels[top] |= SEEN_SHIFT
        } elif (binary && (has_value(ADDITIVE, t.text) || has_value(BITWISE, t.text))) {
            levels[top] |= SEEN_OTHER
        }
    }
    for (level in levels) {
        sites += mixed(level)
    }
    return sites
}

def private span_text(toks : array<Tok>; a, b : int) : string => join([for (i in range(a, b)); toks[i].text], " ")

// whether the call opened at `open` (the index of `(`) takes a bare number literal and nothing else
def private literal_argument(toks : array<Tok>; open : int) : bool => open + 2 < length(toks) && toks[open + 1].kind == TokKind.number && toks[open + 2].text == ")"

// the defects an identifier token at `i` spells, into `sites`; a cast of a bare literal sets
// `literal_cast` instead of a site
def private ident_defects(toks : array<Tok>; i : int; modules : table<string; bool>; var sites : table<string; int>; var literal_cast : bool&) {
    let t = toks[i]
    let n = length(toks)
    let next = i + 1 < n ? toks[i + 1].text : ""
    if (is_temp_name(t.text)) {
        sites["temp_name"]++
    }
    if (t.text |> starts_with("_c_")) {
        sites["c_renames"]++
    } elif (t.text == "label" && i + 1 < n && toks[i + 1].kind == TokKind.number) {
        sites["label_stubs"]++
    } elif (next == "(" && has_value(CAST_NAMES, t.text) && !(i > 0 && toks[i - 1].text == ".")) {
        if (literal_argument(toks, i + 1)) {
            literal_cast = true
        } else {
            sites["cast"]++
        }
    } elif (t.text == "addr" && next == "(") {
        sites["addr"]++
        if (i + 3 < n && ((toks[i + 2].text == "deref" && toks[i + 3].text == "(") || (toks[i + 2].kind == TokKind.ident && toks[i + 3].text == ")" && i + 4 < n && toks[i + 4].text == "."))) {
            sites["addr_deref"]++
        }
    } elif (t.text == "deref" && next == "(") {
        sites["deref"]++
        if (i + 3 < n && toks[i + 2].text == "addr" && toks[i + 3].text == "(") {
            sites["addr_deref"]++
        }
    } elif (t.text == "reinterpret" && !string_reinterpret(toks, i)) {
        sites["reinterpret_casts"]++
    } elif ((t.text == "var" || t.text == "let") && i + 1 < n && (is_temp_name(next) || is_numbered(next, "_first"))) {
        sites["temporaries"]++
    } elif (next == "::" && (t.text == "__" || key_exists(modules, t.text))) {
        sites["qualified_calls"]++
    }
}

// one past the constant operand starting at `at`: a number, or a grouping parenthesis holding
// constants and operators alone (`(0 << 4)`); -1 for any other token
def private constant_end(toks : array<Tok>; at : int) : int {
    if (at >= length(toks) || (at > 0 && toks[at - 1].text == ".")) {
        return -1
    }
    if (toks[at].kind == TokKind.number) {
        return at + 1
    }
    let before = at > 0 ? toks[at - 1] : Tok()
    if (toks[at].text != "(" || (at > 0 && (before.kind == TokKind.ident || before.kind == TokKind.number || before.text == ")" || before.text == "]" || before.text == ">"))) {
        return -1
    }
    var j = at + 1
    while (true) {
        j = constant_end(toks, j)
        if (j < 0 || j >= length(toks)) {
            return -1
        }
        if (toks[j].text == ")") {
            return j + 1
        }
        if (!has_value(ARITH_OPS, toks[j].text)) {
            return -1
        }
        j++
    }
    return -1
}

// whether the constant operand at `at` is the left side of an arithmetic operator whose right side
// is a constant too: literal arithmetic, counted once per operator, a parenthesized constant
// (`3 | (0 << 4)`) a number
def private literal_operation(toks : array<Tok>; at : int) : bool {
    let op = constant_end(toks, at)
    return op > 0 && op < length(toks) && has_value(ARITH_OPS, toks[op].text) && constant_end(toks, op + 1) > 0
}

// the per-function defects of one line, added into `sites` by criterion
def private line_defects(toks : array<Tok>; modules : table<string; bool>; var sites : table<string; int>) {
    let n = length(toks)
    if (n == 1 && toks[0].text == "\{") {
        sites["stray_braces"]++
    }
    sites["lost_parens"] += lost_parens(toks)
    var assigns = 0
    var assign_at = -1
    var literal_cast = false
    for (i, t in count(), toks) {
        if (t.text == "=") {
            assigns++
            assign_at = i
        }
        let next = i + 1 < n ? toks[i + 1].text : ""
        if (t.kind == TokKind.ident) {
            ident_defects(toks, i, modules, sites, literal_cast)
        } elif (literal_operation(toks, i)) {
            sites["literal_arithmetic"]++
        } elif (t.text == "?" && i + 3 < n && next == "1" && toks[i + 2].text == ":" && toks[i + 3].text == "0") {
            sites["bool_roundtrip"]++
        }
    }
    if (assigns == 1 && assign_at > 0 && toks[0].text != "var" && toks[0].text != "let" && span_text(toks, 0, assign_at) == span_text(toks, assign_at + 1, n)) {
        sites["temporaries"]++
        sites["self_assignments"]++
    }
    sites["literal_cast_lines"] += literal_cast ? 1 : 0
}

//! Whether the `reinterpret` at `at` casts a string literal: `reinterpret<T>("...")`.
def string_reinterpret(toks : array<Tok>; at : int) : bool {
    var depth = 0
    for (i in range(at + 1, length(toks))) {
        let t = toks[i].text
        if (t == "<") {
            depth++
        } elif (t == ">") {
            depth--
        } elif (t == ">>") {
            depth -= 2
        } elif (depth <= 0) {
            return t == "(" && i + 1 < length(toks) && toks[i + 1].kind == TokKind.str
        }
    }
    return false
}

//! The criteria noted per function: a function with a site of one counts once under `fn_<name>`.
let FUNCTION_DEFECTS <- ["addr_deref", "bool_roundtrip", "c_renames", "label_stubs", "literal_arithmetic", "lost_parens", "qualified_calls", "reinterpret_casts", "stray_braces", "temporaries"]

//! The sites counted over every line of every module under `<name>_sites`: the function criteria's
//! and the densities' own (`cast`, `addr`, `deref`, `temp_name`).
let SITE_DEFECTS <- ["addr", "addr_deref", "bool_roundtrip", "c_renames", "cast", "deref", "label_stubs", "literal_arithmetic", "lost_parens", "qualified_calls", "reinterpret_casts", "stray_braces", "temp_name", "temporaries"]

// a discarded temporary: `let _tN = ...` whose name the function never reads again
def private discarded_temps(code : array<array<Tok>>; fn : FnExtent) : int {
    var uses : table<string; int>
    var declared : array<string>
    for (l in range(fn.first, fn.last + 1)) {
        for (i, t in count(), code[l]) {
            if (t.kind == TokKind.ident && is_temp_name(t.text)) {
                uses[t.text]++
                if (i == 1 && code[l][0].text == "let") {
                    declared |> push(t.text)
                }
            }
        }
    }
    return length([for (name in declared); name; where(uses?[name] ?? 0) == 1])
}

// the code lines of a span of token lines
def private span_lines(code : array<array<Tok>>; first, last : int) : int => length([for (l in range(first, last + 1)); l; where !empty(code[l])])

// the C side's facts summed over the sources: the counts into `c`, characters, constant uses and
// function-like macro uses by spelling, each function's code lines by name in source order, and the
// comment texts
struct CSide {
    chars, consts, macro_calls : table<string; int>
    fns : table<string; array<int>>
    corpus : array<string>
}

def private c_side(sources : array<CSource>; constants, macros : table<string; bool>; var c : table<string; int>) : CSide {
    var side : CSide
    var inscope code : array<string>
    for (cs in sources) {
        c["c_comment_lines"] += cs.comment_lines
        side.corpus |> push_from(cs.comment_texts)
        c["c_strings"] += cs.strings
        c["c_includes"] += cs.includes
        c["c_switches"] += cs.switches
        for (k, v in keys(cs.chars), values(cs.chars)) {
            side.chars[k] += v
            c["c_char_literals"] += v
        }
        for (k, v in keys(cs.idents), values(cs.idents)) {
            if (key_exists(constants, k)) {
                side.consts[k] += v
                c["c_constant_uses"] += v
            }
        }
        for (k, v in keys(cs.calls), values(cs.calls)) {
            if (key_exists(macros, k)) {
                side.macro_calls[k] += v
                c["c_macro_calls"] += v
            }
        }
        for (fn in cs.functions) {
            side.fns[fn.name] |> push(span_lines(cs.code, fn.first, fn.last)) // nolint:PERF006 - one function per name, mostly
        }
        code |> push_from(code_lines(cs.code))
    }
    c["c_code_lines"] = length(code)
    c["c_repeated_lines"] = repeated_lines(code)
    return <- side
}

// the C comment lines, whole and joined: a das comment is carried when it equals one, or holds two
// words or more and lies inside one
struct CorpusIndex {
    lines : table<string; bool>
    joined : string
}

def private is_carried(corpus : CorpusIndex; comment : string) : bool => key_exists(corpus.lines, comment) || (find(comment, " ") > 0 && find(corpus.joined, comment) >= 0)

// the module-wide counts of one line: comments, long lines, layout checks, slots, string casts,
// switch flags and setjmp trampolines; whether the module is late-bound or layout-checked so far
def private module_line(toks : array<Tok>; constants, macros : table<string; bool>; var c, das_chars, das_consts, das_macros : table<string; int>; var late_bound, layout_check : bool&) {
    for (i, t in count(), toks) {
        let next = i + 1 < length(toks) ? toks[i + 1].text : ""
        if (t.kind == TokKind.chr) {
            das_chars[t.text]++
        } elif (t.kind != TokKind.ident) {
            continue
        }
        if (key_exists(constants, t.text)) {
            das_consts[t.text]++
        }
        if (next == "(" && key_exists(macros, t.text)) {
            das_macros[t.text]++
        }
        if (t.text |> ends_with("_slot")) {
            late_bound = true
        } elif (t.text == "static_assert" && i + 2 < length(toks) && toks[i + 2].text == "typeinfo") {
            layout_check = true
            c["layout_check_lines"]++
        } elif (t.text == "reinterpret" && string_reinterpret(toks, i)) {
            c["das_string_reinterprets"]++
        } elif (is_numbered(t.text, "_flag") && next == "||=") {
            c["flag_lines"]++
        } elif (is_numbered(t.text, "_goto")) {
            c["goto_state_lines"]++
        } elif (t.text == "var" && i + 3 < length(toks) && is_numbered(next, "_flag") && toks[i + 3].text == "false") {
            c["flag_switches"]++
        } elif (t.text == "try" && length(toks) == 2) {
            c["setjmp_sites"]++
        } elif (t.text == "while" && i + 2 < length(toks) && is_numbered(toks[i + 2].text, "_sj_run")) {
            c["setjmp_loops"]++
        }
    }
}

// one module's lines into `c`: carried comments against the C comments, long lines, the module
// flags, every site of `SITE_DEFECTS` into `sites` and the length of each function of the program's
// own into `lengths`
def private module_counts(dm : DasModule; corpus : CorpusIndex; constants, macros : table<string; bool>; stems : table<string; bool>; var c, das_chars, das_consts, das_macros, sites : table<string; int>; var lengths : array<int>) {
    var layout_check = false
    var late_bound = dm.stem |> ends_with("_link")
    var long_line = false
    c["das_requires"] += dm.requires
    for (l, toks in count(), dm.code) {
        let comment = dm.comments[l]
        if (!empty(comment) && !(comment |> starts_with("generated by c2das"))) {
            c["das_comment_lines"]++
            c["das_comments_carried"] += is_carried(corpus, comment) ? 1 : 0
        }
        if (dm.lengths[l] > LONG_LINE) {
            c["long_lines"]++
            long_line = true
        }
        module_line(toks, constants, macros, c, das_chars, das_consts, das_macros, late_bound, layout_check)
        line_defects(toks, stems, sites)
    }
    for (fn in dm.functions) {
        if (!(fn.name |> starts_with(CONVERTER_FUNCTION_PREFIX))) {
            lengths |> push(span_lines(dm.code, fn.first + 1, fn.last - 1))
        }
    }
    c["modules"]++
    c["modules_layout_check"] += layout_check ? 1 : 0
    c["modules_late_bound"] += late_bound ? 1 : 0
    c["modules_long_lines"] += long_line ? 1 : 0
}

// one module's functions matched to the C functions of their name: the lines per C line, the lines
// past the blow-up limit, and per function criterion whether the function has a site
def private function_counts(dm : DasModule; stems : table<string; bool>; var side : CSide; var c, fn_count : table<string; int>; var ratios : array<int>) {
    for (fn in dm.functions) {
        let c_name = fn.name == "c_main" ? "main" : fn.name |> starts_with("_c_") ? slice(fn.name, 3) : fn.name
        var c_lines = 0
        side.fns |> get(c_name) $(lines) {
            c_lines = empty(lines) ? 0 : lines[0]
        }
        if (c_lines == 0) {
            continue
        }
        side.fns[c_name] |> erase(0)
        let das_lines = span_lines(dm.code, fn.first, fn.last)
        c["fn_matched"]++
        let allowed = int(BLOWUP_LIMIT * float(c_lines))
        c["fn_within"] += das_lines <= allowed ? 1 : 0
        c["blowup_lines"] += max(das_lines - allowed, 0)
        ratios |> push(das_lines * 100 / c_lines)
        var inscope sites : table<string; int>
        for (l in range(fn.first + 1, fn.last + 1)) {
            line_defects(dm.code[l], stems, sites)
        }
        c["discarded_temps"] += discarded_temps(dm.code, fn)
        for (d in FUNCTION_DEFECTS) {
            fn_count[d] += (sites?[d] ?? 0) > 0 ? 1 : 0
        }
    }
}


//! The raw counts of one input: its C sources (`.c` files, in link order), its emitted modules and
//! fragments, the names of the program's integer-constant macros and of its function-like macros.
//! A hand-written port has no sources and no macros: only the das side is counted.
[arch(at="ARCHITECTURE_CRITERIA.md#criteria")]
def count_criteria(sources : array<CSource>; modules : array<DasModule>; constants, macros : table<string; bool>) : CriteriaRaw {
    var raw : CriteriaRaw
    var c <- {for (k in RAW_KEYS); k => 0}
    var side <- c_side(sources, constants, macros, c)
    let corpus = CorpusIndex(lines <- {for (line in side.corpus); line => true}, joined = join(side.corpus, "\n"))
    let stems <- {for (dm in modules); dm.stem => true}
    var das_chars, das_consts, das_macros, sites, fn_count : table<string; int>
    var inscope das_code : array<string>
    for (dm in modules) {
        module_counts(dm, corpus, constants, macros, stems, c, das_chars, das_consts, das_macros, sites, raw.lengths)
        das_code |> push_from(code_lines(dm.code))
        function_counts(dm, stems, side, c, fn_count, raw.ratios)
    }
    c["das_code_lines"] = length(das_code)
    c["das_repeated_lines"] = repeated_lines(das_code)
    for (k, v in keys(side.chars), values(side.chars)) {
        c["das_char_literals"] += min(v, das_chars?[k] ?? 0)
    }
    for (k, v in keys(side.consts), values(side.consts)) {
        c["das_constant_names"] += min(v, das_consts?[k] ?? 0)
    }
    for (k, v in keys(side.macro_calls), values(side.macro_calls)) {
        c["das_macro_calls"] += min(v, das_macros?[k] ?? 0)
    }
    for (d in SITE_DEFECTS) {
        c["{d}_sites"] = sites?[d] ?? 0
    }
    c["self_assignments"] = sites?["self_assignments"] ?? 0
    c["literal_cast_lines"] = sites?["literal_cast_lines"] ?? 0
    for (d in FUNCTION_DEFECTS) {
        c["fn_{d}"] = fn_count?[d] ?? 0
    }
    sort(raw.ratios)
    distribution_counts(raw.ratios, raw.lengths, c)
    raw.counts <- c
    return <- raw
}
