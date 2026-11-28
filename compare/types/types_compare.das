options gen2
options indenting = 4

module types_compare public

require strings
require daslib/strings_boost
require daslib/fio
require daslib/clargs
require math
require ../../frontend/diff.das
require ../../converter/cir.das
require ../../converter/dumper_a.das
require ../../converter/dumper_c.das
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
def has_array(types : array<CirType>) : bool {
    for (t in types) {
        return true if (t.k == "array")
    }
    return false
}

//! Whether `types` holds a record, a union or an enum.
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
    bytes : bool                //!< the builder's C-IR text is Dumper A's byte for byte, macro fields and producer aside
    core : bool                 //!< Dumper A's table holds no array either: a unit of the Core phase's acceptance
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
        field(at, "v", ours.v, theirs.v), field(at, "bytes", "{ours.bytes}", "{theirs.bytes}"), field(at, "op", ours.op, theirs.op), field(at, "name", ours.name, theirs.name),
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
        field(at, "label", ours.label_name, theirs.label_name), field(at, "name", ours.name, theirs.name), field(at, "body", "{length(ours.body)}", "{length(theirs.body)}")])
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
        var own = first_of([field(at, "k", o.k, t.k), field(at, "c_name", o.c_name, t.c_name), field(at, "name", o.name, t.name),
            field(at, "t", type_name(ours.types, o.t), type_name(theirs.types, t.t)), field(at, "static", "{o.is_static}", "{t.is_static}"),
            field(at, "extern", "{o.is_extern}", "{t.is_extern}"), field(at, "from_func", o.from_func, t.from_func),
            field(at, "params", join([for (q in o.params); "{q.name}:{type_name(ours.types, q.t)}"], ","), join([for (q in t.params); "{q.name}:{type_name(theirs.types, q.t)}"], ","))])
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

//! The builder's C-IR of `unit` under `target` into `tu` (`converter/dumper_c.das`); `error` names
//! the step that failed.
def builder_tu(unit : string; target : CirTarget; var tu : CirTu; var error : string&) {
    dumper_c_tu(unit, target, default_clang(), DumpInputs(), tu, error)
}

//! `unit` compared under `target`: Dumper A's dump and the builder's C-IR, the type tables by the
//! names of their entries, the declarations with their statements and expressions, and the
//! conversion census.
[arch(at="ARCHITECTURE.md#compared")]
def compare_types(unit : string; target : CirTarget) : TypesResult {
    var r = TypesResult(unit = unit, dialect = is_msvc(target) ? "msvc" : "linux")
    var d = new Dumper
    dump_tu(*d, unit, target, default_clang(), DumpInputs())
    r.dumper_error = d.error
    if (empty(r.dumper_error)) {
        r.aggregate = has_aggregate(d.tu.types)
        r.core = !r.aggregate && !has_array(d.tu.types)
        var error : string
        var tu : CirTu
        builder_tu(unit, target, tu, error)
        r.builder_error = error
        if (empty(error)) {
            let ours <- table_names(tu.types)
            let whole = first_difference(ours, table_names(d.tu.types))
            let cir = cir_difference(tu, d.tu)
            let census = census_difference(tu, d.tu)
            let bytes = cir_diff(write_cir(tu), write_cir(d.tu))
            r.whole = empty(whole)
            r.cir = empty(cir)
            r.census = empty(census)
            r.bytes = empty(bytes)
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
            if (!r.bytes) {
                diffs |> push("bytes {bytes}")
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

//! The counts of a run: per class of `TypesResult`. A unit Dumper A dumps is compared whatever its
//! types; its class is with aggregates (a record, union or enum in Dumper A's table), core (no
//! array either) or else scalar-only.
struct TypesTotals {
    units : int
    dumper_failed : int
    refused : int               //!< units the parser or the builder refused
    whole : int                 //!< units whose whole table agrees
    cir : int                   //!< units whose declarations, statements and expressions agree
    census : int                //!< units whose conversion census agrees
    bytes : int                 //!< units whose C-IR text is byte-identical
    differ : int                //!< units where the table, the C-IR, the census or the bytes differ
    aggregate : int             //!< units with records, unions or enums
    aggregate_bytes : int       //!< of them, byte-identical
    scalar : int                //!< the units with none: scalar-only
    scalar_bytes : int          //!< of them, byte-identical
    core : int                  //!< the scalar-only units with no array type: the Core acceptance set
    core_bytes : int            //!< of them, byte-identical
}

//! The line of a run's counts.
def describe_types_totals(name : string; t : TypesTotals) : string =>
    "{name}: {t.units} units, {t.dumper_failed} Dumper A failed, {t.refused} refused, {t.whole} whole table, {t.cir} C-IR, {t.census} census, {t.bytes} bytes agree, {t.differ} differ; byte-identical: aggregates {t.aggregate_bytes}/{t.aggregate}, scalar-only {t.scalar_bytes}/{t.scalar}, core (no array) {t.core_bytes}/{t.core}"

//! `r` counted into `t`; the line printed for it, "" for a unit that agrees.
def count_types(var t : TypesTotals; r : TypesResult) : string {
    t.units++
    let head = "{r.unit} [{r.dialect}{r.aggregate ? ", aggregate" : r.core ? ", core" : ""}]"
    if (!empty(r.dumper_error)) {
        t.dumper_failed++
        return "{head}: Dumper A failed: {slice(r.dumper_error, 0, 200)}"
    }
    let identical = empty(r.builder_error) && r.bytes
    if (r.aggregate) {
        t.aggregate++
        t.aggregate_bytes += identical ? 1 : 0
    } else {
        t.scalar++
        t.scalar_bytes += identical ? 1 : 0
        t.core += r.core ? 1 : 0
        t.core_bytes += r.core && identical ? 1 : 0
    }
    if (!empty(r.builder_error)) {
        t.refused++
        return "{head}: refused: {r.builder_error}"
    }
    t.whole += r.whole ? 1 : 0
    t.cir += r.cir ? 1 : 0
    t.census += r.census ? 1 : 0
    t.bytes += r.bytes ? 1 : 0
    return "" if (r.whole && r.cir && r.census && r.bytes)
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
    @clarg_name = "gcc-torture"
    @clarg_doc = "compare the fetched gcc-torture execute units its expected_pass.txt lists (Dumper A's passing ids)"
    gcc_torture : bool
    @clarg_doc = "the ratchet of byte-identical suite units, a file that exists: every line `<dialect> <id>` it lists must stay byte-identical (exit 1 otherwise); a byte-identical unit it lacks is reported, and over a whole suite a listed unit the run did not compare; units named on the command line are no suite's and never checked"
    ratchet : string
    @clarg_name = "update-ratchet"
    @clarg_doc = "add to --ratchet every suite unit of this run that is byte-identical, and over a whole suite drop the lines of units it no longer holds; nothing is written when a listed unit is no longer byte-identical"
    update_ratchet : bool
    @clarg_doc = "the folder the suites' fetched units lie under (the repository root when none is named)"
    root : string
    @clarg_positional
    @clarg_doc = "units compared besides the corpus"
    units : array<string>
}

//! The gcc-torture execute units under `root` that `suites/gcc_torture/expected_pass.txt` lists,
//! Dumper A's passing ids, in its order; `error` when the suite is not fetched.
def gcc_torture_units(root : string; var error : string&) : array<string> {
    var units : array<string>
    let folder = path_join(root, "suites/gcc_torture/fetch/gcc/gcc/testsuite/gcc.c-torture/execute")
    if (!stat(folder).is_dir) {
        error = "{folder} is missing (fetch it with suites/gcc_torture/fetch.sh)"
        return <- units
    }
    for (line in split(fread(path_join(root, "suites/gcc_torture/expected_pass.txt")), "\n")) {
        if (!empty(line) && !starts_with(line, "#")) {
            units |> push(path_join(folder, "{line}.c"))
        }
    }
    return <- units
}

//! The ratchet's key of `unit` under `dialect`: `<dialect> <id>`, the id its file stem.
def ratchet_key(dialect, unit : string) : string {
    let name = base_name(unit)
    let dot = find(name, ".")
    return "{dialect} {dot < 0 ? name : slice(name, 0, dot)}"
}

//! The keys a ratchet text lists, its `#` lines aside.
def ratchet_keys(text : string) : table<string; bool> {
    return <- {for (line in split(text, "\n")); line => true; where !empty(line) && !starts_with(line, "#")}
}

//! The keys of `listed` under one of `dialects` that `seen`, the keys a whole-suite run compared,
//! lacks: units the suite no longer holds, sorted.
def ratchet_stale(listed : table<string; bool>; seen : table<string; bool>; dialects : array<string>) : array<string> {
    var stale <- [for (key in keys(listed)); key; where !key_exists(seen, key) && has_value(dialects, slice(key, 0, max(find(key, " "), 0)))]
    sort(stale)
    return <- stale
}

//! The text of a ratchet that lists `listed` but `dropped` and the byte-identical units
//! `identical`, sorted: a list only grows, but for the units its suite no longer holds.
def ratchet_text(listed : table<string; bool>; identical : array<string>; dropped : array<string> = array<string>()) : string {
    var all <- [for (key in keys(listed)); key; where !has_value(dropped, key)]
    all |> push_from([for (key in identical); key; where !key_exists(listed, key)])
    sort(all)
    return "# units whose Dumper C C-IR is Dumper A's byte for byte (compare/types/run.das); the ratchet, kept sorted\n" + join([for (k in all); "{k}\n"], "")
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

// suite unit `key`'s line against the ratchet `listed`: a byte-identical one into `identical`, and
// reported when the list (`has_ratchet`) lacks it; 1 for a listed one no longer byte-identical
def private ratchet_note(listed : table<string; bool>; key : string; bytes, has_ratchet : bool; var identical : array<string>) : int {
    if (bytes) {
        identical |> push(key)
        if (has_ratchet && !key_exists(listed, key)) {
            print("ratchet: {key} is byte-identical and not listed\n")
        }
    } elif (key_exists(listed, key)) {
        print("ratchet: {key} is listed but no longer byte-identical\n")
        return 1
    }
    return 0
}

// the ratchet after a run: over a whole suite each listed unit it no longer holds reported; with
// `--update-ratchet` and no regression, the list written when it grew or lost such a unit
def private ratchet_finish(args : TypesArgs; listed, seen : table<string; bool>; identical, dialects : array<string>; regressed : int) {
    let whole_suite = (args.c_testsuite || args.gcc_torture) && empty(args.units)
    let stale <- whole_suite ? ratchet_stale(listed, seen, dialects) : array<string>()
    for (key in stale) {
        print("ratchet: {key} is listed but the suite holds no such unit\n")
    }
    let grown = !empty(stale) || !empty([for (key in identical); key; where !key_exists(listed, key)])
    if (args.update_ratchet && !empty(args.ratchet) && regressed == 0 && grown) {
        fwrite(args.ratchet, ratchet_text(listed, identical, stale))
    }
}

// `t`'s counts added to `total`
def private add_totals(var total : TypesTotals; t : TypesTotals) {
    total.units += t.units
    total.dumper_failed += t.dumper_failed
    total.aggregate += t.aggregate
    total.aggregate_bytes += t.aggregate_bytes
    total.scalar += t.scalar
    total.scalar_bytes += t.scalar_bytes
    total.refused += t.refused
    total.whole += t.whole
    total.cir += t.cir
    total.census += t.census
    total.bytes += t.bytes
    total.core += t.core
    total.core_bytes += t.core_bytes
    total.differ += t.differ
}

//! The units `args` names compared under each dialect, from the repository root: each line that
//! is not an agreement printed, then the totals; 0 when no scalar-only unit differs or is
//! refused and Dumper A failed on none, else 1 (and for no unit named).
def run_types(args : TypesArgs) : int {
    var error : string
    let root = empty(args.root) ? getcwd() : args.root
    var units <- args.c_testsuite ? c_testsuite_units(root, error) : array<string>()
    if (empty(error) && args.gcc_torture) {
        units |> push_from(gcc_torture_units(root, error))
    }
    if (!empty(error)) {
        to_log(LOG_ERROR, "{error}\n")
        return 1
    }
    let suite_units = length(units)
    units |> push_from(args.units)
    if (empty(units)) {
        to_log(LOG_ERROR, "no unit to compare: name units, --c-testsuite or --gcc-torture\n")
        return 1
    }
    if (!empty(args.ratchet) && !stat(args.ratchet).is_reg) {
        to_log(LOG_ERROR, "the ratchet {args.ratchet} is no file\n")
        return 1
    }
    let listed <- empty(args.ratchet) ? table<string; bool>() : ratchet_keys(fread(args.ratchet))
    var seen : table<string; bool>
    var identical : array<string>
    var regressed = 0
    var dialects := empty(args.dialect) ? ["linux", "msvc"] : args.dialect
    var total : TypesTotals
    for (dialect in dialects) {
        var t : TypesTotals
        for (unit, k in units, count()) {
            let r = compare_types(unit, target_by_name(dialect))
            let line = count_types(t, r)
            if (!empty(line)) {
                print("{line}\n")
            }
            continue if (k >= suite_units)
            let key = ratchet_key(dialect, unit)
            seen[key] = true
            regressed += ratchet_note(listed, key, r.bytes, !empty(args.ratchet), identical)
        }
        print("{describe_types_totals(dialect, t)}\n")
        add_totals(total, t)
    }
    print("{describe_types_totals("total", total)}\n")
    ratchet_finish(args, listed, seen, identical, dialects, regressed)
    if (!empty(args.ratchet)) {
        return regressed == 0 ? 0 : 1
    }
    return total.differ == 0 && total.refused == 0 && total.dumper_failed == 0 ? 0 : 1
}
