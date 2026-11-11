options gen2

module cir public

require strings
require daslib/strings_boost
require daslib/json_boost
require daslib/fio

//! The C-IR interchange format (docs/c-ir-spec.md) as das values, with the canonical writer and
//! the reader: one struct per spec table, kind-tagged the way the spec tags them (`k`, `s`, `e`).

struct CirTarget {
    triple : string
    int_w : int
    long_w : int
    llong_w : int
    ptr_w : int
    char_signed : bool
}

struct CirLoc {
    file : string
    line : int
    col : int
}

// one array dimension of a declarator as the source spells it: the enum constant when the
// dimension is that constant alone, an empty item for any other spelling
struct CirDim {
    enum_t : int
    item : string
}

struct CirField {
    name : string
    t : int
    off : int
    bit_off : int
    bit_w : int
    is_bitfield : bool
    dims : array<CirDim>
}

struct CirEnumItem {
    name : string
    v : int64
}

struct CirType {
    k : string
    w : int
    is_signed : bool
    spell : string
    to : int
    elem : int
    count : int
    ret : int
    params : array<int>
    variadic : bool
    name : string
    size : int
    align : int
    packed : bool
    fields : array<CirField>
    items : array<CirEnumItem>
}

struct CirExpr {
    e : string
    t : int
    v : string
    bytes : array<uint8>
    name : string
    enum_t : int
    item : string
    op : string
    a : CirExpr?
    b : CirExpr?
    c : CirExpr?
    cast_kind : string
    explicit_cast : bool
    fn : CirExpr?
    args : array<CirExpr?>
    base : CirExpr?
    field : int
    arrow : bool
    i : CirExpr?
    init_items : array<CirInitItem>
    // the evaluated value of a `sizeof_v` or an `alignof_v`, whose type `of_t` names
    trait_v : uint64
    of_t : int
    list : CirExpr?
    arg_t : int
    init : CirExpr?
    // an lvalue (`ref`, `member`, `index`, `un deref`) whose C type is volatile-qualified
    vol : bool
    // an `int_lit` that the C source spelled as a character literal
    is_char : bool
    // an expression the C source wrote in parentheses of its own
    paren : bool
    macro : string
}

struct CirInitItem {
    pos : int
    v : CirExpr?
}

struct CirStmt {
    s : string
    body : array<CirStmt?>
    name : string
    t : int
    init : CirExpr?
    e : CirExpr?
    cond : CirExpr?
    then_s : CirStmt?
    else_s : CirStmt?
    body_s : CirStmt?
    init_s : CirStmt?
    inc : CirExpr?
    v : int64
    // a `case` whose label the C source spelled as a character literal
    is_char : bool
    label_name : string
    dims : array<CirDim>
    loc : CirLoc
}

struct CirParam {
    name : string
    t : int
}

struct CirDecl {
    k : string
    name : string
    c_name : string
    t : int
    is_static : bool
    is_extern : bool
    init : CirExpr?
    params : array<CirParam>
    body : CirStmt?
    from_func : string
    dims : array<CirDim>
    loc : CirLoc
}

struct CirTu {
    cir : string
    producer : string
    target : CirTarget
    tu : string
    types : array<CirType>
    decls : array<CirDecl?>
}

let CIR_VERSION = "0.1"

let CAST_KINDS <- {"LValueToRValue", "NoOp", "IntegralCast", "IntegralToFloating", "FloatingToIntegral", "FloatingCast", "IntegralToBoolean", "FloatingToBoolean", "PointerToBoolean", "ArrayToPointerDecay", "FunctionToPointerDecay", "NullToPointer", "BitCast", "PointerToIntegral", "IntegralToPointer", "ToVoid", "BooleanToSignedIntegral"}

def target_llp64_msvc : CirTarget =>
    CirTarget(triple = "x86_64-pc-windows-msvc", int_w = 32, long_w = 32, llong_w = 64, ptr_w = 64, char_signed = false)

def target_lp64_linux : CirTarget =>
    CirTarget(triple = "x86_64-unknown-linux-gnu", int_w = 32, long_w = 64, llong_w = 64, ptr_w = 64, char_signed = false)

//! The dialect a `--target` word names: `msvc` (the documents' LLP64 default) or `linux` (the
//! host's LP64, for differential runs against a native build on this box).
def target_by_name(name : string) : CirTarget => name == "linux" ? target_lp64_linux() : target_llp64_msvc()

//! Whether `text` from byte `from` on is a run of one or more decimal digits.
def is_digit_run(text : string; from : int) : bool {
    var digits = length(text) > from
    peek_data(text) $(bytes) {
        for (idx in range(from, length(bytes))) {
            digits = digits && is_number(int(bytes[idx]))
        }
    }
    return digits
}

//! The C name a call's callee spells, below the decay of a function to its pointer; "" for a
//! call through a pointer.
def called_name(x : CirExpr) : string {
    var target = x.fn
    if (target != null && target.e == "cast" && target.cast_kind == "FunctionToPointerDecay") {
        target = target.a
    }
    return target != null && target.e == "ref" ? target.name : ""
}

//! The name of the opaque record the dumper gives every spelling of C's `jmp_buf`.
let JMP_BUF = "jmp_buf"

//! Whether type `t` of `tu` is the opaque `jmp_buf` record.
def is_jmp_buf(tu : CirTu; t : int) : bool => t >= 0 && t < length(tu.types) && tu.types[t].k == "struct" && tu.types[t].name == JMP_BUF

//! Whether `target` is the `msvc` dialect's.
def is_msvc(target : CirTarget) : bool => find(target.triple, "windows") >= 0

//! The file name of `c_path` up to its first dot: the stem every artifact of the file is named by.
def file_stem(c_path : string) : string {
    let name = base_name(c_path)
    let dot = find(name, ".")
    return dot < 0 ? name : slice(name, 0, dot)
}

//! The words das reserves, and `_`, which c_runtime's `c_switch` reads as `default`: a C name of one
//! is spelled `_c_<name>` (`emit.das`), and so is a module a C file of that stem names
//! (`layout.das`).
let DAS_KEYWORDS <- {"table", "_", "if", "else", "for", "while", "break", "continue", "default", "array", "label", "in", "deref", "addr", "new", "delete", "var", "let", "def", "struct", "class", "enum", "typedef", "return", "yield", "goto", "with", "assume", "unsafe", "try", "recover", "finally", "panic", "static_if", "static_elif", "elif", "cast", "upcast", "reinterpret", "override", "abstract", "sealed", "private", "public", "shared", "where", "expect", "pass", "explicit", "capture", "template", "range", "urange", "range64", "urange64", "block", "function", "lambda", "iterator", "generator", "options", "require", "module", "operator", "true", "false", "null", "string", "int", "uint", "float", "double", "bool", "void", "int8", "uint8", "int16", "uint16", "int64", "uint64", "bitfield", "variant", "tuple", "as", "is", "type", "typeinfo", "sizeof", "typename", "smart_ptr", "invoke", "inscope", "implicit", "const", "static", "match", "generic", "auto", "aka", "defer", "print", "assert", "verify", "debug", "include", "typedecl", "fixed_array", "uninitialized", "int2", "int3", "int4", "uint2", "uint3", "uint4", "float2", "float3", "float4", "float16", "byte2", "byte3", "byte4", "byte8", "byte16", "ubyte2", "ubyte3", "ubyte4", "ubyte8", "ubyte16", "short2", "short3", "short4", "short8", "ushort2", "ushort3", "ushort4", "ushort8", "half2", "half3", "half4", "half8"}

//! A file stem as an identifier: every other character an underscore, a leading digit kept
//! behind one, since `00099__f` is not a name.
def ident_of(name : string) : string {
    let ident = build_string() $(var w) {
        for (ch in name) {
            w |> write(is_alnum(ch) ? to_char(ch) : "_")
        }
    }
    return !empty(ident) && is_number(first_character(ident)) ? "_" + ident : ident
}

//! `want` when no name of `taken` is it, else `want` with the first free number appended; the
//! name is then taken.
def free_name(var taken : table<string>; want : string) : string {
    var name = want
    var n = 1
    while (key_exists(taken, name)) {
        name = "{want}{n}"
        n++
    }
    taken |> insert(name)
    return name
}

//! Frees a node and everything under it: the generated finalizer of a struct already recurses
//! through its pointer fields and its arrays of pointers, so one `delete` is the whole walk and
//! a hand-written walk would free every child twice.
def delete_expr(var x : CirExpr?) {
    unsafe {
        delete x
    }
}

def delete_stmt(var x : CirStmt?) {
    unsafe {
        delete x
    }
}

def delete_decl(var d : CirDecl?) {
    unsafe {
        delete d
    }
}

def delete_tu(var tu : CirTu) {
    unsafe {
        delete tu.decls
    }
}

// canonical writer: one member per line at one space per depth, scalar arrays on one line

// fragments, joined once at the end: a string appended in place would copy the whole text
// into a fresh allocation on every member
struct private Writer {
    out : array<string>
    depth : int
}

def private indent(var w : Writer) {
    w.out |> push(repeat(" ", w.depth))
}

def private json_str(s : string) : string => write_json(JV(s))

def private open_object(var w : Writer) {
    w.out |> push("\{\n")
    w.depth++
}

def private close_object(var w : Writer) {
    w.depth--
    w.out |> push("\n")
    indent(w)
    w.out |> push("\}")
}

def private member(var w : Writer; key : string; first : bool) {
    if (!first) {
        w.out |> push(",\n")
    }
    indent(w)
    w.out |> push("{json_str(key)}: ")
}

def private write_int_array(var w : Writer; arr : array<int>) {
    w.out |> push("[" + join([for (x in arr); "{x}"], ", ") + "]")
}

def private write_type(var w : Writer; t : CirType) {
    open_object(w)
    member(w, "k", true)
    w.out |> push(json_str(t.k))
    if (t.k == "int") {
        member(w, "w", false)
        w.out |> push("{t.w}")
        member(w, "signed", false)
        w.out |> push("{t.is_signed}")
        member(w, "spell", false)
        w.out |> push(json_str(t.spell))
    } elif (t.k == "float") {
        member(w, "w", false)
        w.out |> push("{t.w}")
        member(w, "spell", false)
        w.out |> push(json_str(t.spell))
    } elif (t.k == "ptr") {
        member(w, "to", false)
        w.out |> push("{t.to}")
    } elif (t.k == "array") {
        member(w, "elem", false)
        w.out |> push("{t.elem}")
        member(w, "count", false)
        w.out |> push("{t.count}")
    } elif (t.k == "func") {
        member(w, "ret", false)
        w.out |> push("{t.ret}")
        member(w, "params", false)
        write_int_array(w, t.params)
        member(w, "variadic", false)
        w.out |> push("{t.variadic}")
    } elif (t.k == "struct" || t.k == "union") {
        member(w, "name", false)
        w.out |> push(json_str(t.name))
        member(w, "size", false)
        w.out |> push("{t.size}")
        member(w, "align", false)
        w.out |> push("{t.align}")
        member(w, "packed", false)
        w.out |> push("{t.packed}")
        member(w, "fields", false)
        write_fields(w, t.fields)
    } elif (t.k == "enum") {
        member(w, "name", false)
        w.out |> push(json_str(t.name))
        member(w, "spell", false)
        w.out |> push(json_str(t.spell))
        member(w, "items", false)
        write_enum_items(w, t.items)
        if (!t.is_signed) {
            member(w, "signed", false)
            w.out |> push("false")
        }
    } elif (t.k == "typedef") {
        member(w, "name", false)
        w.out |> push(json_str(t.name))
        member(w, "to", false)
        w.out |> push("{t.to}")
    }
    close_object(w)
}

def private write_fields(var w : Writer; fields : array<CirField>) {
    if (empty(fields)) {
        w.out |> push("[]")
        return
    }
    w.out |> push("[\n")
    w.depth++
    w.out |> reserve(length(w.out) + 16 * length(fields))
    var first = true
    for (f in fields) {
        if (!first) {
            w.out |> push(",\n")
        }
        first = false
        indent(w)
        open_object(w)
        member(w, "name", true)
        w.out |> push(json_str(f.name))
        member(w, "t", false)
        w.out |> push("{f.t}")
        member(w, "off", false)
        w.out |> push("{f.off}")
        if (f.is_bitfield) {
            member(w, "bit_off", false)
            w.out |> push("{f.bit_off}")
            member(w, "bit_w", false)
            w.out |> push("{f.bit_w}")
        }
        write_dims(w, f.dims)
        close_object(w)
    }
    w.depth--
    w.out |> push("\n")
    indent(w)
    w.out |> push("]")
}

// the `dims` member, present only on a declarator whose dimensions name enum constants
def private write_dims(var w : Writer; dims : array<CirDim>) {
    if (empty(dims)) {
        return
    }
    member(w, "dims", false)
    w.out |> push("[\n")
    w.depth++
    w.out |> reserve(length(w.out) + 8 * length(dims))
    var first = true
    for (dim in dims) {
        if (!first) {
            w.out |> push(",\n")
        }
        first = false
        indent(w)
        open_object(w)
        member(w, "enum_t", true)
        w.out |> push("{dim.enum_t}")
        member(w, "item", false)
        w.out |> push(json_str(dim.item))
        close_object(w)
    }
    w.depth--
    w.out |> push("\n")
    indent(w)
    w.out |> push("]")
}

def private write_enum_items(var w : Writer; items : array<CirEnumItem>) {
    if (empty(items)) {
        w.out |> push("[]")
        return
    }
    w.out |> push("[\n")
    w.depth++
    w.out |> reserve(length(w.out) + 8 * length(items))
    var first = true
    for (it in items) {
        if (!first) {
            w.out |> push(",\n")
        }
        first = false
        indent(w)
        open_object(w)
        member(w, "name", true)
        w.out |> push(json_str(it.name))
        member(w, "v", false)
        w.out |> push("{it.v}")
        close_object(w)
    }
    w.depth--
    w.out |> push("\n")
    indent(w)
    w.out |> push("]")
}

def private write_loc(var w : Writer; loc : CirLoc) {
    open_object(w)
    member(w, "file", true)
    w.out |> push(json_str(loc.file))
    member(w, "line", false)
    w.out |> push("{loc.line}")
    member(w, "col", false)
    w.out |> push("{loc.col}")
    close_object(w)
}

def private write_expr_or_null(var w : Writer; x : CirExpr?) {
    if (x == null) {
        w.out |> push("null")
    } else {
        write_expr(w, *x)
    }
}

def private write_expr_array(var w : Writer; xs : array<CirExpr?>) {
    if (empty(xs)) {
        w.out |> push("[]")
        return
    }
    w.out |> push("[\n")
    w.depth++
    w.out |> reserve(length(w.out) + 3 * length(xs))
    var first = true
    for (x in xs) {
        if (!first) {
            w.out |> push(",\n")
        }
        first = false
        indent(w)
        write_expr_or_null(w, x)
    }
    w.depth--
    w.out |> push("\n")
    indent(w)
    w.out |> push("]")
}

def private write_expr_composite(var w : Writer; x : CirExpr) {
    if (x.e == "call") {
        member(w, "fn", false)
        write_expr_or_null(w, x.fn)
        member(w, "args", false)
        write_expr_array(w, x.args)
    } elif (x.e == "member") {
        member(w, "base", false)
        write_expr_or_null(w, x.base)
        member(w, "field", false)
        w.out |> push("{x.field}")
        member(w, "arrow", false)
        w.out |> push("{x.arrow}")
    } elif (x.e == "index") {
        member(w, "base", false)
        write_expr_or_null(w, x.base)
        member(w, "i", false)
        write_expr_or_null(w, x.i)
    } elif (x.e == "cast") {
        member(w, "kind", false)
        w.out |> push(json_str(x.cast_kind))
        member(w, "explicit", false)
        w.out |> push("{x.explicit_cast}")
        member(w, "a", false)
        write_expr_or_null(w, x.a)
    } elif (x.e == "init_list") {
        member(w, "items", false)
        write_init_items(w, x.init_items)
    } elif (x.e == "sizeof_v" || x.e == "alignof_v") {
        member(w, "v", false)
        w.out |> push("{int64(x.trait_v)}")
        member(w, "of_t", false)
        w.out |> push("{x.of_t}")
    } elif (x.e == "offsetof") {
        member(w, "of_t", false)
        w.out |> push("{x.of_t}")
        member(w, "field", false)
        w.out |> push("{x.field}")
    } elif (x.e == "va_arg") {
        member(w, "list", false)
        write_expr_or_null(w, x.list)
        member(w, "arg_t", false)
        w.out |> push("{x.arg_t}")
    } elif (x.e == "compound_lit") {
        member(w, "init", false)
        write_expr_or_null(w, x.init)
    }
}

def private write_expr(var w : Writer; x : CirExpr) {
    open_object(w)
    member(w, "e", true)
    w.out |> push(json_str(x.e))
    member(w, "t", false)
    w.out |> push("{x.t}")
    if (x.e == "int_lit" || x.e == "float_lit") {
        member(w, "v", false)
        w.out |> push(json_str(x.v))
    } elif (x.e == "str_lit") {
        member(w, "bytes", false)
        w.out |> push("[" + join([for (bt in x.bytes); "{int(bt)}"], ", ") + "]")
    } elif (x.e == "ref") {
        member(w, "name", false)
        w.out |> push(json_str(x.name))
    } elif (x.e == "enum_ref") {
        member(w, "enum_t", false)
        w.out |> push("{x.enum_t}")
        member(w, "item", false)
        w.out |> push(json_str(x.item))
    } elif (x.e == "un") {
        member(w, "op", false)
        w.out |> push(json_str(x.op))
        member(w, "a", false)
        write_expr_or_null(w, x.a)
    } elif (x.e == "bin") {
        member(w, "op", false)
        w.out |> push(json_str(x.op))
        member(w, "a", false)
        write_expr_or_null(w, x.a)
        member(w, "b", false)
        write_expr_or_null(w, x.b)
    } elif (x.e == "assign") {
        member(w, "op", false)
        w.out |> push(json_str(x.op))
        member(w, "lhs", false)
        write_expr_or_null(w, x.a)
        member(w, "rhs", false)
        write_expr_or_null(w, x.b)
    } elif (x.e == "cond") {
        member(w, "c", false)
        write_expr_or_null(w, x.c)
        member(w, "a", false)
        write_expr_or_null(w, x.a)
        member(w, "b", false)
        write_expr_or_null(w, x.b)
    } elif (x.e == "comma") {
        member(w, "a", false)
        write_expr_or_null(w, x.a)
        member(w, "b", false)
        write_expr_or_null(w, x.b)
    } else {
        write_expr_composite(w, x)
    }
    if (x.vol) {
        member(w, "vol", false)
        w.out |> push("true")
    }
    if (x.is_char) {
        member(w, "char", false)
        w.out |> push("true")
    }
    if (x.paren) {
        member(w, "paren", false)
        w.out |> push("true")
    }
    if (!empty(x.macro)) {
        member(w, "macro", false)
        w.out |> push(json_str(x.macro))
    }
    close_object(w)
}

def private write_init_items(var w : Writer; items : array<CirInitItem>) {
    if (empty(items)) {
        w.out |> push("[]")
        return
    }
    w.out |> push("[\n")
    w.depth++
    w.out |> reserve(length(w.out) + 8 * length(items))
    var first = true
    for (it in items) {
        if (!first) {
            w.out |> push(",\n")
        }
        first = false
        indent(w)
        open_object(w)
        member(w, "pos", true)
        w.out |> push("{it.pos}")
        member(w, "v", false)
        write_expr_or_null(w, it.v)
        close_object(w)
    }
    w.depth--
    w.out |> push("\n")
    indent(w)
    w.out |> push("]")
}

def private write_stmt_or_null(var w : Writer; x : CirStmt?) {
    if (x == null) {
        w.out |> push("null")
    } else {
        write_stmt(w, *x)
    }
}

def private write_stmt_array(var w : Writer; xs : array<CirStmt?>) {
    if (empty(xs)) {
        w.out |> push("[]")
        return
    }
    w.out |> push("[\n")
    w.depth++
    w.out |> reserve(length(w.out) + 3 * length(xs))
    var first = true
    for (x in xs) {
        if (!first) {
            w.out |> push(",\n")
        }
        first = false
        indent(w)
        write_stmt_or_null(w, x)
    }
    w.depth--
    w.out |> push("\n")
    indent(w)
    w.out |> push("]")
}

def private write_stmt(var w : Writer; x : CirStmt) {
    open_object(w)
    member(w, "s", true)
    w.out |> push(json_str(x.s))
    if (x.s == "compound") {
        member(w, "body", false)
        write_stmt_array(w, x.body)
    } elif (x.s == "decl") {
        member(w, "name", false)
        w.out |> push(json_str(x.name))
        member(w, "t", false)
        w.out |> push("{x.t}")
        member(w, "init", false)
        write_expr_or_null(w, x.init)
        write_dims(w, x.dims)
    } elif (x.s == "expr") {
        member(w, "e", false)
        write_expr_or_null(w, x.e)
    } elif (x.s == "if") {
        member(w, "cond", false)
        write_expr_or_null(w, x.cond)
        member(w, "then", false)
        write_stmt_or_null(w, x.then_s)
        member(w, "else", false)
        write_stmt_or_null(w, x.else_s)
    } elif (x.s == "while") {
        member(w, "cond", false)
        write_expr_or_null(w, x.cond)
        member(w, "body", false)
        write_stmt_or_null(w, x.body_s)
    } elif (x.s == "do") {
        member(w, "body", false)
        write_stmt_or_null(w, x.body_s)
        member(w, "cond", false)
        write_expr_or_null(w, x.cond)
    } elif (x.s == "for") {
        member(w, "init", false)
        write_stmt_or_null(w, x.init_s)
        member(w, "cond", false)
        write_expr_or_null(w, x.cond)
        member(w, "inc", false)
        write_expr_or_null(w, x.inc)
        member(w, "body", false)
        write_stmt_or_null(w, x.body_s)
    } elif (x.s == "switch") {
        member(w, "cond", false)
        write_expr_or_null(w, x.cond)
        member(w, "body", false)
        write_stmt_or_null(w, x.body_s)
    } elif (x.s == "case") {
        member(w, "v", false)
        w.out |> push("{x.v}")
        if (x.is_char) {
            member(w, "char", false)
            w.out |> push("true")
        }
    } elif (x.s == "return") {
        member(w, "e", false)
        write_expr_or_null(w, x.e)
    } elif (x.s == "goto" || x.s == "label") {
        member(w, x.s == "goto" ? "label" : "name", false)
        w.out |> push(json_str(x.label_name))
    }
    member(w, "loc", false)
    write_loc(w, x.loc)
    close_object(w)
}

def private write_decl(var w : Writer; d : CirDecl) {
    open_object(w)
    member(w, "k", true)
    w.out |> push(json_str(d.k))
    if (d.k == "global") {
        member(w, "name", false)
        w.out |> push(json_str(d.name))
        member(w, "c_name", false)
        w.out |> push(json_str(d.c_name))
        member(w, "t", false)
        w.out |> push("{d.t}")
        member(w, "static", false)
        w.out |> push("{d.is_static}")
        member(w, "extern", false)
        w.out |> push("{d.is_extern}")
        member(w, "init", false)
        write_expr_or_null(w, d.init)
        write_dims(w, d.dims)
        if (!empty(d.from_func)) {
            member(w, "from_func", false)
            w.out |> push(json_str(d.from_func))
        }
    } elif (d.k == "func") {
        member(w, "name", false)
        w.out |> push(json_str(d.name))
        member(w, "c_name", false)
        w.out |> push(json_str(d.c_name))
        member(w, "t", false)
        w.out |> push("{d.t}")
        member(w, "static", false)
        w.out |> push("{d.is_static}")
        member(w, "params", false)
        write_params(w, d.params)
        member(w, "body", false)
        write_stmt_or_null(w, d.body)
    } else {
        member(w, "t", false)
        w.out |> push("{d.t}")
    }
    member(w, "loc", false)
    write_loc(w, d.loc)
    close_object(w)
}

def private write_params(var w : Writer; params : array<CirParam>) {
    if (empty(params)) {
        w.out |> push("[]")
        return
    }
    w.out |> push("[\n")
    w.depth++
    w.out |> reserve(length(w.out) + 8 * length(params))
    var first = true
    for (p in params) {
        if (!first) {
            w.out |> push(",\n")
        }
        first = false
        indent(w)
        open_object(w)
        member(w, "name", true)
        w.out |> push(json_str(p.name))
        member(w, "t", false)
        w.out |> push("{p.t}")
        close_object(w)
    }
    w.depth--
    w.out |> push("\n")
    indent(w)
    w.out |> push("]")
}

def private write_target(var w : Writer; target : CirTarget) {
    open_object(w)
    member(w, "triple", true)
    w.out |> push(json_str(target.triple))
    member(w, "int", false)
    w.out |> push("{target.int_w}")
    member(w, "long", false)
    w.out |> push("{target.long_w}")
    member(w, "llong", false)
    w.out |> push("{target.llong_w}")
    member(w, "ptr", false)
    w.out |> push("{target.ptr_w}")
    member(w, "char_signed", false)
    w.out |> push("{target.char_signed}")
    close_object(w)
}

//! The canonical bytes of one declaration, as `write_cir` spells it at depth 0: two declarations
//! with these bytes equal are the same declaration.
def write_cir_decl(d : CirDecl) : string {
    var w : Writer
    write_decl(w, d)
    return join(w.out, "")
}

//! The canonical bytes of a program manifest (docs/c-ir-spec.md section 7): the version, the
//! dialect, the C-IR files of the units in link order and the entry point.
def write_program(target : CirTarget; tus : array<string>; entry : string) : string {
    var w : Writer
    open_object(w)
    member(w, "cir", true)
    w.out |> push(json_str(CIR_VERSION))
    member(w, "target", false)
    write_target(w, target)
    member(w, "tus", false)
    w.out |> push("[" + join([for (name in tus); json_str(name)], ", ") + "]")
    member(w, "entry", false)
    w.out |> push(json_str(entry))
    close_object(w)
    w.out |> push("\n")
    return join(w.out, "")
}

//! The canonical bytes of a TU (docs/c-ir-spec.md section 8): every key in spec order, one
//! member per line at one space per depth, scalar arrays on one line, LF, a final LF.
def write_cir(tu : CirTu) : string {
    var w : Writer
    open_object(w)
    member(w, "cir", true)
    w.out |> push(json_str(tu.cir))
    member(w, "producer", false)
    w.out |> push(json_str(tu.producer))
    member(w, "target", false)
    write_target(w, tu.target)
    member(w, "tu", false)
    w.out |> push(json_str(tu.tu))
    member(w, "types", false)
    if (empty(tu.types)) {
        w.out |> push("[]")
    } else {
        w.out |> push("[\n")
        w.depth++
        w.out |> reserve(length(w.out) + 16 * length(tu.types))
        var first = true
        for (t in tu.types) {
            if (!first) {
                w.out |> push(",\n")
            }
            first = false
            indent(w)
            write_type(w, t)
        }
        w.depth--
        w.out |> push("\n")
        indent(w)
        w.out |> push("]")
    }
    member(w, "decls", false)
    if (empty(tu.decls)) {
        w.out |> push("[]")
    } else {
        w.out |> push("[\n")
        w.depth++
        w.out |> reserve(length(w.out) + 64 * length(tu.decls))
        var first = true
        for (d in tu.decls) {
            if (!first) {
                w.out |> push(",\n")
            }
            first = false
            indent(w)
            write_decl(w, *d)
        }
        w.depth--
        w.out |> push("\n")
        indent(w)
        w.out |> push("]")
    }
    close_object(w)
    w.out |> push("\n")
    return join(w.out, "")
}

// reader

def private js_int(js : JsonValue?; key : string) : int => int(js?[key] ?? 0l)

def private js_str(js : JsonValue?; key : string) : string => js?[key] ?? ""

def private js_bool(js : JsonValue?; key : string) : bool => js?[key] ?? false

def private read_loc(js : JsonValue?) : CirLoc =>
    CirLoc(file = js_str(js, "file"), line = js_int(js, "line"), col = js_int(js, "col"))

def private read_dims(js : JsonValue?) : array<CirDim> {
    var dims : array<CirDim>
    if (js != null && js is _array) {
        dims |> reserve(length(js as _array))
        for (dim in js as _array) {
            dims |> push(CirDim(enum_t = js_int(dim, "enum_t"), item = js_str(dim, "item")))
        }
    }
    return <- dims
}

def private read_type(js : JsonValue?) : CirType {
    var t = CirType(k = js_str(js, "k"))
    if (t.k == "int") {
        t.w = js_int(js, "w")
        t.is_signed = js_bool(js, "signed")
        t.spell = js_str(js, "spell")
    } elif (t.k == "float") {
        t.w = js_int(js, "w")
        t.spell = js_str(js, "spell")
    } elif (t.k == "ptr") {
        t.to = js_int(js, "to")
    } elif (t.k == "array") {
        t.elem = js_int(js, "elem")
        t.count = js_int(js, "count")
    } elif (t.k == "func") {
        t.ret = js_int(js, "ret")
        let params = js?["params"]
        if (params != null && params is _array) {
            t.params |> reserve(length(params as _array))
            for (p in params as _array) {
                t.params |> push(int(p ?? 0l))
            }
        }
        t.variadic = js_bool(js, "variadic")
    } elif (t.k == "struct" || t.k == "union") {
        t.name = js_str(js, "name")
        t.size = js_int(js, "size")
        t.align = js_int(js, "align")
        t.packed = js_bool(js, "packed")
        let fields = js?["fields"]
        if (fields != null && fields is _array) {
            t.fields |> reserve(length(fields as _array))
            for (f in fields as _array) {
                let bw = f?["bit_w"]
                let is_bf = bw != null && !(bw is _null)
                var fld = CirField(name = js_str(f, "name"), t = js_int(f, "t"), off = js_int(f, "off"), bit_off = js_int(f, "bit_off"), bit_w = js_int(f, "bit_w"), is_bitfield = is_bf)
                fld.dims <- read_dims(f?["dims"])
                t.fields |> emplace(fld)
            }
        }
    } elif (t.k == "enum") {
        t.name = js_str(js, "name")
        t.spell = js_str(js, "spell")
        let items = js?["items"]
        if (items != null && items is _array) {
            t.items |> reserve(length(items as _array))
            for (it in items as _array) {
                t.items |> push(CirEnumItem(name = js_str(it, "name"), v = it?["v"] ?? 0l))
            }
        }
        t.is_signed = js?["signed"] ?? true
    } elif (t.k == "typedef") {
        t.name = js_str(js, "name")
        t.to = js_int(js, "to")
    }
    return <- t
}

def private read_expr_composite(js : JsonValue?; var x : CirExpr?) {
    if (x.e == "call") {
        x.fn = read_expr(js?["fn"])
        let args = js?["args"]
        if (args != null && args is _array) {
            x.args |> reserve(length(args as _array))
            for (arg in args as _array) {
                x.args |> push(read_expr(arg))
            }
        }
    } elif (x.e == "member") {
        x.base = read_expr(js?["base"])
        x.field = js_int(js, "field")
        x.arrow = js_bool(js, "arrow")
    } elif (x.e == "index") {
        x.base = read_expr(js?["base"])
        x.i = read_expr(js?["i"])
    } elif (x.e == "cast") {
        x.cast_kind = js_str(js, "kind")
        x.explicit_cast = js_bool(js, "explicit")
        x.a = read_expr(js?["a"])
    } elif (x.e == "init_list") {
        let items = js?["items"]
        if (items != null && items is _array) {
            x.init_items |> reserve(length(items as _array))
            for (it in items as _array) {
                x.init_items |> push(CirInitItem(pos = js_int(it, "pos"), v = read_expr(it?["v"])))
            }
        }
    } elif (x.e == "sizeof_v" || x.e == "alignof_v") {
        x.trait_v = uint64(js?["v"] ?? 0l)
        x.of_t = js_int(js, "of_t")
    } elif (x.e == "offsetof") {
        x.of_t = js_int(js, "of_t")
        x.field = js_int(js, "field")
    } elif (x.e == "va_arg") {
        x.list = read_expr(js?["list"])
        x.arg_t = js_int(js, "arg_t")
    } elif (x.e == "compound_lit") {
        x.init = read_expr(js?["init"])
    }
}

def private read_expr(js : JsonValue?) : CirExpr? {
    if (js == null || js is _null) {
        return null
    }
    var x = new CirExpr(e = js_str(js, "e"), t = js_int(js, "t"))
    if (x.e == "int_lit" || x.e == "float_lit") {
        x.v = js_str(js, "v")
    } elif (x.e == "str_lit") {
        let bytes = js?["bytes"]
        if (bytes != null && bytes is _array) {
            x.bytes |> reserve(length(bytes as _array))
            for (bt in bytes as _array) {
                x.bytes |> push(uint8(bt ?? 0l))
            }
        }
    } elif (x.e == "ref") {
        x.name = js_str(js, "name")
    } elif (x.e == "enum_ref") {
        x.enum_t = js_int(js, "enum_t")
        x.item = js_str(js, "item")
    } elif (x.e == "un") {
        x.op = js_str(js, "op")
        x.a = read_expr(js?["a"])
    } elif (x.e == "bin") {
        x.op = js_str(js, "op")
        x.a = read_expr(js?["a"])
        x.b = read_expr(js?["b"])
    } elif (x.e == "assign") {
        x.op = js_str(js, "op")
        x.a = read_expr(js?["lhs"])
        x.b = read_expr(js?["rhs"])
    } elif (x.e == "cond") {
        x.c = read_expr(js?["c"])
        x.a = read_expr(js?["a"])
        x.b = read_expr(js?["b"])
    } elif (x.e == "comma") {
        x.a = read_expr(js?["a"])
        x.b = read_expr(js?["b"])
    } else {
        read_expr_composite(js, x)
    }
    x.vol = js_bool(js, "vol")
    x.is_char = js_bool(js, "char")
    x.paren = js_bool(js, "paren")
    x.macro = js_str(js, "macro")
    return x
}

def private read_stmt(js : JsonValue?) : CirStmt? {
    if (js == null || js is _null) {
        return null
    }
    var x = new CirStmt(s = js_str(js, "s"))
    if (x.s == "compound") {
        let body = js?["body"]
        if (body != null && body is _array) {
            x.body |> reserve(length(body as _array))
            for (child in body as _array) {
                x.body |> push(read_stmt(child))
            }
        }
    } elif (x.s == "decl") {
        x.name = js_str(js, "name")
        x.t = js_int(js, "t")
        x.init = read_expr(js?["init"])
        x.dims <- read_dims(js?["dims"])
    } elif (x.s == "expr") {
        x.e = read_expr(js?["e"])
    } elif (x.s == "if") {
        x.cond = read_expr(js?["cond"])
        x.then_s = read_stmt(js?["then"])
        x.else_s = read_stmt(js?["else"])
    } elif (x.s == "while" || x.s == "do" || x.s == "switch") {
        x.cond = read_expr(js?["cond"])
        x.body_s = read_stmt(js?["body"])
    } elif (x.s == "for") {
        x.init_s = read_stmt(js?["init"])
        x.cond = read_expr(js?["cond"])
        x.inc = read_expr(js?["inc"])
        x.body_s = read_stmt(js?["body"])
    } elif (x.s == "case") {
        x.v = js?["v"] ?? 0l
        x.is_char = js_bool(js, "char")
    } elif (x.s == "return") {
        x.e = read_expr(js?["e"])
    } elif (x.s == "goto") {
        x.label_name = js_str(js, "label")
    } elif (x.s == "label") {
        x.label_name = js_str(js, "name")
    }
    x.loc = read_loc(js?["loc"])
    return x
}

def private read_decl(js : JsonValue?) : CirDecl? {
    var d = new CirDecl(k = js_str(js, "k"), t = js_int(js, "t"))
    if (d.k == "global") {
        d.name = js_str(js, "name")
        d.c_name = js_str(js, "c_name")
        d.is_static = js_bool(js, "static")
        d.is_extern = js_bool(js, "extern")
        d.init = read_expr(js?["init"])
        d.dims <- read_dims(js?["dims"])
        d.from_func = js_str(js, "from_func")
    } elif (d.k == "func") {
        d.name = js_str(js, "name")
        d.c_name = js_str(js, "c_name")
        d.is_static = js_bool(js, "static")
        let params = js?["params"]
        if (params != null && params is _array) {
            d.params |> reserve(length(params as _array))
            for (p in params as _array) {
                d.params |> push(CirParam(name = js_str(p, "name"), t = js_int(p, "t")))
            }
        }
        d.body = read_stmt(js?["body"])
    }
    d.loc = read_loc(js?["loc"])
    return d
}

//! Parses canonical or any other JSON spelling of a TU; `error` is set and the result empty
//! when the text is not JSON or not this version of the format.
def read_cir(text : string; var error : string&) : CirTu {
    var tu : CirTu
    var js = read_json(text, error)
    if (js == null) {
        return <- tu
    }
    tu.cir = js_str(js, "cir")
    if (tu.cir != CIR_VERSION) {
        error = "c-ir version {tu.cir}, expected {CIR_VERSION}"
        delete_json(js)
        return <- tu
    }
    tu.producer = js_str(js, "producer")
    let tg = js?["target"]
    tu.target = CirTarget(triple = js_str(tg, "triple"), int_w = js_int(tg, "int"), long_w = js_int(tg, "long"), llong_w = js_int(tg, "llong"), ptr_w = js_int(tg, "ptr"), char_signed = js_bool(tg, "char_signed"))
    tu.tu = js_str(js, "tu")
    let types = js?["types"]
    if (types != null && types is _array) {
        tu.types |> reserve(length(types as _array))
        for (t in types as _array) {
            tu.types |> emplace(read_type(t))
        }
    }
    let decls = js?["decls"]
    if (decls != null && decls is _array) {
        tu.decls |> reserve(length(decls as _array))
        for (d in decls as _array) {
            tu.decls |> push(read_decl(d))
        }
    }
    delete_json(js)
    return <- tu
}
