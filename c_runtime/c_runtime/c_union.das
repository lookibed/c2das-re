options gen2

module c_union public

require daslib/ast
require daslib/ast_boost
require daslib/templates_boost
require daslib/macro_boost
require daslib/math_boost
require c_runtime/c_storage

//! C unions over das storage. `[c_union] struct Value { gc : GCObject?; p : void?; n : double; i : int64 }`
//! is written C-shaped; the annotation replaces the members with one storage field
//! `_storage : U[k]`, `U` the unsigned type of the union's alignment and `k` its size over that
//! alignment, and generates per member `operator . name` twice: over a `var` union a reference
//! into the storage (read, store, compound store, `++`, a nested field, `addr`), over a const one
//! the value. `[c_union(size = N, align = A)]` states the size and alignment; the bare form
//! derives them from the members, which takes every member's type known when the struct is
//! parsed. Every member's size and alignment are checked against the storage at inference.

// whether das knows the size of a value of type `t` while the struct is parsed: every type held
// by value resolved, every dimension folded; a pointer or a function value is pointer-sized
// whatever it points at
def private size_known_at_parse(t : TypeDeclPtr) : bool {
    if (t.baseType == Type.tPointer || t.baseType == Type.tFunction) {
        return true
    }
    if (t.baseType == Type.tFixedArray) {
        return t.fixedDim > 0 && size_known_at_parse(t.firstType)
    }
    if (t.baseType == Type.tStructure) {
        for (f in t.structType.fields) {
            if (!size_known_at_parse(f._type)) {
                return false
            }
        }
        return true
    }
    return !t.isAutoOrAlias
}

// the size and alignment the members give, the size rounded up to the alignment; `size` is 0
// when a member's type is not known yet (`size_known_at_parse`)
def private member_layout(st : StructurePtr) : tuple<size : int; align : int> {
    var size = 0
    var align = 1
    for (f in st.fields) {
        if (!size_known_at_parse(f._type)) {
            return (size = 0, align = 1)
        }
        size = max(size, f._type.sizeOf)
        align = max(align, f._type.alignOf)
    }
    return (size = round_up(size, align), align = align)
}

// the integer argument `name` into `value`, -1 when absent; false with `errors` set when it is
// not an integer
def private int_arg(args : AnnotationArgumentList; name : string; var value : int&; var errors : das_string) : bool {
    let arg = find_arg(args, name)
    if (arg is nothing) {
        value = -1
        return true
    }
    if (!(arg is tInt)) {
        errors := "c_union: `{name}` is not an integer"
        return false
    }
    value = arg as tInt
    return true
}

// the shape the annotation takes: a struct with at least one member, none named `_storage`,
// none with an initializer, none of function type; false with `errors` set
def private check_shape(st : StructurePtr; var errors : das_string) : bool {
    if (st.flags.isClass) {
        errors := "c_union: {st.name} is a class; a union is a struct"
        return false
    }
    if (empty(st.fields)) {
        errors := "c_union: {st.name} has no member"
        return false
    }
    for (f in st.fields) {
        if (f.name == "_storage") {
            errors := "c_union: {st.name} has a member named `_storage`, the name of the storage field"
            return false
        }
        if (f.init != null) {
            errors := "c_union: member `{f.name}` has an initializer; a union starts at zero"
            return false
        }
        if (f._type.isFunction) {
            errors := "c_union: function-pointer member `{f.name}` of a union is not lowered yet"
            return false
        }
    }
    return true
}

// the union's size and alignment: the arguments when given, else derived from the members;
// false with `errors` set on arguments the storage cannot spell
def private layout(st : StructurePtr; args : AnnotationArgumentList; var size : int&; var align : int&; var errors : das_string) : bool {
    for (a in args) {
        if (a.name != "size" && a.name != "align") {
            errors := "c_union: unknown argument `{a.name}`; expecting `size` and `align`"
            return false
        }
    }
    if (!int_arg(args, "size", size, errors) || !int_arg(args, "align", align, errors)) {
        return false
    }
    if ((size < 0) != (align < 0)) {
        errors := "c_union: {st.name} gives one of `size` and `align`; give both or neither"
        return false
    }
    if (size < 0) {
        let derived = member_layout(st)
        if (derived.size == 0) {
            errors := "c_union: a member type of {st.name} is not known where it is declared; state `size` and `align`"
            return false
        }
        size = derived.size
        align = derived.align
    }
    if (empty(storage_of_bytes(align).name)) {
        errors := "c_union: alignment {align} of {st.name} is not 1, 2, 4 or 8"
        return false
    }
    if (size <= 0 || size % align != 0) {
        errors := "c_union: size {size} of {st.name} is not a positive multiple of its alignment {align}"
        return false
    }
    return true
}

// `operator . name`: over a `var` union (`by_ref`) a reference into the storage, over a const
// one the value; each after the inference-time check that the member fits the storage
def private make_operator(var st : StructurePtr; f : FieldDeclaration; size, align : int; by_ref : bool) : FunctionPtr {
    let message = "c_union: member `{f.name}` of {st.name} does not fit the storage of size {size} and alignment {align}"
    var fn <- qmacro_function(".`{f.name}") $(var s : $t(st)) : $t(f._type) {
        static_assert(typeinfo sizeof(type<$t(f._type)>) <= $v(size) && typeinfo alignof(type<$t(f._type)>) <= $v(align), $v(message))
        unsafe {
            return *addr<$t(f._type)?>(s._storage)
        }
    }
    if (by_ref) {
        fn.result.flags.ref = true
    } else {
        // a `s : T` parameter is `T const`, as the parser makes it
        fn.arguments[0]._type.flags.constant = true
    }
    fn.flags.generated = true
    fn.at = f.at
    return <- fn
}

[structure_macro(name = "c_union")]
class CUnionAnnotation : AstStructureAnnotation {
    def override apply(var st : StructurePtr; var group : ModuleGroup; var args : AnnotationArgumentList; var errors : das_string) : bool {
        if (!check_shape(st, errors)) {
            return false
        }
        var size, align : int
        if (!layout(st, args, size, align, errors)) {
            return false
        }
        for (f in st.fields) {
            // a twin a source spells itself is the parser's error, before this runs
            for (by_ref in fixed_array(true, false)) {
                var fn <- make_operator(st, f, size, align, by_ref)
                compiling_module() |> add_function(fn)
            }
        }
        let at = st.fields[0].at
        while (length(st.fields) > 1) {
            st.fields |> erase(length(st.fields) - 1)
        }
        st.fields[0].name := "_storage"
        st.fields[0]._type = make_fixed_array_type(size / align, new TypeDecl(baseType = storage_of_bytes(align).base, at = at))
        return true
    }
}
