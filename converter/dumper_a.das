options gen2

module dumper_a public

require strings
require math
require daslib/strings_boost
require daslib/fio
require daslib/json_boost
require crt
require cir

//! Dumper A: `clang -ast-dump=json` normalized into C-IR. Fails closed: the first construct it
//! cannot represent exactly stops the dump with a location in `error`.

struct Dumper {
    tu : CirTu
    error : string
    cur_file : string
    cur_line : int
    type_index : table<string; int>
    tu_prefix : string
    c_path : string
    linkage_names : table<string; string>
    current_fn : string
    local_statics : table<string; string>
}

def private fail(var d : Dumper; what : string; at : CirLoc) {
    if (empty(d.error)) {
        d.error = "{at.file}:{at.line}:{at.col}: {what}"
    }
}

def private node_kind(js : JsonValue?) : string {
    return js?["kind"] ?? ""
}

def private is_present(v : JsonValue?) : bool {
    return v != null && !(v is _null)
}

def private child_count(js : JsonValue?) : int {
    let inner = js?["inner"]
    return inner != null && inner is _array ? length(inner as _array) : 0
}

def private has_loc(js : JsonValue?) : bool {
    return is_present(js?["loc"])
}

// clang omits `file` and `line` from a location that repeats the previous node's: the dumper
// carries them forward in tree order, which is the order clang assigned them in
def private loc_of(var d : Dumper; js : JsonValue?) : CirLoc {
    let at = has_loc(js) ? js?["loc"] : js?["range"]?["begin"]
    let file = at?["file"]
    if (is_present(file)) {
        d.cur_file = file ?? ""
    }
    let line = at?["line"]
    if (is_present(line)) {
        d.cur_line = int(line ?? 0l)
    }
    return CirLoc(file = d.cur_file, line = d.cur_line, col = int(at?["col"] ?? 0l))
}

def private intern(var d : Dumper; key : string; var t : CirType) : int {
    let known = d.type_index?[key] ?? -1
    if (known >= 0) {
        return known
    }
    let idx = length(d.tu.types)
    d.tu.types |> emplace(t)
    d.type_index[key] = idx
    return idx
}

def private int_type(var d : Dumper; w : int; is_signed : bool; spell : string) : int {
    var t = CirType(k = "int", w = w, is_signed = is_signed, spell = spell)
    return intern(d, "int:{w}:{is_signed}:{spell}", t)
}

def private split_params(text : string) : array<string> {
    var out : array<string>
    peek_data(text) $(view) {
        var depth = 0
        var start = 0
        var idx = 0
        for (ch in view) {
            if (ch == '(') {
                depth++
            } elif (ch == ')') {
                depth--
            } elif (ch == ',' && depth == 0) {
                out |> push(strip(slice(view, start, idx)))
                start = idx + 1
            }
            idx++
        }
        let last = strip(slice(view, start, length(view)))
        if (!empty(last)) {
            out |> push(last)
        }
    }
    return <- out
}

// the C99 scalar spellings; -2 when `qt` is not one of them
def private scalar_from_qual(var d : Dumper; qt : string) : int {
    if (qt == "void") {
        var t = CirType(k = "void")
        return intern(d, "void", t)
    }
    if (qt == "int") {
        return int_type(d, d.tu.target.int_w, true, qt)
    }
    if (qt == "unsigned int" || qt == "unsigned") {
        return int_type(d, d.tu.target.int_w, false, "unsigned int")
    }
    if (qt == "char") {
        return int_type(d, 8, d.tu.target.char_signed, qt)
    }
    if (qt == "signed char") {
        return int_type(d, 8, true, qt)
    }
    if (qt == "unsigned char") {
        return int_type(d, 8, false, qt)
    }
    if (qt == "short") {
        return int_type(d, 16, true, qt)
    }
    if (qt == "unsigned short") {
        return int_type(d, 16, false, qt)
    }
    if (qt == "long") {
        return int_type(d, d.tu.target.long_w, true, qt)
    }
    if (qt == "unsigned long") {
        return int_type(d, d.tu.target.long_w, false, qt)
    }
    if (qt == "long long") {
        return int_type(d, d.tu.target.llong_w, true, qt)
    }
    if (qt == "unsigned long long") {
        return int_type(d, d.tu.target.llong_w, false, qt)
    }
    if (qt == "_Bool") {
        return int_type(d, 8, false, qt)
    }
    if (qt == "float") {
        var t = CirType(k = "float", w = 32, spell = qt)
        return intern(d, "float:32", t)
    }
    if (qt == "double" || qt == "long double") {
        var t = CirType(k = "float", w = 64, spell = qt)
        return intern(d, "float:64:{qt}", t)
    }
    return -2
}

//! The type a clang `qualType` spelling names, interned; -1 with `error` set for a spelling
//! the dialect does not cover yet.
// clang appends function attributes to a type spelling; they carry no type
def private without_attributes(qual : string) : string {
    let parts <- split(qual, " __attribute__((")
    if (length(parts) == 1) {
        return qual
    }
    return join([for (idx, part in range(length(parts)), parts); idx == 0 ? part : (find(part, "))") < 0 ? "" : slice(part, find(part, "))") + 2))], "")
}

// `R (*)(params)`: the pointer-to-function spelling, with the parameter list in the last
// parentheses and the result before the ` (*)`
def private function_pointer(var d : Dumper; qt : string; at : CirLoc) : int {
    let star = find(qt, " (*)(")
    if (star < 0 || !(qt |> ends_with(")"))) {
        return -2
    }
    let fn = type_from_qual(d, slice(qt, 0, star) + " (" + slice(qt, star + 5), at)
    if (fn < 0) {
        return -1
    }
    var t = CirType(k = "ptr", to = fn)
    return intern(d, "ptr:{fn}", t)
}

def type_from_qual(var d : Dumper; qual : string; at : CirLoc) : int {
    let qt = unqualified(without_attributes(qual))
    let scalar = scalar_from_qual(d, qt)
    if (scalar != -2) {
        return scalar
    }
    let fn_ptr = function_pointer(d, qt, at)
    if (fn_ptr != -2) {
        return fn_ptr
    }
    if (qt |> ends_with("*")) {
        let to = type_from_qual(d, slice(qt, 0, length(qt) - 1), at)
        if (to < 0) {
            return -1
        }
        var t = CirType(k = "ptr", to = to)
        return intern(d, "ptr:{to}", t)
    }
    if (qt |> ends_with("]")) {
        let open = rfind(qt, "[")
        if (open > 0) {
            let elem = type_from_qual(d, slice(qt, 0, open), at)
            if (elem < 0) {
                return -1
            }
            let dim = strip(slice(qt, open + 1, length(qt) - 1))
            let count = empty(dim) ? -1 : to_int(dim)
            var t = CirType(k = "array", elem = elem, count = count)
            return intern(d, "array:{elem}:{count}", t)
        }
    }
    let paren = find(qt, " (")
    if (paren > 0 && qt |> ends_with(")")) {
        let ret = type_from_qual(d, slice(qt, 0, paren), at)
        if (ret < 0) {
            return -1
        }
        let inside = slice(qt, paren + 2, length(qt) - 1)
        var params : array<int>
        var variadic = false
        if (inside != "void" && !empty(inside)) {
            let pieces <- split_params(inside)
            params |> reserve(length(pieces))
            for (p in pieces) {
                if (p == "...") {
                    variadic = true
                    continue
                }
                let pt = type_from_qual(d, p, at)
                if (pt < 0) {
                    return -1
                }
                params |> push(pt)
            }
        }
        let key = "func:{ret}:" + join([for (p in params); "{p}"], ",") + ":{variadic}"
        var t = CirType(k = "func", ret = ret, variadic = variadic)
        t.params <- params
        return intern(d, key, t)
    }
    fail(d, "unsupported type spelling `{qt}`", at)
    return -1
}

// clang spells a typedef by its name and adds the resolved spelling beside it
def private qual_of(js : JsonValue?) : string {
    let desugared = js?["desugaredQualType"]
    return is_present(desugared) ? (desugared ?? "") : (js?["qualType"] ?? "")
}

def private node_type(var d : Dumper; js : JsonValue?; at : CirLoc) : int {
    return type_from_qual(d, qual_of(js?["type"]), at)
}

// C qualifiers carry no meaning for the das type (docs/c-feature-matrix.md section 1)
def private unqualified(qual : string) : string {
    let spaced = qual |> replace("*const", "* const") |> replace("*volatile", "* volatile") |> replace("*restrict", "* restrict")
    return join([for (tok in split(spaced, " ")); tok; where !empty(tok) && tok != "const" && tok != "volatile" && tok != "restrict"], " ")
}

let UNARY_OPS <- {"-" => "neg", "+" => "plus", "!" => "not", "~" => "bnot", "&" => "addr", "*" => "deref"}

let BINARY_OPS <- {"+" => "add", "-" => "sub", "*" => "mul", "/" => "div", "%" => "rem", "<<" => "shl", ">>" => "shr", "<" => "lt", ">" => "gt", "<=" => "le", ">=" => "ge", "==" => "eq", "!=" => "ne", "&" => "band", "|" => "bor", "^" => "bxor", "&&" => "land", "||" => "lor"}

let COMPOUND_OPS <- {"+=" => "add", "-=" => "sub", "*=" => "mul", "/=" => "div", "%=" => "rem", "<<=" => "shl", ">>=" => "shr", "&=" => "band", "|=" => "bor", "^=" => "bxor"}

def private hex_digit(b : int) : int {
    if (is_number(b)) {
        return b - '0'
    }
    if (b >= 'a' && b <= 'f') {
        return b - 'a' + 10
    }
    if (b >= 'A' && b <= 'F') {
        return b - 'A' + 10
    }
    return -1
}

// one escape of a C string literal, starting at `idx` just past the backslash; returns the
// index past the escape, or -1 for a malformed one
def private decode_escape(view : array<uint8>#; start : int; var out : array<uint8>) : int {
    let n = length(view)
    if (start >= n) {
        return -1
    }
    var idx = start
    let e = int(view[idx])
    idx++
    let simple <- {'n' => 10, 't' => 9, 'r' => 13, 'a' => 7, 'b' => 8, 'f' => 12, 'v' => 11, 'e' => 27}
    let code = simple?[e] ?? -1
    if (code >= 0) {
        out |> push(uint8(code))
        return idx
    }
    if (e == 'x') {
        var v = 0
        var digits = 0
        while (idx < n && hex_digit(int(view[idx])) >= 0) {
            v = v * 16 + hex_digit(int(view[idx]))
            idx++
            digits++
        }
        if (digits == 0) {
            return -1
        }
        out |> push(uint8(v & 255))
        return idx
    }
    if (e >= '0' && e <= '7') {
        var v = e - '0'
        var digits = 1
        while (idx < n && digits < 3 && int(view[idx]) >= '0' && int(view[idx]) <= '7') {
            v = v * 8 + int(view[idx]) - '0'
            idx++
            digits++
        }
        out |> push(uint8(v & 255))
        return idx
    }
    out |> push(uint8(e))
    return idx
}

// the bytes of a C string literal as clang spells it in the dump: quoted, escapes intact,
// adjacent pieces concatenated; the terminating NUL is appended here
def private literal_bytes(spelled : string; var out : array<uint8>) : bool {
    var ok = true
    peek_data(spelled) $(view) {
        var in_quotes = false
        var idx = 0
        let n = length(view)
        while (idx < n && ok) {
            let b = int(view[idx])
            idx++
            if (!in_quotes) {
                in_quotes = b == '"'
            } elif (b == '"') {
                in_quotes = false
            } elif (b != '\\') {
                out |> push(uint8(b))
            } else {
                idx = decode_escape(view, idx, out)
                ok = idx >= 0
            }
        }
    }
    out |> push(uint8(0))
    return ok
}

// the C-IR spelling of a floating literal: clang's decimal text through the CRT and back as
// a hex-float, bit-exact and diff-stable
def private hex_float(decimal : string) : string {
    let text = unsafe(reinterpret<uint8?>(decimal))
    let v = unsafe(crt::strtod(text, null))
    var buf : uint8[64]
    var out = unsafe(addr(buf[0]))
    let spec = unsafe(reinterpret<uint8?>("%a"))
    let n = unsafe(crt::snprintf_double(out, uint64(typeinfo dim(buf)), spec, v))
    let rendered = unsafe(reinterpret<string>(out))
    return slice(rendered, 0, n)
}

def private size_of_type(d : Dumper; t : int) : int64 {
    let k = d.tu.types[t].k
    if (k == "int" || k == "float") {
        return int64(d.tu.types[t].w / 8)
    }
    if (k == "ptr" || k == "func") {
        return int64(d.tu.target.ptr_w / 8)
    }
    if (k == "array") {
        let n = d.tu.types[t].count
        return n < 0 ? -1l : int64(n) * size_of_type(d, d.tu.types[t].elem)
    }
    if (k == "struct" || k == "union") {
        return int64(d.tu.types[t].size)
    }
    return -1l
}

def private linkage_name(d : Dumper; c_name : string) : string {
    let hoisted = d.local_statics?[c_name] ?? ""
    if (!empty(hoisted)) {
        return hoisted
    }
    return d.linkage_names?[c_name] ?? c_name
}

def private dump_args(var d : Dumper; kids : JsonValue?; from : int; count : int; var x : CirExpr?) : bool {
    x.args |> reserve(count - from)
    for (idx in range(from, count)) {
        var arg = dump_expr(d, (kids as _array)[idx])
        if (arg == null) {
            return false
        }
        x.args |> push(arg)
    }
    return true
}

def private child_expr(var d : Dumper; kids : JsonValue?; idx : int) : CirExpr? {
    return dump_expr(d, (kids as _array)[idx])
}

def private dump_cast(var d : Dumper; js : JsonValue?; t : int; at : CirLoc) : CirExpr? {
    let ck = js?["castKind"] ?? ""
    if (!key_exists(CAST_KINDS, ck)) {
        fail(d, "unknown castKind `{ck}`", at)
        return null
    }
    if (child_count(js) == 0) {
        fail(d, "cast without operand", at)
        return null
    }
    var inner = child_expr(d, js?["inner"], 0)
    if (inner == null) {
        return null
    }
    return new CirExpr(e = "cast", t = t, cast_kind = ck, explicit_cast = node_kind(js) == "CStyleCastExpr", a = inner)
}

def private dump_unary(var d : Dumper; js : JsonValue?; t : int; at : CirLoc) : CirExpr? {
    let opcode = js?["opcode"] ?? ""
    var op = ""
    if (opcode == "++" || opcode == "--") {
        let post = js?["isPostfix"] ?? false
        op = opcode == "++" ? (post ? "postinc" : "preinc") : (post ? "postdec" : "predec")
    } else {
        op = UNARY_OPS?[opcode] ?? ""
    }
    if (empty(op) || child_count(js) == 0) {
        fail(d, "unsupported unary operator `{opcode}`", at)
        return null
    }
    var a = child_expr(d, js?["inner"], 0)
    if (a == null) {
        return null
    }
    return new CirExpr(e = "un", t = t, op = op, a = a)
}

def private dump_binary(var d : Dumper; js : JsonValue?; t : int; at : CirLoc) : CirExpr? {
    let opcode = js?["opcode"] ?? ""
    if (child_count(js) < 2) {
        fail(d, "binary operator without two operands", at)
        return null
    }
    let kids = js?["inner"]
    var a = child_expr(d, kids, 0)
    if (a == null) {
        return null
    }
    var b = child_expr(d, kids, 1)
    if (b == null) {
        delete_expr(a)
        return null
    }
    if (opcode == "=") {
        return new CirExpr(e = "assign", t = t, op = "", a = a, b = b)
    }
    if (opcode == ",") {
        return new CirExpr(e = "comma", t = t, a = a, b = b)
    }
    let compound = COMPOUND_OPS?[opcode] ?? ""
    if (!empty(compound)) {
        return new CirExpr(e = "assign", t = t, op = compound, a = a, b = b)
    }
    let op = BINARY_OPS?[opcode] ?? ""
    if (empty(op)) {
        fail(d, "unsupported binary operator `{opcode}`", at)
        delete_expr(a)
        delete_expr(b)
        return null
    }
    return new CirExpr(e = "bin", t = t, op = op, a = a, b = b)
}

def private dump_conditional(var d : Dumper; js : JsonValue?; t : int; at : CirLoc) : CirExpr? {
    if (child_count(js) < 3) {
        fail(d, "conditional without three operands", at)
        return null
    }
    let kids = js?["inner"]
    var x = new CirExpr(e = "cond", t = t)
    x.c = child_expr(d, kids, 0)
    if (x.c != null) {
        x.a = child_expr(d, kids, 1)
    }
    if (x.a != null) {
        x.b = child_expr(d, kids, 2)
    }
    if (x.b == null) {
        delete_expr(x)
        return null
    }
    return x
}

def private dump_call(var d : Dumper; js : JsonValue?; t : int; at : CirLoc) : CirExpr? {
    let nkids = child_count(js)
    if (nkids == 0) {
        fail(d, "call without a callee", at)
        return null
    }
    let kids = js?["inner"]
    var x = new CirExpr(e = "call", t = t)
    x.fn = child_expr(d, kids, 0)
    if (x.fn == null || !dump_args(d, kids, 1, nkids, x)) {
        delete_expr(x)
        return null
    }
    return x
}

def private dump_subscript(var d : Dumper; js : JsonValue?; t : int; at : CirLoc) : CirExpr? {
    if (child_count(js) < 2) {
        fail(d, "subscript without two operands", at)
        return null
    }
    let kids = js?["inner"]
    var x = new CirExpr(e = "index", t = t)
    x.base = child_expr(d, kids, 0)
    if (x.base != null) {
        x.i = child_expr(d, kids, 1)
    }
    if (x.i == null) {
        delete_expr(x)
        return null
    }
    return x
}

def private dump_sizeof(var d : Dumper; js : JsonValue?; t : int; at : CirLoc) : CirExpr? {
    let trait = js?["name"] ?? ""
    if (trait != "sizeof") {
        fail(d, "`{trait}` is not dumped yet", at)
        return null
    }
    var of_t = -1
    let arg_type = js?["argType"]
    if (is_present(arg_type)) {
        of_t = type_from_qual(d, qual_of(arg_type), at)
    } elif (child_count(js) > 0) {
        var operand = child_expr(d, js?["inner"], 0)
        if (operand == null) {
            return null
        }
        of_t = operand.t
        delete_expr(operand)
    }
    if (of_t < 0) {
        return null
    }
    let size = size_of_type(d, of_t)
    if (size < 0l) {
        fail(d, "sizeof of a type without a size", at)
        return null
    }
    return new CirExpr(e = "sizeof_v", t = t, sizeof_v = uint64(size), of_t = of_t)
}

def private dump_literal(var d : Dumper; js : JsonValue?; kind : string; t : int; at : CirLoc) : CirExpr? {
    if (kind == "IntegerLiteral") {
        return new CirExpr(e = "int_lit", t = t, v = js?["value"] ?? "0")
    }
    if (kind == "CharacterLiteral") {
        return new CirExpr(e = "int_lit", t = t, v = "{js?["value"] ?? 0l}")
    }
    if (kind == "FloatingLiteral") {
        return new CirExpr(e = "float_lit", t = t, v = hex_float(js?["value"] ?? "0"))
    }
    var x = new CirExpr(e = "str_lit", t = t)
    if (!literal_bytes(js?["value"] ?? "", x.bytes)) {
        fail(d, "unreadable string literal", at)
        delete_expr(x)
        return null
    }
    return x
}

def dump_expr(var d : Dumper; js : JsonValue?) : CirExpr? {
    let at = loc_of(d, js)
    let kind = node_kind(js)
    if (kind == "ParenExpr") {
        if (child_count(js) == 0) {
            fail(d, "empty parentheses", at)
            return null
        }
        return child_expr(d, js?["inner"], 0)
    }
    let t = node_type(d, js, at)
    if (t < 0) {
        return null
    }
    if (kind == "IntegerLiteral" || kind == "CharacterLiteral" || kind == "FloatingLiteral" || kind == "StringLiteral") {
        return dump_literal(d, js, kind, t, at)
    }
    if (kind == "DeclRefExpr") {
        if ((js?["referencedDecl"]?["kind"] ?? "") == "EnumConstantDecl") {
            fail(d, "enum constants are not dumped yet", at)
            return null
        }
        return new CirExpr(e = "ref", t = t, name = linkage_name(d, js?["referencedDecl"]?["name"] ?? ""))
    }
    if (kind == "ImplicitCastExpr" || kind == "CStyleCastExpr") {
        return dump_cast(d, js, t, at)
    }
    if (kind == "UnaryOperator") {
        return dump_unary(d, js, t, at)
    }
    if (kind == "BinaryOperator" || kind == "CompoundAssignOperator") {
        return dump_binary(d, js, t, at)
    }
    if (kind == "ConditionalOperator") {
        return dump_conditional(d, js, t, at)
    }
    if (kind == "CallExpr") {
        return dump_call(d, js, t, at)
    }
    if (kind == "ArraySubscriptExpr") {
        return dump_subscript(d, js, t, at)
    }
    if (kind == "UnaryExprOrTypeTraitExpr") {
        return dump_sizeof(d, js, t, at)
    }
    fail(d, "unsupported expression `{kind}`", at)
    return null
}

let EXPR_KINDS <- {"IntegerLiteral", "CharacterLiteral", "FloatingLiteral", "StringLiteral", "DeclRefExpr", "ImplicitCastExpr", "CStyleCastExpr", "UnaryOperator", "BinaryOperator", "CompoundAssignOperator", "ConditionalOperator", "CallExpr", "ArraySubscriptExpr", "UnaryExprOrTypeTraitExpr", "ParenExpr"}

// an optional slot of a statement: clang spells an absent one as `{}`
def private slot_stmt(var d : Dumper; kids : JsonValue?; idx : int; var ok : bool&) : CirStmt? {
    let node = (kids as _array)[idx]
    if (!is_present(node) || empty(node_kind(node))) {
        return null
    }
    var st = dump_stmt(d, node)
    if (st == null) {
        ok = false
    }
    return st
}

def private slot_expr(var d : Dumper; kids : JsonValue?; idx : int; var ok : bool&) : CirExpr? {
    let node = (kids as _array)[idx]
    if (!is_present(node) || empty(node_kind(node))) {
        return null
    }
    var e = dump_expr(d, node)
    if (e == null) {
        ok = false
    }
    return e
}

// a local `static` is a module global named `<fn>_<name>` (docs/c-feature-matrix.md section 2):
// the dumper hoists it into `decls` with `from_func` and the body refers to the hoisted name
def private hoist_static(var d : Dumper; js : JsonValue?; at : CirLoc; t : int) : bool {
    let c_name = js?["name"] ?? ""
    let hoisted = "{d.current_fn}_{c_name}"
    var g = new CirDecl(k = "global", name = hoisted, c_name = c_name, t = t, is_static = true, from_func = d.current_fn, loc = at)
    if (child_count(js) > 0) {
        g.init = dump_expr(d, (js?["inner"] as _array)[child_count(js) - 1])
        if (g.init == null) {
            delete_decl(g)
            return false
        }
    }
    d.tu.decls |> push(g)
    d.local_statics[c_name] = hoisted
    return true
}

def private dump_var(var d : Dumper; js : JsonValue?; at : CirLoc) : CirStmt? {
    let t = node_type(d, js, at)
    if (t < 0) {
        return null
    }
    if ((js?["storageClass"] ?? "") == "static") {
        if (!hoist_static(d, js, at, t)) {
            return null
        }
        return new CirStmt(s = "null", loc = at)
    }
    var st = new CirStmt(s = "decl", name = js?["name"] ?? "", t = t, loc = at)
    if (child_count(js) > 0) {
        st.init = dump_expr(d, (js?["inner"] as _array)[child_count(js) - 1])
        if (st.init == null) {
            delete_stmt(st)
            return null
        }
    }
    return st
}

// the variables of one DeclStmt, each as its own `decl` (or hoisted when static)
def private dump_decl_stmt(var d : Dumper; js : JsonValue?; var into : array<CirStmt?>) : bool {
    let vars = js?["inner"]
    into |> reserve(length(into) + child_count(js))
    for (vidx in range(child_count(js))) {
        let v = (vars as _array)[vidx]
        if (node_kind(v) != "VarDecl") {
            fail(d, "unsupported local declaration `{node_kind(v)}`", loc_of(d, v))
            return false
        }
        var vs = dump_var(d, v, loc_of(d, v))
        if (vs == null) {
            return false
        }
        into |> push(vs)
    }
    return true
}

def private dump_compound(var d : Dumper; js : JsonValue?; at : CirLoc) : CirStmt? {
    let kids = js?["inner"]
    let nkids = child_count(js)
    var st = new CirStmt(s = "compound", loc = at)
    st.body |> reserve(nkids)
    for (idx in range(nkids)) {
        let child = (kids as _array)[idx]
        if (node_kind(child) == "DeclStmt") {
            if (!dump_decl_stmt(d, child, st.body)) {
                delete_stmt(st)
                return null
            }
            continue
        }
        var cs = dump_stmt(d, child)
        if (cs == null) {
            delete_stmt(st)
            return null
        }
        st.body |> push(cs)
    }
    return st
}

// if, while and do share the shape: a condition and a body, in one of two orders
def private dump_loop_or_if(var d : Dumper; js : JsonValue?; kind : string; at : CirLoc) : CirStmt? {
    let kids = js?["inner"]
    let nkids = child_count(js)
    var ok = true
    var st = new CirStmt(s = kind == "IfStmt" ? "if" : kind == "WhileStmt" ? "while" : "do", loc = at)
    if (kind == "DoStmt") {
        st.body_s = slot_stmt(d, kids, 0, ok)
        st.cond = nkids > 1 ? slot_expr(d, kids, 1, ok) : null
    } else {
        st.cond = slot_expr(d, kids, 0, ok)
        var body = nkids > 1 ? slot_stmt(d, kids, 1, ok) : null
        if (kind == "IfStmt") {
            st.then_s = body
            st.else_s = nkids > 2 ? slot_stmt(d, kids, 2, ok) : null
        } else {
            st.body_s = body
        }
    }
    let has_body = kind == "IfStmt" ? st.then_s != null : st.body_s != null
    if (!ok || st.cond == null || !has_body) {
        fail(d, "{st.s} without a condition or a body", at)
        delete_stmt(st)
        return null
    }
    return st
}

def private dump_for(var d : Dumper; js : JsonValue?; at : CirLoc) : CirStmt? {
    let kids = js?["inner"]
    if (child_count(js) != 5) {
        fail(d, "for with {child_count(js)} slots", at)
        return null
    }
    var ok = true
    var st = new CirStmt(s = "for", loc = at)
    let init = (kids as _array)[0]
    if (is_present(init) && node_kind(init) == "DeclStmt") {
        var init_block = new CirStmt(s = "compound", loc = loc_of(d, init))
        ok = dump_decl_stmt(d, init, init_block.body)
        st.init_s = init_block
    } elif (is_present(init) && !empty(node_kind(init))) {
        var e = slot_expr(d, kids, 0, ok)
        if (e != null) {
            st.init_s = new CirStmt(s = "expr", e = e, loc = loc_of(d, init))
        }
    }
    st.cond = slot_expr(d, kids, 2, ok)
    st.inc = slot_expr(d, kids, 3, ok)
    st.body_s = slot_stmt(d, kids, 4, ok)
    if (!ok || st.body_s == null) {
        fail(d, "for without a body", at)
        delete_stmt(st)
        return null
    }
    return st
}

let LEAF_STMTS <- {"NullStmt" => "null", "BreakStmt" => "break", "ContinueStmt" => "continue"}

def dump_stmt(var d : Dumper; js : JsonValue?) : CirStmt? {
    let at = loc_of(d, js)
    let kind = node_kind(js)
    if (kind == "CompoundStmt") {
        return dump_compound(d, js, at)
    }
    if (kind == "ReturnStmt") {
        var st = new CirStmt(s = "return", loc = at)
        if (child_count(js) > 0) {
            st.e = child_expr(d, js?["inner"], 0)
            if (st.e == null) {
                delete_stmt(st)
                return null
            }
        }
        return st
    }
    let leaf = LEAF_STMTS?[kind] ?? ""
    if (!empty(leaf)) {
        return new CirStmt(s = leaf, loc = at)
    }
    if (kind == "IfStmt" || kind == "WhileStmt" || kind == "DoStmt") {
        return dump_loop_or_if(d, js, kind, at)
    }
    if (kind == "ForStmt") {
        return dump_for(d, js, at)
    }
    if (key_exists(EXPR_KINDS, kind)) {
        var e = dump_expr(d, js)
        if (e == null) {
            return null
        }
        return new CirStmt(s = "expr", e = e, loc = at)
    }
    fail(d, "unsupported statement `{kind}`", at)
    return null
}

def dump_decl(var d : Dumper; js : JsonValue?) : CirDecl? {
    let at = loc_of(d, js)
    let kind = node_kind(js)
    let c_name = js?["name"] ?? ""
    let storage = js?["storageClass"] ?? ""
    let is_static = storage == "static"
    if (is_static) {
        d.linkage_names[c_name] = "{d.tu_prefix}__{c_name}"
    }
    let name = linkage_name(d, c_name)
    if (kind == "FunctionDecl") {
        let t = node_type(d, js, at)
        if (t < 0) {
            return null
        }
        var fn = new CirDecl(k = "func", name = name, c_name = c_name, t = t, is_static = is_static, loc = at)
        d.current_fn = c_name
        d.local_statics |> clear()
        let kids = js?["inner"]
        for (idx in range(child_count(js))) {
            let child = (kids as _array)[idx]
            let ck = node_kind(child)
            if (ck == "ParmVarDecl") {
                let pat = loc_of(d, child)
                let pt = node_type(d, child, pat)
                if (pt < 0) {
                    delete_decl(fn)
                    return null
                }
                fn.params |> push(CirParam(name = child?["name"] ?? "", t = pt))
            } elif (ck == "CompoundStmt") {
                fn.body = dump_stmt(d, child)
                if (fn.body == null) {
                    delete_decl(fn)
                    return null
                }
            } elif (ck |> ends_with("Attr")) {
                continue
            } else {
                fail(d, "unsupported child `{ck}` of function `{c_name}`", loc_of(d, child))
                delete_decl(fn)
                return null
            }
        }
        return fn
    }
    if (kind == "VarDecl") {
        let t = node_type(d, js, at)
        if (t < 0) {
            return null
        }
        var g = new CirDecl(k = "global", name = name, c_name = c_name, t = t, is_static = is_static, is_extern = storage == "extern" && child_count(js) == 0, loc = at)
        if (child_count(js) > 0) {
            g.init = dump_expr(d, (js?["inner"] as _array)[child_count(js) - 1])
            if (g.init == null) {
                delete_decl(g)
                return null
            }
        }
        return g
    }
    fail(d, "unsupported declaration `{kind}`", at)
    return null
}

def private ident_of(name : string) : string {
    return build_string() $(var w) {
        for (ch in name) {
            w |> write(is_alnum(ch) ? to_char(ch) : "_")
        }
    }
}

def private clang_version(clang : string) : string {
    var out : string
    run_and_capture([clang, "--version"], out, 30.0)
    let first = split(out, "\n")[0]
    let at = find(first, "clang version ")
    return at < 0 ? first : split(slice(first, at + length("clang version ")), " ")[0]
}

// C allows several file-scope declarations of one object (tentative definitions); the one
// with the initializer wins and the others add nothing
def private merge_tentative(var d : Dumper; var cd : CirDecl?) : bool {
    for (idx in range(length(d.tu.decls))) {
        var prev = d.tu.decls[idx]
        if (prev.k == "global" && prev.name == cd.name) {
            if (cd.init != null && prev.init == null) {
                prev.init = cd.init
                cd.init = null
            }
            prev.is_extern = prev.is_extern && cd.is_extern
            return false
        }
    }
    return true
}

//! The pinned clang: the libclang archive's own binary when `PATH_TO_LIBCLANG` is set
//! (`scripts/env.sh`), else whatever `clang` is on PATH.
def default_clang : string {
    return has_env_variable("PATH_TO_LIBCLANG") ? get_env_variable("PATH_TO_LIBCLANG") + "/bin/clang" : "clang"
}

//! Runs clang on `c_path` under the dialect `target` and normalizes the dump; `d.error` names
//! the first unsupported construct, and the dump is then partial.
def dump_tu(c_path : string; target : CirTarget; clang : string) : Dumper {
    var d : Dumper
    d.tu.cir = CIR_VERSION
    d.tu.target = target
    d.tu.tu = base_name(c_path)
    d.c_path = c_path
    d.cur_file = c_path
    d.tu_prefix = ident_of(slice(d.tu.tu, 0, max(find(d.tu.tu, "."), 0)))
    d.tu.producer = "c2das-dumper-a 0.1 / clang {clang_version(clang)}"
    var out : string
    let rc = run_and_capture([clang, "-Xclang", "-ast-dump=json", "-fsyntax-only", "-w", "-funsigned-char", "-target", target.triple, c_path], out, 120.0)
    if (rc != 0) {
        d.error = "clang exited {rc}:\n{out}"
        return <- d
    }
    var err : string
    var js = read_json(out, err)
    if (js == null) {
        d.error = "clang dump is not JSON: {err}"
        return <- d
    }
    let top = js?["inner"]
    for (idx in range(child_count(js))) {
        let decl = (top as _array)[idx]
        continue if (decl?["isImplicit"] ?? false)
        let at = loc_of(d, decl)
        continue if (at.file != c_path)
        var cd = dump_decl(d, decl)
        if (cd == null) {
            break
        }
        if (cd.k == "global" && !merge_tentative(d, cd)) {
            delete_decl(cd)
            continue
        }
        d.tu.decls |> push(cd)
    }
    delete_json(js)
    return <- d
}
