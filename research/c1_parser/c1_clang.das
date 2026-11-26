options gen2
options indenting = 4

module c1_clang shared public

// The probe's clang oracle: clang's `-ast-dump=json` tree and a candidate's AST reduced to one line
// form, compared line by line. Compared: every declaration of the main file (function, variable,
// typedef, parameter, field, enumerator, in order) with its name, its name's line and column, and
// its type spelled as clang spells it where the AST alone fixes the spelling (`?` where it does not:
// an array whose size is not a decimal literal, an anonymous record, `typeof`, an old-style
// parameter, an unnamed parameter's location); every statement and expression of every body and
// initializer with its kind, its operator, its member or referenced name, its operand order and the
// line and column of its first token. Not compared: literal values, the inside of initializer
// lists (clang dumps their semantic form), asm operands, attributes, `__builtin_offsetof` paths,
// goto targets (clang names them by declaration id), implicit casts (clang's semantics).

require strings
require daslib/json_boost
require daslib/strings_boost
require c1_ast public

// ---- the clang side

struct ClangNorm {
    lines : array<string>
    main_file : string
    cur_file : string
    cur_line : int64
    cur_presumed : string
    cur_presumed_line : int64
}

def private present(v : JsonValue?) : bool => v != null && !(v is _null)

def private kind_of(js : JsonValue?) : string => js?["kind"] ?? ""

// one location: clang omits `file` and `line` where they repeat the last written ones, and on
// preprocessed input names the line marker's file and line as `presumedFile` (omitted where it
// repeats) and `presumedLine` (omitted where it repeats the last one written, whatever the file)
def private track_bare(var n : ClangNorm; at : JsonValue?) : int3 {
    if (!present(at?["offset"])) {
        return int3(-1, 0, 0)
    }
    if (present(at?["file"])) {
        n.cur_file = at?["file"] ?? ""
        // a file with no line markers is its own presumed file
        n.cur_presumed = n.cur_file
    }
    if (present(at?["line"])) {
        n.cur_line = at?["line"] ?? 0l
    }
    if (present(at?["presumedLine"])) {
        n.cur_presumed_line = at?["presumedLine"] ?? 0l
    } elif (present(at?["line"]) && n.cur_presumed == n.cur_file) {
        n.cur_presumed_line = n.cur_line
    }
    if (present(at?["presumedFile"])) {
        n.cur_presumed = at?["presumedFile"] ?? ""
    }
    return int3(n.cur_presumed == n.main_file ? 1 : 0, int(n.cur_presumed_line), int(at?["col"] ?? 0l))
}

def private track(var n : ClangNorm; at : JsonValue?) : int3 {
    if (present(at?["spellingLoc"])) {
        track_bare(n, at?["spellingLoc"])
        return track_bare(n, at?["expansionLoc"])
    }
    return track_bare(n, at)
}

def private at_text(at : int3) : string => "@{at.y}:{at.z}"

let private TRANSPARENT <- ["ImplicitCastExpr", "ConstantExpr"]

let private DECL_KINDS <- {"FunctionDecl" => "func", "VarDecl" => "var", "TypedefDecl" => "typedef",
    "ParmVarDecl" => "param", "FieldDecl" => "field", "EnumConstantDecl" => "enumerator"}

let private STMT_KINDS <- {"CompoundStmt" => "compound", "IfStmt" => "if", "WhileStmt" => "while", "DoStmt" => "do",
    "ForStmt" => "for", "SwitchStmt" => "switch", "CaseStmt" => "case", "DefaultStmt" => "default",
    "ReturnStmt" => "return", "BreakStmt" => "break", "ContinueStmt" => "continue", "GotoStmt" => "goto",
    "IndirectGotoStmt" => "goto*", "NullStmt" => "null", "DeclStmt" => "declstmt", "AttributedStmt" => "attributed",
    "CallExpr" => "call", "ArraySubscriptExpr" => "index", "CStyleCastExpr" => "cast", "ParenExpr" => "paren",
    "ConditionalOperator" => "cond", "IntegerLiteral" => "int", "FloatingLiteral" => "float",
    "CharacterLiteral" => "char", "StringLiteral" => "string", "CompoundLiteralExpr" => "compound-literal",
    "StmtExpr" => "stmt-expr", "VAArgExpr" => "va_arg", "AddrLabelExpr" => "label-addr"}

// the kinds whose children are not compared (their inside is semantic, or not in the AST's terms)
let private OPAQUE <- ["GCCAsmStmt", "OffsetOfExpr", "InitListExpr", "PredefinedExpr", "BinaryConditionalOperator", "GotoStmt"]

def private opaque_line(k : string) : string {
    if (k == "GCCAsmStmt") {
        return "asm"
    } elif (k == "OffsetOfExpr") {
        return "offsetof"
    } elif (k == "InitListExpr") {
        return "init-list"
    } elif (k == "PredefinedExpr") {
        return "func-name"
    } elif (k == "BinaryConditionalOperator") {
        return "gnu-cond"
    }
    return "goto"
}

//! clang's type spelling without what the tree keeps as attribute nodes or clang adds from its
//! builtin knowledge: ` __attribute__((...))` and nullability qualifiers.
def private type_without_attributes(t : string) : string {
    var out = t
    for (q in fixed_array(" _Nonnull", " _Nullable")) {
        out = replace(out, q, "")
    }
    let at = find(out, " __attribute__((")
    if (at >= 0) {
        var depth = 0
        var i = at + 1
        while (i < length(out)) {
            let c = character_at(out, i)
            if (c == '(') {
                depth++
            } elif (c == ')') {
                depth--
                if (depth == 0) {
                    break
                }
            }
            i++
        }
        out = slice(out, 0, at) + slice(out, i + 1)
    }
    return out
}

def private indent(depth : int) : string => repeat("  ", depth)

//! Walk `js` in print order, tracking locations; `depth` >= 0 emits the node's line at that depth,
//! -1 walks it for the locations only.
def private cl_walk(var n : ClangNorm; js : JsonValue?; depth : int) {
    if (!(js is _object)) {
        return
    }
    let k = kind_of(js)
    let loc = track(n, js?["loc"])
    let begin = track(n, js?["range"]?["begin"])
    track(n, js?["range"]?["end"])
    var emit = depth >= 0
    if (emit && (empty(k) || ends_with(k, "Attr") || ends_with(k, "Type") || (js?["isImplicit"] ?? false))) {
        emit = false
    }
    var child_depth = -1
    if (emit) {
        if (k == "TranslationUnitDecl") {
            child_depth = 0
            let top = js?["inner"]
            if (top != null && top is _array) {
                for (c in top as _array) {
                    // a top-level declaration counts when the main file holds it
                    cl_top(n, c)
                }
            }
            return
        }
        var line = ""
        if (has_value(TRANSPARENT, k)) {
            child_depth = depth
        } elif (has_value(OPAQUE, k)) {
            line = opaque_line(k) + " " + at_text(begin)
        } elif (DECL_KINDS |> key_exists(k)) {
            let name = js?["name"] ?? ""
            let ty = type_without_attributes(js?["type"]?["qualType"] ?? "")
            line = k == "EnumConstantDecl" ? "enumerator {name} {at_text(loc)}" : "{DECL_KINDS?[k] ?? ""} {name} : {ty} {at_text(loc)}"
            child_depth = depth + 1
        } elif (k == "RecordDecl" || k == "EnumDecl") {
            let inner = js?["inner"]
            let has_body = k == "RecordDecl" ? (js?["completeDefinition"] ?? false) : inner != null && inner is _array
            if (has_body) {
                line = k == "RecordDecl" ? "record" : "enum"
                child_depth = depth + 1
            }
        } elif (k == "LabelStmt") {
            line = "label {js?["name"] ?? ""} {at_text(begin)}"
            child_depth = depth + 1
        } elif (k == "BinaryOperator" || k == "CompoundAssignOperator") {
            let op = js?["opcode"] ?? ""
            let is_assign = k == "CompoundAssignOperator" || op == "="
            line = "{is_assign ? "assign" : "binop"} {op} {at_text(begin)}"
            child_depth = depth + 1
        } elif (k == "UnaryOperator") {
            line = "{(js?["isPostfix"] ?? false) ? "postfix" : "unop"} {js?["opcode"] ?? ""} {at_text(begin)}"
            child_depth = depth + 1
        } elif (k == "UnaryExprOrTypeTraitExpr") {
            let name = js?["name"] ?? ""
            line = "{name == "sizeof" ? "sizeof" : "alignof"} {at_text(begin)}"
            child_depth = depth + 1
        } elif (k == "MemberExpr" && empty(js?["name"] ?? "")) {
            // the access of an anonymous struct or union member clang inserts
            child_depth = depth
        } elif (k == "MemberExpr") {
            line = "member {(js?["isArrow"] ?? false) ? "->" : "."}{js?["name"] ?? ""} {at_text(begin)}"
            child_depth = depth + 1
        } elif (k == "DeclRefExpr") {
            line = "ident {js?["referencedDecl"]?["name"] ?? ""} {at_text(begin)}"
        } elif (STMT_KINDS |> key_exists(k)) {
            line = "{STMT_KINDS?[k] ?? ""} {at_text(begin)}"
            child_depth = depth + 1
        } else {
            line = "?{k} {at_text(begin)}"
        }
        if (!empty(line)) {
            n.lines |> push(indent(depth) + line)
        }
        if (has_value(OPAQUE, k)) {
            child_depth = -1
        }
    }
    for (key in fixed_array("array_filler", "inner")) {
        let inner = js?[key]
        if (inner != null && inner is _array) {
            for (c in inner as _array) {
                cl_walk(n, c, child_depth)
            }
        }
    }
}

def private cl_top(var n : ClangNorm; js : JsonValue?) {
    // peek the location without moving the state: the walk tracks it
    let saved_file = n.cur_file
    let saved_line = n.cur_line
    let saved_presumed = n.cur_presumed
    let saved_presumed_line = n.cur_presumed_line
    let at = track(n, js?["loc"])
    n.cur_file = saved_file
    n.cur_line = saved_line
    n.cur_presumed = saved_presumed
    n.cur_presumed_line = saved_presumed_line
    cl_walk(n, js, at.x == 1 ? 0 : -1)
}

//! The lines of clang's JSON dump `text` for the declarations of `main_file`.
[arch(at="ARCHITECTURE.md#clang-lines")]
def clang_lines(text : string; main_file : string; var error : string&) : array<string> {
    var n : ClangNorm
    n.main_file = main_file
    var js = read_json(text, error)
    if (js == null) {
        return <- n.lines
    }
    cl_walk(n, js, 0)
    unsafe {
        delete js
    }
    return <- n.lines
}

// ---- the AST side

struct AstNorm {
    lines : array<string>
    main_file : int
}

def private nd(ast : Ast; i : int) : Node => ast.nodes[i]

def private loc_line(ast : Ast; i : int) : string {
    let n = ast.nodes[i]
    return "@{n.line}:{n.col}"
}

def private sym_name(src : Source; s : int) : string => name_of(src.names, s)

//! The base type of specifier list `specs` as clang spells it, "?" where it cannot be told.
def private base_spelling(ast : Ast; src : Source; specs : int) : string {
    var n_long = 0
    var n_int = 0
    var signedness = ""
    var base = ""
    var quals = ""
    var is_const = false
    var is_volatile = false
    var complex = false
    var at = specs
    while (at >= 0) {
        let s = ast.nodes[at]
        if (s.kind == int(NK.SPEC_KW)) {
            let k = s.op
            if (k == int(TK.LONG)) {
                n_long++
            } elif (k == int(TK.INT)) {
                n_int++
            } elif (k == int(TK.SIGNED) || k == int(TK.UNSIGNED)) {
                signedness = k == int(TK.SIGNED) ? "signed" : "unsigned"
            } elif (k == int(TK.CONST)) {
                is_const = true
            } elif (k == int(TK.VOLATILE)) {
                is_volatile = true
            } elif (k == int(TK.COMPLEX)) {
                complex = true
            } elif (k == int(TK.VOID) || k == int(TK.CHAR) || k == int(TK.SHORT) || k == int(TK.FLOAT) || k == int(TK.DOUBLE) || k == int(TK.BOOL)) {
                base = k == int(TK.BOOL) ? "_Bool" : kind_name(k)
            }
        } elif (s.kind == int(NK.SPEC_TYPEDEF_NAME)) {
            base = sym_name(src, s.a)
        } elif (s.kind == int(NK.SPEC_RECORD)) {
            if (s.a < 0) {
                return "?"
            }
            base = "{kind_name(s.op)} {sym_name(src, s.a)}"
        } elif (s.kind == int(NK.SPEC_ENUM)) {
            if (s.a < 0) {
                return "?"
            }
            base = "enum {sym_name(src, s.a)}"
        } elif (s.kind == int(NK.SPEC_TYPEOF_EXPR) || s.kind == int(NK.SPEC_TYPEOF_TYPE)) {
            return "?"
        }
        at = s.next
    }
    if (base == "char") {
        base = signedness == "" ? "char" : "{signedness} char"
    } elif (base == "short") {
        base = signedness == "unsigned" ? "unsigned short" : "short"
    } elif (base == "double") {
        base = n_long > 0 ? "long double" : "double"
    } elif (base == "") {
        let width = n_long == 0 ? "int" : n_long == 1 ? "long" : "long long"
        base = signedness == "unsigned" ? "unsigned {width}" : width
    }
    if (complex) {
        base = "_Complex {base}"
    }
    if (is_const) {
        quals = "const "
    }
    if (is_volatile) {
        quals += "volatile "
    }
    return quals + base
}

def private qual_spelling(ast : Ast; quals : int) : string {
    var out = ""
    for (want in [int(TK.CONST), int(TK.VOLATILE), int(TK.RESTRICT)]) {
        var at = quals
        while (at >= 0) {
            let q = ast.nodes[at]
            if (q.kind == int(NK.SPEC_KW) && q.op == want) {
                out += "{empty(out) ? "" : " "}{kind_name(want)}"
                break
            }
            at = q.next
        }
    }
    return out
}

//! Spell the type `base` takes through declarator `d` (outermost first), clang's way, around the
//! text `inner` (the abstract declarator's spelling built so far). "?" when a part cannot be told.
def spell_type(ast : Ast; src : Source; base : string; d : int; inner : string; decay : bool) : string {
    if (base == "?") {
        return "?"
    }
    if (d < 0) {
        if (empty(inner)) {
            return base
        }
        return starts_with(inner, "[") ? base + inner : "{base} {inner}"
    }
    let n = ast.nodes[d]
    if (n.kind == int(NK.D_NAME)) {
        return spell_type(ast, src, base, -1, inner, false)
    } elif (n.kind == int(NK.D_PAREN)) {
        return spell_type(ast, src, base, n.a, inner, decay)
    }
    // the derivation nearest the base is the innermost node of the chain: spell from the name out
    // by collecting the chain first
    var chain : array<int>
    var at = d
    while (at >= 0) {
        let c = ast.nodes[at]
        if (c.kind == int(NK.D_PTR) || c.kind == int(NK.D_ARRAY) || c.kind == int(NK.D_FUNC)) {
            chain |> push(at)
        }
        at = c.kind == int(NK.D_NAME) ? -1 : c.a
    }
    // chain[0] applies to the base first; the last element is the outermost type
    var text = ""
    var prev_kind = -1
    var i = length(chain) - 1
    while (i >= 0) {
        let c = ast.nodes[chain[i]]
        let outermost = i == length(chain) - 1
        if (c.kind == int(NK.D_PTR)) {
            let q = qual_spelling(ast, c.b)
            text = "*{q}{empty(q) || empty(text) ? "" : " "}{text}"
        } elif (c.kind == int(NK.D_ARRAY)) {
            if (outermost && decay) {
                if ((c.op & 2) != 0) {
                    // clang spells a decayed `[*]` parameter its own way
                    return "?"
                }
                let q = qual_spelling(ast, c.c)
                text = "*{q}{empty(q) || empty(text) ? "" : " "}{text}"
                prev_kind = int(NK.D_PTR)
                i--
                continue
            }
            var size = "?"
            if (c.b < 0) {
                size = ""
            } else {
                let sz = ast.nodes[c.b]
                if (sz.kind == int(NK.E_INT)) {
                    let spelled = tok_text(src, sz.a)
                    if (!starts_with(spelled, "0") || spelled == "0") {
                        size = spelled
                    }
                }
            }
            if (size == "?") {
                return "?"
            }
            if (prev_kind == int(NK.D_PTR)) {
                text = "({text})"
            }
            text = "{text}[{size}]"
        } elif (c.kind == int(NK.D_FUNC)) {
            if (outermost && decay) {
                text = "(*)"
            }
            if (prev_kind == int(NK.D_PTR)) {
                text = "({text})"
            }
            let params = param_spelling(ast, src, c)
            if (params == "?") {
                return "?"
            }
            text = "{text}({params})"
        }
        prev_kind = c.kind
        i--
    }
    // a function decayed to a pointer, or a pointer to array or function, already parenthesized
    return spell_type(ast, src, base, -1, text, false)
}

def private param_spelling(ast : Ast; src : Source; f : Node) : string {
    if ((f.op & 2) != 0) {
        return "?"
    }
    var parts : array<string>
    var at = f.b
    while (at >= 0) {
        let prm = ast.nodes[at]
        let base = base_spelling(ast, src, prm.a)
        if (base == "void" && prm.b < 0 && prm.next < 0 && length(parts) == 0) {
            return "void"
        }
        let t = spell_type(ast, src, base, prm.b, "", true)
        if (t == "?") {
            return "?"
        }
        parts |> push(t)
        at = prm.next
    }
    if ((f.op & 1) != 0) {
        parts |> push("...")
    }
    return join(parts, ", ")
}

def private has_kw(ast : Ast; specs, k : int) : bool {
    var at = specs
    while (at >= 0) {
        let s = ast.nodes[at]
        if (s.kind == int(NK.SPEC_KW) && s.op == k) {
            return true
        }
        at = s.next
    }
    return false
}

//! The node that names declarator `d`'s identifier, -1 for an abstract one.
def private name_node(ast : Ast; d : int) : int {
    var at = d
    while (at >= 0) {
        let n = ast.nodes[at]
        if (n.kind == int(NK.D_NAME)) {
            return at
        }
        at = n.a
    }
    return -1
}

def private push_line(var n : AstNorm; depth : int; line : string) {
    n.lines |> push(indent(depth) + line)
}

//! The record and enum definitions in specifier list `specs`, at `depth`.
def private an_specs(var n : AstNorm; ast : Ast; src : Source; specs, depth : int) {
    var at = specs
    while (at >= 0) {
        let s = ast.nodes[at]
        if (s.kind == int(NK.SPEC_RECORD) && s.c == 1) {
            push_line(n, depth, "record")
            var m = s.b
            while (m >= 0) {
                let md = ast.nodes[m]
                if (md.kind == int(NK.MEMBER_DECL)) {
                    an_specs(n, ast, src, md.a, depth + 1)
                    let base = base_spelling(ast, src, md.a)
                    var f = md.b
                    while (f >= 0) {
                        let fd = ast.nodes[f]
                        let nn = name_node(ast, fd.a)
                        let name = nn >= 0 ? sym_name(src, ast.nodes[nn].a) : ""
                        let place = nn >= 0 ? loc_line(ast, nn) : "@?"
                        push_line(n, depth + 1, "field {name} : {spell_type(ast, src, base, fd.a, "", false)} {place}")
                        if (fd.b >= 0) {
                            an_expr(n, ast, src, fd.b, depth + 2)
                        }
                        f = fd.next
                    }
                } elif (md.kind == int(NK.STATIC_ASSERT)) {
                    push_line(n, depth + 1, "?static_assert")
                }
                m = md.next
            }
        } elif (s.kind == int(NK.SPEC_ENUM) && s.c == 1) {
            push_line(n, depth, "enum")
            var e = s.b
            while (e >= 0) {
                let en = ast.nodes[e]
                push_line(n, depth + 1, "enumerator {sym_name(src, en.a)} {loc_line(ast, e)}")
                if (en.b >= 0) {
                    an_expr(n, ast, src, en.b, depth + 2)
                }
                e = en.next
            }
        }
        at = s.next
    }
}

//! A declaration's declarators (DECL or FUNC_DEF heads) at `depth`.
def private an_decl(var n : AstNorm; ast : Ast; src : Source; at, depth : int) {
    let decl = ast.nodes[at]
    an_specs(n, ast, src, decl.a, depth)
    let is_typedef = has_kw(ast, decl.a, int(TK.TYPEDEF))
    let base = base_spelling(ast, src, decl.a)
    var h = decl.b
    while (h >= 0) {
        let head = ast.nodes[h]
        let d = head.a
        let nn = name_node(ast, d)
        let name = nn >= 0 ? sym_name(src, ast.nodes[nn].a) : ""
        let kind = is_typedef ? "typedef" : name_function(ast, d) >= 0 ? "func" : "var"
        var ty = spell_type(ast, src, base, d, "", false)
        if (head.b >= 0 && find(ty, "[]") >= 0) {
            // the initializer completes the size: clang spells the completed type
            ty = "?"
        }
        push_line(n, depth, "{kind} {name} : {ty} {nn >= 0 ? loc_line(ast, nn) : "@?"}")
        if (kind == "func") {
            let f = name_function(ast, d)
            if (f >= 0) {
                var prm = ast.nodes[f].b
                let only_void = prm >= 0 && ast.nodes[prm].next < 0 && ast.nodes[prm].b < 0 && base_spelling(ast, src, ast.nodes[prm].a) == "void"
                while (prm >= 0 && !only_void) {
                    let pn = ast.nodes[prm]
                    if (pn.kind == int(NK.IDENT_PARAM)) {
                        push_line(n, depth + 1, "param {sym_name(src, pn.a)} : ? {loc_line(ast, prm)}")
                    } else {
                        an_specs(n, ast, src, pn.a, depth + 1)
                        let pnn = name_node(ast, pn.b)
                        let pname = pnn >= 0 ? sym_name(src, ast.nodes[pnn].a) : ""
                        let ptype = spell_type(ast, src, base_spelling(ast, src, pn.a), pn.b, "", true)
                        push_line(n, depth + 1, "param {pname} : {ptype} {pnn >= 0 ? loc_line(ast, pnn) : "@?"}")
                    }
                    prm = pn.next
                }
            }
        }
        if (decl.kind == int(NK.FUNC_DEF)) {
            an_stmt(n, ast, src, decl.d, depth + 1)
            return
        }
        if (head.b >= 0) {
            an_expr(n, ast, src, head.b, depth + 1)
        }
        h = head.next
    }
}

def private only_attributes(ast : Ast; specs : int) : bool {
    var at = specs
    while (at >= 0) {
        if (ast.nodes[at].kind != int(NK.ATTRIBUTE)) {
            return false
        }
        at = ast.nodes[at].next
    }
    return specs >= 0
}

def private an_stmt(var n : AstNorm; ast : Ast; src : Source; at, depth : int) {
    if (at < 0) {
        return
    }
    let s = ast.nodes[at]
    let k = s.kind
    let place = loc_line(ast, at)
    if (k == int(NK.S_COMPOUND)) {
        push_line(n, depth, "compound {place}")
        var c = s.a
        while (c >= 0) {
            an_stmt(n, ast, src, c, depth + 1)
            c = ast.nodes[c].next
        }
    } elif (k == int(NK.DECL)) {
        if (s.b < 0 && only_attributes(ast, s.a)) {
            push_line(n, depth, "attributed {place}")
            push_line(n, depth + 1, "null {place}")
            return
        }
        push_line(n, depth, "declstmt {place}")
        an_decl(n, ast, src, at, depth + 1)
    } elif (k == int(NK.STATIC_ASSERT)) {
        push_line(n, depth, "?static_assert")
    } elif (k == int(NK.S_EXPR)) {
        an_expr(n, ast, src, s.a, depth)
    } elif (k == int(NK.S_NULL)) {
        push_line(n, depth, "null {place}")
    } elif (k == int(NK.S_IF)) {
        push_line(n, depth, "if {place}")
        an_expr(n, ast, src, s.a, depth + 1)
        an_stmt(n, ast, src, s.b, depth + 1)
        an_stmt(n, ast, src, s.c, depth + 1)
    } elif (k == int(NK.S_SWITCH) || k == int(NK.S_WHILE)) {
        push_line(n, depth, "{k == int(NK.S_SWITCH) ? "switch" : "while"} {place}")
        an_expr(n, ast, src, s.a, depth + 1)
        an_stmt(n, ast, src, s.b, depth + 1)
    } elif (k == int(NK.S_DO)) {
        push_line(n, depth, "do {place}")
        an_stmt(n, ast, src, s.a, depth + 1)
        an_expr(n, ast, src, s.b, depth + 1)
    } elif (k == int(NK.S_FOR)) {
        push_line(n, depth, "for {place}")
        an_stmt(n, ast, src, s.a, depth + 1)
        an_expr(n, ast, src, s.b, depth + 1)
        an_expr(n, ast, src, s.c, depth + 1)
        an_stmt(n, ast, src, s.d, depth + 1)
    } elif (k == int(NK.S_GOTO)) {
        push_line(n, depth, "goto {place}")
    } elif (k == int(NK.S_GOTO_PTR)) {
        push_line(n, depth, "goto* {place}")
        an_expr(n, ast, src, s.a, depth + 1)
    } elif (k == int(NK.S_CONTINUE) || k == int(NK.S_BREAK)) {
        push_line(n, depth, "{k == int(NK.S_BREAK) ? "break" : "continue"} {place}")
    } elif (k == int(NK.S_RETURN)) {
        push_line(n, depth, "return {place}")
        an_expr(n, ast, src, s.a, depth + 1)
    } elif (k == int(NK.S_LABEL)) {
        push_line(n, depth, "label {sym_name(src, s.a)} {place}")
        an_stmt(n, ast, src, s.b, depth + 1)
    } elif (k == int(NK.S_CASE)) {
        push_line(n, depth, "case {place}")
        an_expr(n, ast, src, s.a, depth + 1)
        an_expr(n, ast, src, s.b, depth + 1)
        an_stmt(n, ast, src, s.c, depth + 1)
    } elif (k == int(NK.S_DEFAULT)) {
        push_line(n, depth, "default {place}")
        an_stmt(n, ast, src, s.a, depth + 1)
    } elif (k == int(NK.S_ASM)) {
        push_line(n, depth, "asm {place}")
    } elif (k == int(NK.S_ATTRIBUTED)) {
        push_line(n, depth, "attributed {place}")
        an_stmt(n, ast, src, s.b, depth + 1)
    } else {
        push_line(n, depth, "?stmt {k}")
    }
}

def private an_expr(var n : AstNorm; ast : Ast; src : Source; at, depth : int) {
    if (at < 0) {
        return
    }
    let e = ast.nodes[at]
    let k = e.kind
    let place = loc_line(ast, at)
    if (k == int(NK.E_IDENT)) {
        push_line(n, depth, "ident {sym_name(src, e.a)} {place}")
    } elif (k == int(NK.E_INT) || k == int(NK.E_FLOAT) || k == int(NK.E_CHAR) || k == int(NK.E_STRING)) {
        let what = k == int(NK.E_INT) ? "int" : k == int(NK.E_FLOAT) ? "float" : k == int(NK.E_CHAR) ? "char" : "string"
        push_line(n, depth, "{what} {place}")
    } elif (k == int(NK.E_FUNC_NAME)) {
        push_line(n, depth, "func-name {place}")
    } elif (k == int(NK.E_PAREN)) {
        push_line(n, depth, "paren {place}")
        an_expr(n, ast, src, e.a, depth + 1)
    } elif (k == int(NK.E_BINARY) || k == int(NK.E_ASSIGN)) {
        push_line(n, depth, "{k == int(NK.E_ASSIGN) ? "assign" : "binop"} {kind_name(e.op)} {place}")
        an_expr(n, ast, src, e.a, depth + 1)
        an_expr(n, ast, src, e.b, depth + 1)
    } elif (k == int(NK.E_COND)) {
        if (e.b < 0) {
            push_line(n, depth, "gnu-cond {place}")
            return
        }
        push_line(n, depth, "cond {place}")
        an_expr(n, ast, src, e.a, depth + 1)
        an_expr(n, ast, src, e.b, depth + 1)
        an_expr(n, ast, src, e.c, depth + 1)
    } elif (k == int(NK.E_UNARY) || k == int(NK.E_POSTFIX)) {
        push_line(n, depth, "{k == int(NK.E_POSTFIX) ? "postfix" : "unop"} {kind_name(e.op)} {place}")
        an_expr(n, ast, src, e.a, depth + 1)
    } elif (k == int(NK.E_EXTENSION)) {
        push_line(n, depth, "unop __extension__ {place}")
        an_expr(n, ast, src, e.a, depth + 1)
    } elif (k == int(NK.E_CAST)) {
        push_line(n, depth, "cast {place}")
        an_expr(n, ast, src, e.b, depth + 1)
    } elif (k == int(NK.E_SIZEOF_EXPR) || k == int(NK.E_ALIGNOF_EXPR)) {
        push_line(n, depth, "{k == int(NK.E_SIZEOF_EXPR) ? "sizeof" : "alignof"} {place}")
        an_expr(n, ast, src, e.a, depth + 1)
    } elif (k == int(NK.E_SIZEOF_TYPE) || k == int(NK.E_ALIGNOF_TYPE)) {
        push_line(n, depth, "{k == int(NK.E_SIZEOF_TYPE) ? "sizeof" : "alignof"} {place}")
    } elif (k == int(NK.E_CALL)) {
        push_line(n, depth, "call {place}")
        an_expr(n, ast, src, e.a, depth + 1)
        var arg = e.b
        while (arg >= 0) {
            an_expr(n, ast, src, arg, depth + 1)
            arg = ast.nodes[arg].next
        }
    } elif (k == int(NK.E_INDEX)) {
        push_line(n, depth, "index {place}")
        an_expr(n, ast, src, e.a, depth + 1)
        an_expr(n, ast, src, e.b, depth + 1)
    } elif (k == int(NK.E_MEMBER)) {
        push_line(n, depth, "member {kind_name(e.op)}{sym_name(src, e.b)} {place}")
        an_expr(n, ast, src, e.a, depth + 1)
    } elif (k == int(NK.E_COMPOUND_LIT)) {
        push_line(n, depth, "compound-literal {place}")
        push_line(n, depth + 1, "init-list {loc_line(ast, e.b)}")
    } elif (k == int(NK.E_STMT_EXPR)) {
        push_line(n, depth, "stmt-expr {place}")
        an_stmt(n, ast, src, e.a, depth + 1)
    } elif (k == int(NK.E_VA_ARG)) {
        push_line(n, depth, "va_arg {place}")
        an_expr(n, ast, src, e.a, depth + 1)
    } elif (k == int(NK.E_OFFSETOF)) {
        push_line(n, depth, "offsetof {place}")
    } elif (k == int(NK.E_LABEL_ADDR)) {
        push_line(n, depth, "label-addr {place}")
    } elif (k == int(NK.INIT_LIST)) {
        push_line(n, depth, "init-list {place}")
    } else {
        push_line(n, depth, "?expr {k}")
    }
}

//! The lines of a candidate's tree for the declarations of file `main_file`.
[arch(at="ARCHITECTURE.md#clang-lines")]
def ast_lines(ast : Ast; src : Source; main_file : string) : array<string> {
    var n : AstNorm
    n.main_file = find_index(src.files, main_file)
    var at = ast.nodes[ast.root].a
    while (at >= 0) {
        let d = ast.nodes[at]
        if (d.file == n.main_file) {
            if (d.kind == int(NK.DECL) || d.kind == int(NK.FUNC_DEF)) {
                an_decl(n, ast, src, at, 0)
            } else {
                push_line(n, 0, "?static_assert")
            }
        }
        at = d.next
    }
    return <- n.lines
}

//! Whether line `a` (the AST's) matches `b` (clang's): equal, or equal where `a` says `?`.
def line_matches(a, b : string) : bool {
    if (a == b) {
        return true
    }
    let pa <- split(a, " ")
    let pb <- split(b, " ")
    // a type spelled `?` stands for the clang type, which may hold spaces: compare the head and tail
    let q = find_index(pa, "?")
    if (q >= 0) {
        let n_head = q
        let n_tail = length(pa) - q - 1
        if (length(pb) < n_head + n_tail) {
            return false
        }
        for (i in range(n_head)) {
            if (pa[i] != pb[i]) {
                return false
            }
        }
        for (i in range(n_tail)) {
            let x = pa[length(pa) - 1 - i]
            let y = pb[length(pb) - 1 - i]
            if (x != y && x != "@?") {
                return false
            }
        }
        return true
    }
    if (length(pa) == length(pb) && pa[length(pa) - 1] == "@?") {
        for (i in range(length(pa) - 1)) {
            if (pa[i] != pb[i]) {
                return false
            }
        }
        return true
    }
    return false
}
