options gen2

module pp_macros public

require strings
require math
require daslib/strings_boost
require daslib/fio
require ../../frontend/pp_record.das
require ../../converter/cir.das
require ../../converter/macro_sites.das
require ../../converter/dumper_a.das
require pp_oracle

//! The expansion record's oracle (`ARCHITECTURE.md#pp5`): a unit through Dumper A, whose marks of
//! function-like expansions come from libclang's preprocessing record and matching, and through
//! the frontend's preprocessor, whose record knows every expansion; every site Dumper A marks must
//! be a call of the record with the same outermost place, macro and argument texts, every argument
//! copy it marks a copy the record holds, and every macro of its table the record's macro.

//! One unit's comparison.
struct Pp5Result {
    unit : string
    error : string              //!< a side failed on the unit: nothing compared
    refused : string            //!< Dumper A refuses the unit: nothing compared
    sites : int                 //!< Dumper A's marked expansions
    matched : int               //!< of them, a call of the record
    copies : int                //!< Dumper A's argument copies on matched sites
    copies_matched : int        //!< of them, a copy the record holds
    candidates : int            //!< the record's calls of the program's markable macros, outside directive lines
    marked : int                //!< of them, a call some site of Dumper A is
    macros : int                //!< Dumper A's macros table
    macros_equal : int          //!< of them, the record's macro with the same params, text and uses
    uses_known : int            //!< parameters Dumper A gives -1 and the record a count
    shown : array<string>       //!< each disagreement
    known : array<string>       //!< each count only the record gives
}

//! The totals of a set of units.
struct Pp5Totals {
    units : int
    errors : int
    refused : int
    differing : int
    sites : int
    matched : int
    copies : int
    copies_matched : int
    candidates : int
    marked : int
    macros : int
    macros_equal : int
    uses_known : int
}

def operator +=(var a : Pp5Totals; b : Pp5Totals) {
    a.units += b.units
    a.errors += b.errors
    a.refused += b.refused
    a.differing += b.differing
    a.sites += b.sites
    a.matched += b.matched
    a.copies += b.copies
    a.copies_matched += b.copies_matched
    a.candidates += b.candidates
    a.marked += b.marked
    a.macros += b.macros
    a.macros_equal += b.macros_equal
    a.uses_known += b.uses_known
}

//! Whether a unit agrees: every site, copy and macro of Dumper A is the record's.
def pp5_agrees(r : Pp5Result) : bool => r.matched == r.sites && r.copies_matched == r.copies && r.macros_equal == r.macros

//! An argument's or a call's text with the spelling differences of the two sides taken out: line
//! splices dropped, each comment and each run of blanks one blank, none at either end. Dumper A
//! slices the file, the record joins tokens where a call is no stretch of a file.
[arch(at="ARCHITECTURE.md#pp5")]
def pp5_normalized(text : string) : string {
    return build_string() $(var w) {
        peek_data(text) $(b) {
            var gap = false
            var wrote = false
            var i = 0
            let n = length(b)
            while (i < n) {
                let c = int(b[i])
                if (c == '\\' && i + 1 < n && b[i + 1] == '\n'u8) {
                    i += 2
                    continue
                }
                if (c == '/' && i + 1 < n && b[i + 1] == '*'u8) {
                    i += 2
                    while (i + 1 < n && !(b[i] == '*'u8 && b[i + 1] == '/'u8)) {
                        i++
                    }
                    i += 2
                    gap = true
                    continue
                }
                if (c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f') {
                    gap = true
                    i++
                    continue
                }
                if (gap && wrote) {
                    w |> write_char(' ')
                }
                gap = false
                wrote = true
                w |> write_char(c)
                i++
            }
        }
    }
}

// a site's key: the outermost call's file and name offset, the macro's name, file and line, and its
// arguments' texts normalized
def private site_key(file : string; at : int; name, def_file : string; def_line : int; args : array<string>) : string {
    let texts <- [for (a in args); pp5_normalized(a)]
    return "{file}:{at} {name}@{def_file}:{def_line} ({join(texts, "\u0001")})"
}

def private canonical(path : string) : string {
    let full = get_full_file_name(path)
    return empty(full) ? path : full
}

// every expression and statement of the unit below `x`, with its marks
def private collect_expr(x : CirExpr const?; var uses : array<CirMacroUse>; var args : array<CirMacroArg>) {
    return if (x == null)
    uses |> push_clone_from(x.fn_macro)
    args |> push_clone_from(x.macro_args)
    for (part in fixed_array<CirExpr const?>(x.a, x.b, x.c, x.fn, x.base, x.i, x.list, x.init)) {
        collect_expr(part, uses, args)
    }
    for (arg in x.args) {
        collect_expr(arg, uses, args)
    }
    for (item in x.init_items) {
        collect_expr(item.v, uses, args)
    }
}

def private collect_stmt(st : CirStmt const?; var uses : array<CirMacroUse>; var args : array<CirMacroArg>) {
    return if (st == null)
    uses |> push_clone_from(st.fn_macro)
    for (e in fixed_array<CirExpr const?>(st.init, st.e, st.cond, st.inc)) {
        collect_expr(e, uses, args)
    }
    for (s in fixed_array<CirStmt const?>(st.then_s, st.else_s, st.body_s, st.init_s)) {
        collect_stmt(s, uses, args)
    }
    for (s in st.body) {
        collect_stmt(s, uses, args)
    }
}

// the unit's flags split for both sides: `-D` entries and `-I` folders; an error for any other flag
def private unit_inputs(flags : array<string>; var defines, dirs : array<string>) : string {
    for (f in flags) {
        if (starts_with(f, "-D")) {
            defines |> push(slice(f, 2))
        } elif (starts_with(f, "-I")) {
            dirs |> push(slice(f, 2))
        } else {
            return "unsupported unit flag {f}"
        }
    }
    return ""
}

// the record's side of a unit: the preprocessor run to the end, the argument copies its tokens
// hold (call * 4096 + parameter), each file's canonical path, the first call of each site key, and
// whether each call is a candidate - a markable macro of the program called from the program
struct private RecordSide {
    pp : Preprocessor
    copied : table<int64>
    paths : array<string>
    call_at : table<string; int>
    candidate : array<bool>
}

// the canonical path of file `file` of the record, "" for none
def private path_of(side : RecordSide; file : int) : string => file >= 0 && file < length(side.paths) ? side.paths[file] : ""

// the unit read by the record with the table, the own headers and the unit's own defines and folders
def private read_record(var side : RecordSide; unit : string; entries, search, defines, dirs : array<string>; var result : Pp5Result) {
    var our_entries := entries
    our_entries |> push_from(defines)
    var our_search := dirs
    our_search |> push_from(search)
    if (!pp_expand_start(side.pp, new PpFioProvider(), unit, our_entries, our_search, ORACLE_EPOCH)) {
        result.error = "the record cannot open {unit}"
    }
    while (pp_next_token(side.pp)) {
        pp_each_copy(side.pp, side.pp.tok.copy) $(call, k) {
            side.copied |> insert(int64(call) * 4096l + int64(k))
        }
    }
    side.paths |> reserve(length(side.pp.files))
    for (f in side.pp.files) {
        side.paths |> push(canonical(f.path))
    }
    let program = canonical(dir_name(unit)) + "/"
    side.candidate |> reserve(length(side.pp.expansion.calls))
    for (c, i in side.pp.expansion.calls, count()) {
        let top & = unsafe(side.pp.expansion.calls[c.outer].name)
        let mac & = unsafe(side.pp.macros[c.macro])
        let def_file = path_of(side, mac.file)
        let at_file = path_of(side, top.file)
        var inscope args <- [for (k in range(c.arg_count)); arg_string(side.pp, i, k)]
        let key = site_key(at_file, top.offset, pp_name(side.pp, mac.name), def_file, mac.line, args)
        if (!key_exists(side.call_at, key)) {
            side.call_at[key] = i
        }
        let candidate = !c.in_line && pp_macro_markable(side.pp, c.macro) && starts_with(def_file, program) && starts_with(at_file, program)
        side.candidate |> push(candidate)
        result.candidates += candidate ? 1 : 0
    }
}

// the text of argument `k` of call `call`, as a string
def private arg_string(var pp : Preprocessor; call, k : int) : string {
    var inscope bytes : array<uint8>
    pp_call_arg_text(pp, call, k, bytes)
    return string(bytes)
}

// each site of Dumper A matched to a call of the record by its key; the call of each site matched
def private match_sites(d : Dumper; uses : array<CirMacroUse>; side : RecordSide; var result : Pp5Result) : table<int; int> {
    var site_call : table<int; int>
    var marked : table<int>
    for (u in uses) {
        result.sites++
        let m & = unsafe(d.tu.macros[u.m])
        let place = d.fn_macros.site_places[u.site]
        let key = site_key(canonical(place.file), place.at, m.name, canonical(m.file), m.line, u.args)
        let call = side.call_at?[key] ?? -1
        if (call < 0) {
            result.shown |> push("site {u.site} {m.name}({join(u.args, ", ")}) at {place.file}:{place.at}: no call of the record")
            continue
        }
        result.matched++
        site_call[u.site] = call
        if (side.candidate[call]) {
            marked |> insert(call)
        }
    }
    result.marked = length(marked)
    return <- site_call
}

// each argument copy Dumper A marks on a matched site held against the record's copies
def private match_copies(copies : array<CirMacroArg>; site_call : table<int; int>; side : RecordSide; var result : Pp5Result) {
    for (a in copies) {
        let call = site_call?[a.site] ?? -1
        continue if (call < 0)
        result.copies++
        if (key_exists(side.copied, int64(call) * 4096l + int64(a.k))) {
            result.copies_matched++
        } else {
            result.shown |> push("copy of argument {a.k} of site {a.site}: the record has no token copied from call {call}'s argument")
        }
    }
}

// the record's definition of Dumper A's macro `m` (its name, file and line), -1 for none
def private record_macro(var side : RecordSide; m : CirMacro) : int {
    let file = canonical(m.file)
    for (j in range(length(side.pp.macros))) {
        let pm & = unsafe(side.pp.macros[j])
        return j if (pm.line == m.line && path_of(side, pm.file) == file && pp_name(side.pp, pm.name) == m.name)
    }
    return -1
}

// what differs between Dumper A's macro `m` and the record's definition `found`, "" for nothing; a use
// only the record counts is listed apart
def private macro_disagreement(var pp : Preprocessor; found : int; m : CirMacro; var result : Pp5Result) : string {
    var inscope text : array<uint8>
    pp_macro_text(pp, found, text)
    var inscope params <- [for (p in pp.macros[found].params); pp_name(pp, p)]
    var why = ""
    if (join(params, ",") != join(m.params, ",")) {
        why = "params {join(params, ",")} / {join(m.params, ",")}"
    } elif (string(text) != m.text) {
        why = "text '{string(text)}' / '{m.text}'"
    }
    for (k in range(length(m.uses))) {
        let ours = k < length(params) ? pp_macro_uses(pp, found, k) : -2
        if (ours != m.uses[k] && m.uses[k] == -1 && ours >= 0) {
            result.uses_known++
            result.known |> push("{m.name} uses[{k}] = {ours}, Dumper A -1")
        } elif (ours != m.uses[k] && empty(why)) {
            why = "uses[{k}] {ours} / {m.uses[k]}"
        }
    }
    return why
}

// each entry of Dumper A's macros table held against the record's definition
def private match_macros(macros : array<CirMacro>; var side : RecordSide; var result : Pp5Result) {
    for (m in macros) {
        result.macros++
        let found = record_macro(side, m)
        if (found < 0) {
            result.shown |> push("macro {m.name} at {m.file}:{m.line}: no definition of the record")
            continue
        }
        let why = macro_disagreement(side.pp, found, m, result)
        if (empty(why)) {
            result.macros_equal++
        } else {
            result.shown |> push("macro {m.name}: {why} (record / Dumper A)")
        }
    }
}

//! One unit through Dumper A and the record under the `linux` table, the own headers and the unit's
//! `-D` and `-I` flags; Dumper A marks only the program's macros, the files under the unit's
//! folder, so the record's candidates are the calls of those.
[arch(at="ARCHITECTURE.md#pp5")]
def compare_unit_pp5(unit : OracleUnit; entries, search : array<string>) : Pp5Result {
    var result = Pp5Result(unit = unit.path)
    var defines, dirs : array<string>
    result.error = unit_inputs(unit.flags, defines, dirs)
    return <- result if (!empty(result.error))
    var d = new Dumper
    dump_tu(*d, unit.path, target_lp64_linux(), default_clang(), DumpInputs(defines := defines, include_dirs := dirs))
    if (empty(d.error)) {
        var uses : array<CirMacroUse>
        var copies : array<CirMacroArg>
        for (decl in d.tu.decls) {
            collect_expr(decl.init, uses, copies)
            collect_stmt(decl.body, uses, copies)
        }
        var side = new RecordSide()
        read_record(*side, unit.path, entries, search, defines, dirs, result)
        let site_call <- match_sites(*d, uses, *side, result)
        match_copies(copies, site_call, *side, result)
        match_macros(d.tu.macros, *side, result)
        unsafe {
            delete side
        }
    } else {
        result.refused = d.error
    }
    unsafe {
        delete d
    }
    return <- result
}

//! The units of one set compared, each that disagrees printed with `show` of its disagreements, and
//! the set's line.
def run_set_pp5(name : string; units : array<OracleUnit>; entries, search : array<string>; show : int) : Pp5Totals {
    var t : Pp5Totals
    for (u in units) {
        let r <- compare_unit_pp5(u, entries, search)
        t.units++
        if (!empty(r.error)) {
            t.errors++
            print("{u.path}: error: {r.error}\n")
            continue
        }
        if (!empty(r.refused)) {
            t.refused++
            continue
        }
        t.sites += r.sites
        t.matched += r.matched
        t.copies += r.copies
        t.copies_matched += r.copies_matched
        t.candidates += r.candidates
        t.marked += r.marked
        t.macros += r.macros
        t.macros_equal += r.macros_equal
        t.uses_known += r.uses_known
        for (i in range(min(show, length(r.known)))) {
            print("{u.path}: the record knows {r.known[i]}\n")
        }
        continue if (pp5_agrees(r))
        t.differing++
        print("{u.path}: sites {r.matched}/{r.sites}, copies {r.copies_matched}/{r.copies}, macros {r.macros_equal}/{r.macros}\n")
        for (i in range(min(show, length(r.shown)))) {
            print("    {r.shown[i]}\n")
        }
    }
    print("{describe_pp5_totals(name, t)}\n")
    return t
}

//! A set's line: the units, those Dumper A refuses and those in error, the sites, copies and macros
//! the record agrees with, and how many more calls the record could mark.
def describe_pp5_totals(name : string; t : Pp5Totals) : string {
    return ("{name} (pp5): {t.units} units, {t.refused} refused by Dumper A, {t.errors} errors, {t.differing} differ; sites {t.matched}/{t.sites}, "
        + "copies {t.copies_matched}/{t.copies}, macros {t.macros_equal}/{t.macros} ({t.uses_known} uses only the record knows); "
        + "record calls of program macros {t.candidates}, {t.marked} of them marked by Dumper A")
}

//! The corpora the expansion record is compared on besides the oracle's: `fixtures`, the converter's
//! test units, which hold Dumper A's macro fixtures.
def pp5_corpus_units(root, corpus : string; var error : string&) : array<string> {
    if (corpus != "fixtures") {
        return <- corpus_units(root, corpus, error)
    }
    var units : array<string>
    let folder = path_join(root, "converter/tests/fixtures")
    dir(folder) $(name) {
        if (ends_with(name, ".c")) {
            units |> push(path_join(folder, name))
        }
    }
    sort(units)
    return <- units
}

//! `--pp5` over the corpora and lists of `args`; 0 when every unit agrees and none is in error.
[arch(at="ARCHITECTURE.md#pp5")]
def run_pp5(args : OracleArgs) : int {
    var error : string
    let setup <- pp2_setup(error)
    if (!empty(error)) {
        to_log(LOG_ERROR, "{error}\n")
        return 1
    }
    let root = getcwd()
    var total : Pp5Totals
    for (corpus in args.corpus) {
        var inscope units <- pp5_corpus_units(root, corpus, error)
        if (!empty(error)) {
            to_log(LOG_ERROR, "{error}\n")
            return 1
        }
        total += run_set_pp5(corpus, oracle_units(units), setup.entries, setup.search, args.show)
    }
    for (list in args.list) {
        if (!stat(list).is_reg) {
            to_log(LOG_ERROR, "corpus list {list} is missing\n")
            return 1
        }
        total += run_set_pp5(base_name(list), list_units(list), setup.entries, setup.search, args.show)
    }
    if (!empty(args.units)) {
        total += run_set_pp5("units", oracle_units(args.units), setup.entries, setup.search, args.show)
    }
    print("{describe_pp5_totals("total", total)}\n")
    return total.differing == 0 && total.errors == 0 ? 0 : 1
}
