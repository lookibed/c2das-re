options gen2
options indenting = 4

module c_types public

require math
require strings
require daslib/strings_boost
require c_parser public
require ../converter/cir.das public

//! The C-IR type table of one unit as Dumper A builds it (`ARCHITECTURE_TYPES.md`): every type a
//! declaration reaches, once, in the order Dumper A's walk first uses it, each `spell` as clang
//! spells it under the dialect. `pool` holds the types the builder has met, typedefs resolved, by
//! the same structural key, a qualified type apart from its unqualified one; `c_types_use` interns
//! a pool type into the table, qualifiers dropped, its parts first.
struct CTypes {
    tu : CirTu
    index : table<string; int>      //!< a table entry's key to its index
    pool : array<CirType>           //!< every type met, referring to other pool types
    pool_index : table<string; int> //!< a pool type's key to its index
    used : array<int>               //!< per pool type, its table index; -1 while no use reached it
    quals : array<int>              //!< per pool type, its own qualifiers (`C_CONST`, `C_VOLATILE`, `C_RESTRICT`)
    unqualified : array<int>        //!< per pool type, the pool type without its own qualifiers
    typedefs : table<int; int>      //!< a typedef name's symbol to the pool type it names
    untyped : table<int; string>    //!< a library typedef name the builder does not type, and why
    undo : array<tuple<sym : int; was : int>>   //!< the bindings a block's end restores
    marks : array<int>
    declared : table<int; bool>     //!< the function names declared so far
    library_dir : string            //!< the own libc headers' folder, whose declarations add no type
    old_style : array<int>          //!< the promoted parameter types an old-style definition's type takes
    err : string
}

//! Open the builder over the dialect `target`, with an empty table; a declaration in a file whose
//! line-marker name starts with `library_dir`, the own libc headers' folder, adds no type, as
//! Dumper A dumps none of them ("" for none).
def c_types_open(var b : CTypes; target : CirTarget; library_dir : string) {
    b.tu.target = target
    b.library_dir = library_dir
    b.tu.types |> clear()
    b.index |> clear()
    b.pool |> clear()
    b.pool_index |> clear()
    b.used |> clear()
    b.quals |> clear()
    b.unqualified |> clear()
    b.typedefs |> clear()
    b.untyped |> clear()
    b.undo |> clear()
    b.marks |> clear()
    b.declared |> clear()
    b.err = ""
}

// the first error, at token `tok`: a construct the builder does not type yet, and `why` after it
def private refuse(var b : CTypes; var p : CParser; tok : int; what : string; why : string = "") {
    if (empty(b.err)) {
        b.err = "{c_where(p.unit, tok)}: {what} is not typed yet{why}"
    }
}

//! The key a type is interned by, in the table or in the pool, as Dumper A keys it: an integer by
//! its width, sign and spelling; `double` and `long double` apart; a pointer, an array and a
//! function by the indices of their parts.
def c_type_key(t : CirType) : string {
    if (t.k == "int") {
        return "int:{t.w}:{t.is_signed}:{t.spell}"
    } elif (t.k == "float") {
        return t.w == 32 ? "float:32" : "float:64:{t.spell}"
    } elif (t.k == "ptr") {
        return "ptr:{t.to}"
    } elif (t.k == "array") {
        return "array:{t.elem}:{t.count}"
    } elif (t.k == "func") {
        let listed = join([for (x in t.params); string(x)], ",")
        return "func:{t.ret}:{listed}:{t.variadic}"
    }
    return t.k
}

// pool type `t`: the index it has, or the next one
def private pooled(var b : CTypes; var t : CirType) : int {
    let key = c_type_key(t)
    let known = b.pool_index?[key] ?? -1
    return known if (known >= 0)
    let idx = length(b.pool)
    b.pool |> emplace(t)
    b.pool_index[key] = idx
    b.used |> push(-1)
    b.quals |> push(0)
    b.unqualified |> push(idx)
    return idx
}

//! The qualifier bits of a pool type.
let C_CONST = 1
let C_VOLATILE = 2
let C_RESTRICT = 4

//! Pool type `t` with qualifiers `q` added: an array's element takes them (C11 6.7.3p9), a function
//! type none.
def c_qualified(var b : CTypes; t, q : int) : int {
    return t if (t < 0 || q == 0 || (b.quals[t] | q) == b.quals[t] || b.pool[t].k == "func")
    if (b.pool[t].k == "array") {
        return array_of(b, c_qualified(b, b.pool[t].elem, q), b.pool[t].count)
    }
    let base = b.unqualified[t]
    let all = b.quals[t] | q
    let key = "q{all}:{base}"
    let known = b.pool_index?[key] ?? -1
    return known if (known >= 0)
    let idx = length(b.pool)
    var copy := b.pool[base]
    b.pool |> emplace(copy)
    b.pool_index[key] = idx
    b.used |> push(-1)
    b.quals |> push(all)
    b.unqualified |> push(base)
    return idx
}

// the qualifier bits of the qualifier keywords in list `at`
def private qualifiers_of(p : CParser; at : int) : int {
    var q = 0
    var n = at
    while (n >= 0) {
        let k = p.ast.nodes[n].op
        if (p.ast.nodes[n].kind == CNode.SPEC_KEYWORD) {
            q |= k == int(CTok.CONST) ? C_CONST : k == int(CTok.VOLATILE) ? C_VOLATILE : k == int(CTok.RESTRICT) ? C_RESTRICT : 0
        }
        n = p.ast.nodes[n].next
    }
    return q
}

// table entry `t` under `key`: the index it has, or the next one
def private intern(var b : CTypes; key : string; var t : CirType) : int {
    let known = b.index?[key] ?? -1
    return known if (known >= 0)
    let idx = length(b.tu.types)
    b.tu.types |> emplace(t)
    b.index[key] = idx
    return idx
}

//! The table index of pool type `pt`, interned with its parts first where no use reached it yet:
//! a pointer's target, an array's element, a function's result and then each parameter left to
//! right - the order Dumper A reads a type's spelling in. -1 for -1.
[arch(at="ARCHITECTURE_TYPES.md#c-types-order")]
def c_types_use(var b : CTypes; pt : int) : int {
    return -1 if (pt < 0)
    return b.used[pt] if (b.used[pt] >= 0)
    var t := b.pool[pt]
    if (t.k == "ptr") {
        t.to = c_types_use(b, t.to)
    } elif (t.k == "array") {
        t.elem = c_types_use(b, t.elem)
    } elif (t.k == "func") {
        t.ret = c_types_use(b, t.ret)
        for (i in range(length(t.params))) {
            t.params[i] = c_types_use(b, t.params[i])
        }
    }
    let idx = intern(b, c_type_key(t), t)
    b.used[pt] = idx
    return idx
}

def private int_type(var b : CTypes; w : int; is_signed : bool; spell : string) : int {
    var t = CirType(k = "int", w = w, is_signed = is_signed, spell = spell)
    return pooled(b, t)
}

def private pointer(var b : CTypes; to : int) : int {
    var t = CirType(k = "ptr", to = to)
    return pooled(b, t)
}

def private array_of(var b : CTypes; elem, count : int) : int {
    var t = CirType(k = "array", elem = elem, count = count)
    return pooled(b, t)
}

def private function_of(var b : CTypes; ret : int; var params : array<int>; variadic : bool) : int {
    var t = CirType(k = "func", ret = ret, variadic = variadic)
    t.params <- [for (x in params); b.unqualified[x]]
    return pooled(b, t)
}

// the bit of a builtin type keyword in a specifier set, by its place after `void`; a second
// `long` is bit `LONG_LONG`
def private bit(k : CTok) : int => 1 << (int(k) - int(CTok.VOID))

let private LONG_LONG = 1 << 12

// the builtin specifier sets and the type each one is, as clang spells it; `w` -1 is the dialect's
// `int`, -2 its `long`, -3 its `long long`, -4 plain `char` (signed as the dialect says)
let private BUILTINS <- [
    (set = bit(CTok.VOID), k = "void", w = 0, sign = false, spell = "void"),
    (set = bit(CTok.BOOL), k = "int", w = 8, sign = false, spell = "_Bool"),
    (set = bit(CTok.CHAR), k = "int", w = -4, sign = false, spell = "char"),
    (set = bit(CTok.CHAR) | bit(CTok.SIGNED), k = "int", w = 8, sign = true, spell = "signed char"),
    (set = bit(CTok.CHAR) | bit(CTok.UNSIGNED), k = "int", w = 8, sign = false, spell = "unsigned char"),
    (set = bit(CTok.SHORT), k = "int", w = 16, sign = true, spell = "short"),
    (set = bit(CTok.INT), k = "int", w = -1, sign = true, spell = "int"),
    (set = bit(CTok.LONG), k = "int", w = -2, sign = true, spell = "long"),
    (set = bit(CTok.LONG) | LONG_LONG, k = "int", w = -3, sign = true, spell = "long long"),
    (set = bit(CTok.FLOAT), k = "float", w = 32, sign = false, spell = "float"),
    (set = bit(CTok.DOUBLE), k = "float", w = 64, sign = false, spell = "double"),
    (set = bit(CTok.LONG) | bit(CTok.DOUBLE), k = "float", w = 64, sign = false, spell = "long double")]

// the pool type of builtin specifier set `set`, -1 for a set that is none: `int` and `signed`
// fold into the set they qualify, and `unsigned` adds `unsigned ` to the spelling of every
// integer but the `char`s, which spell their sign themselves
[arch(at="ARCHITECTURE_TYPES.md#c-types-specifiers")]
def private builtin_type(var b : CTypes; set : int) : int {
    let unsigned_bit = bit(CTok.UNSIGNED)
    let has_unsigned = (set & unsigned_bit) != 0
    var core = set & ~bit(CTok.SIGNED) & ~bit(CTok.INT) & ~unsigned_bit
    if (core == 0) {
        core = bit(CTok.INT)
    } elif (core == bit(CTok.CHAR)) {
        core = set & ~bit(CTok.INT)
    }
    for (entry in BUILTINS) {
        continue if (entry.set != core)
        if (entry.k == "void") {
            var t = CirType(k = "void")
            return pooled(b, t)
        } elif (entry.k == "float") {
            var t = CirType(k = "float", w = entry.w, spell = entry.spell)
            return pooled(b, t)
        }
        let target = b.tu.target
        let w = entry.w == -1 ? target.int_w : entry.w == -2 ? target.long_w : entry.w == -3 ? target.llong_w : entry.w == -4 ? 8 : entry.w
        let sign = entry.w == -4 ? target.char_signed : entry.sign && !has_unsigned
        let spell = has_unsigned && entry.w != 8 && entry.w != -4 ? "unsigned {entry.spell}" : entry.spell
        return int_type(b, w, sign, spell)
    }
    return -1
}

// the attribute words that change the type they stand on
let private TYPE_ATTRIBUTES <- ["mode", "__mode__", "vector_size", "__vector_size__", "ext_vector_type"]

// false with the error set when list `at` holds an attribute naming one of `TYPE_ATTRIBUTES`
def private plain_attributes(var b : CTypes; var p : CParser; at : int) : bool {
    var n = at
    while (n >= 0) {
        if (p.ast.nodes[n].kind == CNode.ATTRIBUTE) {
            for (t in range(p.ast.nodes[n].a, p.ast.nodes[n].b + 1)) {
                if (has_value(TYPE_ATTRIBUTES, c_spelling(p.unit, t))) {
                    refuse(b, p, t, "the attribute '{c_spelling(p.unit, t)}', which changes a type,")
                    return false
                }
            }
        }
        n = p.ast.nodes[n].next
    }
    return true
}

//! The pool type a list of declaration specifiers names; -1 with the error set for one the builder
//! does not type yet. Qualifiers, storage classes and function specifiers give no C-IR type.
[arch(at="ARCHITECTURE_TYPES.md#c-types-specifiers")]
def c_specifier_type(var b : CTypes; var p : CParser; specs : int) : int {
    var set = 0
    var named = -1
    var at = specs
    while (at >= 0) {
        let n = p.ast.nodes[at]
        if (n.kind == CNode.SPEC_KEYWORD) {
            let k = n.op
            if (k >= int(CTok.VOID) && k <= int(CTok.BOOL)) {
                set |= k == int(CTok.LONG) && (set & bit(CTok.LONG)) != 0 ? LONG_LONG : 1 << (k - int(CTok.VOID))
            } elif (k == int(CTok.COMPLEX)) {
                refuse(b, p, n.tok, "a complex type")
                return -1
            } elif (k == int(CTok.ATOMIC)) {
                refuse(b, p, n.tok, "an _Atomic type")
                return -1
            }
        } elif (n.kind == CNode.SPEC_TYPEDEF_NAME) {
            named = b.typedefs?[n.a] ?? -1
            if (named < 0) {
                let why = b.untyped?[n.a] ?? ""
                let name = pp_symbol_text(p.unit.lx, n.a)
                refuse(b, p, n.tok, "the typedef name '{name}'", empty(why) ? "" : ": {why}")
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
        }
        at = n.next
    }
    return -1 if (!plain_attributes(b, p, specs))
    let t = named >= 0 ? named : builtin_type(b, set)
    if (t < 0) {
        refuse(b, p, p.ast.nodes[specs].tok, "this specifier list")
    }
    return c_qualified(b, t, qualifiers_of(p, specs))
}

// false with the error set when list `at` holds `_Atomic`
def private no_atomic(var b : CTypes; var p : CParser; at : int) : bool {
    var n = at
    while (n >= 0) {
        if (p.ast.nodes[n].kind == CNode.SPEC_KEYWORD && p.ast.nodes[n].op == int(CTok.ATOMIC)) {
            refuse(b, p, p.ast.nodes[n].tok, "an _Atomic type")
            return false
        }
        n = p.ast.nodes[n].next
    }
    return true
}

//! The type a value of pool type `t` takes under the default argument promotions (C11 6.5.2.2p6):
//! an integer narrower than `int` is `int`, `float` is `double`, any other type its own,
//! unqualified.
def c_promoted(var b : CTypes; t : int) : int {
    let u = b.unqualified[t]
    assume ty = b.pool[u]
    if (ty.k == "int" && ty.w < b.tu.target.int_w) {
        return builtin_type(b, bit(CTok.INT))
    } elif (ty.k == "float" && ty.w == 32) {
        return builtin_type(b, bit(CTok.DOUBLE))
    }
    return u
}

// whether declarator `d` is at its end: none, its name, or parentheses around one
def private is_end(p : CParser; d : int) : bool {
    var at = d
    while (at >= 0 && p.ast.nodes[at].kind == CNode.D_PAREN) {
        at = p.ast.nodes[at].a
    }
    return at < 0 || p.ast.nodes[at].kind == CNode.D_NAME
}

// the value of node `n`, an integer literal in parentheses or not, as an array size or index (`what`);
// -2 with the error set for any other node (an integer constant expression waits for constant
// folding, a variable-length array is out of scope) and for a value past 2^31 - 1
def private literal_value(var b : CTypes; var p : CParser; n : int; what : string) : int {
    var at = n
    while (p.ast.nodes[at].kind == CNode.PAREN) {
        at = p.ast.nodes[at].a
    }
    if (p.ast.nodes[at].kind != CNode.INT) {
        refuse(b, p, p.ast.nodes[n].tok, "an {what} other than an integer literal")
        return -2
    }
    let spelled = to_lower(c_spelling(p.unit, p.ast.nodes[at].a))
    var end = length(spelled)
    peek_data(spelled) $(text) {
        while (end > 0 && (text[end - 1] == uint8('u') || text[end - 1] == uint8('l'))) {
            end--
        }
    }
    let digits = slice(spelled, 0, end)
    let hex = starts_with(digits, "0x")
    let base = hex ? 16 : starts_with(digits, "0") ? 8 : 10
    var value = 0l
    for (ch in hex ? slice(digits, 2) : digits) {
        let v = is_number(ch) ? ch - '0' : ch >= 'a' && ch <= 'f' ? ch - 'a' + 10 : 99
        if (v >= base) {
            refuse(b, p, p.ast.nodes[n].tok, "the {what} '{c_spelling(p.unit, p.ast.nodes[at].a)}'")
            return -2
        }
        value = value * int64(base) + int64(v)
        if (value > 2147483647l) {
            refuse(b, p, p.ast.nodes[n].tok, "an {what} past 2^31 - 1")
            return -2
        }
    }
    return int(value)
}

// the bytes of a UTF-8 encoding of code point `c`
def private utf8_length(c : int) : int => c < 0x80 ? 1 : c < 0x800 ? 2 : c < 0x10000 ? 3 : 4

// the bytes a run of `count` adjacent string literals from token `first` makes, its NUL included:
// each escape one byte, a universal character name its UTF-8 bytes; -2 with the error set for a
// prefixed literal
[arch(at="ARCHITECTURE_TYPES.md#c-types-arrays")]
def private string_bytes(var b : CTypes; var p : CParser; first, count : int) : int {
    var bytes = 1
    for (t in range(first, first + count)) {
        if (!starts_with(c_spelling(p.unit, t), "\"")) {
            refuse(b, p, t, "a prefixed string literal")
            return -2
        }
        peek_data(c_spelling(p.unit, t)) $(text) {
            let stop = length(text) - 1
            var i = 1
            while (i < stop) {
                var size = 1
                if (text[i] == uint8('\\')) {
                    i++
                    let ch = int(text[i])
                    if (ch == 'x') {
                        while (i + 1 < stop && is_hex(int(text[i + 1]))) {
                            i++
                        }
                    } elif (ch >= '0' && ch <= '7') {
                        var k = 1
                        while (k < 3 && i + 1 < stop && int(text[i + 1]) >= '0' && int(text[i + 1]) <= '7') {
                            i++
                            k++
                        }
                    } elif (ch == 'u' || ch == 'U') {
                        let digits = ch == 'u' ? 4 : 8
                        var code = 0
                        for (k in range(digits)) {
                            let h = int(text[i + 1 + k])
                            code = code * 16 + (is_number(h) ? h - '0' : (h | 0x20) - 'a' + 10)
                        }
                        i += digits
                        size = utf8_length(code)
                    }
                }
                bytes += size
                i++
            }
        }
    }
    return bytes
}

// the count an unsized array of pool type `elem` takes from initializer `init`, the node after the
// declarator's `=`: a string literal's bytes, braced or not for a character array; a list's items, a designator `[k]`
// (an integer literal) moving the next item to `k`, and, for an array of arrays, each item braced
// or a string; -1 for no initializer; -2 with the error set for any other
[arch(at="ARCHITECTURE_TYPES.md#c-types-arrays")]
def private initializer_count(var b : CTypes; var p : CParser; init, elem : int) : int {
    return -1 if (init < 0)
    let n = p.ast.nodes[init]
    if (n.kind == CNode.STRING) {
        return string_bytes(b, p, n.a, n.b)
    } elif (n.kind != CNode.INIT_LIST) {
        refuse(b, p, n.tok, "an unsized array initialized by this expression")
        return -2
    }
    var count = 0
    var next = 0
    var item = n.a
    while (item >= 0) {
        let it = p.ast.nodes[item]
        let value = p.ast.nodes[it.b].kind
        if (it.a >= 0) {
            let desig = p.ast.nodes[it.a]
            if (desig.kind != CNode.DESIG_INDEX || desig.b >= 0 || desig.next >= 0) {
                refuse(b, p, it.tok, "an array sized by this designated initializer")
                return -2
            }
            next = literal_value(b, p, desig.a, "array index")
            return -2 if (next < 0)
        } elif (count == 0 && it.next < 0 && value == CNode.STRING && b.pool[elem].k == "int" && b.pool[elem].w == 8) {
            return string_bytes(b, p, p.ast.nodes[it.b].a, p.ast.nodes[it.b].b)
        }
        if (b.pool[elem].k == "array" && value != CNode.INIT_LIST && value != CNode.STRING) {
            refuse(b, p, it.tok, "an unsized array of arrays initialized with elided braces")
            return -2
        }
        next++
        count = max(count, next)
        item = it.next
    }
    return count
}

// the pool type declarator `d` gives `base`, C's inside-out reading; `adjust` makes an array or a
// function at the end a pointer (a parameter, C11 6.7.6.3p7-8), the array never met; `init` is
// the initializer that sizes an unsized array at the end
[arch(at="ARCHITECTURE_TYPES.md#c-types-declarators")]
def private applied(var b : CTypes; var p : CParser; base, d : int; adjust : bool; init : int = -1) : int {
    return base if (base < 0 || d < 0)
    let n = p.ast.nodes[d]
    if (n.kind == CNode.D_NAME) {
        return base
    } elif (n.kind == CNode.D_PAREN) {
        return -1 if (!plain_attributes(b, p, n.b))
        return applied(b, p, base, n.a, adjust, init)
    } elif (n.kind == CNode.D_POINTER) {
        return -1 if (!plain_attributes(b, p, n.b) || !no_atomic(b, p, n.b))
        return applied(b, p, c_qualified(b, pointer(b, base), qualifiers_of(p, n.b)), n.a, adjust, init)
    } elif (n.kind == CNode.D_ARRAY) {
        let last = is_end(p, n.a)
        if (last && adjust) {
            return -1 if (!no_atomic(b, p, n.c))
            return c_qualified(b, pointer(b, base), qualifiers_of(p, n.c))
        }
        if (n.op == 2) {
            refuse(b, p, n.tok, "a variable-length array")
            return -1
        }
        let count = n.b >= 0 ? literal_value(b, p, n.b, "array size") : last ? initializer_count(b, p, init, base) : -1
        return -1 if (count == -2)
        return applied(b, p, array_of(b, base, count), n.a, adjust, init)
    }
    var params : array<int>
    if (n.op == 2) {
        params := b.old_style
    }
    var param = n.op == 2 || is_void_list(p, n.b) ? -1 : n.b
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

// whether parameter list `param` is `(void)`: one parameter, no declarator, `void` alone with
// qualifiers aside
def private is_void_list(p : CParser; param : int) : bool {
    return false if (param < 0 || p.ast.nodes[param].next >= 0 || p.ast.nodes[param].b >= 0)
    var found = false
    var at = p.ast.nodes[param].a
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

// a typedef's array or function type, which a parameter declared with no declarator of its own
// adjusts too; the array's element is the pointer's target, the array itself never used
def private adjusted_base(var b : CTypes; base : int) : int {
    return base if (base < 0)
    let k = b.pool[base].k
    if (k == "array") {
        return pointer(b, b.pool[base].elem)
    }
    return k == "func" ? pointer(b, base) : base
}

// the adjusted pool type that specifiers `specs` and declarator `d` give a parameter
def private parameter_type(var b : CTypes; var p : CParser; specs, d : int) : int {
    let base = c_specifier_type(b, p, specs)
    return applied(b, p, is_end(p, d) ? adjusted_base(b, base) : base, d, true)
}

//! The adjusted pool type of parameter node `param`: an array or a function is a pointer.
def c_param_type(var b : CTypes; var p : CParser; param : int) : int {
    let n = p.ast.nodes[param]
    return -1 if (!plain_attributes(b, p, n.c))
    return parameter_type(b, p, n.a, n.b)
}

//! The pool type of type-name node `t` (C11 6.7.7).
def c_type_name_type(var b : CTypes; var p : CParser; t : int) : int {
    let base = c_specifier_type(b, p, p.ast.nodes[t].a)
    return applied(b, p, base, p.ast.nodes[t].b, false)
}

// bind typedef name `sym` to pool type `t` in the innermost scope
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

// each parameter type of function declarator `f` used again, as Dumper A reads each parameter's
// declaration after the function's type
def private parameters(var b : CTypes; var p : CParser; f : int) : bool {
    return true if (p.ast.nodes[f].op == 2 || is_void_list(p, p.ast.nodes[f].b))
    var param = p.ast.nodes[f].b
    while (param >= 0) {
        return false if (c_types_use(b, c_param_type(b, p, param)) < 0)
        param = p.ast.nodes[param].next
    }
    return true
}

// whether specifier list `specs` holds `typedef`
def private declares_typedef(p : CParser; specs : int) : bool {
    var at = specs
    while (at >= 0) {
        return true if (p.ast.nodes[at].kind == CNode.SPEC_KEYWORD && p.ast.nodes[at].op == int(CTok.TYPEDEF))
        at = p.ast.nodes[at].next
    }
    return false
}

// declaration node `decl`'s types in Dumper A's order: per init-declarator its type, a typedef's
// entry after the type it names, a function's parameters after its type; `local` in a block,
// where a function declaration of a name declared before adds nothing
[arch(at="ARCHITECTURE_TYPES.md#c-types-order")]
def private declaration(var b : CTypes; var p : CParser; decl : int; local : bool) : bool {
    let n = p.ast.nodes[decl]
    return true if (n.kind != CNode.DECL)
    let typedef_decl = declares_typedef(p, n.a)
    if (n.b < 0) {
        return c_specifier_type(b, p, n.a) >= 0
    }
    var next = n.b
    while (next >= 0) {
        let id = next
        next = p.ast.nodes[id].next
        let d = p.ast.nodes[id].a
        let sym = c_declarator_name(p.ast, d)
        let f = c_name_function(p.ast, d)
        return false if (!plain_attributes(b, p, p.ast.nodes[id].d))
        let base = c_specifier_type(b, p, n.a)
        let t = applied(b, p, base, d, false, p.ast.nodes[id].b)
        return false if (t < 0)
        if (typedef_decl) {
            var td = CirType(k = "typedef", name = pp_symbol_text(p.unit.lx, sym), to = c_types_use(b, t))
            intern(b, "typedef:{td.name}", td)
            bind(b, sym, t)
            continue
        }
        let is_function = b.pool[t].k == "func"
        continue if (local && is_function && key_exists(b.declared, sym))
        c_types_use(b, t)
        if (is_function) {
            b.declared[sym] = true
        }
        return false if (f >= 0 && !parameters(b, p, f))
    }
    return true
}

// the declarations of statement `s` and the statements under it, in source order; no expression's
// own types (C.3), and no declaration inside an expression
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

// the declaration in list `old` that has declarator `d`
def private declaration_of(p : CParser; old, d : int) : int {
    var at = old
    while (at >= 0) {
        var id = p.ast.nodes[at].b
        while (id >= 0) {
            return at if (p.ast.nodes[id].a == d)
            id = p.ast.nodes[id].next
        }
        at = p.ast.nodes[at].next
    }
    return -1
}

// function definition `def_node`'s types: its type (an old-style one's parameters are its
// declared ones under the default argument promotions, as clang types it), then each parameter's
// in the order the declarator lists them, then its body's declarations
[arch(at="ARCHITECTURE_TYPES.md#c-types-order")]
def private definition(var b : CTypes; var p : CParser; def_node : int) : bool {
    let n = p.ast.nodes[def_node]
    let d = p.ast.nodes[n.b].a
    let f = c_name_function(p.ast, d)
    var typed : array<int>
    if (p.ast.nodes[f].op == 2) {
        var param = p.ast.nodes[f].b
        while (param >= 0) {
            let typing = p.ast.nodes[param].b
            let old = declaration_of(p, n.c, typing)
            let pt = parameter_type(b, p, p.ast.nodes[old].a, typing)
            return false if (pt < 0)
            typed |> push(pt)
            b.old_style |> push(c_promoted(b, pt))
            param = p.ast.nodes[param].next
        }
    }
    let base = c_specifier_type(b, p, n.a)
    let t = applied(b, p, base, d, false)
    b.old_style |> clear()
    return false if (c_types_use(b, t) < 0)
    b.declared[c_declarator_name(p.ast, d)] = true
    if (p.ast.nodes[f].op != 2) {
        return parameters(b, p, f) && statement(b, p, n.d)
    }
    for (pt in typed) {
        c_types_use(b, pt)
    }
    return statement(b, p, n.d)
}

// whether external declaration `decl` stands in a file under the own libc headers' folder
def private in_library(b : CTypes; var p : CParser; decl : int) : bool {
    return false if (empty(b.library_dir))
    let file = c_file_name(p.unit, p.unit.toks[p.ast.nodes[decl].tok].file)
    return starts_with(file, b.library_dir)
}

// a library declaration, which adds no type: its typedef names bound to their pool types (or,
// for one the builder does not type, to why), its function names declared
[arch(at="ARCHITECTURE_TYPES.md#c-types-library")]
def private library_declaration(var b : CTypes; var p : CParser; decl : int) {
    let n = p.ast.nodes[decl]
    if (n.kind == CNode.FUNC_DEF) {
        b.declared[c_declarator_name(p.ast, p.ast.nodes[n.b].a)] = true
        return
    }
    return if (n.kind != CNode.DECL)
    let typedef_decl = declares_typedef(p, n.a)
    var id = n.b
    while (id >= 0) {
        let d = p.ast.nodes[id].a
        let sym = c_declarator_name(p.ast, d)
        if (!typedef_decl) {
            b.declared[sym] = true
        } else {
            let t = applied(b, p, c_specifier_type(b, p, n.a), d, false)
            if (t >= 0) {
                bind(b, sym, t)
                b.untyped |> erase(sym)
            } else {
                b.typedefs |> erase(sym)
                b.untyped[sym] = b.err
                b.err = ""
            }
        }
        id = p.ast.nodes[id].next
    }
}

//! The type table of unit node `u`, which `c_unit` built: every declaration's types, in the order
//! Dumper A's walk first uses them (`ARCHITECTURE_TYPES.md`); false with `err` set at the first
//! construct the builder does not type yet. Under the msvc dialect `size_t`, which clang declares
//! there before the unit, is `unsigned long long`.
[arch(at="ARCHITECTURE_TYPES.md#c-types-order")]
def c_types_unit(var b : CTypes; var p : CParser; u : int) : bool {
    if (is_msvc(b.tu.target)) {
        bind(b, c_symbol(p.unit, "size_t"), int_type(b, b.tu.target.llong_w, false, "unsigned long long"))
    }
    var at = p.ast.nodes[u].a
    while (empty(b.err) && at >= 0) {
        if (in_library(b, p, at)) {
            library_declaration(b, p, at)
        } elif (p.ast.nodes[at].kind == CNode.FUNC_DEF) {
            definition(b, p, at)
        } else {
            declaration(b, p, at, false)
        }
        at = p.ast.nodes[at].next
    }
    return empty(b.err)
}
