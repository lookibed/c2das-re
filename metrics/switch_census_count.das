options gen2

module switch_census_count public

require strings
require math
require daslib/strings_boost
require ../converter/cir.das
require ../converter/dumper_a.das

//! The switch census's counting (`metrics/ARCHITECTURE_SWITCH.md`): every `switch` of a C-IR
//! translation unit read into its facts, the facts into a class, and a row as one line of text.

//! The counted facts of a row, in the order a row's line holds them.
let FEATURES <- ["labels", "values", "density", "char_labels", "groups", "shared_labels", "real_falls", "falls_to_break", "fall_line", "early_breaks", "loop_breaks", "continues_out", "goto_cross", "labels_entered", "goto_out", "decl_cross", "decl_used_later", "nested_labels", "before_first"]

//! The classes, in the order the tables print them.
let CLASSES <- ["S1", "S2", "S3", "S4"]

//! The calls after which control does not come back; a program's own (`I_Error`) are not known
//! to the C-IR and read as returning.
let NORETURN_CALLS <- {"exit", "_exit", "_Exit", "abort", "longjmp", "siglongjmp", "__assert_fail", "__builtin_unreachable", "__builtin_trap"}

//! One `switch` of the C source: where it stands, the function holding it, its condition's kind
//! (`int`, `enum`, `char`, `bool` or `other`), where its `default` stands (`none`, `first`,
//! `middle` or `last`), its smallest and largest case value, its counted facts by `FEATURES`
//! name, its class, and whether its function is one a profile puts at the top of the run.
struct SwitchFacts {
    file : string
    line : int
    col : int
    func : string
    cond : string
    default_at : string
    lo : int64
    hi : int64
    n : table<string; int>
    cls : string
    hot : bool
}

// a run of labels and the statements under them
struct private Group {
    labels : int
    stmts : array<CirStmt const?>
}

def private is_loop(st : CirStmt const?) : bool => st.s == "while" || st.s == "do" || st.s == "for"

def private is_marker(st : CirStmt const?) : bool => st.s == "case" || st.s == "default"

// the statements directly under `st`
def private children(st : CirStmt const?) : array<CirStmt const?> {
    var out : array<CirStmt const?>
    out |> reserve(length(st.body) + 4)
    for (child in st.body) { // nolint:PERF022 push_from takes no array<CirStmt?> for an array<CirStmt const?>
        out |> push(child)
    }
    for (child in fixed_array<CirStmt const?>(st.init_s, st.then_s, st.else_s, st.body_s)) {
        if (child != null) {
            out |> push(child)
        }
    }
    return <- out
}

// the `break`s under `st` that leave the switch or loop around it: none inside a nested loop or
// switch, whose own they are
def private own_breaks(st : CirStmt const?) : int {
    if (st == null || is_loop(st) || st.s == "switch") {
        return 0
    }
    var found = st.s == "break" ? 1 : 0
    for (child in children(st)) {
        found += own_breaks(child)
    }
    return found
}

// the `break`s under `st` that leave a loop nested in the switch, a nested switch's left to it
def private loop_breaks(st : CirStmt const?; in_loop : bool) : int {
    if (st == null || st.s == "switch") {
        return 0
    }
    if (st.s == "break") {
        return in_loop ? 1 : 0
    }
    var found = 0
    for (child in children(st)) {
        found += loop_breaks(child, in_loop || is_loop(st))
    }
    return found
}

// the `continue`s under `st` that reach the loop around the switch
def private outer_continues(st : CirStmt const?) : int {
    if (st == null || is_loop(st)) {
        return 0
    }
    var found = st.s == "continue" ? 1 : 0
    for (child in children(st)) {
        found += outer_continues(child)
    }
    return found
}

// the case and default labels under `st` that belong to the switch around it
def private markers_under(st : CirStmt const?) : int {
    if (st == null || st.s == "switch") {
        return 0
    }
    var found = is_marker(st) ? 1 : 0
    for (child in children(st)) {
        found += markers_under(child)
    }
    return found
}

// whether `st` is a `break`, or a block ending in one
def private is_tail_break(st : CirStmt const?) : bool {
    if (st.s == "compound") {
        return !empty(st.body) && is_tail_break(st.body[length(st.body) - 1])
    }
    return st.s == "break"
}

// whether `st` does nothing: a `;`, `(void)0` (an `assert` under NDEBUG), a block of those
def private is_inert(st : CirStmt const?) : bool {
    if (st.s == "compound") {
        for (child in st.body) {
            if (!is_inert(child)) {
                return false
            }
        }
        return true
    }
    if (st.s == "expr") {
        return st.e != null && st.e.e == "cast" && st.e.cast_kind == "ToVoid" && st.e.a != null && st.e.a.e == "int_lit"
    }
    return st.s == "null"
}

// whether the loop `st` has no test that ends it: `for (;;)`, `while (1)`
def private is_endless(st : CirStmt const?) : bool {
    if (st.cond == null) {
        return st.s == "for"
    }
    let test = below_casts(st.cond)
    return test.e == "int_lit" && test.v != "0"
}

// whether control can run past the end of the statements `stmts`: a label makes what follows it
// reachable again
def private run_completes(stmts : array<CirStmt const?>) : bool {
    var reached = true
    for (st in stmts) {
        if (st.s == "label" || is_marker(st)) {
            reached = true
        } elif (reached) {
            reached = completes(st)
        }
    }
    return reached
}

// whether control can run past the end of `st`
def private completes(st : CirStmt const?) : bool {
    if (st.s == "break" || st.s == "continue" || st.s == "return" || st.s == "goto") {
        return false
    }
    if (st.s == "compound") {
        return run_completes(children(st))
    }
    if (st.s == "if") {
        return st.else_s == null || completes(st.then_s) || completes(st.else_s)
    }
    if (is_loop(st)) {
        return !is_endless(st) || own_breaks(st.body_s) > 0
    }
    if (st.s == "switch") {
        var has_default = false
        each_stmt(st.body_s) $(sub) {
            has_default = has_default || sub.s == "default"
        }
        return !has_default || own_breaks(st.body_s) > 0 || completes(st.body_s)
    }
    if (st.s == "expr" && st.e != null) {
        let call = below_casts(st.e)
        return !(call.e == "call" && key_exists(NORETURN_CALLS, called_name(*call)))
    }
    return true
}

def private resolved(tu : CirTu; t : int) : int {
    var at = t
    while (at >= 0 && at < length(tu.types) && tu.types[at].k == "typedef") {
        at = tu.types[at].to
    }
    return at
}

// the kind of the condition of switch `st` below C's implicit conversions: `char` is a plain
// `char`, or an integer whose labels the source spells as character literals
def private cond_kind(tu : CirTu; st : CirStmt const?; char_labels : int) : string {
    var operand = st.cond
    while (operand.e == "cast" && !operand.explicit_cast && operand.a != null && (operand.cast_kind == "IntegralCast" || operand.cast_kind == "LValueToRValue" || operand.cast_kind == "NoOp")) {
        operand = operand.a
    }
    let t = resolved(tu, operand.t)
    if (t < 0 || t >= length(tu.types)) {
        return "other"
    }
    if (tu.types[t].k == "enum") {
        return "enum"
    }
    if (tu.types[t].k != "int") {
        return "other"
    }
    if (tu.types[t].spell == "_Bool") {
        return "bool"
    }
    return tu.types[t].spell == "char" || char_labels > 0 ? "char" : "int"
}

// whether a statement of `stmts` names the variable `name`
def private names_variable(stmts : array<CirStmt const?>; from : int; name : string) : bool {
    var found = false
    for (idx in range(from, length(stmts))) {
        each_expr(stmts[idx]) $(x) {
            found = found || (x.e == "ref" && x.name == name)
        }
    }
    return found
}

//! The class of a switch with the facts `f`: `S4` a condition that is no integer and no enum,
//! `S3` a goto between case groups, a label a goto enters from outside, a declaration a later
//! case names or a case label below the body's level, `S2` a group with statements that falls
//! into the next, `S1` the rest.
def switch_class(f : SwitchFacts) : string {
    if (f.cond == "other") {
        return "S4"
    }
    if ((f.n?["goto_cross"] ?? 0) + (f.n?["labels_entered"] ?? 0) + (f.n?["decl_used_later"] ?? 0) + (f.n?["nested_labels"] ?? 0) > 0) {
        return "S3"
    }
    return (f.n?["real_falls"] ?? 0) > 0 ? "S2" : "S1"
}

// the body of a switch read as groups: the statements at its own level, the groups, and the
// statements before the first label
struct private Body {
    top : array<CirStmt const?>
    groups : array<Group>
    before : array<CirStmt const?>
}

// the statements of the body of switch `st` at its own level
def private body_statements(st : CirStmt const?) : array<CirStmt const?> {
    if (st.body_s != null && st.body_s.s == "compound") {
        return <- children(st.body_s)
    }
    var one : array<CirStmt const?>
    if (st.body_s != null) {
        one |> push(st.body_s)
    }
    return <- one
}

// the body of switch `st` as groups; the label, value and `default` facts into `f`
def private read_body(st : CirStmt const?; var f : SwitchFacts) : Body {
    var body = Body(top <- body_statements(st))
    var distinct : table<int64; bool>
    var default_group = -1
    for (child in body.top) {
        if (!is_marker(child)) {
            if (empty(body.groups)) {
                f.n["before_first"] += child.s == "null" ? 0 : 1
                body.before |> push(child)
            } else {
                body.groups[length(body.groups) - 1].stmts |> push(child)
            }
            continue
        }
        if (empty(body.groups) || !empty(body.groups[length(body.groups) - 1].stmts)) {
            body.groups |> emplace(Group())
        }
        body.groups[length(body.groups) - 1].labels++
        f.n["labels"]++
        if (child.s == "default") {
            default_group = length(body.groups) - 1
        } else {
            f.lo = empty(distinct) ? child.v : min(f.lo, child.v)
            f.hi = empty(distinct) ? child.v : max(f.hi, child.v)
            distinct[child.v] = true
            f.n["char_labels"] += child.is_char ? 1 : 0
        }
    }
    f.n["groups"] = length(body.groups)
    f.n["values"] = length(distinct)
    if (!empty(distinct)) {
        f.n["density"] = int(100.0lf * double(length(distinct)) / (double(f.hi) - double(f.lo) + 1.0lf))
    }
    if (default_group >= 0) {
        f.default_at = default_group == length(body.groups) - 1 ? "last" : default_group == 0 ? "first" : "middle"
    }
    return <- body
}

// the facts each statement at the body's level carries by itself, into `f`: labels below the
// level, breaks, continues and declarations; `early_breaks` still holds every break of the switch
def private count_statements(top : array<CirStmt const?>; var f : SwitchFacts) {
    for (idx, child in range(length(top)), top) {
        if (is_marker(child)) {
            continue
        }
        f.n["nested_labels"] += markers_under(child)
        f.n["loop_breaks"] += loop_breaks(child, false)
        f.n["continues_out"] += outer_continues(child)
        f.n["early_breaks"] += own_breaks(child)
        if (child.s != "decl") {
            continue
        }
        var later = idx + 1
        while (later < length(top) && !is_marker(top[later])) {
            later++
        }
        if (later < length(top)) {
            f.n["decl_cross"]++
            f.n["decl_used_later"] += names_variable(top, later, child.name) ? 1 : 0
        }
    }
}

// the goto facts into `f`: `gotos` counts the function's gotos per label
def private count_gotos(body : Body; gotos : table<string; int>; var f : SwitchFacts) {
    var label_group, inner_count : table<string; int>
    var inner_gotos : array<tuple<target : string; group : int>>
    for (idx in range(-1, length(body.groups))) {
        for (child in idx < 0 ? body.before : body.groups[idx].stmts) {
            each_stmt(child) $(sub) {
                if (sub.s == "label") {
                    label_group[sub.label_name] = idx
                } elif (sub.s == "goto") {
                    inner_gotos |> push((target = sub.label_name, group = idx))
                }
            }
        }
    }
    for (g in inner_gotos) {
        inner_count[g.target]++
        if (!key_exists(label_group, g.target)) {
            f.n["goto_out"]++
        } elif (label_group?[g.target] ?? -1 != g.group) {
            f.n["goto_cross"]++
        }
    }
    for (name in keys(label_group)) {
        f.n["labels_entered"] += (gotos?[name] ?? 0) > (inner_count?[name] ?? 0) ? 1 : 0
    }
}

// whether control entering group `from` leaves the switch with nothing done: the groups from it
// on do nothing up to one that only breaks, or up to the body's end
def private only_breaks(groups : array<Group>; from : int) : bool {
    for (idx in range(from, length(groups))) {
        for (child in groups[idx].stmts) {
            if (!is_inert(child)) {
                return child.s == "break"
            }
        }
    }
    return true
}

// the fall facts into `f`, and each group's tail `break` taken out of `early_breaks`
def private count_falls(groups : array<Group>; var f : SwitchFacts) {
    for (idx, g in range(length(groups)), groups) {
        f.n["shared_labels"] += g.labels - 1
        var acts = false
        for (child in g.stmts) {
            acts = acts || !is_inert(child)
        }
        if (!acts) {
            f.n["shared_labels"] += idx < length(groups) - 1 ? 1 : 0
            continue
        }
        f.n["early_breaks"] -= is_tail_break(g.stmts[length(g.stmts) - 1]) ? 1 : 0
        if (idx < length(groups) - 1 && run_completes(g.stmts)) {
            if (only_breaks(groups, idx + 1)) {
                f.n["falls_to_break"]++
            } else {
                f.n["real_falls"]++
                if (f.n?["fall_line"] ?? 0 == 0) {
                    f.n["fall_line"] = g.stmts[length(g.stmts) - 1].loc.line
                }
            }
        }
    }
}

// the facts of the switch `st` of function `func`, `gotos` the function's gotos per label
def private switch_facts(tu : CirTu; st : CirStmt const?; func : string; gotos : table<string; int>) : SwitchFacts {
    var f = SwitchFacts(file = st.loc.file, line = st.loc.line, col = st.loc.col, func = func, default_at = "none")
    for (name in FEATURES) {
        f.n[name] = 0
    }
    let body <- read_body(st, f)
    count_statements(body.top, f)
    count_gotos(body, gotos, f)
    count_falls(body.groups, f)
    f.cond = cond_kind(tu, st, f.n?["char_labels"] ?? 0)
    f.cls = switch_class(f)
    return <- f
}

//! Every `switch` of `tu`, in the order its functions and statements stand.
def census_tu(tu : CirTu) : array<SwitchFacts> {
    var out : array<SwitchFacts>
    for (d in tu.decls) {
        if (d.k != "func" || d.body == null) {
            continue
        }
        var inscope gotos : table<string; int>
        each_stmt(d.body) $(st) {
            if (st.s == "goto") {
                gotos[st.label_name]++
            }
        }
        each_stmt(d.body) $(st) {
            if (st.s == "switch") {
                out |> emplace(switch_facts(tu, st, d.c_name, gotos))
            }
        }
    }
    return <- out
}

//! The line of `f` in a rows file: tab-separated, the place, the function, the condition's kind,
//! where `default` stands, the smallest and largest value, the class, then `FEATURES` in order.
def facts_line(f : SwitchFacts) : string {
    var cells <- [f.file, "{f.line}", "{f.col}", f.func, f.cond, f.default_at, "{f.lo}", "{f.hi}", f.cls]
    cells |> reserve(length(cells) + length(FEATURES))
    for (name in FEATURES) {
        cells |> push("{f.n?[name] ?? 0}")
    }
    return join(cells, "\t")
}

//! The row a line of `facts_line` holds; `ok` is false for a line of another shape.
def read_facts_line(line : string; var ok : bool&) : SwitchFacts {
    let cells <- split(line, "\t")
    ok = length(cells) == 9 + length(FEATURES)
    var f : SwitchFacts
    if (!ok) {
        return <- f
    }
    f.file = cells[0]
    f.line = to_int(cells[1])
    f.col = to_int(cells[2])
    f.func = cells[3]
    f.cond = cells[4]
    f.default_at = cells[5]
    f.lo = to_int64(cells[6])
    f.hi = to_int64(cells[7])
    f.cls = cells[8]
    for (idx, name in range(length(FEATURES)), FEATURES) {
        f.n[name] = to_int(cells[9 + idx])
    }
    return <- f
}

//! A row of the census tables: a program and its switches, each counted once.
struct ProgramCensus {
    name : string
    rows : array<SwitchFacts>
}

//! The program `name` of `rows`: a switch that several translation units hold (a header's
//! function, a file two programs share) kept once, by place and function, in the order met,
//! and marked hot when its function is one of `hot`.
def program_census(name : string; rows : array<SwitchFacts>; hot : array<string>) : ProgramCensus {
    var seen : table<string; bool>
    var p = ProgramCensus(name = name)
    p.rows |> reserve(length(rows))
    for (f in rows) {
        let key = "{f.file}:{f.line}:{f.col}:{f.func}"
        if (!key_exists(seen, key)) {
            seen[key] = true
            p.rows |> push_clone(f)
            p.rows[length(p.rows) - 1].hot = has_value(hot, f.func)
        }
    }
    return <- p
}

def private share(part, whole : int) : string => whole == 0 ? "0" : "{part} ({(part * 100 + whole / 2) / whole}%)"

def private md_row(cells : array<string>) : string => "| " + join(cells, " | ") + " |\n"

def private md_head(cells : array<string>) : string => md_row(cells) + md_row([for (_ in cells); "---"])

def private count_where(p : ProgramCensus; hot_only : bool; pred : block<(f : SwitchFacts) : bool>) : int {
    var found = 0
    for (f in p.rows) {
        if ((!hot_only || f.hot) && invoke(pred, f)) {
            found++
        }
    }
    return found
}

// `programs` and, when `total` is named, a row of that name pooling them
def private with_total(programs : array<ProgramCensus>; total : string) : array<ProgramCensus> {
    var out : array<ProgramCensus>
    var all = ProgramCensus(name = total)
    out |> reserve(length(programs) + 1)
    for (p in programs) {
        out |> push_clone(p)
        all.rows |> push_clone_from(p.rows)
    }
    if (!empty(total)) {
        out |> emplace(all)
    }
    return <- out
}

// the class table's row of `p`
def private class_row(p : ProgramCensus) : string {
    let all = length(p.rows)
    let hot = count_where(p, true) $(_f) => true
    let classes <- [for (cls in CLASSES); share(count_where(p, false) $(f) => f.cls == cls, all)]
    return md_row([p.name, "{all}", classes[0], classes[1], classes[2], classes[3], "{hot}", share(count_where(p, true) $(f) => f.cls == "S1", hot)])
}

//! The class table: per program its switches, each class with its share, the switches of the
//! hot functions and how many of those are `S1`; a row `total` pooling the programs when named.
def render_classes(programs : array<ProgramCensus>; total : string) : string =>
    md_head(["program", "switch", "S1", "S2", "S3", "S4", "hot", "hot S1"]) + join([for (p in with_total(programs, total)); class_row(p)], "")

//! The columns of the feature table: a heading and the `FEATURES` name whose non-zero count puts
//! a switch in the column.
let FEATURE_COLUMNS <- [("shared labels", "shared_labels"), ("real fall", "real_falls"), ("fall to break", "falls_to_break"), ("early break", "early_breaks"), ("loop break", "loop_breaks"), ("continue out", "continues_out"), ("goto case", "goto_cross"), ("label entered", "labels_entered"), ("goto out", "goto_out"), ("decl over label", "decl_cross"), ("decl used later", "decl_used_later"), ("nested case", "nested_labels")]

let private KIND_COLUMNS <- ["int", "enum", "char", "bool"]

let private SHAPE_COLUMNS <- ["default", "default not last", "under 4 values", "4 to 7", "8 and more", "8 and more, half full"]

// the feature table's row of `p`
def private feature_row(p : ProgramCensus; hot_only : bool) : string {
    var cells <- [p.name, "{count_where(p, hot_only) $(_f) => true}"]
    cells |> reserve(length(cells) + length(KIND_COLUMNS) + length(SHAPE_COLUMNS) + length(FEATURE_COLUMNS))
    for (kind in KIND_COLUMNS) {
        cells |> push("{count_where(p, hot_only) $(f) => f.cond == kind}")
    }
    cells |> push("{count_where(p, hot_only) $(f) => f.default_at != "none"}")
    cells |> push("{count_where(p, hot_only) $(f) => f.default_at == "first" || f.default_at == "middle"}")
    cells |> push("{count_where(p, hot_only) $(f) => (f.n?["values"] ?? 0) < 4}")
    cells |> push("{count_where(p, hot_only) $(f) => (f.n?["values"] ?? 0) >= 4 && (f.n?["values"] ?? 0) < 8}")
    cells |> push("{count_where(p, hot_only) $(f) => (f.n?["values"] ?? 0) >= 8}")
    cells |> push("{count_where(p, hot_only) $(f) => (f.n?["values"] ?? 0) >= 8 && (f.n?["density"] ?? 0) >= 50}")
    for (c in FEATURE_COLUMNS) {
        cells |> push("{count_where(p, hot_only) $(f) => (f.n?[c._1] ?? 0) > 0}")
    }
    return md_row(cells)
}

//! The feature table: per program the number of switches by condition kind, by `default` and
//! its place, by value count and density, and with each feature of `FEATURE_COLUMNS`; with
//! `hot_only` over the switches of the hot functions alone.
def render_features(programs : array<ProgramCensus>; total : string; hot_only : bool) : string {
    var head <- ["program", "switch"]
    head |> push_from(KIND_COLUMNS, SHAPE_COLUMNS, [for (c in FEATURE_COLUMNS); c._0])
    return md_head(head) + join([for (p in with_total(programs, total)); feature_row(p, hot_only)], "")
}

// the site list's line of `f`
def private site_line(f : SwitchFacts) : string {
    var notes <- ["{f.n?["values"] ?? 0} values", "{f.n?["density"] ?? 0}% full", "default {f.default_at}"]
    notes |> reserve(length(notes) + length(FEATURE_COLUMNS) + 1)
    for (c in FEATURE_COLUMNS) {
        if ((f.n?[c._1] ?? 0) > 0) {
            notes |> push("{c._0} {f.n?[c._1] ?? 0}")
        }
    }
    if ((f.n?["fall_line"] ?? 0) > 0) {
        notes |> push("first fall at line {f.n?["fall_line"] ?? 0}")
    }
    return "- {f.file}:{f.line} `{f.func}` {f.cls}{f.hot ? " hot" : ""} {f.cond}: {join(notes, ", ")}\n"
}

//! The switches of `p` that are not `S1` or stand in a hot function, one line each: the place,
//! the function, the class, `hot`, the value count and density, and every non-zero feature.
def render_sites(p : ProgramCensus) : string => join([for (f in p.rows); site_line(f); where f.cls != "S1" || f.hot], "")

//! Every `switch` of the C file `c_path`, dumped under the `linux` dialect with no sidecar;
//! `error` is the dumper's when it refuses the file.
def census_c_file(c_path : string; var error : string&) : array<SwitchFacts> {
    var d <- dump_tu(c_path, target_by_name("linux"), default_clang(), DumpInputs())
    error = d.error
    var rows <- empty(error) ? census_tu(d.tu) : array<SwitchFacts>()
    delete_tu(d.tu)
    return <- rows
}
