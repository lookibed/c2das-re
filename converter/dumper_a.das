options gen2

module dumper_a public

require strings
require math
require daslib/strings_boost
require daslib/fio
require daslib/json_boost
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
def type_from_qual(var d : Dumper; qual : string; at : CirLoc) : int {
    let qt = strip(qual)
    let scalar = scalar_from_qual(d, qt)
    if (scalar != -2) {
        return scalar
    }
    if (qt |> ends_with(" *")) {
        let to = type_from_qual(d, slice(qt, 0, length(qt) - 2), at)
        if (to < 0) {
            return -1
        }
        var t = CirType(k = "ptr", to = to)
        return intern(d, "ptr:{to}", t)
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

def private node_type(var d : Dumper; js : JsonValue?; at : CirLoc) : int {
    return type_from_qual(d, js?["type"]?["qualType"] ?? "", at)
}

def dump_expr(var d : Dumper; js : JsonValue?) : CirExpr? {
    let at = loc_of(d, js)
    let kind = node_kind(js)
    let kids = js?["inner"]
    let nkids = child_count(js)
    if (kind == "ParenExpr") {
        if (nkids == 0) {
            fail(d, "empty parentheses", at)
            return null
        }
        return dump_expr(d, (kids as _array)[0])
    }
    let t = node_type(d, js, at)
    if (t < 0) {
        return null
    }
    if (kind == "IntegerLiteral") {
        return new CirExpr(e = "int_lit", t = t, v = js?["value"] ?? "0")
    }
    if (kind == "ImplicitCastExpr" || kind == "CStyleCastExpr") {
        let ck = js?["castKind"] ?? ""
        if (!key_exists(CAST_KINDS, ck)) {
            fail(d, "unknown castKind `{ck}`", at)
            return null
        }
        if (nkids == 0) {
            fail(d, "cast without operand", at)
            return null
        }
        var inner = dump_expr(d, (kids as _array)[0])
        if (inner == null) {
            return null
        }
        return new CirExpr(e = "cast", t = t, cast_kind = ck, explicit_cast = kind == "CStyleCastExpr", a = inner)
    }
    fail(d, "unsupported expression `{kind}`", at)
    return null
}

def dump_stmt(var d : Dumper; js : JsonValue?) : CirStmt? {
    let at = loc_of(d, js)
    let kind = node_kind(js)
    let kids = js?["inner"]
    let nkids = child_count(js)
    if (kind == "CompoundStmt") {
        var st = new CirStmt(s = "compound", loc = at)
        st.body |> reserve(nkids)
        for (idx in range(nkids)) {
            var cs = dump_stmt(d, (kids as _array)[idx])
            if (cs == null) {
                delete_stmt(st)
                return null
            }
            st.body |> push(cs)
        }
        return st
    }
    if (kind == "ReturnStmt") {
        var st = new CirStmt(s = "return", loc = at)
        if (nkids > 0) {
            st.e = dump_expr(d, (kids as _array)[0])
            if (st.e == null) {
                delete_stmt(st)
                return null
            }
        }
        return st
    }
    fail(d, "unsupported statement `{kind}`", at)
    return null
}

def dump_decl(var d : Dumper; js : JsonValue?) : CirDecl? {
    let at = loc_of(d, js)
    let kind = node_kind(js)
    if (kind == "FunctionDecl") {
        let c_name = js?["name"] ?? ""
        let is_static = (js?["storageClass"] ?? "") == "static"
        let t = node_type(d, js, at)
        if (t < 0) {
            return null
        }
        var fn = new CirDecl(k = "func", name = is_static ? "{d.tu_prefix}__{c_name}" : c_name, c_name = c_name, t = t, is_static = is_static, loc = at)
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
            } else {
                fail(d, "unsupported child `{ck}` of function `{c_name}`", loc_of(d, child))
                delete_decl(fn)
                return null
            }
        }
        return fn
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
    d.tu_prefix = ident_of(slice(d.tu.tu, 0, max(find(d.tu.tu, "."), 0)))
    d.tu.producer = "c2das-dumper-a 0.1 / clang {clang_version(clang)}"
    var out : string
    let rc = run_and_capture([clang, "-Xclang", "-ast-dump=json", "-fsyntax-only", "-w", "-target", target.triple, c_path], out, 120.0)
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
        var cd = dump_decl(d, decl)
        if (cd == null) {
            break
        }
        d.tu.decls |> push(cd)
    }
    return <- d
}
