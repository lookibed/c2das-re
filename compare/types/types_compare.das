options gen2
options indenting = 4

module types_compare public

require strings
require daslib/strings_boost
require daslib/fio
require daslib/clargs
require math
require ../../frontend/c_ir.das
require ../../frontend/c_defines.das
require ../../converter/cir.das
require ../../converter/dumper_a.das
require ../../metrics/conversion_census_count.das

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

//! One unit under one dialect: what each side gave and how they compare.
struct TypesResult {
    unit : string
    dialect : string
    dumper_error : string       //!< Dumper A failed: nothing compared
    builder_error : string      //!< clang -E, the parser or the builder failed
    aggregate : bool            //!< Dumper A's table holds a record, union or enum
    whole : bool                //!< the builder's table is Dumper A's
    cir : bool                  //!< the builder's declarations, statements and expressions are Dumper A's
    census : bool               //!< the conversion census of the builder's C-IR is Dumper A's
    difference : string         //!< the first difference of each kind that differs, `; `-joined
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

// one field of a node pair: "" when equal, else `<where>.<what>: builder <ours>, Dumper A <theirs>`
def private field(at, what, ours, theirs : string) : string => ours == theirs ? "" : "{at}.{what}: builder {ours}, Dumper A {theirs}"

// the first of a list of field differences, "" for none
def private first_of(diffs : array<string>) : string {
    for (d in diffs) {
        return d if (!empty(d))
    }
    return ""
}

//! The first difference of expressions `ours` (in table `ot`) and `theirs` (in `tt`) at path `at`,
//! "" for equal ones: every field the C-IR spec lists but a reference's name (C.4's), the macro
//! fields and the source parentheses (the preprocessor's, which `clang -E` text does not carry).
[arch(at="ARCHITECTURE.md#compared")]
def expr_difference(ot : array<CirType>; ours : CirExpr const?; tt : array<CirType>; theirs : CirExpr const?; at : string) : string {
    if (ours == null || theirs == null) {
        return ours == null && theirs == null ? "" : "{at}: builder {ours == null ? "none" : ours.e}, Dumper A {theirs == null ? "none" : theirs.e}"
    }
    let own = first_of([field(at, "e", ours.e, theirs.e), field(at, "t", type_name(ot, ours.t), type_name(tt, theirs.t)),
        field(at, "v", ours.v, theirs.v), field(at, "bytes", "{ours.bytes}", "{theirs.bytes}"), field(at, "op", ours.op, theirs.op),
        field(at, "cast", "{ours.cast_kind}{ours.explicit_cast ? "!" : ""}", "{theirs.cast_kind}{theirs.explicit_cast ? "!" : ""}"),
        field(at, "char", "{ours.is_char}", "{theirs.is_char}"), field(at, "vol", "{ours.vol}", "{theirs.vol}"),
        field(at, "trait_v", "{ours.trait_v}", "{theirs.trait_v}"), field(at, "of_t", type_name(ot, ours.of_t), type_name(tt, theirs.of_t)),
        field(at, "args", "{length(ours.args)}", "{length(theirs.args)}"), field(at, "items", "{length(ours.init_items)}", "{length(theirs.init_items)}")])
    return own if (!empty(own))
    for (i in range(length(ours.init_items))) {
        let pos = field("{at}.item{i}", "pos", "{ours.init_items[i].pos}", "{theirs.init_items[i].pos}")
        return pos if (!empty(pos))
        let item = expr_difference(ot, ours.init_items[i].v, tt, theirs.init_items[i].v, "{at}.item{i}")
        return item if (!empty(item))
    }
    for (i in range(length(ours.args))) {
        let arg = expr_difference(ot, ours.args[i], tt, theirs.args[i], "{at}.arg{i}")
        return arg if (!empty(arg))
    }
    return first_of([expr_difference(ot, ours.a, tt, theirs.a, "{at}.a"), expr_difference(ot, ours.b, tt, theirs.b, "{at}.b"),
        expr_difference(ot, ours.c, tt, theirs.c, "{at}.c"), expr_difference(ot, ours.fn, tt, theirs.fn, "{at}.fn"),
        expr_difference(ot, ours.base, tt, theirs.base, "{at}.base"), expr_difference(ot, ours.i, tt, theirs.i, "{at}.i"),
        expr_difference(ot, ours.init, tt, theirs.init, "{at}.init")])
}

//! The first difference of statements `ours` and `theirs` at path `at`, "" for equal ones: kind,
//! type, value, label, expressions and the statements under them; names (C.4's) and places aside.
def stmt_difference(ot : array<CirType>; ours : CirStmt const?; tt : array<CirType>; theirs : CirStmt const?; at : string) : string {
    if (ours == null || theirs == null) {
        return ours == null && theirs == null ? "" : "{at}: builder {ours == null ? "none" : ours.s}, Dumper A {theirs == null ? "none" : theirs.s}"
    }
    let own = first_of([field(at, "s", ours.s, theirs.s), field(at, "t", type_name(ot, ours.t), type_name(tt, theirs.t)),
        field(at, "v", "{ours.v}", "{theirs.v}"), field(at, "char", "{ours.is_char}", "{theirs.is_char}"),
        field(at, "label", ours.label_name, theirs.label_name), field(at, "body", "{length(ours.body)}", "{length(theirs.body)}")])
    return own if (!empty(own))
    let exprs = first_of([expr_difference(ot, ours.init, tt, theirs.init, "{at}.init"), expr_difference(ot, ours.e, tt, theirs.e, "{at}.e"),
        expr_difference(ot, ours.cond, tt, theirs.cond, "{at}.cond"), expr_difference(ot, ours.inc, tt, theirs.inc, "{at}.inc")])
    return exprs if (!empty(exprs))
    for (i in range(length(ours.body))) {
        let kid = stmt_difference(ot, ours.body[i], tt, theirs.body[i], "{at}.{i}")
        return kid if (!empty(kid))
    }
    return first_of([stmt_difference(ot, ours.init_s, tt, theirs.init_s, "{at}.init_s"), stmt_difference(ot, ours.then_s, tt, theirs.then_s, "{at}.then"),
        stmt_difference(ot, ours.else_s, tt, theirs.else_s, "{at}.else"), stmt_difference(ot, ours.body_s, tt, theirs.body_s, "{at}.body_s")])
}

//! The first difference of units `ours` and `theirs` by their declarations in order, "" for equal
//! ones: each declaration's kind, C name, type, linkage, parameters' types, initializer and body.
[arch(at="ARCHITECTURE.md#compared")]
def cir_difference(ours, theirs : CirTu) : string {
    let n = min(length(ours.decls), length(theirs.decls))
    for (i in range(n)) {
        let o = ours.decls[i]
        let t = theirs.decls[i]
        let at = "decl {i} ({t.c_name})"
        var own = first_of([field(at, "k", o.k, t.k), field(at, "c_name", o.c_name, t.c_name),
            field(at, "t", type_name(ours.types, o.t), type_name(theirs.types, t.t)), field(at, "static", "{o.is_static}", "{t.is_static}"),
            field(at, "extern", "{o.is_extern}", "{t.is_extern}"), field(at, "from_func", o.from_func, t.from_func),
            field(at, "params", join([for (q in o.params); type_name(ours.types, q.t)], ","), join([for (q in t.params); type_name(theirs.types, q.t)], ","))])
        if (empty(own)) {
            own = first_of([expr_difference(ours.types, o.init, theirs.types, t.init, "{at}.init"), stmt_difference(ours.types, o.body, theirs.types, t.body, "{at}.body")])
        }
        return own if (!empty(own))
    }
    return length(ours.decls) == length(theirs.decls) ? "" : "decls: builder {length(ours.decls)}, Dumper A {length(theirs.decls)}"
}

//! The first lines of two units' conversion censuses (`metrics/conversion_census_count.das`) that
//! differ, "" for equal censuses: each key with both counts.
[arch(at="ARCHITECTURE.md#compared")]
def census_difference(ours, theirs : CirTu) : string {
    var oc, tc : ConversionCensus
    census_tu(ours, oc)
    census_tu(theirs, tc)
    var listed <- [for (k in keys(oc.n)); k]
    listed |> push_from([for (k in keys(tc.n)); k; where !key_exists(oc.n, k)])
    sort(listed)
    let diffs <- [for (k in listed); "{k} builder {count_of(oc, k)}, Dumper A {count_of(tc, k)}"; where count_of(oc, k) != count_of(tc, k)]
    return join([for (i in range(min(3, length(diffs)))); diffs[i]], " | ")
}

//! The builder's C-IR of `unit` under `target` into `tu`: `clang -E` under Dumper A's flags into
//! `work`, line markers kept, then the parser and the builder over that text, the own headers'
//! folder as the library; `error` names the step that failed.
def builder_tu(unit, work : string; target : CirTarget; var tu : CirTu; var error : string&) {
    let flags <- dumper_frontend_flags(target, error)
    return if (!empty(error))
    mkdir_rec(work)
    let dialect = is_msvc(target) ? "msvc" : "linux"
    let preprocessed = path_join(work, "{base_name(unit)}.{dialect}.i")
    var argv <- [default_clang(), "-E"]
    argv |> push_from(flags, [unit, "-o", preprocessed])
    var out : string
    if (run_and_capture(argv, out, 300.0) != 0) {
        error = "clang -E: {slice(out, 0, 400)}"
        return
    }
    let text = fread(preprocessed)
    var p = new CParser
    c_parser_open_text(*p, text, unit, is_msvc(target))
    let u = c_unit(*p)
    if (p.failed) {
        error = "parser: {p.err}"
    } else {
        var r = new CIr
        c_ir_open(*r, target, get_full_file_name(own_include_dir()) + "/")
        if (!c_ir_unit(*r, *p, u)) {
            error = "builder: {r.b.err}"
        }
        delete_tu(tu)
        tu <- r.b.tu
        unsafe {
            delete r
        }
    }
    unsafe {
        delete p
    }
}

//! `unit` compared under `target`: Dumper A's dump and the builder's C-IR, the type tables by the
//! names of their entries, the declarations with their statements and expressions, and the
//! conversion census.
[arch(at="ARCHITECTURE.md#compared")]
def compare_types(unit, work : string; target : CirTarget) : TypesResult {
    var r = TypesResult(unit = unit, dialect = is_msvc(target) ? "msvc" : "linux")
    var d = new Dumper
    dump_tu(*d, unit, target, default_clang(), DumpInputs())
    r.dumper_error = d.error
    if (empty(r.dumper_error)) {
        r.aggregate = has_aggregate(d.tu.types)
        var error : string
        var tu : CirTu
        builder_tu(unit, work, target, tu, error)
        r.builder_error = error
        if (empty(error)) {
            let ours <- table_names(tu.types)
            let whole = first_difference(ours, table_names(d.tu.types))
            let cir = cir_difference(tu, d.tu)
            let census = census_difference(tu, d.tu)
            r.whole = empty(whole)
            r.cir = empty(cir)
            r.census = empty(census)
            var diffs : array<string>
            if (!r.whole) {
                diffs |> push("table {whole}")
            }
            if (!r.cir) {
                diffs |> push("C-IR {cir}")
            }
            if (!r.census) {
                diffs |> push("census {census}")
            }
            r.difference = join(diffs, "; ")
        }
        delete_tu(tu)
    }
    delete_tu(d.tu)
    unsafe {
        delete d
    }
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
    cir : int                   //!< scalar-only units whose declarations, statements and expressions agree
    census : int                //!< scalar-only units whose conversion census agrees
    differ : int                //!< scalar-only units where the table, the C-IR or the census differs
}

//! The line of a run's counts.
def describe_types_totals(name : string; t : TypesTotals) : string =>
    "{name}: {t.units} units, {t.dumper_failed} Dumper A failed, {t.aggregate} with aggregates, {t.scalar} scalar-only: {t.whole} whole table, {t.cir} C-IR, {t.census} census agree; {t.differ} differ, {t.refused} refused"

//! `r` counted into `t`; the line printed for it, "" for a unit that agrees and one with aggregates
//! the builder refused.
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
    }
    t.whole += r.whole ? 1 : 0
    t.cir += r.cir ? 1 : 0
    t.census += r.census ? 1 : 0
    return "" if (r.whole && r.cir && r.census)
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
        total.cir += t.cir
        total.census += t.census
        total.differ += t.differ
    }
    print("{describe_types_totals("total", total)}\n")
    return total.differ == 0 && total.refused == 0 && total.dumper_failed == 0 ? 0 : 1
}
