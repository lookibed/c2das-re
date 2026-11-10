options gen2

module readability_count public

require strings
require math
require daslib/strings_boost
require daslib/ast
require daslib/ast_boost
require daslib/fio
require ../converter/pipeline.das
require readability_file

//! The readability counts of one emitted module, read off the daslang AST the compiler builds
//! with every `unsafe` scope kept and no optimization (metrics/ARCHITECTURE.md, the counting
//! definitions): `count_module` compiles the file and walks what its own text spells.

//! One counted site: the metric, the line, and for `literal_named` the name the literal could use.
struct Site {
    metric : string
    line : int
    suggested_name : string
}

//! What one module counts: `error` when it does not compile, else a count per metric and its sites.
struct ModuleCount {
    error : string
    counts : table<string; int>
    sites : array<Site>
}

// an integer literal of any width or signedness, read as an int64
def private int_literal(expr : ExpressionPtr; var value : int64&) : bool {
    if (expr is ExprConstInt) {
        value = int64((expr as ExprConstInt).value)
    } elif (expr is ExprConstUInt) {
        value = int64((expr as ExprConstUInt).value)
    } elif (expr is ExprConstInt64) {
        value = (expr as ExprConstInt64).value
    } elif (expr is ExprConstUInt64) {
        value = int64((expr as ExprConstUInt64).value)
    } elif (expr is ExprConstInt8) {
        value = int64((expr as ExprConstInt8).value)
    } elif (expr is ExprConstUInt8) {
        value = int64((expr as ExprConstUInt8).value)
    } elif (expr is ExprConstInt16) {
        value = int64((expr as ExprConstInt16).value)
    } elif (expr is ExprConstUInt16) {
        value = int64((expr as ExprConstUInt16).value)
    } else {
        return false
    }
    return true
}

//! The number `text` spells after any leading casts (`int8(`, `uint(int64(`): an optional
//! minus, then decimal digits or `0x` and hex digits; false when no digit follows.
def spelled_number(text : string; var value : int64&) : bool {
    var ok = false
    peek_data(text) $(bytes) {
        let n = length(bytes)
        var at = 0
        var open = find(text, "(")
        while (open > at && is_alpha(int(bytes[at]))) {
            at = open + 1
            open = find(text, "(", at)
        }
        let negative = at < n && int(bytes[at]) == '-'
        if (negative) {
            at++
        }
        let hex = at + 1 < n && int(bytes[at]) == '0' && (int(bytes[at + 1]) == 'x' || int(bytes[at + 1]) == 'X')
        if (hex) {
            at += 2
        }
        var v = 0ul
        while (at < n && (is_number(int(bytes[at])) || (hex && is_hex(int(bytes[at]))))) {
            let c = int(bytes[at])
            let digit = is_number(c) ? c - '0' : (c | 32) - 'a' + 10
            v = v * (hex ? 16ul : 10ul) + uint64(digit)
            ok = true
            at++
        }
        value = negative ? -int64(v) : int64(v)
    }
    return ok
}

//! True when the expression whose text starts at `column` of `line` sits directly inside an
//! `unsafe(...)`: the nearest unclosed parenthesis before it follows the word `unsafe`.
def inside_unsafe_call(line : string; column : int) : bool {
    var inside = false
    peek_data(line) $(bytes) {
        var depth = 0
        var at = min(column, length(bytes)) - 1
        while (at >= 0) {
            let c = int(bytes[at])
            if (c == ')') {
                depth++
            } elif (c == '(' && depth > 0) {
                depth--
            } elif (c == '(') {
                break
            }
            at--
        }
        inside = at >= 6 && slice(line, at - 6, at) == "unsafe" && (at == 6 || !is_alnum(int(bytes[at - 7])))
    }
    return inside
}

// the pointer arithmetic daslang infers `p + i`, `p - i`, `p - q`, `p++` and `p += i` into
def private is_pointer_step(expr : ExpressionPtr) : bool => expr is ExprCall && (expr as ExprCall).func != null && (expr as ExprCall).func.name |> starts_with("i_das_ptr_")

// a local variable read or written by name, through the value read daslang wraps it in
def private local_name(expr : ExpressionPtr) : string {
    let inner = expr is ExprRef2Value ? (expr as ExprRef2Value).subexpr : expr
    if (inner is ExprVar && (inner as ExprVar).varFlags.local) {
        return string((inner as ExprVar).name)
    }
    return ""
}

// the variable an assignment's target is rooted at, through fields, indexes and value reads
def private root_var(expr : ExpressionPtr) : ExprVar? {
    var e = expr
    while (true) {
        if (e is ExprRef2Value) {
            e = (e as ExprRef2Value).subexpr
        } elif (e is ExprField) {
            e = (e as ExprField).value
        } elif (e is ExprAt) {
            e = (e as ExprAt).subexpr
        } elif (e is ExprPtr2Ref) {
            e = (e as ExprPtr2Ref).subexpr
        } else {
            break
        }
    }
    return e is ExprVar ? e as ExprVar : null
}

def private root_name(expr : ExpressionPtr) : string {
    let v = root_var(expr)
    return v != null ? string(v.name) : ""
}

let private STEP_UP <- ["++", "+++"]
let private STEP_DOWN <- ["--", "---"]
let private COMPOUND <- ["+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "<<=", ">>=", "<<<=", ">>>=", "&&=", "||=", "^^="]

// +1 or -1 when `expr` steps the local `v` by a literal in that direction, else 0
def private step_direction(expr : ExpressionPtr; v : string) : int {
    if (expr is ExprOp1 && local_name((expr as ExprOp1).subexpr) == v) {
        let op = string((expr as ExprOp1).op)
        return STEP_UP |> has_value(op) ? 1 : STEP_DOWN |> has_value(op) ? -1 : 0
    }
    if (!(expr is ExprOp2) || root_name((expr as ExprOp2).left) != v) {
        return 0
    }
    var c = 0l
    if (!int_literal((expr as ExprOp2).right, c) || c <= 0l) {
        return 0
    }
    let op = string((expr as ExprOp2).op)
    return op == "+=" ? 1 : op == "-=" ? -1 : 0
}

// what a loop body writes (an assignment, a step, an address taken, a reference argument),
// its `continue`s and its exits (`break` or `return`), a nested loop's `continue` and `break` aside
class private BodyScan : AstVisitor {
    written : table<string>
    // the module-level globals among them
    written_globals : table<string>
    continues : int
    exits : int
    loop_depth : int
    def wrote(target : ExpressionPtr) {
        let v = root_var(target)
        if (v != null) {
            written |> insert(string(v.name))
            if (!v.varFlags.local && !v.varFlags.argument && !v.varFlags._block) {
                written_globals |> insert(string(v.name))
            }
        }
    }
    def override preVisitExprCopy(expr : ExprCopy?) {
        wrote(expr.left)
    }
    def override preVisitExprMove(expr : ExprMove?) {
        wrote(expr.left)
    }
    def override preVisitExprClone(expr : ExprClone?) {
        wrote(expr.left)
    }
    def override preVisitExprOp1(expr : ExprOp1?) {
        if (STEP_UP |> has_value(string(expr.op)) || STEP_DOWN |> has_value(string(expr.op))) {
            wrote(expr.subexpr)
        }
    }
    def override preVisitExprOp2(expr : ExprOp2?) {
        if (COMPOUND |> has_value(string(expr.op))) {
            wrote(expr.left)
        }
    }
    def override preVisitExprRef2Ptr(expr : ExprRef2Ptr?) {
        wrote(expr.subexpr)
    }
    def override preVisitExprCall(expr : ExprCall?) {
        if (expr.func == null) {
            return
        }
        for (i in range(min(length(expr.arguments), length(expr.func.arguments)))) {
            let declared = expr.func.arguments[i]._type
            if (declared != null && declared.isRef && !declared.isConst) {
                wrote(expr.arguments[i])
            }
        }
    }
    def override preVisitExprWhile(expr : ExprWhile?) {
        loop_depth++
    }
    def override visitExprWhile(var expr : ExprWhile?) : ExpressionPtr {
        loop_depth--
        return expr
    }
    def override preVisitExprFor(expr : ExprFor?) {
        loop_depth++
    }
    def override visitExprFor(var expr : ExprFor?) : ExpressionPtr {
        loop_depth--
        return expr
    }
    def override preVisitExprContinue(expr : ExprContinue?) {
        if (loop_depth == 0) {
            continues++
        }
    }
    def override preVisitExprBreak(expr : ExprBreak?) {
        if (loop_depth == 0) {
            exits++
        }
    }
    def override preVisitExprReturn(expr : ExprReturn?) {
        exits++
    }
}

class private ReadScan : AstVisitor {
    names : table<string>
    def override preVisitExprVar(expr : ExprVar?) {
        names |> insert(string(expr.name))
    }
}

def private reads_of(expr : ExpressionPtr) : table<string> {
    var scan = new ReadScan()
    make_visitor(*scan) $(adapter) {
        visit(expr, adapter)
    }
    var names <- scan.names
    unsafe {
        delete scan
    }
    return <- names
}

//! True when the `while` at `index` of `parent`'s statements (its `finally` statements under
//! `in_final`) is a raw loop a `range` loop could spell (metrics/ARCHITECTURE.md, section 3).
def is_while_rangeable(parent : ExprBlock?; index : int; in_final : bool) : bool {
    let wh = (in_final ? parent.finalList[index] : parent.list[index]) as ExprWhile
    if (!(wh.cond is ExprOp2) || !(wh.body is ExprBlock)) {
        return false
    }
    let cond = wh.cond as ExprOp2
    let op = string(cond.op)
    let want = op == "<" || op == "<=" ? 1 : op == ">" || op == ">=" ? -1 : 0
    let v = local_name(cond.left)
    if (want == 0 || empty(v) || cond.left._type == null || !cond.left._type.isInteger) {
        return false
    }
    let bound_reads <- reads_of(cond.right)
    let body = wh.body as ExprBlock
    let n = length(body.list)
    if (n == 0 || key_exists(bound_reads, v)) {
        return false
    }
    let last = body.list[n - 1]
    var scan = new BodyScan()
    var by_finally = false
    make_visitor(*scan) $(adapter) {
        for (i in range(n - 1)) {
            visit(body.list[i], adapter)
        }
        if (last is ExprBlock) {
            let inner = last as ExprBlock
            if (length(inner.finalList) == 1 && step_direction(inner.finalList[0], v) == want) {
                by_finally = true
                for (stmt in inner.list) {
                    visit(stmt, adapter)
                }
            }
        }
    }
    let stepped = by_finally || step_direction(last, v) == want
    var clean = stepped && (by_finally || scan.continues == 0) && !key_exists(scan.written, v)
    for (name in keys(bound_reads)) {
        clean = clean && !key_exists(scan.written, name)
    }
    let exits = scan.exits
    unsafe {
        delete scan
    }
    if (clean && exits > 0) {
        let count = in_final ? length(parent.finalList) : length(parent.list)
        for (i in range(index + 1, count)) {
            clean = clean && !key_exists(reads_of(in_final ? parent.finalList[i] : parent.list[i]), v)
        }
    }
    return clean
}

// the generics of the module that have an instance
class private InstanceScan : AstVisitor {
    generics : table<uint64>
    def override canVisitFunction(fun : Function?) : bool {
        if (fun.fromGeneric != null) {
            generics |> insert(intptr(fun.fromGeneric))
        }
        return false
    }
}

//! the emitter's per-module `[init]` that sets the dialect, the same in every module that has it
let DIALECT_INIT = "c2das_dialect"

// the word that starts the text of each metric a keyword spells: `enum_from_int(type<E>, i)` and
// `cstr("...")` expand to a reinterpret located at the call, which the text does not spell
let private METRIC_KEYWORDS <- {"reinterpret" => "reinterpret", "unsafe_block" => "unsafe", "goto" => "goto", "label" => "label"}

class private Counter : AstVisitor {
    // the files whose text is counted, each with its lines, which tell a literal from a folded
    // constant: the module's own, and the fragments a cluster module includes
    files : table<string; array<string>>
    counts : table<string; int>
    sites : array<Site>
    // the expressions met already: the visitor reaches a constant twice
    seen : table<uint64>
    // the pointer steps counted, each once, an index's step among them
    steps : table<uint64>
    checked_for_unsafe : table<uint64>
    name_of_value : table<int64; string>
    literals : array<tuple<line : int; value : int64>>
    in_enum : bool
    // the globals some function of the module writes
    written_globals : table<string>
    // generics with an instance: the instance is walked, the generic as written is not
    instanced : table<uint64>
    // the instance walked for each generic
    first_instance : table<uint64; uint64>
    skip_body : bool
    def counted(at : LineInfo) : bool => !skip_body && at.fileInfo != null && key_exists(files, string(at.fileInfo.name))
    // the line of the counted file `at` names
    def line_at(at : LineInfo) : string {
        var text = ""
        files |> get(string(at.fileInfo.name)) $(lines) {
            text = lines[int(at.line) - 1]
        }
        return text
    }
    // whether the text at `at` spells the keyword of `metric`, true for a metric without one: a call
    // macro's expansion leaves no mark on its nodes and sits at the call, whose text is the macro's
    def spells_keyword(metric : string; at : LineInfo) : bool {
        let keyword = METRIC_KEYWORDS?[metric] ?? ""
        return empty(keyword) || slice(line_at(at), int(at.column)) |> starts_with(keyword)
    }
    def count(metric : string; at : LineInfo) {
        if (counted(at) && spells_keyword(metric, at)) {
            counts[metric]++
            sites |> push(Site(metric = metric, line = int(at.line)))
        }
    }
    def first_time(expr : ExpressionPtr) : bool {
        let id = intptr(expr)
        if (key_exists(seen, id)) {
            return false
        }
        seen |> insert(id)
        return true
    }
    // the compiler folds a cast of a constant into a literal, `int(E.X)` and `int8(7)` alike,
    // and `5 + 7` into 12, so a literal counts only when its text spells its value
    def spells_value(expr : ExpressionPtr; value : int64) : bool {
        let text = slice(line_at(expr.at), int(expr.at.column))
        var spelled = 0l
        return spelled_number(text, spelled) && spelled == value
    }
    def name_value(name : string; value : int64) {
        if (!key_exists(name_of_value, value) || name < name_of_value[value]) {
            name_of_value[value] = name
        }
    }
    def override canVisitFunction(fun : Function?) : bool {
        if (fun.flags.generated || fun.name == DIALECT_INIT || fun.at.fileInfo == null || !key_exists(files, string(fun.at.fileInfo.name))) {
            return false
        }
        if (fun.fromGeneric == null) {
            return true
        }
        let generic = intptr(fun.fromGeneric)
        if (!key_exists(first_instance, generic)) {
            first_instance[generic] = intptr(fun)
        }
        return first_instance[generic] == intptr(fun)
    }
    // a global with a literal initializer that no function writes names its value: a `let`, or
    // the `var` the emitter writes for a C `static const`
    def override canVisitGlobalVariable(arg : Variable?) : bool {
        var value = 0l
        if (arg.init != null && int_literal(arg.init, value)) {
            if (!key_exists(written_globals, string(arg.name))) {
                name_value(string(arg.name), value)
            }
            return false
        }
        return true
    }
    def override preVisitEnumeration(enu : EnumerationPtr) {
        in_enum = true
    }
    def override visitEnumeration(var enu : EnumerationPtr) : EnumerationPtr {
        in_enum = false
        return enu
    }
    def override preVisitEnumerationValue(enu : EnumerationPtr; name : das_string; value : ExpressionPtr; last : bool) {
        var v = 0l
        if (value != null && int_literal(value, v)) {
            name_value("{enu.name}.{name}", v)
        }
    }
    def override preVisitFunction(fun : FunctionPtr) {
        skip_body = key_exists(instanced, intptr(fun))
    }
    def override visitFunction(var fun : FunctionPtr) : FunctionPtr {
        if (find_annotation(fun, "c_function") != null) {
            count("c_function", fun.at)
        }
        skip_body = false
        return fun
    }
    def override preVisitExpression(expr : ExpressionPtr) {
        if (!first_time(expr) || !counted(expr.at)) {
            return
        }
        if (expr.genFlags.userSaidItsSafe) {
            count("unsafe_expr", expr.at)
        }
        var value = 0l
        if (!in_enum && int_literal(expr, value) && value != 0l && value != 1l && value != -1l && spells_value(expr, value)) {
            literals |> push((line = int(expr.at.line), value = value))
        }
    }
    def override preVisitExprUnsafe(expr : ExprUnsafe?) {
        count("unsafe_block", expr.at)
    }
    def override preVisitExprPtr2Ref(expr : ExprPtr2Ref?) {
        if (is_pointer_step(expr.subexpr)) {
            steps |> insert(intptr(expr.subexpr))
            count("pointer_index", expr.at)
        }
    }
    def override preVisitExprAt(expr : ExprAt?) {
        if (expr.subexpr._type != null && expr.subexpr._type.isPointer) {
            count("pointer_index", expr.at)
        }
    }
    // inference turns `unsafe(p + i)` into a pointer-step call that drops the parser's flag,
    // so the step's own text tells whether an `unsafe(` encloses it
    def override preVisitExprCall(expr : ExprCall?) {
        let id = intptr(expr)
        if (!is_pointer_step(expr) || !counted(expr.at)) {
            return
        }
        if (!key_exists(checked_for_unsafe, id)) {
            checked_for_unsafe |> insert(id)
            if (!expr.genFlags.userSaidItsSafe && inside_unsafe_call(line_at(expr.at), int(expr.at.column))) {
                count("unsafe_expr", expr.at)
            }
        }
        if (!key_exists(steps, id)) {
            steps |> insert(id)
            count("pointer_arith", expr.at)
        }
    }
    def override preVisitExprCast(expr : ExprCast?) {
        if (expr.castFlags.reinterpretCast) {
            count("reinterpret", expr.at)
        }
    }
    def override preVisitExprGoto(expr : ExprGoto?) {
        count("goto", expr.at)
    }
    def override preVisitExprLabel(expr : ExprLabel?) {
        count("label", expr.at)
    }
    def override preVisitExprBlock(blk : ExprBlock?) {
        for (i in range(length(blk.list))) {
            if (blk.list[i] is ExprWhile && is_while_rangeable(blk, i, false)) {
                count("while_rangeable", blk.list[i].at)
            }
        }
        for (i in range(length(blk.finalList))) {
            if (blk.finalList[i] is ExprWhile && is_while_rangeable(blk, i, true)) {
                count("while_rangeable", blk.finalList[i].at)
            }
        }
    }
    // the literals that equal a named value, counted once every name is known
    def resolve_literals {
        for (lit in literals) {
            if (key_exists(name_of_value, lit.value)) {
                counts["literal_named"]++
                sites |> push(Site(metric = "literal_named", line = lit.line, suggested_name = name_of_value[lit.value]))
            }
        }
    }
}

//! The counts of the module at `das_path`.
def count_module(das_path : string) : ModuleCount => <- count_module(das_path, array<string>())

//! The counts of a program's modules `das_paths`, each counted with the fragments its `include`
//! lines name, summed; at the first module that fails, its error with `failed` its path.
def count_program(das_paths : array<string>; var failed : string&) : ModuleCount {
    var total : ModuleCount
    total.counts <- {for (m in METRICS); m => 0}
    for (path in das_paths) {
        var inscope included : array<string>
        for (ln in split(fread(path), "\n")) {
            // a layout file holds the layout check alone, which the criteria count as a test's
            if (ln |> starts_with("include ") && !is_layout_file(ln)) {
                included |> push(path_join(dir_name(path), slice(ln, length("include "))))
            }
        }
        let mc <- count_module(path, included)
        if (!empty(mc.error)) {
            failed = path
            return ModuleCount(error = mc.error)
        }
        for (m in METRICS) {
            total.counts[m] += mc.counts?[m] ?? 0
        }
    }
    return <- total
}

//! The counts of the module at `das_path` and of the fragments it includes, `included` each by the
//! name daslang gives it: the module's folder joined with the `include` line's path.
def count_module(das_path : string; included : array<string>) : ModuleCount {
    var res : ModuleCount
    res.counts <- {for (m in METRICS); m => 0}
    compile_as_written(das_path) $(ok, program, output) {
        if (!ok) {
            res.error = output
            return
        }
        var instances = new InstanceScan()
        make_visitor(*instances) $(adapter) {
            visit(program, adapter)
        }
        var writes = new BodyScan()
        make_visitor(*writes) $(adapter) {
            visit(program, adapter)
        }
        var counter = new Counter()
        counter.files[das_path] <- split(fread(das_path), "\n")
        for (f in included) {
            counter.files[f] <- split(fread(f), "\n")
        }
        counter.instanced <- instances.generics
        counter.written_globals <- writes.written_globals
        counter.counts <- res.counts
        make_visitor(*counter) $(adapter) {
            visit_with_generics(program, adapter)
        }
        counter->resolve_literals()
        res.counts <- counter.counts
        res.sites <- counter.sites
        unsafe {
            delete counter
            delete instances
            delete writes
        }
    }
    return <- res
}

//! A module's counts as the worker file spells them: `ok` or `error <first line>`, a
//! `<metric> <count>` line per metric, then a `site <metric> <line> <name>` line per site.
def count_text(mc : ModuleCount) : string {
    var lines <- [empty(mc.error) ? "ok" : "error {replace(mc.error, "\n", " ")}"]
    lines |> reserve(1 + length(METRICS) + length(mc.sites))
    for (m in METRICS) {
        lines |> push("{m} {mc.counts?[m] ?? 0}")
    }
    for (s in mc.sites) {
        lines |> push("site {s.metric} {s.line} {s.suggested_name}")
    }
    return join(lines, "\n") + "\n"
}

//! The counts `count_text` wrote; a text that does not open with `ok` or `error` is an error.
def read_count_text(text : string) : ModuleCount {
    var mc : ModuleCount
    var lines <- split(text, "\n")
    if (empty(lines) || (lines[0] != "ok" && !(lines[0] |> starts_with("error ")))) {
        mc.error = "no counts"
        return <- mc
    }
    if (lines[0] != "ok") {
        mc.error = slice(lines[0], length("error "))
    }
    for (line in lines) {
        var inscope fields <- split(line, " ")
        if (length(fields) == 2 && METRICS |> has_value(fields[0])) {
            mc.counts[fields[0]] = to_int(fields[1])
        } elif (length(fields) >= 3 && fields[0] == "site") {
            let name_at = length(fields[0]) + length(fields[1]) + length(fields[2]) + 3
            mc.sites |> push(Site(metric = fields[1], line = to_int(fields[2]), suggested_name = slice(line, name_at)))
        }
    }
    return <- mc
}
