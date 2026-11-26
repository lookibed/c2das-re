options gen2
options indenting = 4

module c_types public

require strings
require daslib/strings_boost
require c_parser public
require ../converter/cir.das public

//! The C-IR type table of one unit as Dumper A interns it: each type once, by a structural key,
//! in the order its first use reaches it; the typedef names in scope, each bound to the type it
//! names; and the first error, `file:line:col: what`.
struct CTypes {
    tu : CirTu
    index : table<string; int>
    typedefs : table<int; int>                  //!< a typedef name's symbol to the type it names
    undo : array<tuple<sym : int; was : int>>   //!< the bindings a block's end restores
    marks : array<int>
    declared : table<int; bool>                 //!< the function names declared so far
    library_dir : string                        //!< the own libc headers' folder, whose declarations add no type
    err : string
}

//! Open the builder over the dialect `target`, with an empty table; a declaration in a file under
//! `library_dir`, the own libc headers' folder, adds no type, as Dumper A dumps none of them.
def c_types_open(var b : CTypes; target : CirTarget; library_dir : string) {
    b.tu.target = target
    b.library_dir = library_dir
    b.tu.types |> clear()
    b.index |> clear()
    b.typedefs |> clear()
    b.undo |> clear()
    b.marks |> clear()
    b.declared |> clear()
    b.err = ""
}

// the first error, at token `tok`: a construct the builder does not type yet
def private refuse(var b : CTypes; var p : CParser; tok : int; what : string) {
    if (empty(b.err)) {
        b.err = "{c_where(p.unit, tok)}: {what} is not typed yet"
    }
}

// type `t` under key `key`: the index it has, or the next one
def private intern(var b : CTypes; key : string; var t : CirType) : int {
    let known = b.index?[key] ?? -1
    return known if (known >= 0)
    let idx = length(b.tu.types)
    b.tu.types |> emplace(t)
    b.index[key] = idx
    return idx
}

def private int_type(var b : CTypes; w : int; is_signed : bool; spell : string) : int {
    var t = CirType(k = "int", w = w, is_signed = is_signed, spell = spell)
    return intern(b, "int:{w}:{is_signed}:{spell}", t)
}

def private pointer(var b : CTypes; to : int) : int {
    var t = CirType(k = "ptr", to = to)
    return intern(b, "ptr:{to}", t)
}

def private array_of(var b : CTypes; elem, count : int) : int {
    var t = CirType(k = "array", elem = elem, count = count)
    return intern(b, "array:{elem}:{count}", t)
}

// the function type returning `ret` with the adjusted parameter types `params`
def private function_of(var b : CTypes; ret : int; var params : array<int>; variadic : bool) : int {
    let key = "func:{ret}:{join([for (x in params); "{x}"], ",")}:{variadic}"
    var t = CirType(k = "func", ret = ret, variadic = variadic)
    t.params <- params
    return intern(b, key, t)
}

//! The bit of each builtin type keyword in a specifier set, by its kind's place after `void`.
def private bit(k : CTok) : int => 1 << (int(k) - int(CTok.VOID))

//! The builtin specifier sets and the type each one is, as clang spells it: `w` -1 for `int`,
//! -2 for `long`, -3 for `long long`, -4 for plain `char`, the dialect's widths.
let private BUILTINS <- [
    (set = bit(CTok.VOID), k = "void", w = 0, sign = false, spell = "void"),
    (set = bit(CTok.BOOL), k = "int", w = 8, sign = false, spell = "_Bool"),
    (set = bit(CTok.CHAR), k = "int", w = -4, sign = false, spell = "char"),
    (set = bit(CTok.CHAR) | bit(CTok.SIGNED), k = "int", w = 8, sign = true, spell = "signed char"),
    (set = bit(CTok.CHAR) | bit(CTok.UNSIGNED), k = "int", w = 8, sign = false, spell = "unsigned char"),
    (set = bit(CTok.SHORT), k = "int", w = 16, sign = true, spell = "short"),
    (set = bit(CTok.INT), k = "int", w = -1, sign = true, spell = "int"),
    (set = bit(CTok.LONG), k = "int", w = -2, sign = true, spell = "long"),
    (set = bit(CTok.LONG) | (1 << 12), k = "int", w = -3, sign = true, spell = "long long"),
    (set = bit(CTok.FLOAT), k = "float", w = 32, sign = false, spell = "float"),
    (set = bit(CTok.DOUBLE), k = "float", w = 64, sign = false, spell = "double"),
    (set = bit(CTok.LONG) | bit(CTok.DOUBLE), k = "float", w = 64, sign = false, spell = "long double")]

// the type of builtin specifier set `set` (a second `long` bit 12), -1 for no builtin type: `int`
// and the signs fold into the set they qualify, an unsigned one adding `unsigned ` to the spelling
def private builtin_type(var b : CTypes; set : int) : int {
    let unsigned_bit = bit(CTok.UNSIGNED)
    let has_unsigned = (set & unsigned_bit) != 0
    var core = set & ~bit(CTok.SIGNED) & ~bit(CTok.INT) & ~unsigned_bit
    if (core == 0) {
        core = bit(CTok.INT)
    }
    if (core == bit(CTok.CHAR)) {
        core = set & ~bit(CTok.INT)
    }
    for (entry in BUILTINS) {
        continue if (entry.set != core)
        if (entry.k == "void") {
            var t = CirType(k = "void")
            return intern(b, "void", t)
        } elif (entry.k == "float") {
            var t = CirType(k = "float", w = entry.w, spell = entry.spell)
            return intern(b, entry.w == 32 ? "float:32" : "float:64:{entry.spell}", t)
        }
        let target = b.tu.target
        let w = entry.w == -1 ? target.int_w : entry.w == -2 ? target.long_w : entry.w == -3 ? target.llong_w : entry.w == -4 ? 8 : entry.w
        let sign = entry.w == -4 ? target.char_signed : entry.sign && !has_unsigned
        let spell = has_unsigned && entry.w != 8 && entry.w != -4 ? "unsigned {entry.spell}" : entry.spell
        return int_type(b, w, sign, spell)
    }
    return -1
}

// whether attribute node `n` names an attribute that changes the type it qualifies
def private type_attribute(var p : CParser; n : int) : bool {
    for (t in range(p.ast.nodes[n].a, p.ast.nodes[n].b + 1)) {
        let word = c_spelling(p.unit, t)
        return true if (word == "mode" || word == "__mode__" || word == "vector_size" || word == "__vector_size__" || word == "ext_vector_type")
    }
    return false
}

//! The type a list of declaration specifiers names, interned; -1 with the error set for one the
//! builder does not type yet. Qualifiers and storage classes give no C-IR type.
[arch(at="ARCHITECTURE_TYPES.md#c-types-specifiers")]
def c_specifier_type(var b : CTypes; var p : CParser; specs : int) : int {
    var set = 0
    var named = -1
    var at = specs
    while (at >= 0) {
        let n = p.ast.nodes[at]
        if (n.kind == CNode.SPEC_KEYWORD) {
            let k = n.op
            if (k == int(CTok.COMPLEX)) {
                refuse(b, p, n.tok, "a complex type")
                return -1
            } elif (k == int(CTok.ATOMIC)) {
                refuse(b, p, n.tok, "an _Atomic type")
                return -1
            } elif (k >= int(CTok.VOID) && k <= int(CTok.COMPLEX)) {
                set |= k == int(CTok.LONG) && (set & bit(CTok.LONG)) != 0 ? 1 << 12 : 1 << (k - int(CTok.VOID))
            }
        } elif (n.kind == CNode.SPEC_TYPEDEF_NAME) {
            named = b.typedefs?[n.a] ?? -1
            if (named < 0) {
                refuse(b, p, n.tok, "the typedef name '{pp_symbol_text(p.unit.lx, n.a)}'")
                return -1
            }
        } elif (n.kind == CNode.SPEC_TYPEOF_TYPE) {
            named = c_type_name_type(b, p, n.a)
            return -1 if (named < 0)
        } elif (n.kind == CNode.SPEC_RECORD) {
            refuse(b, p, n.tok, "a {c_kind_name(n.op)} type")
            return -1
        } elif (n.kind == CNode.SPEC_ENUM) {
            refuse(b, p, n.tok, "an enum type")
            return -1
        } elif (n.kind == CNode.SPEC_TYPEOF_EXPR) {
            refuse(b, p, n.tok, "typeof of an expression")
            return -1
        } elif (n.kind == CNode.SPEC_ALIGNAS_EXPR || n.kind == CNode.SPEC_ALIGNAS_TYPE) {
            refuse(b, p, n.tok, "an _Alignas alignment")
            return -1
        } elif (n.kind == CNode.ATTRIBUTE && type_attribute(p, at)) {
            refuse(b, p, n.tok, "an attribute that changes a type")
            return -1
        }
        at = n.next
    }
    return named if (named >= 0)
    let t = builtin_type(b, set)
    if (t < 0) {
        refuse(b, p, p.ast.nodes[specs].tok, "this specifier list")
    }
    return t
}

// the end of a declarator: none, its name, or parentheses around one
def private is_end(var p : CParser; d : int) : bool {
    var at = d
    while (at >= 0 && p.ast.nodes[at].kind == CNode.D_PAREN) {
        at = p.ast.nodes[at].a
    }
    return at < 0 || p.ast.nodes[at].kind == CNode.D_NAME
}

// the count of an array whose size is integer constant `n`, -2 with the error set for any other size
def private array_count(var b : CTypes; var p : CParser; size : int) : int {
    var at = size
    while (p.ast.nodes[at].kind == CNode.PAREN) {
        at = p.ast.nodes[at].a
    }
    if (p.ast.nodes[at].kind != CNode.INT) {
        refuse(b, p, p.ast.nodes[size].tok, "an array size other than an integer constant")
        return -2
    }
    let text = to_lower(c_spelling(p.unit, p.ast.nodes[at].a))
    var digits = text
    while (!empty(digits) && (ends_with(digits, "u") || ends_with(digits, "l"))) {
        digits = slice(digits, 0, length(digits) - 1)
    }
    var value = 0l
    let hex = starts_with(digits, "0x")
    let base = hex ? 16l : starts_with(digits, "0") ? 8l : 10l
    for (ch in hex ? slice(digits, 2) : digits) {
        let v = ch >= 'a' ? ch - 'a' + 10 : ch - '0'
        value = value * base + int64(v)
        if (value > 0x7FFFFFFFl) {
            refuse(b, p, p.ast.nodes[size].tok, "an array size past 2^31")
            return -2
        }
    }
    return int(value)
}

// the bytes a run of string literals from token `first`, `count` of them, makes, its NUL
// included; -2 with the error set for a prefixed literal
def private string_bytes(var b : CTypes; var p : CParser; first, count : int) : int {
    var bytes = 1
    for (t in range(first, first + count)) {
        let text = c_spelling(p.unit, t)
        if (!starts_with(text, "\"")) {
            refuse(b, p, t, "a prefixed string literal")
            return -2
        }
        var i = 1
        while (i < length(text) - 1) {
            if (character_at(text, i) == '\\') {
                i++
                let ch = character_at(text, i)
                if (ch == 'x') {
                    i++
                    while (i < length(text) - 1 && is_hex(character_at(text, i))) {
                        i++
                    }
                    i--
                } elif (ch >= '0' && ch <= '7') {
                    var k = 1
                    while (k < 3 && i + 1 < length(text) - 1 && character_at(text, i + 1) >= '0' && character_at(text, i + 1) <= '7') {
                        i++
                        k++
                    }
                }
            }
            bytes++
            i++
        }
    }
    return bytes
}

// the count an unsized array takes from initializer `init`: a list's items when none is
// designated, a string literal's bytes; -2 with the error set for any other
def private initializer_count(var b : CTypes; var p : CParser; init, at : int) : int {
    if (init >= 0 && p.ast.nodes[init].kind == CNode.STRING) {
        return string_bytes(b, p, p.ast.nodes[init].a, p.ast.nodes[init].b)
    } elif (init >= 0 && p.ast.nodes[init].kind == CNode.INIT_LIST) {
        var count = 0
        var item = p.ast.nodes[init].a
        while (item >= 0) {
            if (p.ast.nodes[item].a >= 0) {
                refuse(b, p, p.ast.nodes[item].tok, "an array sized by a designated initializer")
                return -2
            }
            count++
            item = p.ast.nodes[item].next
        }
        return count
    }
    return -1
}

// the type declarator `d` gives `base`, C's inside-out reading, each part interned as the reading
// reaches it; `adjust` makes an array or function at the end a pointer (a parameter, C11
// 6.7.6.3p7-8); `init` is the initializer that sizes an unsized array at the end
[arch(at="ARCHITECTURE_TYPES.md#c-types-order")]
def private applied(var b : CTypes; var p : CParser; base, d : int; adjust : bool; init : int = -1) : int {
    return base if (base < 0)
    if (d < 0 || p.ast.nodes[d].kind == CNode.D_NAME) {
        return base
    }
    let n = p.ast.nodes[d]
    if (n.kind == CNode.D_PAREN) {
        return applied(b, p, base, n.a, adjust, init)
    } elif (n.kind == CNode.D_POINTER) {
        return applied(b, p, pointer(b, base), n.a, adjust, init)
    } elif (n.kind == CNode.D_ARRAY) {
        let last = is_end(p, n.a)
        if (last && adjust) {
            return pointer(b, base)
        }
        var count = n.b >= 0 ? array_count(b, p, n.b) : last ? initializer_count(b, p, init, d) : -1
        if (n.op == 2) {
            refuse(b, p, n.tok, "a variable-length array")
            count = -2
        }
        return -1 if (count == -2)
        return applied(b, p, array_of(b, base, count), n.a, adjust, init)
    }
    var params : array<int>
    var param = n.op == 2 ? -1 : n.b
    if (param >= 0 && p.ast.nodes[param].next < 0 && p.ast.nodes[param].b < 0 && is_void(p, p.ast.nodes[param].a)) {
        param = -1
    }
    while (param >= 0) {
        let pt = c_param_type(b, p, param)
        return -1 if (pt < 0)
        params |> push(pt)
        param = p.ast.nodes[param].next
    }
    let f = function_of(b, base, params, n.op == 1)
    if (is_end(p, n.a) && adjust) {
        return pointer(b, f)
    }
    return applied(b, p, f, n.a, adjust, init)
}

// whether specifier list `specs` is `void` alone, qualifiers aside
def private is_void(var p : CParser; specs : int) : bool {
    var found = false
    var at = specs
    while (at >= 0) {
        let n = p.ast.nodes[at]
        if (n.kind == CNode.SPEC_KEYWORD && n.op == int(CTok.VOID)) {
            found = true
        } elif (n.kind != CNode.SPEC_KEYWORD || n.op < int(CTok.CONST) || n.op > int(CTok.RESTRICT)) {
            return false
        }
        at = n.next
    }
    return found
}

//! The adjusted type of parameter node `param`: an array or a function is a pointer.
def c_param_type(var b : CTypes; var p : CParser; param : int) : int {
    let n = p.ast.nodes[param]
    let base = c_specifier_type(b, p, n.a)
    return applied(b, p, is_end(p, n.b) ? adjusted_base(b, base) : base, n.b, true)
}

// a typedef's array or function type, which a parameter declared with no declarator of its own
// adjusts too
def private adjusted_base(var b : CTypes; base : int) : int {
    return base if (base < 0)
    let k = b.tu.types[base].k
    if (k == "array") {
        return pointer(b, b.tu.types[base].elem)
    }
    return k == "func" ? pointer(b, base) : base
}

//! The type of type-name node `t` (C11 6.7.7).
def c_type_name_type(var b : CTypes; var p : CParser; t : int) : int {
    let base = c_specifier_type(b, p, p.ast.nodes[t].a)
    return applied(b, p, base, p.ast.nodes[t].b, false)
}

// bind typedef name `sym` to type `t` in the innermost scope
def private bind(var b : CTypes; sym, t : int) {
    b.undo |> push((sym = sym, was = b.typedefs?[sym] ?? -1))
    b.typedefs[sym] = t
}

def private scope_open(var b : CTypes) {
    b.marks |> push(length(b.undo))
}

def private scope_close(var b : CTypes) {
    let mark = b.marks[length(b.marks) - 1]
    b.marks |> pop()
    var at = length(b.undo) - 1
    while (at >= mark) {
        let entry = b.undo[at]
        if (entry.was < 0) {
            b.typedefs |> erase(entry.sym)
        } else {
            b.typedefs[entry.sym] = entry.was
        }
        at--
    }
    b.undo |> resize(mark)
}

// the function declarator a declarator applies to its name, -1 when it declares no function
def private name_function(var p : CParser; d : int) : int => c_name_function(p.ast, d)

// the parameters of function declarator `f` interned again, as Dumper A reads each parameter's
// declaration after the function's type
def private parameters(var b : CTypes; var p : CParser; f : int) : bool {
    return true if (p.ast.nodes[f].op == 2)
    var param = p.ast.nodes[f].b
    while (param >= 0) {
        if (p.ast.nodes[param].b >= 0 || !is_void(p, p.ast.nodes[param].a)) {
            return false if (c_param_type(b, p, param) < 0)
        }
        param = p.ast.nodes[param].next
    }
    return true
}

// declaration node `decl`'s types in Dumper A's order: per init-declarator its type, a typedef's
// entry after the type it names, a function's parameters after its type; `local` in a block,
// where a function declaration the unit declared before adds nothing
[arch(at="ARCHITECTURE_TYPES.md#c-types-order")]
def private declaration(var b : CTypes; var p : CParser; decl : int; local : bool) : bool {
    let n = p.ast.nodes[decl]
    return true if (n.kind != CNode.DECL)
    var typedef_decl = false
    var at = n.a
    while (at >= 0) {
        typedef_decl ||= p.ast.nodes[at].kind == CNode.SPEC_KEYWORD && p.ast.nodes[at].op == int(CTok.TYPEDEF)
        at = p.ast.nodes[at].next
    }
    var id = n.b
    if (id < 0 && has_tag(p, n.a)) {
        return c_specifier_type(b, p, n.a) >= 0
    }
    while (id >= 0) {
        let d = p.ast.nodes[id].a
        let sym = c_declarator_name(p.ast, d)
        let f = name_function(p, d)
        if (local && f >= 0 && !typedef_decl && key_exists(b.declared, sym)) {
            id = p.ast.nodes[id].next
            continue
        }
        if (f >= 0 && !typedef_decl) {
            b.declared[sym] = true
        }
        let base = c_specifier_type(b, p, n.a)
        let t = applied(b, p, base, d, false, p.ast.nodes[id].b)
        return false if (t < 0)
        if (typedef_decl) {
            var td = CirType(k = "typedef", name = pp_symbol_text(p.unit.lx, sym), to = t)
            intern(b, "typedef:{td.name}", td)
            bind(b, sym, t)
        } elif (f >= 0 && !parameters(b, p, f)) {
            return false
        }
        id = p.ast.nodes[id].next
    }
    return true
}

// whether specifier list `specs` holds a struct, union or enum
def private has_tag(var p : CParser; specs : int) : bool {
    var at = specs
    while (at >= 0) {
        let k = p.ast.nodes[at].kind
        return true if (k == CNode.SPEC_RECORD || k == CNode.SPEC_ENUM)
        at = p.ast.nodes[at].next
    }
    return false
}

// the declarations of statement `s` and the statements under it, in source order; an expression's
// own types are not read here
[arch(at="ARCHITECTURE_TYPES.md#c-types-order")]
def private statement(var b : CTypes; var p : CParser; s : int) : bool {
    return true if (s < 0)
    let n = p.ast.nodes[s]
    if (n.kind == CNode.DECL) {
        return declaration(b, p, s, true)
    } elif (n.kind == CNode.COMPOUND) {
        scope_open(b)
        var item = n.a
        var ok = true
        while (ok && item >= 0) {
            ok = statement(b, p, item)
            item = p.ast.nodes[item].next
        }
        scope_close(b)
        return ok
    } elif (n.kind == CNode.IF) {
        return statement(b, p, n.b) && statement(b, p, n.c)
    } elif (n.kind == CNode.SWITCH || n.kind == CNode.WHILE || n.kind == CNode.LABEL) {
        return statement(b, p, n.b)
    } elif (n.kind == CNode.DO || n.kind == CNode.DEFAULT) {
        return statement(b, p, n.a)
    } elif (n.kind == CNode.CASE) {
        return statement(b, p, n.c)
    } elif (n.kind == CNode.FOR) {
        scope_open(b)
        let ok = statement(b, p, n.a) && statement(b, p, n.d)
        scope_close(b)
        return ok
    }
    return true
}

// function definition `def`'s types: its type (an old-style one has no parameter types in it),
// then each parameter's in the order the declarator lists them, then its body's declarations
[arch(at="ARCHITECTURE_TYPES.md#c-types-order")]
def private definition(var b : CTypes; var p : CParser; def_node : int) : bool {
    let n = p.ast.nodes[def_node]
    let d = p.ast.nodes[n.b].a
    let base = c_specifier_type(b, p, n.a)
    if (applied(b, p, base, d, false) < 0) {
        return false
    }
    b.declared[c_declarator_name(p.ast, d)] = true
    let f = name_function(p, d)
    if (p.ast.nodes[f].op != 2) {
        return parameters(b, p, f) && statement(b, p, n.d)
    }
    var param = p.ast.nodes[f].b
    while (param >= 0) {
        let typing = p.ast.nodes[param].b
        var old = n.c
        while (old >= 0 && !holds_declarator(p, old, typing)) {
            old = p.ast.nodes[old].next
        }
        let base = c_specifier_type(b, p, p.ast.nodes[old].a)
        let pt = applied(b, p, is_end(p, typing) ? adjusted_base(b, base) : base, typing, true)
        return false if (pt < 0)
        param = p.ast.nodes[param].next
    }
    return statement(b, p, n.d)
}

// whether declaration `decl` has declarator `d` among its init-declarators
def private holds_declarator(var p : CParser; decl, d : int) : bool {
    var id = p.ast.nodes[decl].b
    while (id >= 0) {
        return true if (p.ast.nodes[id].a == d)
        id = p.ast.nodes[id].next
    }
    return false
}

// whether external declaration `decl` stands in a file under the own libc headers' folder
def private in_library(var b : CTypes; var p : CParser; decl : int) : bool {
    return false if (empty(b.library_dir))
    let file = c_file_name(p.unit, p.unit.toks[p.ast.nodes[decl].tok].file)
    return starts_with(file, b.library_dir)
}

// the function names a library declaration declares, which a block's declaration of them then
// redeclares
def private note_library_names(var b : CTypes; var p : CParser; decl : int) {
    return if (p.ast.nodes[decl].kind != CNode.DECL)
    var id = p.ast.nodes[decl].b
    while (id >= 0) {
        b.declared[c_declarator_name(p.ast, p.ast.nodes[id].a)] = true
        id = p.ast.nodes[id].next
    }
}

//! The type table of unit node `u`, which `c_unit` built: every declaration's types, in the order
//! Dumper A's walk first uses them (`ARCHITECTURE_TYPES.md`); false with `err` set at the first
//! construct the builder does not type yet.
[arch(at="ARCHITECTURE_TYPES.md#c-types-order")]
def c_types_unit(var b : CTypes; var p : CParser; u : int) : bool {
    var at = p.ast.nodes[u].a
    while (empty(b.err) && at >= 0) {
        let kind = p.ast.nodes[at].kind
        if (in_library(b, p, at)) {
            note_library_names(b, p, at)
        } elif (kind == CNode.FUNC_DEF) {
            definition(b, p, at)
        } else {
            declaration(b, p, at, false)
        }
        at = p.ast.nodes[at].next
    }
    return empty(b.err)
}
