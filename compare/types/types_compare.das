options gen2
options indenting = 4

module types_compare public

require strings
require daslib/strings_boost
require daslib/fio
require daslib/clargs
require math
require ../../frontend/c_types.das
require ../../frontend/c_defines.das
require ../../converter/cir.das
require ../../converter/dumper_a.das

//! The type-table comparison of Dumper C's builder, `frontend/c_types.das`, with Dumper A
//! (`compare/types/ARCHITECTURE.md`): one unit dumped by Dumper A and preprocessed by clang for the
//! builder under one dialect, the two tables compared entry by entry by structure.

//! The structural name of entry `idx` of `types`, the same for one type in any table: an integer
//! by width, sign and spelling, a float by width and spelling, a pointer, an array, a function and
//! a typedef through their parts' names, a record or an enum by its kind and name.
def type_name(types : array<CirType>; idx : int) : string {
    return "?" if (idx < 0 || idx >= length(types))
    assume t = types[idx]
    if (t.k == "int") {
        return "{t.spell}/{t.w}{t.is_signed ? "s" : "u"}"
    } elif (t.k == "float") {
        return "{t.spell}/{t.w}"
    } elif (t.k == "ptr") {
        return "ptr({type_name(types, t.to)})"
    } elif (t.k == "array") {
        return "array({type_name(types, t.elem)},{t.count})"
    } elif (t.k == "func") {
        let listed = join([for (x in t.params); type_name(types, x)], ",")
        return "func({type_name(types, t.ret)};{listed}{t.variadic ? ";..." : ""})"
    } elif (t.k == "typedef") {
        return "typedef({t.name}={type_name(types, t.to)})"
    } elif (t.k == "void") {
        return "void"
    }
    return "{t.k} {t.name}"
}

//! The names of every entry of `types`, in table order.
def table_names(types : array<CirType>) : array<string> => <- [for (i in range(length(types))); type_name(types, i)]

//! Whether `types` holds a record, a union or an enum: a unit the builder refuses until the
//! Aggregates phase.
def has_aggregate(types : array<CirType>) : bool {
    for (t in types) {
        return true if (t.k == "struct" || t.k == "union" || t.k == "enum")
    }
    return false
}

// the walk that orders Dumper A's declaration types: the names reached, each once
struct private OrderWalk {
    names : array<string>
    seen : table<string; bool>
}

// type `idx` of `types` reached: its parts first, as a spelling is read, then itself
def private reach(var w : OrderWalk; types : array<CirType>; idx : int) {
    return if (idx < 0 || idx >= length(types))
    let name = type_name(types, idx)
    return if (key_exists(w.seen, name))
    assume t = types[idx]
    if (t.k == "ptr" || t.k == "typedef") {
        reach(w, types, t.to)
    } elif (t.k == "array") {
        reach(w, types, t.elem)
    } elif (t.k == "func") {
        reach(w, types, t.ret)
        for (x in t.params) {
            reach(w, types, x)
        }
    }
    return if (key_exists(w.seen, name))
    w.seen[name] = true
    w.names |> push(name)
}

// whether place `a` comes before place `b` of the same file
def private before(a, b : CirLoc) : bool => a.line < b.line || (a.line == b.line && a.col < b.col)

// declaration `j` of `tu.decls`: its type, its parameters', then its body's; `inner` the indices
// of the declarations Dumper A put before it from its body - the statics it hoisted and the block
// declarations of functions - each reached where its place falls among the body's statements
def private reach_decl(var w : OrderWalk; tu : CirTu; j : int; inner : array<int>) {
    let d = tu.decls[j]
    reach(w, tu.types, d.t)
    for (param in d.params) {
        reach(w, tu.types, param.t)
    }
    return if (d.body == null)
    var next = 0
    reach_stmt(w, tu, d.body, inner, next)
    let none : array<int>
    for (i in range(next, length(inner))) {
        reach_decl(w, tu, inner[i], none)
    }
}

// statement `s` walked in source order: each declaration of `inner` that stands at or before it
// first, a `decl` statement's type, then the statements under it
def private reach_stmt(var w : OrderWalk; tu : CirTu; s : CirStmt?; inner : array<int>; var next : int&) {
    return if (s == null)
    let none : array<int>
    while (next < length(inner) && !before(s.loc, tu.decls[inner[next]].loc)) {
        next++
        reach_decl(w, tu, inner[next - 1], none)
    }
    if (s.s == "decl") {
        reach(w, tu.types, s.t)
    }
    reach_stmt(w, tu, s.init_s, inner, next)
    for (kid in s.body) {
        reach_stmt(w, tu, kid, inner, next)
    }
    reach_stmt(w, tu, s.then_s, inner, next)
    reach_stmt(w, tu, s.else_s, inner, next)
    reach_stmt(w, tu, s.body_s, inner, next)
}

//! The names of Dumper A's declaration-derived types in the order its walk reached them, rebuilt
//! from `tu.decls` (`ARCHITECTURE.md#declaration-order`): each declaration's type, a function's
//! parameters, then its body's `decl` statements and the hoisted statics and block function
//! declarations Dumper A put in `decls` before the function, each where its place falls among
//! the body's statements; every type's parts before it. Expression types are not reached.
[arch(at="ARCHITECTURE.md#declaration-order")]
def declaration_order(tu : CirTu) : array<string> {
    var w : OrderWalk
    let n = length(tu.decls)
    var taken : array<bool>
    taken |> resize(n)
    for (j in range(n)) {
        let f = tu.decls[j]
        continue if (f.k != "func" || f.body == null)
        var i = j - 1
        while (i >= 0 && !taken[i] && tu.decls[i].loc.file == f.loc.file && before(f.loc, tu.decls[i].loc)) {
            taken[i] = true
            i--
        }
    }
    var inner : array<int>
    for (j in range(n)) {
        if (taken[j]) {
            inner |> push(j)
            continue
        }
        reach_decl(w, tu, j, inner)
        inner |> clear()
    }
    return <- w.names
}

//! One unit under one dialect: what each side gave and how they compare.
struct TypesResult {
    unit : string
    dialect : string
    dumper_error : string       //!< Dumper A failed: nothing compared
    builder_error : string      //!< clang -E, the parser or the builder failed
    aggregate : bool            //!< Dumper A's table holds a record, union or enum
    whole : bool                //!< the builder's table is Dumper A's
    declarations : bool         //!< the builder's table is Dumper A's declaration order
    difference : string         //!< the first difference from the declaration order
    builder_count : int
    dumper_count : int
}

//! The first difference of two name lists, "" for equal ones: the place and each side's name there.
def first_difference(ours, theirs : array<string>) : string {
    let n = min(length(ours), length(theirs))
    for (at in range(n)) {
        if (ours[at] != theirs[at]) {
            return "entry {at}: builder {ours[at]}, Dumper A {theirs[at]}"
        }
    }
    if (length(ours) == length(theirs)) {
        return ""
    }
    return length(ours) > n ? "entry {n}: builder {ours[n]}, Dumper A has {n} entries" : "entry {n}: Dumper A {theirs[n]}, builder has {n} entries"
}

//! The builder's table of `unit` under `target`: `clang -E` under Dumper A's flags into `work`,
//! line markers kept, then the parser and the builder over that text, the own headers' folder
//! as the library; `error` names the step that failed.
def builder_table(unit, work : string; target : CirTarget; var error : string&) : array<CirType> {
    var types : array<CirType>
    let flags <- dumper_frontend_flags(target, error)
    return <- types if (!empty(error))
    mkdir_rec(work)
    let dialect = is_msvc(target) ? "msvc" : "linux"
    let preprocessed = path_join(work, "{base_name(unit)}.{dialect}.i")
    var argv <- [default_clang(), "-E"]
    argv |> push_from(flags, [unit, "-o", preprocessed])
    var out : string
    if (run_and_capture(argv, out, 300.0) != 0) {
        error = "clang -E: {slice(out, 0, 400)}"
        return <- types
    }
    let text = fread(preprocessed)
    var p = new CParser
    c_parser_open_text(*p, text, unit, is_msvc(target))
    let u = c_unit(*p)
    if (p.failed) {
        error = "parser: {p.err}"
    } else {
        var b = new CTypes
        c_types_open(*b, target, get_full_file_name(own_include_dir()) + "/")
        if (c_types_unit(*b, *p, u)) {
            types <- b.tu.types
        } else {
            error = "builder: {b.err}"
        }
        unsafe {
            delete b
        }
    }
    unsafe {
        delete p
    }
    return <- types
}

//! `unit` compared under `target`: Dumper A's dump and the builder's table, by the names of their
//! entries, whole and against Dumper A's declaration order.
[arch(at="ARCHITECTURE.md#compared")]
def compare_types(unit, work : string; target : CirTarget) : TypesResult {
    var r = TypesResult(unit = unit, dialect = is_msvc(target) ? "msvc" : "linux")
    var d = new Dumper
    dump_tu(*d, unit, target, default_clang(), DumpInputs())
    r.dumper_error = d.error
    let failed = !empty(r.dumper_error)
    let theirs <- failed ? array<string>() : table_names(d.tu.types)
    let order <- failed ? array<string>() : declaration_order(d.tu)
    r.aggregate = !failed && has_aggregate(d.tu.types)
    delete_tu(d.tu)
    unsafe {
        delete d
    }
    return <- r if (!empty(r.dumper_error))
    var error : string
    let types <- builder_table(unit, work, target, error)
    r.builder_error = error
    return <- r if (!empty(error))
    let ours <- table_names(types)
    r.builder_count = length(ours)
    r.dumper_count = length(theirs)
    r.whole = empty(first_difference(ours, theirs))
    r.difference = first_difference(ours, order)
    r.declarations = empty(r.difference)
    return <- r
}

//! The counts of a run: per class of `TypesResult`.
struct TypesTotals {
    units : int
    dumper_failed : int
    aggregate : int             //!< units with records, unions or enums (the builder refuses them)
    scalar : int                //!< the others: the scalar-only units
    refused : int               //!< scalar-only units the parser or the builder refused
    whole : int                 //!< scalar-only units whose whole table agrees
    declarations : int          //!< scalar-only units whose declaration order agrees
    differ : int                //!< scalar-only units whose declaration order differs
}

//! The line of a run's counts.
def describe_types_totals(name : string; t : TypesTotals) : string =>
    "{name}: {t.units} units, {t.dumper_failed} Dumper A failed, {t.aggregate} with aggregates, {t.scalar} scalar-only: {t.declarations} declaration order agrees ({t.whole} whole table), {t.differ} differ, {t.refused} refused"

//! `r` counted into `t`; the line printed for it, "" for a unit whose order agrees and one with
//! aggregates the builder refused.
def count_types(var t : TypesTotals; r : TypesResult) : string {
    t.units++
    let head = "{r.unit} [{r.dialect}]"
    if (!empty(r.dumper_error)) {
        t.dumper_failed++
        return "{head}: Dumper A failed: {slice(r.dumper_error, 0, 200)}"
    } elif (r.aggregate) {
        t.aggregate++
        return empty(r.builder_error) ? "{head}: aggregates in Dumper A's table, but the builder typed the unit" : ""
    }
    t.scalar++
    if (!empty(r.builder_error)) {
        t.refused++
        return "{head}: refused: {r.builder_error}"
    } elif (r.declarations) {
        t.declarations++
        if (r.whole) {
            t.whole++
        }
        return ""
    }
    t.differ++
    return "{head}: differs: {r.difference}"
}

//! The command line of `run.das`.
[CommandLineArgs]
struct TypesArgs {
    @clarg_doc = "compare the fetched c-testsuite single-exec units"
    c_testsuite : bool
    @clarg_doc = "a dialect to compare under: linux or msvc (repeatable; both when none is named)"
    dialect : array<string>
    @clarg_doc = "the folder the preprocessed units are written to"
    work : string = "compare/work/types"
    @clarg_positional
    @clarg_doc = "units compared besides the corpus"
    units : array<string>
}

//! The c-testsuite single-exec units under `root`, sorted; `error` when the suite is not fetched.
def c_testsuite_units(root : string; var error : string&) : array<string> {
    var units : array<string>
    let folder = path_join(root, "suites/c_testsuite/fetch/c-testsuite/tests/single-exec")
    if (!stat(folder).is_dir) {
        error = "{folder} is missing (fetch it with suites/c_testsuite/fetch.sh)"
        return <- units
    }
    dir(folder) $(name) {
        if (ends_with(name, ".c")) {
            units |> push(path_join(folder, name))
        }
    }
    sort(units)
    return <- units
}

//! The units `args` names compared under each dialect, from the repository root: each line that
//! is not an agreement printed, then the totals; 0 when no scalar-only unit differs or is
//! refused and Dumper A failed on none, else 1 (and for no unit named).
def run_types(args : TypesArgs) : int {
    var error : string
    var units <- args.c_testsuite ? c_testsuite_units(getcwd(), error) : array<string>()
    if (!empty(error)) {
        to_log(LOG_ERROR, "{error}\n")
        return 1
    }
    units |> push_from(args.units)
    if (empty(units)) {
        to_log(LOG_ERROR, "no unit to compare: name units or --c-testsuite\n")
        return 1
    }
    var dialects := empty(args.dialect) ? ["linux", "msvc"] : args.dialect
    mkdir_rec(args.work)
    var total : TypesTotals
    for (dialect in dialects) {
        var t : TypesTotals
        for (unit in units) {
            let line = count_types(t, compare_types(unit, args.work, target_by_name(dialect)))
            if (!empty(line)) {
                print("{line}\n")
            }
        }
        print("{describe_types_totals(dialect, t)}\n")
        total.units += t.units
        total.dumper_failed += t.dumper_failed
        total.aggregate += t.aggregate
        total.scalar += t.scalar
        total.refused += t.refused
        total.whole += t.whole
        total.declarations += t.declarations
        total.differ += t.differ
    }
    print("{describe_types_totals("total", total)}\n")
    return total.differ == 0 && total.refused == 0 && total.dumper_failed == 0 ? 0 : 1
}
