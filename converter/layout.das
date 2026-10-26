options gen2

module layout public

require strings
require daslib/strings_boost
require daslib/fio
require math
require daslib/algorithm
require cir
require link

//! The source module layout (`ARCHITECTURE_LAYOUT.md`): the partition of a linked program into das
//! modules that mirror its C files. The nodes are the units and every file that defines a record or
//! an enum the program uses (a header, or the shared node of the types no single file defines); an
//! edge goes from a unit to the unit defining each function or object it references and from any
//! node to the owner of each record or enum its declarations spell. Each strongly connected
//! component is one module, since daslang refuses a cyclic `require`. Nothing here knows clang or
//! daslang syntax.

//! A node of the partition: a unit (`unit` its index), a non-unit file defining types (a header),
//! or the one node of the types no single file defines; `stem` names its module or fragment, `dir`
//! is its file's folder relative to the program's root ("" for the root).
struct LayoutNode {
    kind : string
    file : string
    stem : string
    unit : int
    dir : string
}

//! One output module: its name (its file is `<name>.das`), its folder relative to the program's
//! root, its member nodes in include order, whether it is a cluster (a `.das.inc` fragment per
//! member), and the modules it requires.
struct LayoutModule {
    name : string
    dir : string
    members : array<int>
    cluster : bool
    requires : array<int>
}

//! The partition: the nodes, the modules, the module of each node, the node of each unit, the node
//! owning each record and enum, the module holding `main`, the program's root folder (the common
//! folder of its C files), the edges between nodes with the names that make each, and a refusal.
struct LayoutPlan {
    nodes : array<LayoutNode>
    modules : array<LayoutModule>
    node_module : array<int>
    unit_node : array<int>
    type_node : table<int; int>
    entry : int
    root : string
    edges : array<table<int>>
    reasons : table<string; array<string>>
    // the symbols of each edge between two units, by `<from>><to>`
    symbols : table<string; array<EdgeSymbol>>
    // the cycle cut of the `source` layout: each late-bound function, by name, with the node of
    // the unit defining it and the slot the link module holds for it; the link module (-1: none);
    // and the cut's report lines, one per cut symbol and per cluster no cut breaks
    late : table<string; int>
    slots : table<string; string>
    // the edges between two units a type makes (the target unit defines a record the source spells),
    // which no cut takes, and the node of the unit holding `main`, whose own edges no cut takes
    type_edges : table<string>
    entry_node : int
    link : int = -1
    cut_report : array<string>
    error : string
}

//! A function or object an edge between two units carries: its name, its call sites in the calling
//! unit, its dynamic call count from that unit when a profile has one, and why a cut cannot
//! late-bind it ("" when it can: a function every reference of the program calls directly, whose
//! type spells no unit's record).
struct EdgeSymbol {
    name : string
    calls : int
    dynamic : int64
    why_not : string
}

//! The kinds of a node.
let NODE_UNIT = "unit"
let NODE_HEADER = "header"
let NODE_TYPES = "types"

//! The stem of the node of the types no single file defines: an external record (`struct tm`),
//! one the program reaches only through pointers (`FILE`), or one two files define alike.
let TYPES_STEM = "c_types"

// a record or enum that is the program's own type: neither the `va_list` record nor `jmp_buf`, which
// c_runtime spells
def private owned_kind(t : CirType) : bool =>
    (t.k == "struct" || t.k == "union" || t.k == "enum") && t.spell != "va_list" && t.name != "jmp_buf"

// the records and enums type `t` spells, through pointers, arrays, functions and typedefs (a
// record's fields are its own owner's)
def private spelled_types(types : array<CirType>; t : int; var out : table<int>) {
    if (t < 0 || t >= length(types)) {
        return
    }
    let k = types[t].k
    if (owned_kind(types[t])) {
        out |> insert(t)
    } elif (k == "ptr" || k == "typedef") {
        spelled_types(types, types[t].to, out)
    } elif (k == "array") {
        spelled_types(types, types[t].elem, out)
    } elif (k == "func") {
        spelled_types(types, types[t].ret, out)
        for (p in types[t].params) {
            spelled_types(types, p, out)
        }
    }
}

def private dims_types(types : array<CirType>; dims : array<CirDim>; var out : table<int>) {
    for (dim in dims) {
        if (!empty(dim.item)) {
            spelled_types(types, dim.enum_t, out)
        }
    }
}

// what a unit's declarations use: the records and enums they spell, the names they reference other
// than as a direct call's callee, and the names they call with the count of call sites
struct private Refs {
    types : table<int>
    names : table<string>
    calls : table<string; int>
}

// the name a call's callee is when it is one, below the decay of a function to its pointer
def private callee_ref(fn : CirExpr const?) : string {
    var at = fn
    if (at != null && at.e == "cast" && at.cast_kind == "FunctionToPointerDecay") {
        at = at.a
    }
    return at != null && at.e == "ref" ? at.name : ""
}

def private expr_uses(types : array<CirType>; x : CirExpr const?; var r : Refs) {
    if (x == null) {
        return
    }
    spelled_types(types, x.t, r.types)
    if (x.e == "enum_ref") {
        spelled_types(types, x.enum_t, r.types)
    } elif (x.e == "sizeof_v" || x.e == "alignof_v" || x.e == "offsetof") {
        spelled_types(types, x.of_t, r.types)
    } elif (x.e == "va_arg") {
        spelled_types(types, x.arg_t, r.types)
    } elif (x.e == "ref") {
        r.names |> insert(x.name)
    }
    let callee = x.e == "call" ? callee_ref(x.fn) : ""
    if (!empty(callee)) {
        r.calls[callee] = (r.calls?[callee] ?? 0) + 1
    } else {
        expr_uses(types, x.fn, r)
    }
    expr_uses(types, x.a, r)
    expr_uses(types, x.b, r)
    expr_uses(types, x.c, r)
    expr_uses(types, x.base, r)
    expr_uses(types, x.i, r)
    expr_uses(types, x.list, r)
    expr_uses(types, x.init, r)
    for (arg in x.args) {
        expr_uses(types, arg, r)
    }
    for (item in x.init_items) {
        expr_uses(types, item.v, r)
    }
}

def private stmt_uses(types : array<CirType>; x : CirStmt const?; var r : Refs) {
    if (x == null) {
        return
    }
    if (x.s == "decl") {
        spelled_types(types, x.t, r.types)
        dims_types(types, x.dims, r.types)
    }
    expr_uses(types, x.init, r)
    expr_uses(types, x.e, r)
    expr_uses(types, x.cond, r)
    expr_uses(types, x.inc, r)
    stmt_uses(types, x.then_s, r)
    stmt_uses(types, x.else_s, r)
    stmt_uses(types, x.body_s, r)
    stmt_uses(types, x.init_s, r)
    for (child in x.body) {
        stmt_uses(types, child, r)
    }
}

// a declaration the unit emits itself: a function it defines, an object it defines (tentatively
// too) and every static; a prototype or an `extern` declaration is the defining unit's
def private emitted_by_unit(d : CirDecl const?) : bool =>
    (d.k == "func" && (d.body != null || d.is_static)) || (d.k == "global" && (!d.is_extern || d.is_static))

// a type's name for a reason line
def private type_label(t : CirType; idx : int) : string {
    let name = empty(t.name) ? "anon_{idx}" : t.name
    return "{t.k} {name}"
}

// an edge `from` -> `to`, `why` one of the names that make it
def private add_edge(var plan : LayoutPlan; from, to : int; why : string) {
    if (from == to || to < 0) {
        return
    }
    plan.edges[from] |> insert(to)
    let key = "{from}>{to}"
    if (!has_value(plan.reasons?[key] ?? array<string>(), why)) {
        plan.reasons[key] |> push(why)
    }
}

// the node of non-unit file `file` (a header), made on first use
def private header_node(var plan : LayoutPlan; var by_file : table<string; int>; file : string) : int {
    let known = by_file?[file] ?? -1
    if (known >= 0) {
        return known
    }
    let idx = length(plan.nodes)
    plan.nodes |> push(LayoutNode(kind = NODE_HEADER, file = file, stem = ident_of(base_name(file)), unit = -1))
    plan.edges |> resize(length(plan.nodes))
    by_file[file] = idx
    return idx
}

// the node owning each record and enum: the one file every unit anchors it in (its own `.c` for a
// unit's type), else the shared types node
def private own_types(var plan : LayoutPlan; tus : array<CirTu>; types : array<CirType>; var by_file : table<string; int>) {
    var anchors : table<int; array<string>>
    for (tu in tus) {
        for (d in tu.decls) {
            if (d.k == "record" || d.k == "enumdef") {
                let file = get_full_file_name(d.loc.file)
                if (!has_value(anchors?[d.t] ?? array<string>(), file)) {
                    anchors[d.t] |> push(file)
                }
            }
        }
    }
    var types_node = -1
    for (t in range(length(types))) {
        if (!owned_kind(types[t])) {
            continue
        }
        var node = -1
        anchors |> get(t) $(files) {
            if (length(files) == 1) {
                node = by_file?[files[0]] ?? header_node(plan, by_file, files[0])
            }
        }
        if (node < 0) {
            if (types_node < 0) {
                types_node = length(plan.nodes)
                plan.nodes |> push(LayoutNode(kind = NODE_TYPES, stem = TYPES_STEM, unit = -1))
                plan.edges |> resize(length(plan.nodes))
            }
            node = types_node
        }
        plan.type_node[t] = node
    }
    claim_header_types(plan, tus, types, by_file)
}

// a record a header spells is the header's, even where a unit's `.c` defines it (`lstate.h`'s
// pointer to the `struct lua_longjmp` of `ldo.c`): a header typedef naming it, or a field of a record
// the header owns, through pointers, claims it; the claim repeats through the claimed record's own
// fields, so no unit is ever required by a header
def private claim_header_types(var plan : LayoutPlan; tus : array<CirTu>; types : array<CirType>; var by_file : table<string; int>) {
    for (tu in tus) {
        for (d in tu.decls) {
            if (d.k == "typedefdecl") {
                let file = get_full_file_name(d.loc.file)
                let owner = by_file?[file] ?? -1
                if (owner < 0 || plan.nodes[owner].kind != NODE_UNIT) {
                    var inscope named : table<int>
                    spelled_types(types, d.t, named)
                    for (r in keys(named)) {
                        let held = plan.type_node?[r] ?? -1
                        if (held >= 0 && plan.nodes[held].kind == NODE_UNIT) {
                            plan.type_node[r] = owner >= 0 ? owner : header_node(plan, by_file, file)
                        }
                    }
                }
            }
        }
    }
    var changed = true
    while (changed) {
        var inscope claims : table<int; int>
        for (t, node in keys(plan.type_node), values(plan.type_node)) {
            if (plan.nodes[node].kind != NODE_UNIT) {
                var inscope spelled : table<int>
                for (f in types[t].fields) {
                    spelled_types(types, f.t, spelled)
                }
                for (r in keys(spelled)) {
                    let held = plan.type_node?[r] ?? -1
                    if (held >= 0 && plan.nodes[held].kind == NODE_UNIT && !key_exists(claims, r)) {
                        claims[r] = node
                    }
                }
            }
        }
        for (r, node in keys(claims), values(claims)) {
            plan.type_node[r] = node
        }
        changed = !empty(claims)
    }
}

// why a cut cannot late-bind the symbol whose definition is `d` (null: an object), "" when it can
def private why_not_cut(plan : LayoutPlan; types : array<CirType>; d : CirDecl const?; addressed : bool) : string {
    if (d == null) {
        return "an object"
    }
    if (addressed) {
        return "its address is taken"
    }
    var why = ""
    var inscope signature : table<int>
    spelled_types(types, d.t, signature)
    for (t in keys(signature)) {
        let owner = plan.type_node?[t] ?? -1
        if (owner >= 0 && plan.nodes[owner].kind == NODE_UNIT) {
            why = "its type spells a record of {base_name(plan.nodes[owner].file)}"
        }
    }
    return why
}

// the edges of the program: unit to unit by the functions and objects it references, each with
// its symbols (a function's call sites, and whether a cut may late-bind it), every node to the
// owners of the records and enums it spells
def private find_edges(var plan : LayoutPlan; tus : array<CirTu>; types : array<CirType>; facts : LinkFacts) {
    var inscope refs : array<Refs>
    refs |> resize(length(tus))
    var inscope addressed : table<string>
    for (ti, tu in count(), tus) {
        for (d in tu.decls) {
            if (emitted_by_unit(d)) {
                spelled_types(types, d.t, refs[ti].types)
                for (p in d.params) {
                    spelled_types(types, p.t, refs[ti].types)
                }
                dims_types(types, d.dims, refs[ti].types)
                expr_uses(types, d.init, refs[ti])
                stmt_uses(types, d.body, refs[ti])
            }
        }
        for (name in keys(refs[ti].names)) {
            addressed |> insert(name)
        }
    }
    var defined : table<string; CirDecl const?> // nolint:STYLE027 - a comprehension takes one source, the units' declarations are many
    for (tu in tus) {
        for (d in tu.decls) {
            if (d.k == "func" && d.body != null && !d.is_static) {
                defined[d.name] = d
            }
        }
    }
    for (ti in range(length(tus))) {
        let from = plan.unit_node[ti]
        var inscope names <- clone_to_move(refs[ti].names)
        for (name in keys(refs[ti].calls)) {
            names |> insert(name)
        }
        for (name in keys(facts.refs[ti])) {
            names |> insert(name)
        }
        for (name in keys(names)) {
            let def_unit = facts.defined_in?[name] ?? -1
            if (def_unit >= 0 && def_unit != ti) {
                let to = plan.unit_node[def_unit]
                add_edge(plan, from, to, name)
                let why = why_not_cut(plan, types, defined?[name] ?? null, key_exists(addressed, name))
                plan.symbols["{from}>{to}"] |> push(EdgeSymbol(name = name, calls = refs[ti].calls?[name] ?? 0, why_not = why))
            }
        }
        for (t in keys(refs[ti].types)) {
            let owner = plan.type_node?[t] ?? -1
            add_edge(plan, from, owner, type_label(types[t], t))
            if (owner >= 0 && owner != from && plan.nodes[owner].kind == NODE_UNIT) {
                plan.type_edges |> insert("{from}>{owner}")
            }
        }
    }
    for (t, node in keys(plan.type_node), values(plan.type_node)) {
        var inscope used : table<int>
        for (f in types[t].fields) {
            spelled_types(types, f.t, used)
            dims_types(types, f.dims, used)
        }
        for (u in keys(used)) {
            add_edge(plan, node, plan.type_node?[u] ?? -1, type_label(types[u], u))
        }
    }
}

struct private Tarjan {
    index : array<int>
    low : array<int>
    on_stack : array<bool>
    stack : array<int>
    next : int
    components : array<array<int>>
}

def private strong_connect(var tj : Tarjan; edges : array<table<int>>; v : int) {
    tj.index[v] = tj.next
    tj.low[v] = tj.next
    tj.next++
    tj.stack |> push(v)
    tj.on_stack[v] = true
    var inscope succ <- [for (w in keys(edges[v])); w]
    sort(succ)
    for (w in succ) {
        if (tj.index[w] < 0) {
            strong_connect(tj, edges, w)
            tj.low[v] = min(tj.low[v], tj.low[w])
        } elif (tj.on_stack[w]) {
            tj.low[v] = min(tj.low[v], tj.index[w])
        }
    }
    if (tj.low[v] == tj.index[v]) {
        var comp : array<int>
        while (true) {
            let w = tj.stack[length(tj.stack) - 1]
            tj.stack |> pop()
            tj.on_stack[w] = false
            comp |> push(w)
            break if (w == v)
        }
        sort(comp)
        tj.components |> emplace(comp)
    }
}

//! The strongly connected components of a graph given as each node's successors, each sorted, in
//! the order Tarjan's algorithm closes them (a component before every one that reaches it).
def components_of(edges : array<table<int>>) : array<array<int>> {
    var tj : Tarjan
    let n = length(edges)
    tj.index |> resize(n)
    tj.low |> resize(n)
    tj.on_stack |> resize(n)
    for (v in range(n)) {
        tj.index[v] = -1
    }
    for (v in range(n)) {
        if (tj.index[v] < 0) {
            strong_connect(tj, edges, v)
        }
    }
    return <- tj.components
}

// the folder of `file` relative to `root`, "" for the root itself; `error` when it lies outside (a
// guard: a header is the program's only under its unit's folder, which is under the root)
def private relative_dir(root, file : string; var error : string&) : string {
    let dir = dir_name(file)
    if (dir == root) {
        return ""
    }
    if (!(dir |> starts_with(root + "/"))) {
        error = "{file} lies outside the program's root {root}, the common folder of its C files"
        return ""
    }
    return slice(dir, length(root) + 1)
}

// the common folder of the full paths `paths`
def private common_dir(paths : array<string>) : string {
    var root = dir_name(paths[0])
    for (p in paths) {
        while (root != "/" && !empty(root) && dir_name(p) != root && !(dir_name(p) |> starts_with(root + "/"))) {
            root = dir_name(root)
        }
    }
    return root
}

// the records type `t` holds by value, through arrays (a pointer's target is no part of its storage)
def private held_records(types : array<CirType>; t : int; var out : table<int>) {
    if (t < 0 || t >= length(types)) {
        return
    }
    if (types[t].k == "array") {
        held_records(types, types[t].elem, out)
    } elif (types[t].k == "typedef") {
        held_records(types, types[t].to, out)
    } elif (owned_kind(types[t]) && types[t].k != "enum") {
        out |> insert(t)
    }
}

// `nodes` in order, each after every node of `after` it waits for where the order allows (a node
// in a cycle keeps its place)
def private ordered_after(nodes : array<int>; after : table<int; table<int>>) : array<int> {
    var order : array<int>
    var placed : table<int>
    while (length(placed) < length(nodes)) {
        var pick = -1
        for (m in nodes) {
            if (!key_exists(placed, m)) {
                var ready = true
                after |> get(m) $(before) {
                    for (b in keys(before)) {
                        ready = ready && key_exists(placed, b)
                    }
                }
                if (ready) {
                    pick = m
                    break
                }
            }
        }
        if (pick < 0) {
            for (m in nodes) {
                if (!key_exists(placed, m)) {
                    pick = m
                    break
                }
            }
        }
        placed |> insert(pick)
        order |> push(pick)
    }
    return <- order
}

// the include order of a cluster's members: its type nodes first, each after the members whose
// records its own hold by value (an annotation reads a member's record where it is declared), then
// its units in link order, a unit whose global initializers take the address of another member's
// global after that member, each where the order allows (a cycle keeps the link order)
def private include_order(plan : LayoutPlan; tus : array<CirTu>; types : array<CirType>; facts : LinkFacts; members : array<int>) : array<int> {
    let type_nodes <- [for (m in members); m; where plan.nodes[m].kind != NODE_UNIT]
    var units <- [for (m in members); m; where plan.nodes[m].kind == NODE_UNIT]
    var holds : table<int; table<int>>
    for (t, node in keys(plan.type_node), values(plan.type_node)) {
        if (has_value(type_nodes, node)) {
            var inscope held : table<int>
            for (f in types[t].fields) {
                held_records(types, f.t, held)
            }
            for (h in keys(held)) {
                let owner = plan.type_node?[h] ?? -1
                if (owner != node && has_value(type_nodes, owner)) {
                    holds[node] |> insert(owner)
                }
            }
        }
    }
    var order <- ordered_after(type_nodes, holds)
    var after : table<int; table<int>>
    for (m in units) {
        var inscope r : Refs
        for (d in tus[plan.nodes[m].unit].decls) {
            if (d.k == "global" && d.init != null) {
                expr_uses(array<CirType>(), d.init, r)
            }
        }
        for (name in keys(r.names)) {
            let def_unit = facts.defined_in?[name] ?? -1
            if (def_unit >= 0 && plan.unit_node[def_unit] != m && has_value(units, plan.unit_node[def_unit])) {
                after[m] |> insert(plan.unit_node[def_unit])
            }
        }
    }
    order |> push_from(ordered_after(units, after))
    return <- order
}

// a module per component of the edges, named and placed as `plan_layout` states, its members in
// include order; `plan.error` names two modules of one name
def private name_modules(var plan : LayoutPlan; tus : array<CirTu>; types : array<CirType>; facts : LinkFacts; entry_unit : int) {
    let components <- components_of(plan.edges)
    plan.modules |> reserve(length(components))
    var names : table<string; string>
    for (comp in components) {
        var inscope stems <- [for (m in comp); plan.nodes[m].stem]
        sort(stems)
        let entry_node = plan.unit_node[entry_unit]
        let holds_entry = has_value(comp, entry_node)
        let name = holds_entry ? plan.nodes[entry_node].stem : length(comp) == 1 ? stems[0] : "{stems[0]}_cluster"
        var lead = holds_entry ? entry_node : comp[0]
        for (m in comp) {
            if (plan.nodes[m].stem == stems[0] && !holds_entry) {
                lead = m
            }
        }
        let other = names?[name] ?? ""
        let shown = plan.nodes[lead].kind == NODE_TYPES ? "the types no single file defines" : base_name(plan.nodes[lead].file)
        if (is_taken_module(name)) {
            plan.error = "the module of {shown} would be `{name}.das`, which a module daslang or c2das-re loads by that name takes; rename the file"
            return
        }
        if (!empty(other)) {
            plan.error = "the modules of {other} and {shown} would both be `{name}.das`; rename a file"
            return
        }
        names[name] = shown
        var dir = ""
        if (plan.nodes[lead].kind != NODE_TYPES) {
            dir = relative_dir(plan.root, plan.nodes[lead].file, plan.error)
        }
        if (!empty(plan.error)) {
            return
        }
        let mi = length(plan.modules)
        for (m in comp) {
            plan.node_module[m] = mi
        }
        if (holds_entry) {
            plan.entry = mi
        }
        plan.modules |> emplace(LayoutModule(name = name, dir = dir, members <- include_order(plan, tus, types, facts, comp), cluster = length(comp) > 1))
    }
}

// each module's requires: the other modules its members' edges reach, by name
def private require_modules(var plan : LayoutPlan) {
    for (m in range(length(plan.modules))) {
        var inscope required : table<int>
        for (node in plan.modules[m].members) {
            for (to in keys(plan.edges[node])) {
                if (plan.node_module[to] != m) {
                    required |> insert(plan.node_module[to])
                }
            }
        }
        plan.modules[m].requires <- [for (r in keys(required)); r]
        sort(plan.modules[m].requires) $(a, b) => plan.modules[a].name < plan.modules[b].name
    }
}

//! The choices of the cycle cut (`ARCHITECTURE_LAYOUT.md`, "The cycle cut"): whether to cut at
//! all (the `source` layout; `scc` keeps every cycle a cluster), the weight above which an edge is
//! never cut (-1: none), the symbols never cut, the groups of units (by file stem) kept in one
//! module, the symbols always cut, and the dynamic call counts of a profiled native run, by symbol
//! and calling unit's stem (empty: none, the static count of call sites weighs instead).
struct CutOptions {
    cut_cycles : bool
    threshold : int64 = -1l
    keep_symbols : table<string>
    keep_units : array<array<string>>
    always_cut : table<string>
    profile : table<string; table<string; int64>>
}

// the weight an edge's symbols give it: their dynamic call counts from the calling unit when the
// options hold a profile, else their call sites
def private edge_weight(plan : LayoutPlan; opts : CutOptions; from : int; syms : array<EdgeSymbol>) : int64 {
    var w = 0l
    for (sym in syms) {
        if (empty(opts.profile)) {
            w += int64(sym.calls)
        } else {
            opts.profile |> get(sym.name) $(by_unit) {
                w += by_unit?[plan.nodes[from].stem] ?? 0l
            }
        }
    }
    return w
}

// the units `--layout` keeps in one module: both ends in one group of `keep_units`
def private kept_together(plan : LayoutPlan; opts : CutOptions; a, b : int) : bool {
    for (group in opts.keep_units) {
        if (has_value(group, plan.nodes[a].stem) && has_value(group, plan.nodes[b].stem)) {
            return true
        }
    }
    return false
}

// why the edge `from` -> `to` between two units cannot be cut, "" when it can
def private uncuttable(plan : LayoutPlan; opts : CutOptions; from, to : int; weight : int64) : string {
    if (plan.nodes[from].kind != NODE_UNIT || plan.nodes[to].kind != NODE_UNIT) {
        return "a type"
    }
    if (key_exists(plan.type_edges, "{from}>{to}")) {
        return "a type {base_name(plan.nodes[to].file)} defines"
    }
    if (kept_together(plan, opts, from, to)) {
        return "layout.keep_together"
    }
    var why = ""
    plan.symbols |> get("{from}>{to}") $(syms) {
        for (sym in syms) {
            if (!empty(sym.why_not)) {
                why = "{sym.name}: {sym.why_not}"
            } elif (key_exists(opts.keep_symbols, sym.name)) {
                why = "{sym.name}: layout.keep_together"
            }
        }
    }
    if (!empty(why)) {
        return why
    }
    return opts.threshold >= 0l && weight > opts.threshold ? "its weight {weight} is above layout.threshold" : ""
}

//! The weight of an edge no cut may take.
let NO_CUT = 4611686018427387903l

//! The order of `n` nodes, lowest first, that minimizes the weight of the edges going up it (an
//! edge `a` -> `b` with `a` placed below `b`), `w[a * n + b]` each edge's weight (`NO_CUT` for one
//! never cut), node `top` (-1 for none) placed highest: exact over the subsets for up to 16 nodes,
//! among the orders of least weight one leaving the fewest nodes whose every caller is below them,
//! else a greedy order (a node requiring nothing unplaced goes lowest, one nothing unplaced requires
//! highest, else the node most required over what it requires).
def cut_order(n : int; w : array<int64>; top : int = -1) : array<int> => <- n <= 16 ? exact_order(n, w, top) : greedy_order(n, w, top)

// `cut_order` over the subsets: the least weight of each set of nodes placed lowest, built a node at
// a time
def private exact_order(n : int; w : array<int64>; top : int) : array<int> {
    var order : array<int>
    let full = (1 << n) - 1
    var best : array<int64>
    var orphans, last, callers : array<int>
    best |> resize(full + 1)
    orphans |> resize(full + 1)
    last |> resize(full + 1)
    callers |> resize(n)
    for (set in range(1, full + 1)) {
        best[set] = NO_CUT
    }
    best[0] = 0l
    for (v in range(n)) {
        for (u in range(n)) {
            if (u != v && w[u * n + v] != 0l) {
                callers[v] |= 1 << u
            }
        }
    }
    let below_top = top >= 0 ? full & ~(1 << top) : full
    for (set in range(full + 1)) {
        if (best[set] < NO_CUT) {
            for (v in range(n)) {
                if ((set & (1 << v)) == 0 && (v != top || set == below_top)) {
                    var cost = best[set]
                    for (u in range(n)) {
                        if ((set & (1 << u)) != 0) {
                            cost = min(NO_CUT, cost + w[u * n + v])
                        }
                    }
                    // a node every caller of which is below it is left without a caller
                    let left = orphans[set] + (callers[v] != 0 && (callers[v] & ~set) == 0 ? 1 : 0)
                    let next = set | (1 << v)
                    if (cost < best[next] || (cost == best[next] && left < orphans[next])) {
                        best[next] = cost
                        orphans[next] = left
                        last[next] = v
                    }
                }
            }
        }
    }
    var set = full
    while (set != 0) {
        order |> push(last[set])
        set &= ~(1 << last[set])
    }
    reverse(order)
    return <- order
}

// `cut_order` by the greedy rule
def private greedy_order(n : int; w : array<int64>; top : int) : array<int> {
    var order : array<int>
    var placed : array<bool>
    placed |> resize(n)
    var low, high : array<int>
    if (top >= 0) {
        placed[top] = true
        high |> push(top)
    }
    for (_ in range(top >= 0 ? n - 1 : n)) {
        var sink, source, pick = -1
        var best = -NO_CUT
        for (v in range(n)) {
            if (!placed[v]) {
                var outgoing, incoming = 0l
                for (u in range(n)) {
                    if (!placed[u] && u != v) {
                        outgoing = min(NO_CUT, outgoing + w[v * n + u])
                        incoming = min(NO_CUT, incoming + w[u * n + v])
                    }
                }
                if (outgoing == 0l && sink < 0) {
                    sink = v
                } elif (incoming == 0l && source < 0) {
                    source = v
                } elif (pick < 0 || incoming - outgoing > best) {
                    pick = v
                    best = incoming - outgoing
                }
            }
        }
        // a node requiring nothing unplaced goes lowest, one nothing unplaced requires highest,
        // else the node most required over what it requires goes lowest
        if (sink >= 0) {
            placed[sink] = true
            low |> push(sink)
        } elif (source >= 0) {
            placed[source] = true
            high |> push(source)
        } else {
            placed[pick] = true
            low |> push(pick)
        }
    }
    order <- low
    reverse(high)
    order |> push_from(high)
    return <- order
}

// one strongly connected component with a cut: the edges never cut collapse into groups that stay
// one module, the groups take the order `cut_order` finds, and every cuttable edge going up it is cut
// the weight of each edge inside component `comp` by `<from>><to>` (-1 for one `layout.cut`
// forces), and in `fixed` each edge no cut may take
def private component_edges(plan : LayoutPlan; opts : CutOptions; comp : array<int>; var fixed : array<table<int>>; var weights : table<string; int64>) {
    fixed |> resize(length(plan.nodes))
    for (a in comp) {
        for (b in keys(plan.edges[a])) {
            if (has_value(comp, b)) {
                let key = "{a}>{b}"
                let weight = edge_weight(plan, opts, a, plan.symbols?[key] ?? array<EdgeSymbol>())
                let forced = has_value([for (sym in plan.symbols?[key] ?? array<EdgeSymbol>()); key_exists(opts.always_cut, sym.name)], true)
                let why = forced ? "" : uncuttable(plan, opts, a, b, weight)
                weights[key] = forced ? -1l : weight
                if (!empty(why)) {
                    fixed[a] |> insert(b)
                }
            }
        }
    }
}

// the report line of each symbol cut on the edge `a` -> `b` of weight `weight`
def private report_cut(var plan : LayoutPlan; opts : CutOptions; a, b : int; key : string; weight : int64) {
    plan.cut_report |> reserve(length(plan.cut_report) + length(plan.symbols?[key] ?? array<EdgeSymbol>()))
    for (sym in plan.symbols?[key] ?? array<EdgeSymbol>()) {
        plan.late[sym.name] = b
        let own = empty(opts.profile) ? int64(sym.calls) : (opts.profile?[sym.name]?[plan.nodes[a].stem] ?? 0l)
        let unit = empty(opts.profile) ? "call sites" : "calls profiled"
        let forced = weight < 0l ? ", layout.cut" : ""
        plan.cut_report |> push("cut {sym.name}: {plan.nodes[a].stem} -> {plan.nodes[b].stem}, {own} {unit} of the edge's {max(weight, 0l)}{forced}")
    }
}

// the entry module is highest in its component's order: every node with a path of edges never cut
// to `entry` would stay above it, so it is kept in the entry's module (an edge from the entry to it
// in `fixed` closes the cycle)
def private join_entry(comp : array<int>; entry : int; var fixed : array<table<int>>) {
    var inscope above : table<int>
    var inscope todo <- [entry]
    while (!empty(todo)) {
        let m = todo[length(todo) - 1]
        todo |> pop()
        for (a in comp) {
            if (key_exists(fixed[a], m) && !key_exists(above, a) && a != entry) {
                above |> insert(a)
                todo |> push(a)
            }
        }
    }
    for (a in keys(above)) {
        fixed[entry] |> insert(a)
    }
}

def private cut_component(var plan : LayoutPlan; opts : CutOptions; comp : array<int>) {
    var inscope fixed : array<table<int>>
    var inscope weights : table<string; int64>
    component_edges(plan, opts, comp, fixed, weights)
    let entry = has_value(comp, plan.entry_node) ? plan.entry_node : -1
    if (entry >= 0) {
        join_entry(comp, entry, fixed)
    }
    var inscope group_of : table<int; int>
    var inscope groups : array<array<int>>
    for (g in components_of(fixed)) {
        if (has_value(comp, g[0])) {
            for (m in g) {
                group_of[m] = length(groups)
            }
            groups |> push_clone(g)
        }
    }
    let n = length(groups)
    var inscope w : array<int64>
    w |> resize(n * n)
    for (key, weight in keys(weights), values(weights)) {
        var inscope parts <- split(key, ">")
        let ga = group_of[to_int(parts[0])]
        let gb = group_of[to_int(parts[1])]
        if (ga != gb) {
            let cost = key_exists(fixed[to_int(parts[0])], to_int(parts[1])) ? NO_CUT : max(weight, 0l)
            w[ga * n + gb] = min(NO_CUT, w[ga * n + gb] + cost)
        }
    }
    let order <- cut_order(n, w, entry >= 0 ? group_of[entry] : -1)
    var inscope place : array<int>
    place |> resize(n)
    for (at, g in count(), order) {
        place[g] = at
    }
    for (key, weight in keys(weights), values(weights)) {
        var inscope parts <- split(key, ">")
        let a = to_int(parts[0])
        let b = to_int(parts[1])
        let ga = group_of[a]
        let gb = group_of[b]
        if (ga != gb && !key_exists(fixed[a], b) && (weight < 0l || place[ga] < place[gb])) {
            plan.edges[a] |> erase(b)
            report_cut(plan, opts, a, b, key, weight)
        }
    }
    for (g in groups) {
        if (length(g) > 1 && has_value([for (m in g); plan.nodes[m].kind == NODE_UNIT], true)) {
            var inscope kept <- [for (m in g); plan.nodes[m].stem]
            sort(kept)
            plan.cut_report |> push("kept together: {join(kept, " ")}")
        }
    }
}

// why `layout.cut` may not force the edge `a` -> `b` of a cycle, carrying `syms`: "" when it may
def private refused_forced(plan : LayoutPlan; a, b : int; key : string; syms : array<EdgeSymbol>) : string {
    let edge = "layout.cut forces the edge {plan.nodes[a].stem} -> {plan.nodes[b].stem}"
    if (a == plan.entry_node) {
        return "{edge} out of the entry module, which every cycle's cut keeps"
    }
    if (key_exists(plan.type_edges, key)) {
        return "{edge}, which carries a type {base_name(plan.nodes[b].file)} defines"
    }
    for (sym in syms) {
        if (!empty(sym.why_not)) {
            return "{edge}, which carries `{sym.name}`, which no cut can late-bind: {sym.why_not}"
        }
    }
    return ""
}

// why the cut's options are refused, "" when they are not: a `layout.keep_together` group naming a
// file the program has not, a symbol it names that no file calls from another, a `layout.cut`
// symbol no cycle's edge carries or that `layout.keep_together` names too, and an edge `layout.cut`
// forces out of the entry module or that carries a type or a symbol no cut can late-bind
def private refused_options(plan : LayoutPlan; opts : CutOptions) : string {
    var stems : table<string>
    for (n in plan.unit_node) {
        stems |> insert(plan.nodes[n].stem)
    }
    for (group in opts.keep_units) {
        for (stem in group) {
            if (!key_exists(stems, stem)) {
                return "layout.keep_together names `{stem}`, which is no file of the program"
            }
        }
    }
    var called, cyclic : table<string>
    var inscope comp_of : table<int; int>
    for (ci, comp in count(), components_of(plan.edges)) {
        for (m in comp) {
            comp_of[m] = length(comp) > 1 ? ci : -1
        }
    }
    for (key, syms in keys(plan.symbols), values(plan.symbols)) {
        var inscope parts <- split(key, ">")
        let a = to_int(parts[0])
        let b = to_int(parts[1])
        let in_cycle = (comp_of?[a] ?? -1) >= 0 && (comp_of?[a] ?? -1) == (comp_of?[b] ?? -1)
        for (sym in syms) {
            called |> insert(sym.name)
            if (in_cycle) {
                cyclic |> insert(sym.name)
            }
        }
        if (in_cycle && has_value([for (sym in syms); key_exists(opts.always_cut, sym.name)], true)) {
            let why = refused_forced(plan, a, b, key, syms)
            if (!empty(why)) {
                return why
            }
        }
    }
    for (name in keys(opts.keep_symbols)) {
        if (!key_exists(called, name)) {
            return "layout.keep_together names `{name}`, which no file calls from another"
        }
        if (key_exists(opts.always_cut, name)) {
            return "layout.keep_together and layout.cut both name `{name}`"
        }
    }
    for (name in keys(opts.always_cut)) {
        if (!key_exists(cyclic, name)) {
            return "layout.cut names `{name}`, which no edge of a cycle carries"
        }
    }
    return ""
}

// the cycle cut over every strongly connected component of more than one node; refused when
// the options are (`refused_options`)
[arch(at="ARCHITECTURE_LAYOUT.md#cut")]
def private cut_cycles(var plan : LayoutPlan; opts : CutOptions) {
    plan.error = refused_options(plan, opts)
    if (!empty(plan.error)) {
        return
    }
    for (comp in components_of(plan.edges)) {
        if (length(comp) > 1) {
            cut_component(plan, opts, comp)
        }
    }
    sort(plan.cut_report)
}

// the slot of each late-bound function in the link module, `<name>_slot` past every name of the
// program
def private name_slots(var plan : LayoutPlan; tus : array<CirTu>) {
    var inscope taken : table<string>
    for (tu in tus) {
        for (d in tu.decls) {
            taken |> insert(d.name)
        }
    }
    var inscope names <- [for (name in keys(plan.late)); name]
    sort(names)
    for (name in names) {
        plan.slots[name] = free_name(taken, "{name}_slot")
    }
}

// the link module of a cut program, `<entry stem>_link` at the root: required by every module whose
// cut edge it carries and by every module defining a late-bound function; it requires the modules
// of the types their signatures spell, the lowest layer of the program
def private add_link_module(var plan : LayoutPlan; types : array<CirType>; tus : array<CirTu>; entry_unit : int) {
    let name = "{plan.nodes[plan.unit_node[entry_unit]].stem}_link"
    if (is_taken_module(name)) {
        plan.error = "the link module would be `{name}.das`, which a module daslang or c2das-re loads by that name takes; rename the entry file"
        return
    }
    for (mod in plan.modules) {
        if (mod.name == name) {
            plan.error = "the link module would be `{name}.das`, the module of {mod.name}'s file too; rename a file"
            return
        }
    }
    plan.link = length(plan.modules)
    var inscope required : table<int>
    for (tu in tus) {
        for (d in tu.decls) {
            if (d.k == "func" && d.body != null && key_exists(plan.late, d.name)) {
                var inscope spelled : table<int>
                spelled_types(types, d.t, spelled)
                for (t in keys(spelled)) {
                    let owner = plan.type_node?[t] ?? -1
                    if (owner >= 0) {
                        required |> insert(plan.node_module[owner])
                    }
                }
            }
        }
    }
    plan.modules |> emplace(LayoutModule(name = name, requires <- [for (r in keys(required)); r]))
    sort(plan.modules[plan.link].requires) $(a, b) => plan.modules[a].name < plan.modules[b].name
    for (from in range(length(plan.nodes))) {
        for (key, syms in keys(plan.symbols), values(plan.symbols)) {
            if (key |> starts_with("{from}>")) {
                for (sym in syms) {
                    let definer = plan.late?[sym.name] ?? -1
                    let to = to_int(slice(key, find(key, ">") + 1))
                    if (definer == to && !key_exists(plan.edges[from], to)) {
                        plan.modules[plan.node_module[from]].requires |> push(plan.link)
                    }
                }
            }
        }
    }
    for (definer in values(plan.late)) {
        plan.modules[plan.node_module[definer]].requires |> push(plan.link)
    }
    require_unreached(plan)
    for (mod in plan.modules) {
        var inscope unique : table<int>
        for (r in mod.requires) {
            unique |> insert(r)
        }
        mod.requires <- [for (r in keys(unique)); r]
        sort(mod.requires) $(a, b) => plan.modules[a].name < plan.modules[b].name
    }
}

// the modules `from` requires, directly or through others
def private reached(plan : LayoutPlan; from : int) : table<int> {
    var seen : table<int>
    var todo <- [from]
    while (!empty(todo)) {
        let m = todo[length(todo) - 1]
        todo |> pop()
        for (r in plan.modules[m].requires) {
            if (!key_exists(seen, r)) {
                seen |> insert(r)
                todo |> push(r)
            }
        }
    }
    return <- seen
}

// a cut leaves a module whose functions are called only late-bound reached by no require, so it
// would never load and never bind its slots: the entry module requires every module it does not
// reach. One that reaches the entry module itself is outside the entry's cycles (the entry is
// highest in their order), so `main` never calls it: it stays unrequired, compiled on its own
def private require_unreached(var plan : LayoutPlan) {
    let reach <- reached(plan, plan.entry)
    for (m in range(length(plan.modules))) {
        if (m != plan.entry && !key_exists(reach, m) && !key_exists(reached(plan, m), plan.entry)) {
            plan.modules[plan.entry].requires |> push(m)
        }
    }
}

//! The source layout of a program linked from `tus` (their C files `c_paths`, in link order):
//! `types` is the merged table and `facts` the link's, as `link_tus` hands them to its scoping block.
//! A singleton component is the module of its node, `<stem>`; a component of several nodes is
//! `<lexically first stem>_cluster` with a fragment per member, the component holding `main` named
//! by the entry unit's stem; a header's types are `<header stem>_h` (`lobject.h` -> `lobject_h`),
//! the types no single file defines `c_types`. Two modules of one name are refused.
[arch(at="ARCHITECTURE_LAYOUT.md#layout")]
def plan_layout(tus : array<CirTu>; types : array<CirType>; facts : LinkFacts; c_paths : array<string>; opts : CutOptions) : LayoutPlan {
    var plan = LayoutPlan()
    let full <- [for (p in c_paths); get_full_file_name(p)]
    plan.root = common_dir(full)
    var by_file : table<string; int>
    var entry_unit = 0
    for (ti, tu in count(), tus) {
        plan.unit_node |> push(length(plan.nodes))
        plan.nodes |> push(LayoutNode(kind = NODE_UNIT, file = full[ti], stem = ident_of(file_stem_of(tu.tu)), unit = ti))
        by_file[full[ti]] = ti
        for (d in tu.decls) {
            if (d.k == "func" && d.c_name == "main" && !d.is_static && d.body != null) {
                entry_unit = ti
            }
        }
    }
    plan.edges |> resize(length(plan.nodes))
    plan.entry_node = plan.unit_node[entry_unit]
    own_types(plan, tus, types, by_file)
    find_edges(plan, tus, types, facts)
    if (opts.cut_cycles) {
        cut_cycles(plan, opts)
        if (!empty(plan.error)) {
            return <- plan
        }
        name_slots(plan, tus)
    }
    plan.node_module |> resize(length(plan.nodes))
    name_modules(plan, tus, types, facts, entry_unit)
    if (!empty(plan.error)) {
        return <- plan
    }
    for (node in plan.nodes) {
        if (node.kind != NODE_TYPES) {
            node.dir = relative_dir(plan.root, node.file, plan.error)
        }
    }
    require_modules(plan)
    if (!empty(plan.late)) {
        add_link_module(plan, types, tus, entry_unit)
    }
    return <- plan
}

//! The c_runtime modules a converted module requires, and the crt module.
let TAKEN_MODULES <- ["crt", "c_runtime", "c_args", "c_bitfields", "c_bounds", "c_builtins", "c_exit", "c_function", "c_signal", "c_sort", "c_storage", "cstr_array", "c_union", "c_volatile", "enum_from_int", "printf", "scanf", "setjmp", "variadic"]

// whether a generated module named `name` would meet a module daslang or c2das-re loads by that name
// (daslib's, c_runtime's, crt), which a bare `require` reaches first
def private is_taken_module(name : string) : bool {
    if (has_value(TAKEN_MODULES, name)) {
        return true
    }
    let path = "{get_das_root()}/daslib/{name}.das"
    return fexist(path) || name == "math" || name == "strings" || name == "rtti" || name == "ast" || name == "fio" || name == "jobque" || name == "network" || name == "uriparser" || name == "debugapi"
}

//! The scope of each unit for `link_tus`: the module that holds it.
def unit_scopes(plan : LayoutPlan) : array<int> => <- empty(plan.error) ? [for (n in plan.unit_node); plan.node_module[n]] : array<int>()

// a file name up to its first dot
def private file_stem_of(name : string) : string {
    let dot = find(name, ".")
    return dot < 0 ? name : slice(name, 0, dot)
}

//! The partition as report lines: each module with its members (a cluster's marked), then for each
//! cluster the edges among its members, each with the names that make it, then the cycle cut's
//! lines: each late-bound function with its edge and weight, each group no cut may part.
def layout_report(plan : LayoutPlan) : array<string> {
    var lines : array<string>
    lines |> reserve(length(plan.modules) + length(plan.cut_report))
    var order <- [for (m in range(length(plan.modules))); m]
    sort(order) $(a, b) => plan.modules[a].name < plan.modules[b].name
    for (m in order) {
        assume mod = plan.modules[m]
        let members = join([for (n in mod.members); plan.nodes[n].stem], " ")
        lines |> push(mod.cluster ? "{mod.name}: cluster of {length(mod.members)}: {members}" : "{mod.name}")
    }
    for (m in order) {
        if (plan.modules[m].cluster) {
            for (from in plan.modules[m].members) {
                var inscope targets <- [for (to in keys(plan.edges[from])); to; where plan.node_module[to] == m]
                sort(targets)
                for (to in targets) {
                    let key = "{from}>{to}"
                    let why = join(plan.reasons?[key] ?? array<string>(), ", ")
                    lines |> push("{plan.modules[m].name}: {plan.nodes[from].stem} -> {plan.nodes[to].stem}: {why}")
                }
            }
        }
    }
    lines |> push_from(plan.cut_report)
    return <- lines
}
