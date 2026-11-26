options gen2

module dumper_a public

require strings
require math
require daslib/strings_boost
require daslib/fio
require daslib/json_boost
require crt
require cbind
require daslib/safe_addr
require daslib/algorithm
require cir
require bit_units
require macro_sites
require ../frontend/c_defines.das

//! Dumper A: `clang -ast-dump=json` normalized into C-IR. Fails closed: the first construct it
//! cannot represent exactly stops the dump with a location in `error`.

// one field of a record as libclang lays it out; `spelling` is the canonical type spelling,
// the same text the JSON dump desugars the field's type to
struct ClangField {
    name : string
    loc_key : string
    spelling : string
    bit_off : int64
    bit_w : int
    is_bitfield : bool
}

// one record definition of the translation unit with clang's size, alignment and fields,
// keyed by its canonical spelling (`struct X`, `struct (unnamed at f:l:c)`) and its location;
// a tag defined again keeps the dump's spelling in `c_spelling` and takes a numbered one
struct ClangRecord {
    spelling : string
    c_spelling : string
    block_scope : bool
    // defined in a function's parameter list, a scope that ends with the declarator
    prototype_scope : bool
    at : CirLoc
    is_union : bool
    size : int64
    align : int64
    fields : array<ClangField>
}

// one enum definition of the translation unit, keyed like a record; `underlying_*` describe
// the integer type clang chose for it
struct ClangEnum {
    spelling : string
    items : array<CirEnumItem>
    underlying_w : int64
    underlying_signed : bool
    spelling_shared : bool
}

// an enum constant the source spells, by its enum's spelling
struct ClangEnumRef {
    item : string
    enum_spelling : string
}

def private is_constant(r : ClangEnumRef) : bool => !empty(r.item)

// an `offsetof(T, f)` as libclang sees it: the type as the source spells it and the member; `path`
// when the designator is more than one member (`a.b`, `arr[2]`); `in_init` when it sits in an
// initializer list, whose designators order libclang's walk by the source and the dump's by the
// object
struct ClangOffsetof {
    type_text : string
    member : string
    path : bool
    in_init : bool
}

struct Dumper {
    tu : CirTu
    layout : LayoutMemo
    error : string
    cur_file : string
    cur_line : int
    type_index : table<string; int>
    tu_prefix : string
    c_path : string
    // the canonical program root (the sidecar's `program_root`, else the main file's directory)
    // with a trailing `/`: a declaration in a file under it belongs to the program
    program_dir : string
    // the own libc headers' folder, canonical with a trailing `/`: a file under it is external
    // though it lies under `program_dir`
    own_headers_dir : string
    // every record and enum definition of the unit as the layout guard compares it
    layouts : LayoutSet
    // where each enum of `enum_by_loc` is defined, for the guard's message
    enum_ats : table<string; CirLoc>
    // each file name the dump or libclang spells, made canonical
    canonical_files : table<string; string>
    linkage_names : table<string; string>
    current_fn : string
    // the C-IR name of every declaration of the program by clang's declaration id: a reference
    // binds by the id clang resolved, never by its spelling, so a local hiding a static keeps
    // its own binding (`docs/probe-findings.md` F47)
    decl_names : table<string; string>
    // the hoisted names of static locals taken so far
    hoisted_names : table<string>
    // clang's implicit declaration of a library function by declaration id: its type spelling
    library_decls : table<string; string>
    // a library function the unit redeclares with another result (`int strlen(char *)`, C99
    // 6.2.7's undefined behaviour): the library's result type a call returns before C's
    // conversion to the declared one
    library_results : table<string; int>
    // the wrapper standing for each such function's value (`library_value`)
    library_wrappers : table<string; string>
    // those declared without a prototype, whose value has no parameters to pass on
    library_unprototyped : table<string>
    // the callee of a call is being dumped: a library function's name there is a call, not a value
    dumping_callee : bool
    // every file-scope name the unit's dump declares (a system header's included, so a libc
    // function the unit calls), and every parameter and local of the function being dumped: a
    // hoisted local static's name passes both
    file_scope_names : table<string>
    fn_all_locals : table<string>
    // the names the current function's block-scope `extern` declarations and prototypes declare
    fn_extern_names : table<string>
    records : array<ClangRecord>
    record_by_spelling : table<string; int>
    // the tags defined more than once (`struct T` at file scope and again in a block), the
    // file-scope definition of each, and the block scopes the walk is in, innermost last, each
    // binding such a tag to the record a block defines (`scoped_record`)
    shared_tags : table<string>
    file_record_by_tag : table<string; int>
    tag_scopes : array<table<string; int>>
    // the scopes below this index are set aside while a file-scope record's fields are read
    tag_floor : int
    // after a tag's second definition, the record each expression's type names by that tag, by
    // the key of the expression's first token (libclang's answer: `s1.x` in a block that hides
    // `s1`'s tag is the outer record's), -1 where two expressions there disagree; and the key of
    // the expression whose type is being read
    expr_records : table<string; table<string; int>>
    expr_key : string
    // the names of the program's functions and variables, which a numbered tag avoids: das
    // spells a record's constructor as a call of its name
    unit_names : table<string>
    // the declaration statement being dumped declares a tag and nothing else (`struct T;`)
    lone_tag_decl : bool
    record_by_loc : table<string; int>
    record_hash : table<string; uint>
    typedef_spellings : table<string; string>
    anon_spellings : table<string; string>
    enums : array<ClangEnum>
    enum_by_spelling : table<string; int>
    enum_by_loc : table<string; int>
    enum_ref_by_loc : table<string; ClangEnumRef>
    enum_dims_by_loc : table<string; array<ClangEnumRef>>
    // the `offsetof` expressions at each key, in tree order: one macro expansion can spell two
    // (both keyed at the expansion site and at stddef.h's `__builtin_offsetof`), and the JSON walk
    // takes them in the same order, counting each key's nodes
    offsetofs_by_loc : table<string; array<ClangOffsetof>>
    offsetof_taken : table<string; int>
    // where the dump first met each key's `offsetof`, and how many initializer lists enclose the
    // cursor libclang's walk is at
    offsetof_at : table<string; CirLoc>
    init_lists : int
    // the text of each file a macro expansion names, read on first use, and one past the offset
    // of the object-like macro expansion whose node the dump is in (0 outside one)
    macro_texts : table<string; string>
    macro_in : int64
    // one past the offset each end of the enclosing expression's range expands from: a node that
    // shares an end's expansion with its parent is a piece of the parent's macro, never the whole
    parent_begin : int64
    parent_end : int64
    // clang's answer to each `__builtin_constant_p` call by its key (`register_constant_p`): 1 or
    // 0, or `CONSTANT_P_NESTED` or `CONSTANT_P_SPLIT` for a call the conversion refuses
    constant_p_by_loc : table<string; int>
    // libclang's canonical spelling of each `typeof (...)` a declaration or a cast of the program
    // spells, by clang's spelling of it; "" where two of one spelling name different types
    typeof_spellings : table<string; string>
    // those naming a function, an array or a pointer to one, whose spelling takes a declarator
    typeof_declarators : table<string>
    // the type being read is the operand of a `sizeof`, an `_Alignof` or a `va_arg`, a place the
    // libclang pass reads no type of: a `typeof` there is never resolved by its spelling
    type_operand : bool
    // clang's value of each `sizeof`-like expression it folds, by its key (`register_trait_value`),
    // `TRAIT_SPLIT` where two at one key differ: GNU `__alignof` reads it
    trait_by_loc : table<string; int64>
    // the text of each file that spells a `__builtin_types_compatible_p`, "" for any other file
    // (`spells_types_compatible`)
    trait_texts : table<string; string>
    // the labels of the function being dumped, by the id a GotoStmt names
    label_names : table<string; string>
    // the typedef names whose declaration reaches clang's implicit `__builtin_va_list`, and the
    // names of every other typedef, from the libclang pass; a name in both is declared each way
    // in some scope (`va_word`)
    va_names : table<string>
    other_names : table<string>
    // the JSON ids of the typedef declarations that reach the builtin, which a node's type
    // names as `typeAliasDeclId`
    va_ids : table<string>
    // the JSON ids of the typedef declarations whose type carries `__attribute__((aligned(N)))`,
    // their own or one down their chain, to clang's alignment (N; 0 for an attribute the dumper
    // does not read: no value, or an array's element), and their names
    aligned_ids : table<string; int>
    aligned_names : table<string>
    // the macro names clang spells in a type in place of the calling convention they expand to
    // (wasm3's `vectorcall` for `__attribute__((preserve_none))`), from its `MacroQualifiedType`s
    convention_macros : table<string>
    // the bytes of clang's JSON dump
    json_bytes : int64
    // libclang's macro definitions and expansions, and the function-like expansions found in the
    // dump (`macro_sites.das`)
    fn_macros : MacroIndex
    // why the conversion refuses each asm statement by its key (`register_asm`), "" for a barrier
    asm_by_loc : table<string; string>
    // the names the program defines (a function with a body, a variable with no `extern` or
    // with an initializer): a `weak` attribute is dropped only on one of these
    defined_names : table<string>
    // the records of an external file the program reaches a member, a variable or the size of
    // (`struct tm`, `struct lconv`), by index into `records`: each is anchored where it is
    // first interned, since the walk skips its file
    external_records : table<int>
}

def private fail(var d : Dumper; what : string; at : CirLoc) {
    if (empty(d.error)) {
        d.error = "{at.file}:{at.line}:{at.col}: {what}"
    }
}

def private node_kind(js : JsonValue?) : string => js?["kind"] ?? ""

def private is_present(v : JsonValue?) : bool => v != null && !(v is _null)

def private child_count(js : JsonValue?) : int {
    let inner = js?["inner"]
    return inner != null && inner is _array ? length(inner as _array) : 0
}

def private has_loc(js : JsonValue?) : bool => is_present(js?["loc"])

// a location as the dump reports it: the expansion site of a macro-produced node, else its own
def private loc_given(js : JsonValue?) : JsonValue const? {
    let given = has_loc(js) ? js?["loc"] : js?["range"]?["begin"]
    return is_present(given?["expansionLoc"]) ? given?["expansionLoc"] : given
}

// a node's location: `complete_locs` gave every valid location its file and line; an invalid
// one (`{}`, a builtin's) takes the last valid one's
def private loc_of(var d : Dumper; js : JsonValue?) : CirLoc {
    let at = loc_given(js)
    if (is_present(at?["file"])) {
        d.cur_file = at?["file"] ?? ""
        d.cur_line = int(at?["line"] ?? 0l)
    }
    return CirLoc(file = d.cur_file, line = d.cur_line, col = int(at?["col"] ?? 0l))
}

// the file and line clang last wrote, the state it omits a repeating `file` and `line` against
struct LocState {
    file : string
    line : int64
}

// one location without a `spellingLoc` split: the state clang compared it against moves on, and
// a `file` or `line` clang omitted is written back from it
def private complete_bare(var at : JsonValue?; var last : LocState&) {
    if (!is_present(at?["offset"])) {
        return
    }
    if (is_present(at?["file"])) {
        last.file = at?["file"] ?? ""
        last.line = at?["line"] ?? 0l
        return
    }
    if (is_present(at?["line"])) {
        last.line = at?["line"] ?? 0l
    } else {
        (at as _object)["line"] = new JsonValue(value <- JsValue(_longint = last.line))
    }
    (at as _object)["file"] = JV(last.file)
}

def private complete_loc(var at : JsonValue?; var last : LocState&) {
    if (is_present(at?["spellingLoc"])) {
        complete_bare(at?["spellingLoc"], last)
        complete_bare(at?["expansionLoc"], last)
    } else {
        complete_bare(at, last)
    }
}

// clang writes a location's `file` and `line` only where they differ from the last location it
// wrote, over every location of the dump in print order: a node's `loc` (a macro-produced one as
// its `spellingLoc`, then its `expansionLoc`), its `range.begin` and `range.end`, then its
// children, `array_filler` before `inner`; an `includedFrom` file is not part of that state.
// This walk writes the omitted values back, so every valid location names its own file and line
[arch(at="ARCHITECTURE_DUMPER.md#file-policy")]
def private complete_locs(var js : JsonValue?; var last : LocState&) {
    if (!(js is _object)) {
        return
    }
    complete_loc(js?["loc"], last)
    complete_loc(js?["range"]?["begin"], last)
    complete_loc(js?["range"]?["end"], last)
    for (key in fixed_array("array_filler", "inner")) {
        var kids = js?[key]
        if (kids is _array) {
            for (kid in kids as _array) {
                complete_locs(kid, last)
            }
        }
    }
}

// the record definitions of the program through libclang, nested ones included, under the
// same target and dialect flags as the JSON dump; the pass is the layout read-out of
// docs/very-detailed-plan.md section 4.1
def private register_record(var d : Dumper; var c : CXCursor) {
    let key = cursor_key(d, c)
    if (key_exists(d.record_by_loc, key)) {
        // a block-scoped record is visited under its statement and again under the variable's
        // type; another cursor at the same key is a second record one macro expansion made
        if ((d.record_hash?[key] ?? 0u) != clang_hashCursor(c)) {
            fail(d, "anonymous records from one macro expansion are not dumped yet", cursor_loc(c))
        }
        return
    }
    var ct = clang_getCursorType(c)
    let is_union = clang_getCursorKind(c) == CXCursorKind.UnionDecl
    // libclang spells an anonymous record by its typedef name alone (`thinker_t`) where the
    // JSON dump keeps the tag (`struct thinker_t`); the dump's spelling is the key
    let raw = unscoped_spelling(string(clang_getTypeSpelling(ct)))
    let tagged = raw |> starts_with("struct ") || raw |> starts_with("union ")
    var rec = ClangRecord(spelling = tagged ? raw : (is_union ? "union " : "struct ") + raw, is_union = is_union, size = clang_Type_getSizeOf(ct), align = clang_Type_getAlignOf(ct), block_scope = in_block_scope(c), prototype_scope = in_prototype_scope(c), at = cursor_loc(c))
    rec.c_spelling = rec.spelling
    // an unnamed record is spelled by its expansion location, which a macro shares
    let unnamed = find(rec.spelling, "(anonymous ") >= 0 || find(rec.spelling, "(unnamed ") >= 0
    if (key_exists(d.record_by_spelling, rec.spelling)) {
        if (unnamed) {
            fail(d, "anonymous records from one macro expansion are not dumped yet", cursor_loc(c))
            return
        }
        // a tag defined again in another scope: keyed apart until `name_shared_tags` names it
        d.shared_tags |> insert(rec.spelling)
        rec.spelling = "{rec.spelling}#{length(d.records)}"
    }
    if (!tagged) {
        d.anon_spellings[raw] = rec.spelling
    }
    clang_visitChildren(c) $(var fc, _fp) {
        let fk = clang_getCursorKind(fc)
        if ((fk == CXCursorKind.StructDecl || fk == CXCursorKind.UnionDecl) && clang_isCursorDefinition(fc) != 0u) {
            register_record(d, fc)
            let inner = d.record_by_loc?[cursor_key(d, fc)] ?? -1
            if (inner >= 0 && clang_Cursor_isAnonymousRecordDecl(fc) != 0u) {
                // an anonymous member: libclang visits its record, never the implicit field
                let bit_off = anonymous_offset(d, ct, inner)
                if (bit_off < 0l) {
                    fail(d, "anonymous member of `{rec.spelling}` exposes no field name; not dumped yet", cursor_loc(fc))
                }
                var canonical = clang_getCanonicalType(clang_getCursorType(fc))
                rec.fields |> push(ClangField(loc_key = cursor_key(d, fc), spelling = string(clang_getTypeSpelling(canonical)), bit_off = bit_off))
            }
        } elif (fk == CXCursorKind.EnumDecl && clang_isCursorDefinition(fc) != 0u) {
            register_enum(d, fc)
        } elif (fk == CXCursorKind.FieldDecl) {
            register_dims(d, fc)
            var declared = clang_getCursorType(fc)
            // a program record holding an external one by value (`struct tm t;`) needs its layout
            register_external_type(d, declared)
            var canonical = clang_getCanonicalType(declared)
            let is_bf = clang_Cursor_isBitField(fc) != 0u
            // a `va_list` field is known by its declaration chain, which the msvc canonical
            // `char *` loses
            let va = type_holds_va(declared)
            let spelling = va == VA_EXACT ? VA_BUILTIN : string(clang_getTypeSpelling(canonical))
            if (va == VA_INSIDE) {
                fail(d, "`{string(clang_getTypeSpelling(declared))}`: a pointer to a `va_list` or an array of them is not lowered yet", cursor_loc(fc))
            }
            rec.fields |> push(ClangField(name = string(clang_getCursorSpelling(fc)), loc_key = cursor_key(d, fc), spelling = spelling, bit_off = clang_Cursor_getOffsetOfField(fc), bit_w = is_bf ? clang_getFieldDeclBitWidth(fc) : 0, is_bitfield = is_bf))
        }
        return CXChildVisitResult.Continue
    }
    let idx = length(d.records)
    if (!rec.block_scope && !unnamed) {
        d.file_record_by_tag[rec.c_spelling] = idx
    }
    d.record_by_spelling[rec.spelling] = idx
    d.record_by_loc[key] = idx
    d.record_hash[key] = clang_hashCursor(c)
    d.records |> emplace(rec)
}

// whether a record definition lies in a block: C scopes a record nested in another with the
// outer one, and libclang's semantic parent of either is then the unit
def private in_block_scope(var c : CXCursor) : bool => clang_getCursorKind(clang_getCursorSemanticParent(c)) != CXCursorKind.TranslationUnit

// whether a record definition lies in a function's parameter list: before the function's body
def private in_prototype_scope(var c : CXCursor) : bool {
    var owner = clang_getCursorSemanticParent(c)
    if (clang_getCursorKind(owner) != CXCursorKind.FunctionDecl) {
        return false
    }
    var body_at = -1
    clang_visitChildren(owner) $(var kid, _parent) {
        if (clang_getCursorKind(kid) == CXCursorKind.CompoundStmt) {
            body_at = cursor_offset(kid)
        }
        return CXChildVisitResult.Continue
    }
    return body_at < 0 || cursor_offset(c) < body_at
}

// a cursor's expansion offset in its file
def private cursor_offset(var c : CXCursor) : int {
    var file : CXFile
    var line, column, offset : uint
    clang_getExpansionLocation(clang_getCursorLocation(c), safe_addr(file), safe_addr(line), safe_addr(column), safe_addr(offset))
    return int(offset)
}

// each record whose tag another definition took first gets the first numbered tag no record,
// enum or typedef of the unit spells (`struct T` again in a block is `struct T1`)
[arch(at="ARCHITECTURE_DUMPER_TAGS.md#shared-tags")]
def private name_shared_tags(var d : Dumper) {
    var taken : table<string>
    for (rec in d.records) {
        taken |> insert(tag_of(rec.c_spelling))
    }
    for (en in d.enums) {
        taken |> insert(tag_of(en.spelling))
    }
    for (name in keys(d.typedef_spellings)) {
        taken |> insert(name)
    }
    for (name in keys(d.unit_names)) {
        taken |> insert(name)
    }
    for (ridx in range(length(d.records))) {
        if (d.records[ridx].prototype_scope && key_exists(d.shared_tags, d.records[ridx].c_spelling)) {
            fail(d, "`{d.records[ridx].c_spelling}` defined in a parameter list, while the file defines it elsewhere too; not lowered yet", d.records[ridx].at)
            return
        }
        let temp = d.records[ridx].spelling
        if (find(temp, "#") < 0) {
            continue
        }
        let tag = tag_of(d.records[ridx].c_spelling)
        var n = 1
        while (key_exists(taken, "{tag}{n}")) {
            n++
        }
        taken |> insert("{tag}{n}")
        d.records[ridx].spelling = "{d.records[ridx].is_union ? "union" : "struct"} {tag}{n}"
        d.record_by_spelling |> erase(temp)
        d.record_by_spelling[d.records[ridx].spelling] = ridx
    }
}

// the tag of a `struct`, `union` or `enum` spelling
def private tag_of(spelling : string) : string {
    let space = find(spelling, " ")
    return space < 0 ? spelling : slice(spelling, space + 1)
}

// the bit offset of anonymous member record `inner` inside the record of type `ct`: clang
// answers by a name the member makes visible, less that name's offset inside the member; -1
// when it makes none visible
def private anonymous_offset(d : Dumper; var ct : CXType; inner : int) : int64 {
    var name_bit_off = 0l
    let name = visible_name(d, inner, 0, name_bit_off)
    if (empty(name)) {
        return -1l
    }
    let at = clang_Type_getOffsetOf(ct, name)
    return at < 0l ? -1l : at - name_bit_off
}

// a named field record `idx` makes visible, through its own anonymous members (at most
// `MAX_ANONYMOUS_DEPTH` deep), and its bit offset inside the record (into `bit_off`); "" when
// there is none
def private visible_name(d : Dumper; idx, depth : int; var bit_off : int64&) : string {
    if (depth > MAX_ANONYMOUS_DEPTH) {
        return ""
    }
    for (f in d.records[idx].fields) {
        if (!empty(f.name)) {
            bit_off = f.bit_off
            return f.name
        }
        let inner = f.is_bitfield ? -1 : d.record_by_loc?[f.loc_key] ?? -1
        if (inner >= 0 && inner != idx && f.bit_off >= 0l) {
            var name_bit_off = 0l
            let name = visible_name(d, inner, depth + 1, name_bit_off)
            if (!empty(name)) {
                bit_off = f.bit_off + name_bit_off
                return name
            }
        }
    }
    return ""
}

// how deep `visible_name` follows anonymous members inside anonymous members
let private MAX_ANONYMOUS_DEPTH = 64

// a file name as the dump or libclang spells it, made canonical (symbolic links and `..`
// resolved); "" for a buffer that is no file (`<scratch space>`, `<built-in>`)
def private canonical_file(var d : Dumper; name : string) : string {
    if (empty(name) || name |> starts_with("<")) {
        return ""
    }
    var full = d.canonical_files?[name] ?? ""
    if (empty(full)) {
        full = get_full_file_name(name)
        d.canonical_files[name] = full
    }
    return full
}

// whether a declaration in file `name` belongs to the program: a file under the program root
// outside the own libc headers' folder; every other file (a libc header's) is external
[arch(at="ARCHITECTURE_DUMPER.md#file-policy")]
def private in_program(var d : Dumper; name : string) : bool {
    let full = canonical_file(d, name)
    return full |> starts_with(d.program_dir) && !(full |> starts_with(d.own_headers_dir))
}

// the file of a libclang location, as `clang_getExpansionLocation` and its siblings give it
def private file_name(var file : CXFile) : string => file == null ? "" : string(clang_getFileName(file))

// a cursor's location as the dump reports it: the expansion file, line and column
def private cursor_loc(var c : CXCursor) : CirLoc {
    var file : CXFile
    var line, column, offset : uint
    clang_getExpansionLocation(clang_getCursorLocation(c), safe_addr(file), safe_addr(line), safe_addr(column), safe_addr(offset))
    return CirLoc(file = file_name(file), line = int(line), col = int(column))
}

// the key that joins a libclang cursor to the JSON dump's node for it: the canonical file and
// byte offset of the expansion site and of the spelling (the two differ for a macro-produced
// token, and are the token's own otherwise); the offset, unlike the line, is on every JSON
// location, and `complete_locs` gives each its file
[arch(at="ARCHITECTURE_DUMPER.md#file-policy")]
def private cursor_key(var d : Dumper; var c : CXCursor) : string {
    var file, spelled_file : CXFile
    var line, column, offset, spelled : uint
    var loc = clang_getCursorLocation(c)
    clang_getExpansionLocation(loc, safe_addr(file), safe_addr(line), safe_addr(column), safe_addr(offset))
    clang_getSpellingLocation(loc, safe_addr(spelled_file), safe_addr(line), safe_addr(column), safe_addr(spelled))
    return "{canonical_file(d, file_name(file))}:{int(offset)}:{canonical_file(d, file_name(spelled_file))}:{int(spelled)}"
}

def private node_key(var d : Dumper; js : JsonValue?) : string {
    let given = has_loc(js) ? js?["loc"] : js?["range"]?["begin"]
    let at = is_present(given?["expansionLoc"]) ? given?["expansionLoc"] : given
    let spelled = is_present(given?["spellingLoc"]) ? given?["spellingLoc"] : given
    return "{canonical_file(d, at?["file"] ?? "")}:{int(at?["offset"] ?? -1l)}:{canonical_file(d, spelled?["file"] ?? "")}:{int(spelled?["offset"] ?? -1l)}"
}

// the key of a node's first token, as `extent_key` gives a cursor's
def private begin_key(var d : Dumper; js : JsonValue?) : string {
    let given = js?["range"]?["begin"]
    let at = is_present(given?["expansionLoc"]) ? given?["expansionLoc"] : given
    let spelled = is_present(given?["spellingLoc"]) ? given?["spellingLoc"] : given
    return "{canonical_file(d, at?["file"] ?? "")}:{int(at?["offset"] ?? -1l)}:{canonical_file(d, spelled?["file"] ?? "")}:{int(spelled?["offset"] ?? -1l)}"
}

// the key of a cursor's first token, in `cursor_key`'s form
def private extent_key(var d : Dumper; var c : CXCursor) : string {
    var file, spelled_file : CXFile
    var line, column, offset, spelled : uint
    var loc = clang_getRangeStart(clang_getCursorExtent(c))
    clang_getExpansionLocation(loc, safe_addr(file), safe_addr(line), safe_addr(column), safe_addr(offset))
    clang_getSpellingLocation(loc, safe_addr(spelled_file), safe_addr(line), safe_addr(column), safe_addr(spelled))
    return "{canonical_file(d, file_name(file))}:{int(offset)}:{canonical_file(d, file_name(spelled_file))}:{int(spelled)}"
}

// every program expression whose type names a tag defined more than once, noted for
// `scoped_record`, once every definition is registered
[arch(at="ARCHITECTURE_DUMPER_TAGS.md#shared-tags")]
def private note_shared_exprs(var d : Dumper; var c : CXCursor) {
    clang_visitChildren(c) $(var kid, _parent) {
        if (!in_program(d, cursor_loc(kid).file)) {
            return CXChildVisitResult.Continue
        }
        if (clang_isExpression(clang_getCursorKind(kid)) != 0u) {
            note_expr_record(d, kid)
        }
        return CXChildVisitResult.Recurse
    }
}

// the record of a tag defined more than once that expression `c`'s type names, through pointers
// and arrays, noted at the expression's first token for `scoped_record`
[arch(at="ARCHITECTURE_DUMPER_TAGS.md#shared-tags")]
def private note_expr_record(var d : Dumper; var c : CXCursor) {
    var t = clang_getCanonicalType(clang_getCursorType(c))
    while (t.kind == CXTypeKind.Pointer || t.kind == CXTypeKind.ConstantArray || t.kind == CXTypeKind.IncompleteArray) {
        t = clang_getCanonicalType(t.kind == CXTypeKind.Pointer ? clang_getPointeeType(t) : clang_getArrayElementType(t))
    }
    if (t.kind != CXTypeKind.Record) {
        return
    }
    var definition = clang_getCursorDefinition(clang_getTypeDeclaration(t))
    if (clang_Cursor_isNull(definition) != 0) {
        return
    }
    let ridx = d.record_by_loc?[cursor_key(d, definition)] ?? -1
    if (ridx < 0 || !key_exists(d.shared_tags, d.records[ridx].c_spelling)) {
        return
    }
    let key = extent_key(d, c)
    let tag = d.records[ridx].c_spelling
    let known = d.expr_records?[key]?[tag] ?? ridx
    d.expr_records[key][tag] = known == ridx ? ridx : -1
}

// an enum definition with clang's evaluated values; a typedef-named anonymous enum takes its
// tag back the way a record does
def private register_enum(var d : Dumper; var c : CXCursor) {
    // a block-scoped enum is visited under its statement and again under the variable's type
    if (key_exists(d.enum_by_loc, cursor_key(d, c))) {
        return
    }
    var underlying = clang_getEnumDeclIntegerType(c)
    var en = ClangEnum(spelling = own_spelling(d, c, "enum"), underlying_w = clang_Type_getSizeOf(underlying) * 8l, underlying_signed = !(string(clang_getTypeSpelling(underlying)) |> starts_with("unsigned ")))
    clang_visitChildren(c) $(var ic, _ip) {
        if (clang_getCursorKind(ic) == CXCursorKind.EnumConstantDecl) {
            // the value as C reads it: past INT_MAX for an unsigned underlying type
            let v = en.underlying_signed ? clang_getEnumConstantDeclValue(ic) : int64(clang_getEnumConstantDeclUnsignedValue(ic))
            en.items |> push(CirEnumItem(name = string(clang_getCursorSpelling(ic)), v = v))
        }
        return CXChildVisitResult.Continue
    }
    let idx = length(d.enums)
    // block-scoped enums of one tag cannot be told apart by the dump's spelling
    let earlier = d.enum_by_spelling?[en.spelling] ?? -1
    if (earlier >= 0) {
        d.enums[earlier].spelling_shared = true
        en.spelling_shared = true
    }
    d.enum_by_spelling[en.spelling] = idx
    d.enum_by_loc[cursor_key(d, c)] = idx
    d.enum_ats[cursor_key(d, c)] = cursor_loc(c)
    d.enums |> emplace(en)
}

// the dump's spelling of a tagged type: libclang spells a typedef-named anonymous one by the
// typedef name alone, where the dump keeps the tag
def private own_spelling(var d : Dumper; var c : CXCursor; tag : string) : string {
    let raw = unscoped_spelling(string(clang_getTypeSpelling(clang_getCursorType(c))))
    if (raw |> starts_with(tag + " ")) {
        return raw
    }
    d.anon_spellings[raw] = tag + " " + raw
    return tag + " " + raw
}

// the enum constant a `DeclRefExpr` names, with its enum's spelling; empty for any other cursor
def private enum_constant_of(var c : CXCursor) : ClangEnumRef {
    var ref = clang_getCursorReferenced(c)
    if (clang_getCursorKind(ref) != CXCursorKind.EnumConstantDecl) {
        return ClangEnumRef()
    }
    var owner = clang_getCursorSemanticParent(ref)
    return ClangEnumRef(item = string(clang_getCursorSpelling(ref)), enum_spelling = unscoped_spelling(string(clang_getTypeSpelling(clang_getCursorType(owner)))))
}

// the dimensions of an array declarator, outermost first: libclang lists the size expressions
// as children innermost first, and a variable's initializer after them
def private register_dims(var d : Dumper; var c : CXCursor) {
    var init = clang_getCursorKind(c) == CXCursorKind.VarDecl ? clang_Cursor_getVarDeclInitializer(c) : clang_getNullCursor()
    var dims : array<ClangEnumRef>
    var named = false
    clang_visitChildren(c) $(var kid, _kp) {
        let kk = clang_getCursorKind(kid)
        if (clang_isExpression(kk) == 0u || clang_equalCursors(kid, init) != 0u) {
            return CXChildVisitResult.Continue
        }
        let ref = enum_constant_of(kid)
        dims |> push(ref)
        named = named || is_constant(ref)
        return CXChildVisitResult.Continue
    }
    if (named) {
        dims |> reverse()
        d.enum_dims_by_loc[cursor_key(d, c)] <- dims
    }
}

// an `offsetof(T, f)`, which libclang shows as an unexposed expression whose children are the
// type's reference, then one member reference per designator member (an index an expression); a
// designated initializer has member references but no type reference
def private register_offsetof(var d : Dumper; var c : CXCursor) {
    var off : ClangOffsetof
    var members = 0
    var others = 0
    clang_visitChildren(c) $(var kid, _kp) {
        let kind = clang_getCursorKind(kid)
        if (kind == CXCursorKind.TypeRef && empty(off.type_text)) {
            off.type_text = string(clang_getCursorSpelling(kid))
        } elif (kind == CXCursorKind.MemberRef) {
            off.member = string(clang_getCursorSpelling(kid))
            members++
        } else {
            others++
        }
        return CXChildVisitResult.Continue
    }
    if (members == 0 || empty(off.type_text)) {
        return
    }
    off.path = members > 1 || others > 0
    off.in_init = d.init_lists > 0
    let key = cursor_key(d, c)
    if (!key_exists(d.offsetofs_by_loc, key)) {
        d.offsetofs_by_loc[key] <- array<ClangOffsetof>()
    }
    d.offsetofs_by_loc[key] |> emplace(off)
}

// an asm statement, as clang parsed it (the template a macro argument gives included): a compiler
// barrier, an empty template with no operand and no `goto` and at most clobbers, is "", since it
// orders nothing a das run observes; any other is the reason the conversion refuses it, an asm one
// macro expansion spells twice from one token keeping the first refusal
[arch(at="ARCHITECTURE_DUMPER.md#attributes-and-asm")]
def private register_asm(var d : Dumper; var c : CXCursor) {
    var reason = ""
    if (clang_Cursor_isGCCAssemblyHasGoto(c) != 0u) {
        reason = "`asm goto` jumps to a label from machine code; no emulation exists in the das runtime"
    } elif (!empty(string(clang_Cursor_getGCCAssemblyTemplate(c)))) {
        reason = "inline asm with template text is machine code; no emulation exists in the das runtime"
    } elif (clang_Cursor_getGCCAssemblyNumOutputs(c) != 0u || clang_Cursor_getGCCAssemblyNumInputs(c) != 0u) {
        reason = "inline asm with operands is a register binding; no emulation exists in the das runtime"
    }
    let key = cursor_key(d, c)
    let earlier = d.asm_by_loc?[key] ?? ""
    d.asm_by_loc[key] = empty(earlier) ? reason : earlier
}

let CONSTANT_P = "__builtin_constant_p"

// a `__builtin_constant_p` whose argument holds another one clang's evaluator cannot fold: the
// -O0 build answers by what its code generator folds, which no evaluation reproduces
let CONSTANT_P_NESTED = -1

// two calls at one key (one macro expansion spelling both from one token) clang answers apart
let CONSTANT_P_SPLIT = -2

// a call the libclang pass never met
let CONSTANT_P_UNSEEN = -3

// a `__builtin_constant_p` the evaluator cannot fold whose argument holds a comma operator: the
// code generator emits the right operand on its own, which can be a constant
let CONSTANT_P_COMMA = -4

// clang's answer to a `__builtin_constant_p` call, as the pinned clang's -O0 build gives it: the
// evaluator's fold of the call (`clang_Cursor_Evaluate`); where it gives none the build answers
// `llvm.is_constant` over the value its code generator emits for the argument, which is 0 but
// across a comma operator, whose right operand the generator emits on its own, or a nested call:
// those two are refused (`probes/test_toolchain.das`)
[arch(at="ARCHITECTURE_DUMPER.md#builtin-constant-p")]
def private register_constant_p(var d : Dumper; var c : CXCursor) {
    if (string(clang_getCursorSpelling(c)) != CONSTANT_P) {
        return
    }
    var v = 0
    var res = clang_Cursor_Evaluate(c)
    if (res != null) {
        v = clang_EvalResult_getKind(res) == CXEvalResultKind.Int && clang_EvalResult_getAsLongLong(res) != 0l ? 1 : 0
        clang_EvalResult_dispose(res)
    } elif (holds_constant_p(c)) {
        v = CONSTANT_P_NESTED
    } elif (holds_comma(c)) {
        v = CONSTANT_P_COMMA
    }
    let key = cursor_key(d, c)
    let earlier = d.constant_p_by_loc?[key] ?? v
    d.constant_p_by_loc[key] = earlier == v ? v : CONSTANT_P_SPLIT
}

// clang's spelling of a GNU `typeof`, `__typeof__` included
let TYPEOF = "typeof"

// the `typeof (...)` types under type `t`, each with the canonical spelling of the type it names:
// the dump spells a `typeof` by its operand and desugars only a whole spelling, so one inside a
// pointer, an array or a function type (`typeof (x) *`) resolves by this spelling
def private register_typeof(var d : Dumper; var t : CXType) {
    if (find(string(clang_getTypeSpelling(t)), TYPEOF) < 0) {
        return
    }
    if (t.kind == CXTypeKind.Pointer) {
        register_typeof(d, clang_getPointeeType(t))
    } elif (t.kind == CXTypeKind.ConstantArray || t.kind == CXTypeKind.IncompleteArray) {
        register_typeof(d, clang_getArrayElementType(t))
    } elif (t.kind == CXTypeKind.FunctionProto || t.kind == CXTypeKind.FunctionNoProto) {
        // a parameter's type is its own declaration's, a cursor under the declarator's
        register_typeof(d, clang_getResultType(t))
    } else {
        var bare = clang_getUnqualifiedType(t)
        let spelled = string(clang_getTypeSpelling(bare))
        if (spelled |> starts_with(TYPEOF)) {
            var named = clang_getCanonicalType(bare)
            let canonical = string(clang_getTypeSpelling(named))
            let earlier = d.typeof_spellings?[spelled] ?? canonical
            d.typeof_spellings[spelled] = earlier == canonical ? canonical : ""
            while (named.kind == CXTypeKind.Pointer) {
                named = clang_getCanonicalType(clang_getPointeeType(named))
            }
            if (named.kind == CXTypeKind.ConstantArray || named.kind == CXTypeKind.IncompleteArray || named.kind == CXTypeKind.FunctionProto || named.kind == CXTypeKind.FunctionNoProto) {
                d.typeof_declarators |> insert(spelled)
            }
        }
    }
}

// the `typeof`s of cursor `c` when it spells a type: a declaration, a cast, a compound literal
def private register_typeof_site(var d : Dumper; var c : CXCursor; kind : CXCursorKind) {
    if (clang_isDeclaration(kind) != 0u || kind == CXCursorKind.CStyleCastExpr || kind == CXCursorKind.CompoundLiteralExpr) {
        register_typeof(d, kind == CXCursorKind.TypedefDecl ? clang_getTypedefDeclUnderlyingType(c) : clang_getCursorType(c))
    }
}

// the same over every cursor of the unit, the files outside the program included: a header's
// declaration can spell a `typeof` a program expression's type then carries, and a spelling
// resolves only when every place that spells it names one type
def private note_typeofs(var d : Dumper; var c : CXCursor) {
    clang_visitChildren(c) $(var kid, _parent) {
        register_typeof_site(d, kid, clang_getCursorKind(kid))
        return CXChildVisitResult.Recurse
    }
}

// two `sizeof`-like expressions at one key (one macro expansion spelling both from one token)
// that clang values apart
let TRAIT_SPLIT = -1l

// clang's value of `sizeof`-like expression `c`, where its evaluator folds one: the preferred
// alignment GNU `__alignof` asks for, a declaration's own (`__alignof__(f)` of an `aligned`
// function) included, is clang's to give
def private register_trait_value(var d : Dumper; var c : CXCursor) {
    var res = clang_Cursor_Evaluate(c)
    if (res == null) {
        return
    }
    if (clang_EvalResult_getKind(res) == CXEvalResultKind.Int) {
        let v = clang_EvalResult_getAsLongLong(res)
        let key = cursor_key(d, c)
        let earlier = d.trait_by_loc?[key] ?? v
        d.trait_by_loc[key] = earlier == v ? v : TRAIT_SPLIT
    }
    clang_EvalResult_dispose(res)
}

// the builtins whose value is clang's fold of the node (`register_trait_value`): a call of the
// first, and the type trait the second spells, which libclang shows as an unexposed expression
let CLASSIFY_TYPE = "__builtin_classify_type"
let TYPES_COMPATIBLE = "__builtin_types_compatible_p"

// whether cursor `c` is spelled from a `__builtin_types_compatible_p` token, by its file's text at
// the spelling location; the text of a file that never spells one is kept empty, so the pass
// pays for a comparison only where the trait is used
def private spells_types_compatible(var d : Dumper; var c : CXCursor) : bool {
    var file : CXFile
    var line, column, offset : uint
    clang_getSpellingLocation(clang_getCursorLocation(c), safe_addr(file), safe_addr(line), safe_addr(column), safe_addr(offset))
    let name = file_name(file)
    if (!key_exists(d.trait_texts, name)) {
        let text = stat(name).is_reg ? fread(name) : ""
        d.trait_texts[name] = find(text, TYPES_COMPATIBLE) >= 0 ? text : ""
    }
    return slice(d.trait_texts?[name] ?? "", int(offset), int(offset) + length(TYPES_COMPATIBLE)) == TYPES_COMPATIBLE
}

// whether a `__builtin_constant_p` call sits anywhere under cursor `c`
def private holds_constant_p(var c : CXCursor) : bool {
    var found = false
    clang_visitChildren(c) $(var kid, _parent) {
        found = clang_getCursorKind(kid) == CXCursorKind.CallExpr && string(clang_getCursorSpelling(kid)) == CONSTANT_P
        return found ? CXChildVisitResult.Break : CXChildVisitResult.Recurse
    }
    return found
}

// whether a comma operator sits anywhere under cursor `c`, casts included
def private holds_comma(var c : CXCursor) : bool {
    var found = false
    clang_visitChildren(c) $(var kid, _parent) {
        found = clang_getCursorKind(kid) == CXCursorKind.BinaryOperator && string(clang_getCursorSpelling(kid)) == ","
        return found ? CXChildVisitResult.Break : CXChildVisitResult.Recurse
    }
    return found
}

// the definition of an external file's record that `decl` declares, laid out like a program's,
// and every external record its fields hold by value; nothing for a program's record or one
// no file defines
[arch(at="ARCHITECTURE_DUMPER.md#file-policy")]
def private register_external(var d : Dumper; var decl : CXCursor) {
    let kind = clang_getCursorKind(decl)
    if (kind != CXCursorKind.StructDecl && kind != CXCursorKind.UnionDecl) {
        return
    }
    var definition = clang_getCursorDefinition(decl)
    if (clang_Cursor_isNull(definition) != 0 || in_program(d, cursor_loc(definition).file)) {
        return
    }
    // a record nested in an external one (`mbstate_t`'s anonymous union) is registered with it,
    // and is external all the same
    let key = cursor_key(d, definition)
    if (!key_exists(d.record_by_loc, key)) {
        register_record(d, definition)
    }
    let idx = d.record_by_loc?[key] ?? -1
    if (idx < 0 || key_exists(d.external_records, idx)) {
        return
    }
    d.external_records |> insert(idx)
    clang_visitChildren(definition) $(var fc, _fp) {
        if (clang_getCursorKind(fc) == CXCursorKind.FieldDecl) {
            register_external_type(d, clang_getCursorType(fc))
        }
        return CXChildVisitResult.Continue
    }
}

// `register_external` for the record a type holds by value, through arrays and typedefs
def private register_external_type(var d : Dumper; var t : CXType) {
    var canonical = clang_getCanonicalType(t)
    while (canonical.kind == CXTypeKind.ConstantArray || canonical.kind == CXTypeKind.IncompleteArray) {
        canonical = clang_getCanonicalType(clang_getArrayElementType(canonical))
    }
    if (canonical.kind == CXTypeKind.Record) {
        register_external(d, clang_getTypeDeclaration(canonical))
    }
}

// the external records a program expression reaches: a member's record (`localeconv()->
// decimal_point`) and the type `sizeof` or `_Alignof` names
def private register_external_use(var d : Dumper; var c : CXCursor) {
    let kind = clang_getCursorKind(c)
    if (kind == CXCursorKind.MemberRefExpr) {
        var field = clang_getCursorReferenced(c)
        if (clang_getCursorKind(field) == CXCursorKind.FieldDecl) {
            register_external(d, clang_getCursorSemanticParent(field))
        }
    } elif (kind == CXCursorKind.UnaryExpr) {
        // the type `sizeof` names, or its operand's (`sizeof *p`)
        clang_visitChildren(c) $(var kid, _kp) {
            let kk = clang_getCursorKind(kid)
            if (kk == CXCursorKind.TypeRef || clang_isExpression(kk) != 0u) {
                register_external_type(d, clang_getCursorType(kid))
            }
            return CXChildVisitResult.Continue
        }
    }
}

def private walk_records(var d : Dumper; var c : CXCursor) {
    clang_visitChildren(c) $(var kid, _parent) {
        let kind = clang_getCursorKind(kid)
        if (kind != CXCursorKind.TypedefDecl && kind != CXCursorKind.MacroDefinition && !in_program(d, cursor_loc(kid).file)) {
            return CXChildVisitResult.Continue
        }
        if (kind == CXCursorKind.FunctionDecl) {
            d.unit_names |> insert(string(clang_getCursorSpelling(kid)))
        }
        register_typeof_site(d, kid, kind)
        if ((kind == CXCursorKind.StructDecl || kind == CXCursorKind.UnionDecl) && clang_isCursorDefinition(kid) != 0u) {
            register_record(d, kid)
        } elif (kind == CXCursorKind.EnumDecl && clang_isCursorDefinition(kid) != 0u) {
            register_enum(d, kid)
        } elif (kind == CXCursorKind.VarDecl) {
            d.unit_names |> insert(string(clang_getCursorSpelling(kid)))
            register_dims(d, kid)
            // a variable of an external record (`struct tm ts;`) needs its layout
            register_external_type(d, clang_getCursorType(kid))
            walk_records(d, kid)
        } elif (kind == CXCursorKind.MemberRefExpr || kind == CXCursorKind.UnaryExpr) {
            register_external_use(d, kid)
            if (kind == CXCursorKind.UnaryExpr) {
                register_trait_value(d, kid)
            }
            walk_records(d, kid)
        } elif (kind == CXCursorKind.UnexposedExpr) {
            register_offsetof(d, kid)
            if (spells_types_compatible(d, kid)) {
                register_trait_value(d, kid)
            }
            walk_records(d, kid)
        } elif (kind == CXCursorKind.CallExpr) {
            register_constant_p(d, kid)
            if (string(clang_getCursorSpelling(kid)) == CLASSIFY_TYPE) {
                register_trait_value(d, kid)
            }
            walk_records(d, kid)
        } elif (kind == CXCursorKind.AsmStmt) {
            register_asm(d, kid)
            walk_records(d, kid)
        } elif (kind == CXCursorKind.InitListExpr) {
            d.init_lists++
            walk_records(d, kid)
            d.init_lists--
        } elif (kind == CXCursorKind.DeclRefExpr) {
            // a reference to an enum constant resolves by its location, since C scopes let
            // two enums of one file spell the same constant name
            let ref = enum_constant_of(kid)
            if (is_constant(ref)) {
                d.enum_ref_by_loc[cursor_key(d, kid)] = ref
            }
        } elif (kind == CXCursorKind.MacroExpansion) {
            register_macro_expansion(d, kid)
        } elif (kind == CXCursorKind.MacroDefinition) {
            register_macro_definition(d, kid)
        } elif (kind == CXCursorKind.TypedefDecl) {
            var under = clang_getTypedefDeclUnderlyingType(kid)
            var canonical = clang_getCanonicalType(under)
            let name = string(clang_getCursorSpelling(kid))
            d.typedef_spellings[name] = string(clang_getTypeSpelling(canonical))
            // the msvc `va_list` is canonically a `char *`, so a typedef is one by its
            // declaration chain
            if (typedef_reaches_va(kid)) {
                d.va_names |> insert(name)
            } else {
                d.other_names |> insert(name)
            }
        } else {
            walk_records(d, kid)
        }
        return CXChildVisitResult.Continue
    }
}

// a macro expansion in a program file: where its name stands, keyed to its definition; a system
// header's function-like macro is none of the program's, and an object-like one is kept only to
// find where an expansion's tokens are spelled
[arch(at="ARCHITECTURE_DUMPER_MACROS.md#fn-macros")]
def private register_macro_expansion(var d : Dumper; var c : CXCursor) {
    var target = clang_getCursorReferenced(c)
    if (clang_Cursor_isNull(target) != 0) {
        return
    }
    var file, def_file : CXFile
    var line, column, offset, def_line, def_offset : uint
    clang_getSpellingLocation(clang_getCursorLocation(c), safe_addr(file), safe_addr(line), safe_addr(column), safe_addr(offset))
    clang_getSpellingLocation(clang_getCursorLocation(target), safe_addr(def_file), safe_addr(def_line), safe_addr(column), safe_addr(def_offset))
    let given = file_name(def_file)
    let def_at = canonical_file(d, given)
    let at = canonical_file(d, file_name(file))
    if (empty(def_at) || empty(at)) {
        return
    }
    let fn_like = clang_Cursor_isMacroFunctionLike(target) != 0u
    if ((fn_like && !in_program(d, given)) || !in_program(d, file_name(file))) {
        return
    }
    let idx = macro_def_index(d.fn_macros, string(clang_getCursorSpelling(target)), def_at, given, int(def_line), int(def_offset), fn_like)
    macro_expansion_at(d.fn_macros, at, int(offset), idx)
}

// a macro definition of a program file, which a body may call by its name; a system header's
// function-like macro is only named, so a body calling it is followed no further
[arch(at="ARCHITECTURE_DUMPER_MACROS.md#fn-macros")]
def private register_macro_definition(var d : Dumper; var c : CXCursor) {
    var file : CXFile
    var line, column, offset : uint
    clang_getSpellingLocation(clang_getCursorLocation(c), safe_addr(file), safe_addr(line), safe_addr(column), safe_addr(offset))
    let given = file_name(file)
    let at = canonical_file(d, given)
    if (empty(at)) {
        return
    }
    let fn_like = clang_Cursor_isMacroFunctionLike(c) != 0u
    if (!in_program(d, given)) {
        if (fn_like) {
            system_macro(d.fn_macros, string(clang_getCursorSpelling(c)))
        }
    } else {
        macro_def_index(d.fn_macros, string(clang_getCursorSpelling(c)), at, given, int(line), int(offset), fn_like)
    }
}

// libclang's `CXTranslationUnit_DetailedPreprocessingRecord`, which dasClangBind exports only as a type
let private DETAILED_PREPROCESSING_RECORD = 1u

def private collect_records(var d : Dumper; frontend : array<string>; inputs : array<string>) {
    var args : array<string>
    args |> push_from(frontend, inputs)
    var idx = clang_createIndex(0, 0)
    // the detailed record lists each macro expansion of a file with its definition
    var unit = clang_parseTranslationUnit(idx, d.c_path, unsafe(addr(args[0])), length(args), null, 0u, DETAILED_PREPROCESSING_RECORD)
    if (unit != null) {
        // an error libclang meets (a header the own set lacks) leaves records and
        // typedefs out of what the pass collects
        for (i in urange(clang_getNumDiagnostics(unit))) {
            var diag = clang_getDiagnostic(unit, i)
            let severity = clang_getDiagnosticSeverity(diag)
            if (empty(d.error) && (severity == CXDiagnosticSeverity.Error || severity == CXDiagnosticSeverity.Fatal)) {
                d.error = "libclang: {string(clang_formatDiagnostic(diag, clang_defaultDiagnosticDisplayOptions()))}"
            }
            clang_disposeDiagnostic(diag)
        }
        var root = clang_getTranslationUnitCursor(unit)
        walk_records(d, root)
        collect_layouts(d, root, "", d.layouts)
        name_unnamed_types(d.layouts)
        if (!empty(d.shared_tags)) {
            note_shared_exprs(d, root)
        }
        if (!empty(d.typeof_spellings)) {
            note_typeofs(d, root)
        }
        clang_disposeTranslationUnit(unit)
    }
    clang_disposeIndex(idx)
    name_shared_tags(d)
    for (ridx in range(length(d.records))) {
        for (fidx in range(length(d.records[ridx].fields))) {
            d.records[ridx].fields[fidx].spelling = tagged_spelling(d, d.records[ridx].fields[fidx].spelling)
        }
    }
    let names <- [for (name in keys(d.typedef_spellings)); name]
    for (name in names) {
        d.typedef_spellings[name] = tagged_spelling(d, d.typedef_spellings[name])
    }
    let typeofs <- [for (spelled in keys(d.typeof_spellings)); spelled]
    for (spelled in typeofs) {
        d.typeof_spellings[spelled] = tagged_spelling(d, d.typeof_spellings[spelled])
    }
}

// a record spelling without its owner's scope: libclang qualifies an unnamed nested record by
// its owner, `struct Q::(unnamed at ...)`, and the dump does so for an anonymous member,
// `union S::(anonymous at ...)`; both key the record as `struct (unnamed at ...)`
def private unscoped_spelling(spelling : string) : string {
    let scope = rfind(spelling, "::(")
    if (scope < 0) {
        return spelling
    }
    // the scope follows the first tag word and runs to the last `::`; an anonymous member's own
    // scope is parenthesized (`union N::(anonymous struct)::(anonymous at f:l:c)`), and a
    // function's spells its signature (`union f(const char **)::(unnamed at f:l:c)`)
    var start = -1
    for (tag in fixed_array("struct ", "union ", "enum ")) {
        let at = find(spelling, tag)
        if (at >= 0 && (start < 0 || at + length(tag) < start)) {
            start = at + length(tag)
        }
    }
    // C spells every record and enum type with its tag word
    return start < 0 ? spelling : slice(spelling, 0, start) + slice(spelling, scope + 2)
}

// a libclang spelling in the dump's form: the leading type name, when it is an anonymous
// record's typedef name, takes its tag back
def private tagged_spelling(d : Dumper; raw : string) : string {
    let spelling = unscoped_spelling(raw)
    var head = length(spelling)
    for (stop in [find(spelling, " "), find(spelling, "*"), find(spelling, "[")]) {
        if (stop >= 0 && stop < head) {
            head = stop
        }
    }
    let tagged = d.anon_spellings?[slice(spelling, 0, head)] ?? ""
    return empty(tagged) ? spelling : tagged + slice(spelling, head)
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
    if (qt == "_Bool" || qt == "bool") {
        // clang spells `_Bool` as `bool` wherever `<stdbool.h>`'s macro is in scope (wasm3's
        // prototypes): one type, spelled `_Bool`
        return int_type(d, 8, false, "_Bool")
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

// whether an array spelling has a dimension clang left as a size expression: it folds every
// constant dimension to its count, so `int[n]` is a variable-length array
def private has_variable_dimension(spelling : string) : bool {
    var inside = false
    for (ch in spelling) {
        if (ch == '[') {
            inside = true
        } elif (ch == ']') {
            inside = false
        } elif (inside && !is_number(ch) && ch != ' ') {
            return true
        }
    }
    return false
}

// an array dimension as clang spells it: the count, -1 for `[]`; -2 with the error set for a
// variable-length array's size expression
def private dimension_count(var d : Dumper; dim, qual : string; at : CirLoc) : int {
    if (empty(dim)) {
        return -1
    }
    if (has_variable_dimension("[{dim}]")) {
        fail(d, "`{qual}`: a variable-length array is not lowered (out of scope in v1)", at)
        return -2
    }
    return to_int(dim)
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
// `R (*)(P)` is a pointer to the function `R (P)`; `R (*[N])(P)` is an array of N of them
def private function_pointer(var d : Dumper; qt : string; at : CirLoc) : int {
    // clang writes `void *(*)(P)` with no space after a pointer return. A `(*` with a `(` before
    // it sits inside a parameter list: `void (void (*)(int), int)` is a function taking a
    // function pointer, not a pointer
    let star = find(qt, "(*")
    if (star <= 0 || !(qt |> ends_with(")")) || find(slice(qt, 0, star), "(") >= 0) {
        return -2
    }
    let close = find(qt, ")(")
    if (close < star) {
        return -2
    }
    // `(**)` is a pointer to the pointer, one level per extra star; a qualifier on the pointer
    // (`(* const)`, a member read through a const record; `(* volatile)`) changes nothing das spells
    let between = slice(qt, star + 2, close) |> replace("const", "") |> replace("volatile", "") |> replace(" ", "")
    let extra = length([for (ch in between); ch; where ch == '*'])
    let dims = slice(between, extra)
    if (!(between |> starts_with(repeat("*", extra))) || (!empty(dims) && !(dims |> starts_with("[")))) {
        return -2
    }
    let ret_text = strip(slice(qt, 0, star))
    let fn = type_from_qual(d, ret_text + " (" + slice(qt, close + 2), at)
    if (fn < 0) {
        return -1
    }
    var ptr = CirType(k = "ptr", to = fn)
    var p = intern(d, "ptr:{fn}", ptr)
    for (_level in range(extra)) {
        var outer = CirType(k = "ptr", to = p)
        p = intern(d, "ptr:{p}", outer)
    }
    if (empty(dims)) {
        return p
    }
    // the dimensions wrap the pointer, outermost first, as for any array
    let count = dimension_count(d, slice(dims, 1, find(dims, "]")), qt, at)
    if (count == -2) {
        return -1
    }
    let rest = slice(dims, find(dims, "]") + 1)
    let elem = empty(rest) ? p : type_from_qual(d, "{ret_text} (*{rest})({slice(qt, close + 2)}", at)
    if (elem < 0) {
        return -1
    }
    var arr = CirType(k = "array", elem = elem, count = count)
    return intern(d, "array:{elem}:{count}", arr)
}

// an unnamed record is spelled with its location in parentheses, which the attribute
// stripping would eat: it, a pointer to it and an array of it resolve before the normal walk
def private unnamed_record_type(var d : Dumper; qual : string; at : CirLoc) : int {
    let bare = strip(qual |> replace("const ", "") |> replace("volatile ", ""))
    if (bare |> ends_with("*")) {
        let to = unnamed_record_type(d, strip(slice(bare, 0, length(bare) - 1)), at)
        if (to < 0) {
            return -1
        }
        var t = CirType(k = "ptr", to = to)
        return intern(d, "ptr:{to}", t)
    }
    if (bare |> ends_with("]")) {
        // the first bracket is the outer dimension, as in `type_from_qual`
        let open = find(bare, ")[") + 1
        let close = find(bare, "]", open)
        if (open > 0 && close > open) {
            let elem = unnamed_record_type(d, slice(bare, 0, open) + slice(bare, close + 1), at)
            if (elem < 0) {
                return -1
            }
            let count = dimension_count(d, strip(slice(bare, open + 1, close)), qual, at)
            if (count == -2) {
                return -1
            }
            var t = CirType(k = "array", elem = elem, count = count)
            return intern(d, "array:{elem}:{count}", t)
        }
    }
    let tagged = tagged_type(d, bare, at)
    if (tagged != -2) {
        return tagged
    }
    fail(d, "unsupported type spelling `{qual}`", at)
    return -1
}

// `R (P, ...)`: the return type before the paren, the parameters split at the top level
def private function_type(var d : Dumper; qt : string; paren : int; at : CirLoc) : int {
    let ret = type_from_qual(d, strip(slice(qt, 0, paren)), at)
    if (ret < 0) {
        return -1
    }
    return function_returning(d, ret, strip(slice(qt, paren + 1, length(qt) - 1)), at)
}

// the function type returning `ret` whose parameter list, without its parentheses, is `inside`
def private function_returning(var d : Dumper; ret : int; inside : string; at : CirLoc) : int {
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

// the index of the `)` closing the `(` at `open` of `view` (the `]` of a `[`, which never nests
// in a spelling), -1 when the text ends first
def private closing_paren(view : array<uint8>#; open : int) : int {
    var depth = 0
    for (idx in range(open, length(view))) {
        if (view[idx] == uint8('(') || view[idx] == uint8('[')) {
            depth++
        } elif (view[idx] == uint8(')') || view[idx] == uint8(']')) {
            depth--
            if (depth == 0) {
                return idx
            }
        }
    }
    return -1
}

// `B (D)S`, a declarator group the shapes `function_pointer` reads do not cover: `int (*const)`
// (a parenthesized pointer, clang's `ParenType`), `int (*(int, int))(int, int)` (a function
// returning a function pointer), `int (*(void))[3]` (one returning a pointer to an array). The
// group is the first parenthesis whose text starts with `*`, as a parameter list never does; -2
// for a spelling with none and for `T (*)[N]`, the row pointer `type_from_qual` cuts by text
def private declarator_group(var d : Dumper; qt : string; at : CirLoc) : int {
    let open = find(qt, "(*")
    if (open <= 0 || find(slice(qt, 0, open), "(") >= 0 || (find(qt, "(*)") == open && !(qt |> ends_with(")")))) {
        return -2
    }
    let base = type_from_qual(d, strip(slice(qt, 0, open)), at)
    return base < 0 ? -1 : applied_declarator(d, base, slice(qt, open), at)
}

// the type an abstract declarator gives `base`, C's inside-out reading: its leading `*`s (and
// their qualifiers) point at `base`, its trailing `[N]` and `(P)` suffixes wrap that from the
// last one in, and a group the suffixes follow is the declarator of the result
def private applied_declarator(var d : Dumper; base : int; decl : string; at : CirLoc) : int {
    var stars = 0
    var group = ""
    var inscope suffixes : array<string>
    var ok = true
    peek_data(decl) $(view) {
        let n = length(view)
        var pos = 0
        while (pos < n) {
            if (view[pos] == uint8('*')) {
                stars++
                pos++
            } elif (view[pos] == uint8(' ')) {
                pos++
            } else {
                var word = 0
                for (q in ["const", "volatile", "restrict"]) {
                    if (word == 0 && pos + length(q) <= n && slice(view, pos, pos + length(q)) == q) {
                        word = length(q)
                    }
                }
                break if (word == 0)
                pos += word
            }
        }
        if (pos + 1 < n && view[pos] == uint8('(') && view[pos + 1] == uint8('*')) {
            let close = closing_paren(view, pos)
            ok = close > pos
            group = ok ? slice(view, pos + 1, close) : ""
            pos = ok ? close + 1 : n
        }
        while (pos < n && ok) {
            let close = view[pos] == uint8('(') || view[pos] == uint8('[') ? closing_paren(view, pos) : -1
            ok = close > pos
            if (ok) {
                suffixes |> push(slice(view, pos, close + 1))
                pos = close + 1
            }
        }
    }
    if (!ok) {
        fail(d, "unsupported type spelling `{decl}`", at)
        return -1
    }
    var t = base
    for (_level in range(stars)) {
        t = pointer_to(d, t)
    }
    for (idx in range(length(suffixes))) {
        let suffix = suffixes[length(suffixes) - 1 - idx]
        let inside = strip(slice(suffix, 1, length(suffix) - 1))
        if (suffix |> starts_with("[")) {
            let count = dimension_count(d, inside, decl, at)
            if (count == -2) {
                return -1
            }
            var arr = CirType(k = "array", elem = t, count = count)
            t = intern(d, "array:{t}:{count}", arr)
        } else {
            t = function_returning(d, t, inside, at)
        }
        if (t < 0) {
            return -1
        }
    }
    return empty(group) ? t : applied_declarator(d, t, group, at)
}

// an opaque record of this repository's (`ARCHITECTURE.md` section 2): one field of type
// `field_t`, at clang's size and alignment, interned under its name
def private opaque_record(var d : Dumper; name : string; size, align : int; field_name : string; field_t : int) : int {
    var rec = CirType(k = "struct", name = name, spell = name, size = size, align = align)
    var field = CirField(name = field_name, t = field_t)
    rec.fields |> emplace(field)
    return intern(d, "record:{name}", rec)
}

def private pointer_to(var d : Dumper; to : int) : int {
    var p = CirType(k = "ptr", to = to)
    return intern(d, "ptr:{to}", p)
}

// glibc spells `jmp_buf` as `struct __jmp_buf_tag[1]`, and its decay and a pointer to it as
// `struct __jmp_buf_tag *`: every such spelling is the one opaque `jmp_buf` record, which the
// lowering fills with its own protocol (docs/lowering-examples.md "setjmp / longjmp")
def private jmp_buf_type(var d : Dumper; qual : string) : int {
    let r = opaque_record(d, "jmp_buf", 4, 4, "val", int_type(d, 32, true, "int"))
    return qual |> ends_with("*") || find(qual, "(*)") >= 0 ? pointer_to(d, r) : r
}

// the name of clang's own `va_list` declaration, implicit in every unit; the headers' `va_list`
// and `__gnuc_va_list` are typedefs over it
let VA_BUILTIN = "__builtin_va_list"

// whether typedef declaration `decl` reaches clang's implicit `__builtin_va_list` through its
// chain of typedefs: the declaration, not the name, decides, so a program's own
// `typedef char *va_list` is none
def private typedef_reaches_va(decl : CXCursor) : bool {
    var at = decl
    for (_depth in range(64)) {
        if (clang_getCursorKind(at) != CXCursorKind.TypedefDecl) {
            return false
        }
        if (string(clang_getCursorSpelling(at)) == VA_BUILTIN) {
            var file : CXFile
            var line, column, offset : uint
            clang_getFileLocation(clang_getCursorLocation(at), safe_addr(file), safe_addr(line), safe_addr(column), safe_addr(offset))
            return file == null
        }
        var under = clang_getTypedefDeclUnderlyingType(at)
        if (under.kind == CXTypeKind.Elaborated) {
            under = clang_Type_getNamedType(under)
        }
        if (under.kind != CXTypeKind.Typedef) {
            return false
        }
        at = clang_getTypeDeclaration(under)
    }
    return false
}

// a libclang type as a `va_list` sees it: none, exactly one, or one inside a pointer or array
let VA_NONE = 0

let VA_EXACT = 1

let VA_INSIDE = 2

def private type_holds_va(t : CXType) : int {
    var at = t
    var depth = 0
    while (depth < 64) {
        if (at.kind == CXTypeKind.Elaborated) {
            at = clang_Type_getNamedType(at)
        }
        if (at.kind == CXTypeKind.Typedef) {
            var decl = clang_getTypeDeclaration(at)
            if (typedef_reaches_va(decl)) {
                return depth == 0 ? VA_EXACT : VA_INSIDE
            }
            at = clang_getTypedefDeclUnderlyingType(decl)
        } elif (at.kind == CXTypeKind.Pointer) {
            at = clang_getPointeeType(at)
            depth++
        } elif (at.kind == CXTypeKind.ConstantArray || at.kind == CXTypeKind.IncompleteArray) {
            at = clang_getArrayElementType(at)
            depth++
        } else {
            return VA_NONE
        }
    }
    return VA_NONE
}

// what the words of a spelling with no declaration to follow (a function type's parameters, a
// pointer's pointee) say of a `va_list`: linux's `struct __va_list_tag` is one; a typedef name
// is one when every typedef of that name reaches the builtin, and undecidable when some do and
// some do not (`VA_AMBIGUOUS`); `struct va_list` is a C record of that tag
let VA_AMBIGUOUS = 3

def private va_word(d : Dumper; qual : string) : int {
    if (find(qual, "__va_list_tag") >= 0) {
        return VA_EXACT
    }
    let words <- split_by_chars(qual, " *&()[],")
    for (idx, word in range(length(words)), words) {
        let tagged = idx > 0 && (words[idx - 1] == "struct" || words[idx - 1] == "union" || words[idx - 1] == "enum")
        if (!tagged && (key_exists(d.va_names, word) || word == VA_BUILTIN)) {
            return key_exists(d.other_names, word) ? VA_AMBIGUOUS : VA_EXACT
        }
    }
    return VA_NONE
}

// the JSON ids of the typedef declarations that reach clang's implicit `__builtin_va_list`, in
// tree order, so a typedef's own chain is known before the typedefs over it
def private collect_va_ids(var d : Dumper; js : JsonValue?) {
    if (node_kind(js) == "TypedefDecl") {
        let root = (js?["isImplicit"] ?? false) && (js?["name"] ?? "") == VA_BUILTIN
        if (root || key_exists(d.va_ids, js?["type"]?["typeAliasDeclId"] ?? "")) {
            d.va_ids |> insert(js?["id"] ?? "")
        }
    }
    for (idx in range(child_count(js))) {
        collect_va_ids(d, (js?["inner"] as _array)[idx])
    }
}

// the typedef names of spelling `qual` that can set its alignment, a tag's name left out: none
// behind a pointer, whose alignment is the pointer's
def private aligning_words(qual : string) : array<string> {
    if (find(qual, "*") >= 0) {
        return <- array<string>()
    }
    let words <- split_by_chars(qual, " &()[],")
    return <- [for (idx, word in range(length(words)), words); word; where !(idx > 0 && (words[idx - 1] == "struct" || words[idx - 1] == "union" || words[idx - 1] == "enum"))]
}

// the calling conventions clang spells as a type attribute: das has one convention, so a function
// type keeps its result and parameters and drops the attribute
let CALLING_CONVENTIONS <- {"cdecl", "stdcall", "fastcall", "thiscall", "vectorcall", "pascal", "regcall", "ms_abi", "sysv_abi", "preserve_none", "preserve_most", "preserve_all", "swiftcall", "swiftasynccall"}

// the calling convention `qual` opens with as `__attribute__((cc)) `, "" for none
def private leading_convention(qual : string) : string {
    if (!(qual |> starts_with("__attribute__(("))) {
        return ""
    }
    let close = find(qual, ")) ")
    let name = close < 0 ? "" : slice(qual, length("__attribute__(("), close)
    return key_exists(CALLING_CONVENTIONS, name) ? name : ""
}

// the macro names a `MacroQualifiedType` spells over a calling convention (`convention_macros`)
def private collect_convention_macros(var d : Dumper; js : JsonValue?) {
    if (node_kind(js) == "MacroQualifiedType" && child_count(js) > 0) {
        let under = (js?["inner"] as _array)[0]
        if (node_kind(under) == "AttributedType" && !empty(leading_convention(under?["type"]?["qualType"] ?? ""))) {
            d.convention_macros |> insert(js?["macroName"] ?? "")
        }
    }
    for (idx in range(child_count(js))) {
        collect_convention_macros(d, (js?["inner"] as _array)[idx])
    }
}

// `qual` without the calling conventions clang spells before a function type's result: a macro
// over one (`vectorcall m3ret_t (int *, int)`) or the attribute itself
def private without_conventions(d : Dumper; qual : string) : string {
    let cc = leading_convention(qual)
    var bare = empty(cc) ? qual : slice(qual, length("__attribute__(({cc})) "))
    for (name in keys(d.convention_macros)) {
        bare = slice(replace(" {bare}", " {name} ", " ") |> replace("({name} ", "("), 1)
    }
    return bare
}

// the typedef declarations whose type an `aligned` attribute sets (`aligned_ids`), in tree order,
// so a typedef's own chain is known before the typedefs over it: a typedef's own attribute (the
// largest, when it has several) gives clang's alignment, even one below the type's, and a typedef
// over an aligned one without its own takes that one's
def private collect_aligned_typedefs(var d : Dumper; js : JsonValue?) {
    if (node_kind(js) == "TypedefDecl") {
        var own = -1
        for (idx in range(child_count(js))) {
            let kid = (js?["inner"] as _array)[idx]
            if (node_kind(kid) == "AlignedAttr") {
                let value = child_count(kid) > 0 ? (kid?["inner"] as _array)[0]?["value"] ?? "" : ""
                own = max(own, empty(value) ? 0 : to_int(value))
            }
        }
        let under = js?["type"]?["typeAliasDeclId"] ?? ""
        if (own < 0 && key_exists(d.aligned_ids, under)) {
            own = d.aligned_ids?[under] ?? 0
        }
        if (own < 0) {
            for (word in aligning_words(js?["type"]?["qualType"] ?? "")) {
                if (key_exists(d.aligned_names, word)) {
                    own = 0
                }
            }
        }
        if (own >= 0) {
            d.aligned_ids[js?["id"] ?? ""] = own
            d.aligned_names |> insert(js?["name"] ?? "")
        }
    }
    for (idx in range(child_count(js))) {
        collect_aligned_typedefs(d, (js?["inner"] as _array)[idx])
    }
}

// a C `va_list` is the one opaque record `va_list` of clang's size and alignment (24 and 8 on
// linux, where it is `struct __va_list_tag[1]`; 8 and 8 on msvc, where it is a `char *`), which
// the lowering spells as the runtime's cursor; linux's decay and parameter, `struct
// __va_list_tag *`, is a pointer to it. A function type naming one in its parameters goes
// through the usual parse; a pointer to one or an array of them fails closed.
def private va_list_type(var d : Dumper; qual : string; at : CirLoc) : int {
    var bare = unqualified(qual)
    if (bare |> ends_with(")")) {
        return NOT_SPECIAL
    }
    if (bare |> ends_with(" &")) {
        // msvc's builtins take the list by reference
        bare = slice(bare, 0, length(bare) - 2)
    }
    let words = is_msvc(d.tu.target) ? 1 : 3
    var words_array = CirType(k = "array", elem = int_type(d, 64, false, "unsigned long long"), count = words)
    let words_t = intern(d, "array:{words_array.elem}:{words}", words_array)
    let r = opaque_record(d, "va_list", 8 * words, 8, "words", words_t)
    if (key_exists(d.va_names, bare) || bare == VA_BUILTIN || bare == "struct __va_list_tag[1]") {
        return r
    }
    if (bare == "struct __va_list_tag *") {
        return pointer_to(d, r)
    }
    if (find(bare, "*") >= 0 || find(bare, "[") >= 0) {
        fail(d, "`{qual}`: a pointer to a `va_list` or an array of them is not lowered yet", at)
    } else {
        fail(d, "`{qual}`: a spelling of `va_list` the dumper does not know", at)
    }
    return -1
}

// the result of a spelling reader that does not take the spelling, so the next one may
let NOT_SPECIAL = -2

// the spellings that are not C types: a `va_list`, glibc's `jmp_buf`, a builtin's prototype-less function
// type (read only through its decay, since the emitter resolves the callee by name), and an
// unnamed record, whose location in parentheses the attribute stripping would eat; -2 for a
// spelling that is none of these
def private special_type(var d : Dumper; qual : string; at : CirLoc) : int {
    let va_kind = va_word(d, qual)
    if (va_kind == VA_AMBIGUOUS && !(unqualified(qual) |> ends_with(")"))) {
        fail(d, "`{qual}`: a typedef name that is a `va_list` in one scope and another type in another, reached without its declaration; not lowered yet", at)
        return -1
    }
    if (va_kind != VA_NONE) {
        let va = va_list_type(d, qual, at)
        if (va != NOT_SPECIAL) {
            return va
        }
    }
    if (find(qual, "__jmp_buf_tag") >= 0) {
        return jmp_buf_type(d, unqualified(qual))
    }
    if (qual == "<builtin fn type>") {
        var void_t = CirType(k = "void")
        var t = CirType(k = "func", ret = intern(d, "void", void_t), variadic = true)
        return intern(d, "func:builtin", t)
    }
    if (find(qual, "(unnamed ") >= 0 || find(qual, "(anonymous ") >= 0) {
        return unnamed_record_type(d, qual, at)
    }
    return -2
}

// spelling `qual` with each `typeof (...)` in it replaced by the type libclang resolves it to
// (`register_typeof`); "" with the error set for one libclang resolves to no one type, or to a
// function, an array or a pointer to one under a declarator, which no text in its place spells
def private without_typeof(var d : Dumper; qual : string; at : CirLoc) : string {
    if (find(qual, TYPEOF) < 0) {
        return qual
    }
    var parts : array<string>
    var ok = true
    peek_data(qual) $(view) {
        // the text before `done` is in `parts`
        var done = 0
        var from = find(qual, TYPEOF)
        while (from >= 0 && ok) {
            let after = from + length(TYPEOF)
            let open = after < length(view) && view[after] == uint8(' ') ? after + 1 : after
            let in_name = from > 0 && (is_alpha(int(view[from - 1])) || is_number(int(view[from - 1])) || view[from - 1] == uint8('_'))
            let close = !in_name && open < length(view) && view[open] == uint8('(') ? closing_paren(view, open) : -1
            if (close < 0) {
                // a name that holds the word (`typeof_unqual`, `my_typeof_t`)
                from = find(qual, TYPEOF, after)
                continue
            }
            let leaf = slice(view, from, close + 1)
            let canonical = d.typeof_spellings?[leaf] ?? ""
            if (d.type_operand) {
                // another scope's declaration may spell the same `typeof` for another type
                fail(d, "`{qual}`: a `typeof` under a declarator in the operand of `sizeof`, `_Alignof` or `va_arg` is not lowered yet (the libclang pass reads no type there)", at)
                ok = false
            } elif (empty(canonical)) {
                fail(d, "`{leaf}`: a `typeof` libclang resolves to no one type (two of this spelling name different types, or no declaration or cast spells it) is not lowered yet", at)
                ok = false
            } elif ((from > 0 || close + 1 < length(view)) && key_exists(d.typeof_declarators, leaf)) {
                fail(d, "`{qual}`: a `typeof` of a function, an array or a pointer to one (`{canonical}`) under a declarator is not lowered yet", at)
                ok = false
            } else {
                parts |> push(slice(view, done, from))
                parts |> push(canonical)
                done = close + 1
                from = find(qual, TYPEOF, done)
            }
        }
        if (ok) {
            parts |> push(slice(view, done, length(view)))
        }
    }
    return ok ? join(parts, "") : ""
}

def type_from_qual(var d : Dumper; spelled : string; at : CirLoc) : int {
    let qual = without_typeof(d, spelled, at)
    return empty(qual) ? -1 : type_from_text(d, qual, at)
}

// the type of spelling `qual`, which holds no `typeof`
def private type_from_text(var d : Dumper; qual : string; at : CirLoc) : int {
    let special = special_type(d, qual, at)
    if (special != -2) {
        return special
    }
    let qt = unqualified(without_attributes(without_conventions(d, qual)))
    let scalar = scalar_from_qual(d, qt)
    if (scalar != -2) {
        return scalar
    }
    // a group goes before the paths below, which cut a spelling's trailing `[N]` by text
    let fn_ptr = function_pointer(d, qt, at)
    let grouped = fn_ptr != -2 ? fn_ptr : declarator_group(d, qt, at)
    if (grouped != -2) {
        return grouped
    }
    if (qt |> ends_with("*")) {
        let to = type_from_qual(d, slice(qt, 0, length(qt) - 1), at)
        if (to < 0) {
            return -1
        }
        var t = CirType(k = "ptr", to = to)
        return intern(d, "ptr:{to}", t)
    }
    // a pointer to an array, `T (*)[N]`: the pointee is the array `T[N]`
    let row = find(qt, "(*)")
    if (row > 0 && qt |> ends_with("]")) {
        let to = type_from_qual(d, strip(slice(qt, 0, row)) + slice(qt, row + 3), at)
        if (to < 0) {
            return -1
        }
        var t = CirType(k = "ptr", to = to)
        return intern(d, "ptr:{to}", t)
    }
    // `T[2][3]` is two arrays of `T[3]`: the first dimension is the outer one
    if (qt |> ends_with("]")) {
        let open = find(qt, "[")
        let close = find(qt, "]")
        if (open > 0 && close > open) {
            let elem = type_from_qual(d, strip(slice(qt, 0, open)) + slice(qt, close + 1), at)
            if (elem < 0) {
                return -1
            }
            let count = dimension_count(d, strip(slice(qt, open + 1, close)), qual, at)
            if (count == -2) {
                return -1
            }
            var t = CirType(k = "array", elem = elem, count = count)
            return intern(d, "array:{elem}:{count}", t)
        }
    }
    // `R (P, ...)`, and `R *(P)` when the return type is a pointer: clang puts no space
    // after a `*`
    let paren = find(qt, "(")
    if (paren > 0 && qt |> ends_with(")")) {
        return function_type(d, qt, paren, at)
    }
    let tagged = tagged_type(d, qt, at)
    if (tagged != -2) {
        return tagged
    }
    // the dump desugars only the top level of a spelling: a typedef name inside `P_t *` or
    // `P_t (P_t, int)` resolves through libclang's canonical spelling of the typedef
    let canonical = d.typedef_spellings?[qt] ?? ""
    if (!empty(canonical) && canonical != qt) {
        return type_from_qual(d, canonical, at)
    }
    // clang's implicit builtin typedefs (`__size_t` in a builtin's prototype) have no
    // cursor: they are the pointer-wide integers of the dialect
    let pointer_wide = d.tu.target.long_w == d.tu.target.ptr_w ? "long" : "long long"
    if (qt == "__size_t" || qt == "__uintptr_t") {
        return type_from_qual(d, "unsigned {pointer_wide}", at)
    }
    if (qt == "__ssize_t" || qt == "__ptrdiff_t" || qt == "__intptr_t") {
        return type_from_qual(d, pointer_wide, at)
    }
    fail(d, "unsupported type spelling `{qt}`", at)
    return -1
}

// a `struct`, `union` or `enum` spelling to its type; -2 for a spelling with no such tag
def private tagged_type(var d : Dumper; qt : string; at : CirLoc) : int {
    if (qt |> starts_with("struct ") || qt |> starts_with("union ")) {
        // the dump scopes an anonymous member's record by its owner too (`union S::(anonymous
        // at f:l:c)`), and libclang's records are keyed unscoped
        let spelling = scoped_record(d, unscoped_spelling(qt), at)
        return empty(spelling) ? -1 : record_type(d, spelling, at)
    }
    if (qt |> starts_with("enum ")) {
        return enum_type(d, qt, at)
    }
    return -2
}

// the record a dump spelling names where the walk stands: a tag defined more than once is the
// innermost block's definition the walk has passed, else the file-scope one; "" with the error
// set for a tag only blocks define, named outside them (C's new incomplete type)
[arch(at="ARCHITECTURE_DUMPER_TAGS.md#shared-tags")]
def private scoped_record(var d : Dumper; spelling : string; at : CirLoc) : string {
    if (!key_exists(d.shared_tags, spelling)) {
        return spelling
    }
    if (!empty(d.expr_key)) {
        // an expression's record is libclang's note at its first token, never the scopes'
        let named = d.expr_records?[d.expr_key]?[spelling] ?? -2
        if (named < 0) {
            fail(d, named == -1 ? "`{spelling}` names two of its definitions in one expression; not lowered yet" : "`{spelling}`: libclang names no record of this expression's type at its first token, while the file defines the tag more than once; not lowered yet", at)
            return ""
        }
        return d.records[named].spelling
    }
    for (depth in range(length(d.tag_scopes) - d.tag_floor)) {
        let ridx = d.tag_scopes[length(d.tag_scopes) - 1 - depth]?[spelling] ?? -1
        if (ridx >= 0) {
            return d.records[ridx].spelling
        }
    }
    let ridx = d.file_record_by_tag?[spelling] ?? -1
    if (ridx < 0) {
        fail(d, "`{spelling}` names no definition in scope here, while blocks define it more than once; not lowered yet", at)
        return ""
    }
    return d.records[ridx].spelling
}

// clang spells an unnamed tag by its location, `(unnamed at f:l:c)`
def private is_unnamed_tag(tag : string) : bool => tag |> starts_with("(")

// a record type: its own slot first so a self-referential pointer field finds it, then the
// fields interned depth-first; a record libclang never saw defined stays incomplete (size -1)
def private record_type(var d : Dumper; qt : string; at : CirLoc) : int {
    let key = "record:{qt}"
    let known = d.type_index?[key] ?? -1
    if (known >= 0) {
        return known
    }
    let is_union = qt |> starts_with("union ")
    let tag = slice(qt, is_union ? 6 : 7)
    let ridx = d.record_by_spelling?[qt] ?? -1
    var t = CirType(k = is_union ? "union" : "struct", name = is_unnamed_tag(tag) ? "" : tag, spell = qt, size = -1, align = -1)
    if (ridx >= 0) {
        t.size = int(d.records[ridx].size)
        t.align = int(d.records[ridx].align)
    }
    let idx = intern(d, key, t)
    if (ridx < 0) {
        return idx
    }
    var fields : array<CirField>
    fields |> reserve(length(d.records[ridx].fields))
    // a file-scope record's fields name file-scope tags, whichever block first reaches it
    // and no expression's note reaches them
    let floor = d.tag_floor
    let expr_key = d.expr_key
    d.expr_key = ""
    if (!d.records[ridx].block_scope) {
        d.tag_floor = length(d.tag_scopes)
    }
    var ok = true
    for (f in d.records[ridx].fields) {
        let ft = type_from_qual(d, f.spelling, at)
        var fld = CirField(name = f.name, t = ft, off = int(f.bit_off / 8l), bit_off = int(f.bit_off), bit_w = f.bit_w, is_bitfield = f.is_bitfield)
        if (ft < 0 || !enum_dims(d, f.loc_key, ft, at, fld.dims)) {
            ok = false
            break
        }
        fields |> emplace(fld)
    }
    d.tag_floor = floor
    d.expr_key = expr_key
    if (!ok) {
        return -1
    }
    d.tu.types[idx].fields <- fields
    d.tu.types[idx].packed = !natural_layout(d.tu, d.layout, idx)
    if (key_exists(d.external_records, ridx)) {
        // an external file's record has no definition the walk meets: its anchor is its first use
        d.tu.decls |> push(new CirDecl(k = "record", name = d.tu.types[idx].name, c_name = d.tu.types[idx].name, t = idx, loc = at))
    }
    return idx
}

// an enum type from its definition's libclang entry: the C-IR's enum is the dialect's `int`
// wide, signed or not as clang chose, so an enum of another width fails closed
def private enum_type(var d : Dumper; qt : string; at : CirLoc) : int {
    let key = "enum:{qt}"
    let known = d.type_index?[key] ?? -1
    if (known >= 0) {
        return known
    }
    let eidx = d.enum_by_spelling?[qt] ?? -1
    if (eidx < 0) {
        fail(d, "`{qt}` has no definition in this file", at)
        return -1
    }
    if (d.enums[eidx].spelling_shared) {
        fail(d, "`{qt}` is defined more than once in this file; same-tag block-scoped enums are not lowered yet", at)
        return -1
    }
    if (d.enums[eidx].underlying_w != int64(d.tu.target.int_w)) {
        fail(d, "`{qt}` is {d.enums[eidx].underlying_w} bits wide; the C-IR's enum is the dialect's int of {d.tu.target.int_w}", at)
        return -1
    }
    let tag = slice(qt, length("enum "))
    var t = CirType(k = "enum", name = is_unnamed_tag(tag) ? "" : tag, spell = qt, is_signed = d.enums[eidx].underlying_signed)
    t.items := d.enums[eidx].items
    return intern(d, key, t)
}

// the enum constants a declarator spells its array dimensions by, one slot per dimension of
// type `t`, outermost first; a dimension spelled otherwise, or by a constant whose value is
// not the count (two declarators of one macro expansion share a key), keeps an empty item.
// Nothing when no dimension names a constant; false with `error` set on an unresolved enum
def private enum_dims(var d : Dumper; key : string; t : int; at : CirLoc; var out : array<CirDim>) : bool {
    if (!key_exists(d.enum_dims_by_loc, key)) {
        return true
    }
    var level = t
    var named = false
    for (ref in d.enum_dims_by_loc[key]) {
        break if (d.tu.types[level].k != "array")
        var dim : CirDim
        if (is_constant(ref)) {
            let enum_t = enum_type(d, tagged_spelling(d, ref.enum_spelling), at)
            if (enum_t < 0) {
                return false
            }
            for (it in d.tu.types[enum_t].items) {
                if (it.name == ref.item && it.v == int64(d.tu.types[level].count)) {
                    dim = CirDim(enum_t = enum_t, item = ref.item)
                    named = true
                }
            }
        }
        out |> push(dim)
        level = d.tu.types[level].elem
    }
    if (!named) {
        out |> clear()
    }
    return true
}

// the index of record `rec`'s field `name`, or for an empty name its anonymous member whose
// record type is `t`; -1 when there is none or `rec` is no record
def private member_index(d : Dumper; rec : int; name : string; t : int) : int {
    if (rec < 0 || rec >= length(d.tu.types) || (d.tu.types[rec].k != "struct" && d.tu.types[rec].k != "union")) {
        return -1
    }
    for (idx, f in range(length(d.tu.types[rec].fields)), d.tu.types[rec].fields) {
        if (empty(name) ? empty(f.name) && !f.is_bitfield && f.t == t : f.name == name) {
            return idx
        }
    }
    return -1
}

// the spelling of a JSON type: clang spells a typedef by its name and adds the resolved
// spelling beside it, which is the one read; a typedef whose declaration reaches the builtin is
// a `va_list`, which the msvc desugaring to `char *` loses, and a spelling with no declaration
// beside it (`va_list *`) is read by its words
def private type_spelling(d : Dumper; type_js : JsonValue?) : string {
    let alias = type_js?["typeAliasDeclId"] ?? ""
    if (key_exists(d.va_ids, alias)) {
        return VA_BUILTIN
    }
    let named = type_js?["qualType"] ?? ""
    let desugared = type_js?["desugaredQualType"]
    if (!is_present(desugared) || (empty(alias) && va_word(d, named) != VA_NONE)) {
        return named
    }
    return desugared ?? named
}

def private node_type(var d : Dumper; js : JsonValue?; at : CirLoc) : int => type_from_qual(d, type_spelling(d, js?["type"]), at)

// C qualifiers carry no meaning for the das type (docs/c-feature-matrix.md section 1)
def private unqualified(qual : string) : string {
    let spaced = qual |> replace("*const", "* const") |> replace("*volatile", "* volatile") |> replace("*restrict", "* restrict")
    return join([for (tok in split(spaced, " ")); tok; where !empty(tok) && tok != "const" && tok != "volatile" && tok != "restrict"], " ")
}

let UNARY_OPS <- {"-" => "neg", "+" => "plus", "!" => "not", "~" => "bnot", "&" => "addr", "*" => "deref"}

let BINARY_OPS <- {"+" => "add", "-" => "sub", "*" => "mul", "/" => "div", "%" => "rem", "<<" => "shl", ">>" => "shr", "<" => "lt", ">" => "gt", "<=" => "le", ">=" => "ge", "==" => "eq", "!=" => "ne", "&" => "band", "|" => "bor", "^" => "bxor", "&&" => "land", "||" => "lor"}

// the operators whose macro-body parentheses the C-IR keeps (`dump_expr_node`)
let private BIT_OPS <- {"shl", "shr", "band", "bor", "bxor"}
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

def private linkage_name(d : Dumper; c_name : string) : string => d.linkage_names?[c_name] ?? c_name

// the name a reference binds to: the declaration clang resolved, by its id; a declaration
// outside the program (a libc function, `stderr`) by its file-scope name
def private bound_name(d : Dumper; referenced : JsonValue?) : string {
    let bound = d.decl_names?[referenced?["id"] ?? ""] ?? ""
    return empty(bound) ? linkage_name(d, referenced?["name"] ?? "") : bound
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

def private child_expr(var d : Dumper; kids : JsonValue?; idx : int) : CirExpr? =>
    dump_expr(d, (kids as _array)[idx])

def private dump_cast(var d : Dumper; js : JsonValue?; t : int; at : CirLoc) : CirExpr? {
    // a `__builtin_*` reference decays by clang's own kind, which the pinned list spells as the
    // plain decay (docs/probe-findings.md F23)
    let raw = js?["castKind"] ?? ""
    let ck = raw == "BuiltinFnToFnPtr" ? "FunctionToPointerDecay" : raw
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
    if (opcode == "__extension__" && child_count(js) == 1) {
        // GNU `__extension__` only silences pedantic warnings: the operand is the value
        return child_expr(d, js?["inner"], 0)
    }
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
    if (callee_name((kids as _array)[0]) == CONSTANT_P) {
        return dump_constant_p(d, js, t, at)
    }
    if (callee_name((kids as _array)[0]) == CLASSIFY_TYPE) {
        // clang classifies a `_Bool` as 4 where GCC, the suites' reference, gives 1
        let operand = nkids > 1 ? (kids as _array)[1]?["type"] : null
        let spelled = operand?["desugaredQualType"] ?? (operand?["qualType"] ?? "")
        if (spelled == "_Bool" || spelled |> ends_with(" _Bool")) {
            fail(d, "`{CLASSIFY_TYPE}` of a `_Bool` is not lowered (clang's value is not GCC's)", at)
            return null
        }
        return dump_folded(d, js, t, at, CLASSIFY_TYPE)
    }
    let library_ret = callee_kind((kids as _array)[0]) == "FunctionDecl" ? d.library_results?[callee_name((kids as _array)[0])] ?? -1 : -1
    var x = new CirExpr(e = "call", t = library_ret >= 0 ? library_ret : t)
    d.dumping_callee = library_ret >= 0
    x.fn = child_expr(d, kids, 0)
    d.dumping_callee = false
    if (x.fn == null || !dump_args(d, kids, 1, nkids, x)) {
        delete_expr(x)
        return null
    }
    return library_ret >= 0 ? new CirExpr(e = "cast", t = t, cast_kind = "IntegralCast", a = x) : x
}

// the name a callee references through its decay and parentheses, "" for any other callee
def private callee_name(js : JsonValue?) : string {
    let kind = node_kind(js)
    if (child_count(js) > 0 && (kind == "ImplicitCastExpr" || kind == "ParenExpr")) {
        return callee_name((js?["inner"] as _array)[0])
    }
    return kind == "DeclRefExpr" ? js?["referencedDecl"]?["name"] ?? "" : ""
}

// the declaration kind a callee references as `callee_name` reads it, "" for any other callee
def private callee_kind(js : JsonValue?) : string {
    let kind = node_kind(js)
    if (child_count(js) > 0 && (kind == "ImplicitCastExpr" || kind == "ParenExpr")) {
        return callee_kind((js?["inner"] as _array)[0])
    }
    return kind == "DeclRefExpr" ? js?["referencedDecl"]?["kind"] ?? "" : ""
}

// a `__builtin_constant_p` call is the integer literal clang's answer is, so the argument is
// never dumped, let alone evaluated
[arch(at="ARCHITECTURE_DUMPER.md#builtin-constant-p")]
def private dump_constant_p(var d : Dumper; js : JsonValue?; t : int; at : CirLoc) : CirExpr? {
    let v = d.constant_p_by_loc?[node_key(d, js)] ?? CONSTANT_P_UNSEEN
    if (v >= 0) {
        return new CirExpr(e = "int_lit", t = t, v = "{v}")
    }
    if (v == CONSTANT_P_NESTED) {
        fail(d, "a `__builtin_constant_p` whose argument holds another one clang cannot fold is not lowered (the -O0 answer is the code generator's)", at)
    } elif (v == CONSTANT_P_COMMA) {
        fail(d, "a `__builtin_constant_p` over a comma operator clang cannot fold is not lowered (the -O0 answer is the code generator's, which emits a constant across a comma)", at)
    } elif (v == CONSTANT_P_SPLIT) {
        fail(d, "two `__builtin_constant_p` calls of one macro expansion that clang answers apart are not lowered", at)
    } else {
        fail(d, "`__builtin_constant_p`: libclang reports no call at this location", at)
    }
    return null
}

// a `__builtin_classify_type` call or a `__builtin_types_compatible_p` trait (`what`) is the
// integer literal of clang's fold of the node (`register_trait_value`): its operands are types,
// or an expression C never evaluates, and are not dumped
[arch(at="ARCHITECTURE_DUMPER_TAGS.md#folded-builtins")]
def private dump_folded(var d : Dumper; js : JsonValue?; t : int; at : CirLoc; what : string) : CirExpr? {
    let key = node_key(d, js)
    if (!key_exists(d.trait_by_loc, key)) {
        fail(d, "`{what}`: libclang gives no value at this location", at)
        return null
    }
    let v = d.trait_by_loc?[key] ?? TRAIT_SPLIT
    if (v == TRAIT_SPLIT) {
        fail(d, "two `{what}` of one macro expansion that clang values apart are not lowered", at)
        return null
    }
    return new CirExpr(e = "int_lit", t = t, v = "{v}")
}

// `__builtin_choose_expr(c, a, b)` is the operand clang chose, by the value its dump gives the
// constant `c`; neither `c` nor the other operand is dumped
[arch(at="ARCHITECTURE_DUMPER_TAGS.md#folded-builtins")]
def private dump_choose(var d : Dumper; js : JsonValue?; at : CirLoc) : CirExpr? {
    let kids = js?["inner"]
    let chosen = child_count(js) == 3 ? (kids as _array)[0]?["value"] ?? "" : ""
    if (empty(chosen)) {
        fail(d, "`__builtin_choose_expr`: the dump gives its condition no value", at)
        return null
    }
    return child_expr(d, kids, chosen == "0" ? 2 : 1)
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

// `sizeof` and `_Alignof` (clang's `alignof`, which C23's `alignof` spells too) of a type or
// an expression's type, with clang's value; GNU `__alignof__` (clang's `__alignof`) likewise
def private dump_sizeof(var d : Dumper; js : JsonValue?; t : int; at : CirLoc) : CirExpr? {
    let trait = js?["name"] ?? ""
    if (trait != "sizeof" && trait != "alignof" && trait != GNU_ALIGNOF) {
        fail(d, "`{trait}` is not dumped yet", at)
        return null
    }
    var of_t = -1
    let arg_type = js?["argType"]
    if (is_present(arg_type)) {
        d.type_operand = true
        of_t = type_from_qual(d, type_spelling(d, arg_type), at)
        d.type_operand = false
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
    if (trait == GNU_ALIGNOF) {
        return dump_gnu_alignof(d, js, t, of_t, at)
    }
    if (trait == "alignof") {
        let aligned = typedef_alignment(d, js, at)
        if (aligned == 0) {
            return null
        }
        let align = aligned > 0 ? aligned : type_align(d.tu, of_t)
        if (align < 0) {
            fail(d, "alignof of a type without an alignment", at)
            return null
        }
        return new CirExpr(e = "alignof_v", t = t, trait_v = uint64(align), of_t = of_t)
    }
    let size = type_size(d.tu, of_t)
    if (size < 0l) {
        fail(d, "sizeof of a type without a size", at)
        return null
    }
    return new CirExpr(e = "sizeof_v", t = t, trait_v = uint64(size), of_t = of_t)
}

let GNU_ALIGNOF = "__alignof"

// GNU `__alignof__` of a type or an expression: the value is clang's (`register_trait_value`),
// since it is the preferred alignment, and of a declaration its own, neither of which the interned
// type `of_t` tells; the emitter spells das's alignment of the type where the two agree
def private dump_gnu_alignof(var d : Dumper; js : JsonValue?; t, of_t : int; at : CirLoc) : CirExpr? {
    let key = node_key(d, js)
    if (!key_exists(d.trait_by_loc, key)) {
        fail(d, "`__alignof__`: libclang gives no value at this location", at)
        return null
    }
    let v = d.trait_by_loc?[key] ?? TRAIT_SPLIT
    if (v == TRAIT_SPLIT) {
        fail(d, "two `__alignof__` of one macro expansion that clang values apart are not lowered", at)
        return null
    }
    return new CirExpr(e = "alignof_v", t = t, trait_v = uint64(v), of_t = of_t)
}

// the JSON type of the operand of trait node `js`: its `argType`, else its expression's
def private trait_operand_type(js : JsonValue?) : JsonValue const? {
    let arg_type = js?["argType"]
    if (is_present(arg_type) || child_count(js) == 0) {
        return arg_type
    }
    return (js?["inner"] as _array)[0]?["type"]
}

// clang's alignment of the operand of `_Alignof` node `js` when an `aligned` typedef sets it (the
// interned type has lost the typedef): the attribute's value; -1 when no aligned typedef sets
// the operand's alignment, 0 with the error set when one does where the dumper reads no value
def private typedef_alignment(var d : Dumper; js : JsonValue?; at : CirLoc) : int {
    let spelled = trait_operand_type(js)
    let qual = spelled?["qualType"] ?? ""
    let id = spelled?["typeAliasDeclId"] ?? ""
    var align = key_exists(d.aligned_ids, id) ? d.aligned_ids?[id] ?? 0 : -1
    if (align < 0) {
        for (word in aligning_words(qual)) {
            if (key_exists(d.aligned_names, word)) {
                align = 0
            }
        }
    }
    if (align == 0) {
        fail(d, "`_Alignof({qual})`: an `aligned` typedef whose alignment the dump does not give (an array's element, or one with no value) is not lowered yet; an aligned type is marshal-only", at)
    }
    return align
}

def private dump_member(var d : Dumper; js : JsonValue?; t : int; at : CirLoc) : CirExpr? {
    var base = child_expr(d, js?["inner"], 0)
    if (base == null) {
        return null
    }
    let arrow = js?["isArrow"] ?? false
    let rec = arrow ? (d.tu.types[base.t].k == "ptr" ? d.tu.types[base.t].to : -1) : base.t
    let name = js?["name"] ?? ""
    // an anonymous member is the unnamed field of the member's own record type
    let field = member_index(d, rec, name, t)
    if (field < 0 && rec >= 0 && d.tu.types[rec].size < 0) {
        // a record of an external file (a system header's `struct lconv`, `struct tm`) has no
        // layout here
        fail(d, "member `{name}` of `{d.tu.types[rec].spell}`, a record no file of the program defines, is not lowered yet", at)
        delete_expr(base)
        return null
    }
    if (field < 0) {
        fail(d, "member `{name}` is not a direct field of the base's type", at)
        delete_expr(base)
        return null
    }
    return new CirExpr(e = "member", t = t, base = base, field = field, arrow = arrow)
}

// clang's semantic form: one child per field (an unnamed bitfield has none) or element in
// order, `ImplicitValueInitExpr` for a slot the source left out, which the positional form
// leaves to its zero; an array with a trailing run of zeros lists the filler first under
// `array_filler`, then the elements up to the last one written
def private dump_init_list(var d : Dumper; js : JsonValue?; t : int; at : CirLoc) : CirExpr? {
    let k = d.tu.types[t].k
    if (k == "union") {
        return dump_union_init(d, js, t, at)
    }
    if (k != "struct" && k != "array" && child_count(js) == 1) {
        // `T *p = { NULL }`, `int n = { 3 }`: a scalar's braced value is the unbraced one, which
        // clang already converted to the scalar's type
        return dump_expr(d, (js?["inner"] as _array)[0])
    }
    if (k != "struct" && k != "array") {
        fail(d, "`{k}` initializer lists are not dumped yet", at)
        return null
    }
    let filled = is_present(js?["array_filler"])
    let entries = filled ? js?["array_filler"] : js?["inner"]
    let count = entries != null && entries is _array ? length(entries as _array) : 0
    let first = filled ? 1 : 0
    if (k == "array" && !filled && count == 1 && node_kind((entries as _array)[0]) == "StringLiteral" && node_type(d, (entries as _array)[0], at) == t) {
        // `char s[] = { "ab" }`: clang types the literal as the whole array, which is the
        // unbraced `char s[] = "ab"`
        return dump_expr(d, (entries as _array)[0])
    }
    var x = new CirExpr(e = "init_list", t = t)
    x.init_items |> reserve(count)
    for (idx in range(first, count)) {
        let kid = (entries as _array)[idx]
        // a file-scope compound literal wraps each left-out slot in a `ConstantExpr`
        let wrapped = node_kind(kid) == "ConstantExpr" && child_count(kid) == 1 && node_kind((kid?["inner"] as _array)[0]) == "ImplicitValueInitExpr"
        continue if (node_kind(kid) == "ImplicitValueInitExpr" || wrapped)
        var v = dump_expr(d, kid)
        if (v == null) {
            delete_expr(x)
            return null
        }
        let pos = k == "struct" ? initialized_field(d.tu.types[t], idx - first) : idx - first
        x.init_items |> push(CirInitItem(pos = pos, v = v))
    }
    return x
}

// `(T){...}`: the `compound_lit` node over its initializer list; a scalar's list (`(int){5}`)
// holds its one value at position 0, none for `(int){}`
def private dump_compound_literal(var d : Dumper; js : JsonValue?; t : int; at : CirLoc) : CirExpr? {
    if (child_count(js) != 1 || node_kind((js?["inner"] as _array)[0]) != "InitListExpr") {
        fail(d, "a compound literal without an initializer list", at)
        return null
    }
    let list = (js?["inner"] as _array)[0]
    var init : CirExpr?
    let k = d.tu.types[t].k
    if (k == "struct" || k == "union" || k == "array") {
        init = dump_init_list(d, list, t, at)
    } else {
        init = new CirExpr(e = "init_list", t = t)
        if (child_count(list) == 1) {
            var v = child_expr(d, list?["inner"], 0)
            if (v == null) {
                delete_expr(init)
                return null
            }
            init.init_items |> push(CirInitItem(pos = 0, v = v))
        } elif (child_count(list) > 1) {
            fail(d, "a scalar compound literal of {child_count(list)} values", at)
            delete_expr(init)
            return null
        }
    }
    if (init == null) {
        return null
    }
    return new CirExpr(e = "compound_lit", t = t, init = init)
}

// a union's initializer: clang names the member it initializes under `field` and gives at
// most one child, none for `{}`, which leaves the union zero
def private dump_union_init(var d : Dumper; js : JsonValue?; t : int; at : CirLoc) : CirExpr? {
    var x = new CirExpr(e = "init_list", t = t)
    if (child_count(js) == 0) {
        return x
    }
    let name = js?["field"]?["name"] ?? ""
    if (empty(name)) {
        fail(d, "an initializer of an anonymous member of a union is not dumped yet", at)
        delete_expr(x)
        return null
    }
    let pos = member_index(d, t, name, -1)
    if (pos < 0 || child_count(js) != 1) {
        fail(d, "a union initializer of {child_count(js)} values for member `{name}` is not dumped yet", at)
        delete_expr(x)
        return null
    }
    var v = child_expr(d, js?["inner"], 0)
    if (v == null) {
        delete_expr(x)
        return null
    }
    x.init_items |> push(CirInitItem(pos = pos, v = v))
    return x
}

// the field index of a record initializer's `slot`-th child: clang initializes every field but
// an unnamed bitfield, which is padding
def private initialized_field(rec : CirType; slot : int) : int {
    var seen = 0
    for (idx, f in range(length(rec.fields)), rec.fields) {
        if (!is_unnamed_bitfield(f)) {
            if (seen == slot) {
                return idx
            }
            seen++
        }
    }
    return slot
}

def private any_in_init(offs : array<ClangOffsetof>) : bool {
    for (off in offs) {
        if (off.in_init) {
            return true
        }
    }
    return false
}

// whether the `offsetof`s of one key spell one type and member alike, so that any pairing of
// them with the dump's nodes gives each node its value
def private offsetofs_alike(offs : array<ClangOffsetof>) : bool {
    for (off in offs) {
        if (off.type_text != offs[0].type_text || off.member != offs[0].member || off.path != offs[0].path) {
            return false
        }
    }
    return true
}

// clang's JSON carries neither the components nor the value of `offsetof(T, f)`
// (docs/probe-findings.md F20): libclang's cursor of the expression gives `T` as the source
// spells it and `f`, a direct field of a record only. Every `offsetof` of one macro expansion
// shares a key (the expansion site, and stddef.h's `__builtin_offsetof` as the spelling), and the
// dump has no location of its member: the n-th node of a key takes the n-th cursor there. That pairing holds while both walks meet the key's `offsetof`s in source
// order; an initializer list's designators reorder the dump's, so a key whose `offsetof`s differ
// and one sits in an initializer list fails closed, as does a key the two walks count apart
// (`check_offsetof_counts`)
[arch(at="ARCHITECTURE_DUMPER.md#file-policy")]
def private dump_offsetof(var d : Dumper; js : JsonValue?; t : int; at : CirLoc) : CirExpr? {
    let key = node_key(d, js)
    let slot = d.offsetof_taken?[key] ?? 0
    d.offsetof_taken[key] = slot + 1
    if (slot == 0) {
        d.offsetof_at[key] = at
    }
    var off : ClangOffsetof
    var found = false
    var reordered = false
    get(d.offsetofs_by_loc, key) $(offs) {
        if (slot < length(offs)) {
            off = offs[slot]
            found = true
        }
        reordered = !offsetofs_alike(offs) && any_in_init(offs)
    }
    if (reordered) {
        fail(d, "offsetof: one macro expansion spells `offsetof`s of different members, one of them in an initializer list, whose designators clang's dump reorders; not lowered", at)
        return null
    }
    if (!found) {
        fail(d, "offsetof: libclang reports no `offsetof` at this location", at)
        return null
    }
    if (off.path) {
        fail(d, "offsetof({off.type_text}, ...): a member path (`a.b`, `a[i]`) is not lowered yet", at)
        return null
    }
    let of_t = type_from_qual(d, off.type_text, at)
    if (of_t < 0) {
        return null
    }
    let field = member_index(d, of_t, off.member, -1)
    if (field < 0) {
        fail(d, "offsetof: `{off.member}` is not a direct field of `{off.type_text}`", at)
        return null
    }
    return new CirExpr(e = "offsetof", t = t, of_t = of_t, field = field)
}

def private dump_literal(var d : Dumper; js : JsonValue?; kind : string; t : int; at : CirLoc) : CirExpr? {
    if (kind == "IntegerLiteral") {
        return new CirExpr(e = "int_lit", t = t, v = js?["value"] ?? "0")
    }
    if (kind == "CharacterLiteral") {
        return new CirExpr(e = "int_lit", t = t, v = "{js?["value"] ?? 0l}", is_char = true)
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

// the name of the object-like macro whose expansion is exactly node `js` (both ends of its range
// expand from one identifier no `(` follows, other than the expansion enclosing the node), and the
// expansion's offset; "" for any other node
[arch(at="ARCHITECTURE_DUMPER.md#macro-names")]
def private macro_expansion(var d : Dumper; js : JsonValue?; var offset : int64&) : string {
    let a = js?["range"]?["begin"]?["expansionLoc"]
    let b = js?["range"]?["end"]?["expansionLoc"]
    if (a == null || b == null || (a?["isMacroArgExpansion"] ?? false)) {
        return ""
    }
    offset = a?["offset"] ?? -1l
    let file = a?["file"] ?? ""
    let len = int(a?["tokLen"] ?? 0l)
    if (offset < 0l || offset + 1l == d.macro_in || (b?["offset"] ?? -1l) != offset || empty(file) || len <= 0) {
        return ""
    }
    // a system header's macro may share its name with a das builtin (`INT_MAX`)
    let defined_in = js?["range"]?["begin"]?["spellingLoc"]?["file"] ?? ""
    if (empty(defined_in) || !in_program(d, defined_in)) {
        return ""
    }
    if (!key_exists(d.macro_texts, file)) {
        d.macro_texts[file] = stat(file).is_reg ? fread(file) : ""
    }
    var name = ""
    peek_data(d.macro_texts[file]) $(t) {
        let at = int(offset)
        if (at + len > length(t) || !(is_alpha(int(t[at])) || int(t[at]) == '_')) {
            return
        }
        var after = at + len
        while (after < length(t) && (int(t[after]) == ' ' || int(t[after]) == '\t')) {
            after++
        }
        if (after >= length(t) || int(t[after]) != '(') {
            name = slice(t, at, at + len)
        }
    }
    return name
}

// whether the `#define` of `name` (in the file the node's first token is spelled in, else the
// main file) has a body that is one operand: a token, a parenthesized group, or a call
def private atomic_body(var d : Dumper; js : JsonValue?; name : string) : bool {
    for (file in [js?["range"]?["begin"]?["spellingLoc"]?["file"] ?? "", d.c_path]) {
        if (empty(file)) {
            continue
        }
        if (!key_exists(d.macro_texts, file)) {
            d.macro_texts[file] = stat(file).is_reg ? fread(file) : ""
        }
        let body = define_body(d.macro_texts?[file] ?? "", name)
        if (!empty(body)) {
            return is_one_operand(body)
        }
    }
    return false
}

// the body of `#define name` in `text`, one line, a trailing comment dropped; "" when absent
def private define_body(text : string; name : string) : string {
    for (raw in split(text, "\n")) {
        let line = strip(raw)
        if (!(line |> starts_with("#"))) {
            continue
        }
        let rest = strip(slice(line, 1))
        if (!(rest |> starts_with("define "))) {
            continue
        }
        let decl = strip(slice(rest, 7))
        if (decl |> starts_with("{name} ") || decl |> starts_with("{name}\t")) {
            let body = strip(slice(decl, length(name)))
            let block_at = find(body, "/*")
            let line_comment = find(body, "//")
            let cut = block_at >= 0 && (line_comment < 0 || block_at < line_comment) ? block_at : line_comment
            return cut >= 0 ? strip(slice(body, 0, cut)) : body
        }
    }
    return ""
}

// whether macro body `body` is one operand: a single token, a parenthesized group, or a name
// followed by one parenthesized group
def private is_one_operand(body : string) : bool {
    var depth = 0
    var first_open = -1
    var closes_at = -1
    var spaced = false
    peek_data(body) $(b) {
        for (i in range(length(b))) {
            let c = int(b[i])
            if (c == '(') {
                if (depth == 0 && first_open < 0) {
                    first_open = i
                }
                depth++
            } elif (c == ')') {
                depth--
                if (depth == 0 && closes_at < 0) {
                    closes_at = i
                }
            } elif (depth == 0 && (c == ' ' || c == '\t' || !(is_alnum(c) || c == '_' || c == '.' || c == '\''))) {
                spaced = true
            }
        }
    }
    if (first_open < 0) {
        return !spaced
    }
    return !spaced && closes_at == length(body) - 1
}

// the name of the object-like macro whose body node `js` spells whole, for a node a macro
// expansion made inside another (`POS_A` in `#define POS_B (POS_A + SIZE_A)`, or in a
// function-like macro's body): both ends spelled in one program file, the first at the body's
// first token and the last ending its last; "" for any other node, and for a node one of whose
// operands spells the same range (`A + A` spelled from two expansions of `#define A 1`)
[arch(at="ARCHITECTURE_DUMPER.md#macro-names")]
def private nested_macro(var d : Dumper; js : JsonValue?) : string {
    let b = js?["range"]?["begin"]
    let e = js?["range"]?["end"]
    if (b?["expansionLoc"] == null || e?["expansionLoc"] == null || (b?["expansionLoc"]?["offset"] ?? -1l) != (e?["expansionLoc"]?["offset"] ?? -2l)) {
        return ""
    }
    let file = b?["spellingLoc"]?["file"] ?? ""
    let first = b?["spellingLoc"]?["offset"] ?? -1l
    let last = e?["spellingLoc"]?["offset"] ?? -1l
    let last_len = e?["spellingLoc"]?["tokLen"] ?? 0l
    if (empty(file) || file != (e?["spellingLoc"]?["file"] ?? "") || first < 0l || last < first || last_len <= 0l || !in_program(d, file)) {
        return ""
    }
    for (idx in range(child_count(js))) {
        if (spells_from_to(below_wrappers((js?["inner"] as _array)[idx]), first, last)) {
            return ""
        }
    }
    if (!key_exists(d.macro_texts, file)) {
        d.macro_texts[file] = stat(file).is_reg ? fread(file) : ""
    }
    var name = ""
    peek_data(d.macro_texts[file]) $(t) {
        name = define_spelling(t, int(first), int(last + last_len))
    }
    return name
}

// node `js` below the wrappers clang adds over an operand with its range
def private below_wrappers(js : JsonValue?) : JsonValue const? {
    let kind = node_kind(js)
    if ((kind == "ImplicitCastExpr" || kind == "ConstantExpr") && child_count(js) > 0) {
        return below_wrappers((js?["inner"] as _array)[0])
    }
    return js
}

// whether node `js`'s range is spelled from offset `first` to `last`
def private spells_from_to(js : JsonValue const?; first, last : int64) : bool =>
    (js?["range"]?["begin"]?["spellingLoc"]?["offset"] ?? -1l) == first && (js?["range"]?["end"]?["spellingLoc"]?["offset"] ?? -1l) == last

// the name of the object-like `#define` of text `t` whose body is bytes `first` to `stop`
// (comments, blanks and line continuations aside); "" when they are no such body
def private define_spelling(t : array<uint8>#; first, stop : int) : string {
    if (stop > length(t)) {
        return ""
    }
    var at = first
    while (at > 0 && int(t[at - 1]) != '\n') {
        at--
    }
    while (continues_line(t, at)) {
        at--
        while (at > 0 && int(t[at - 1]) != '\n') {
            at--
        }
    }
    at = skip_blanks(t, at, first)
    if (at >= first || int(t[at]) != '#') {
        return ""
    }
    at = skip_blanks(t, at + 1, first)
    if (!is_word(t, at, "define")) {
        return ""
    }
    let name_at = skip_blanks(t, at + 6, first)
    var name_end = name_at
    while (name_end < first && (is_alnum(int(t[name_end])) || int(t[name_end]) == '_')) {
        name_end++
    }
    if (skip_blanks(t, name_end, first) != first) {
        return ""
    }
    let after = skip_blanks(t, stop, length(t))
    if (after < length(t) && int(t[after]) != '\n') {
        return ""
    }
    return slice(t, name_at, name_end)
}

// whether the line of `t` starting at `at` continues the line above it (a `\` before the newline)
def private continues_line(t : array<uint8>#; at : int) : bool {
    var prev = at - 2
    if (prev >= 0 && int(t[prev]) == '\r') {
        prev--
    }
    return at >= 1 && prev >= 0 && int(t[prev]) == '\\'
}

// the first byte of `t` from `at` (below `stop`) that is no blank, comment or line continuation
def private skip_blanks(t : array<uint8>#; at, stop : int) : int {
    var i = at
    while (i < stop) {
        let c = int(t[i])
        if (c == ' ' || c == '\t' || c == '\r') {
            i++
        } elif (c == '\\' && i + 1 < stop && int(t[i + 1]) == '\n') {
            i += 2
        } elif (c == '\\' && i + 2 < stop && int(t[i + 1]) == '\r' && int(t[i + 2]) == '\n') {
            i += 3
        } elif (c == '/' && i + 1 < stop && int(t[i + 1]) == '*') {
            i += 2
            while (i + 1 < stop && !(int(t[i]) == '*' && int(t[i + 1]) == '/')) {
                i++
            }
            i = min(i + 2, stop)
        } elif (c == '/' && i + 1 < stop && int(t[i + 1]) == '/') {
            while (i < stop && int(t[i]) != '\n') {
                i++
            }
        } else {
            return i
        }
    }
    return stop
}

// whether `t` spells `word` at `at`, no identifier byte after it
def private is_word(t : array<uint8>#; at : int; word : string) : bool {
    let n = length(word)
    if (at + n > length(t) || (at + n < length(t) && (is_alnum(int(t[at + n])) || int(t[at + n]) == '_'))) {
        return false
    }
    var same = true
    peek_data(word) $(w) {
        for (i in range(n)) {
            same = same && t[at + i] == w[i]
        }
    }
    return same
}

// one past the offset location `at` expands from, its own where no macro made it
def private expansion_at(at : JsonValue?) : int64 {
    let e = at?["expansionLoc"]
    return (e != null ? e?["offset"] ?? -1l : at?["offset"] ?? -1l) + 1l
}

def dump_expr(var d : Dumper; js : JsonValue?) : CirExpr? {
    let kind = node_kind(js)
    // a wrapper clang adds spans its operand's range exactly: the operand's parent is the
    // wrapper's
    let wrapper = kind == "ImplicitCastExpr" || kind == "ConstantExpr"
    var offset = -1l
    var name = wrapper ? "" : macro_expansion(d, js, offset)
    // `#define X 1 + 2` in `X * 3`: the `1` expands from `X` whole, but its parent `1 + 2 * 3`
    // starts in that expansion too, so `X` names no node there; a parent sharing an end is
    // the node's own context only where the body is one operand (`8`, `(...)`, `f(...)`)
    if (!empty(name) && (d.parent_begin == offset + 1l || d.parent_end == offset + 1l) && !atomic_body(d, js, name)) {
        name = ""
    }
    // a macro inside another one's expansion names its own node (`#define POS_B (POS_A + 1)`)
    let nested = wrapper || !empty(name) ? "" : nested_macro(d, js)
    let outer_begin = d.parent_begin
    let outer_end = d.parent_end
    if (!wrapper) {
        d.parent_begin = expansion_at(js?["range"]?["begin"])
        d.parent_end = expansion_at(js?["range"]?["end"])
    }
    let outer = d.macro_in
    if (!empty(name)) {
        d.macro_in = offset + 1l
    }
    var x = dump_expr_node(d, js)
    d.macro_in = outer
    d.parent_begin = outer_begin
    d.parent_end = outer_end
    if (x != null && !empty(name)) {
        x.macro = name
    } elif (x != null && !empty(nested)) {
        x.macro = nested
    }
    if (x != null && !wrapper) {
        let key = unsafe(reinterpret<uint64>(js))
        get(d.fn_macros.fn_marks, key) $(uses) {
            // a node collapsed through its parentheses already holds its inner node's marks, an
            // expansion inside this one: this node's go first, outermost first
            var own := uses
            for (u in x.fn_macro) {
                own |> push_clone(u)
            }
            delete x.fn_macro
            x.fn_macro <- own
        }
        get(d.fn_macros.arg_marks, key) $(args) {
            x.macro_args |> push_from(args)
        }
    }
    return x
}

// a reference: an enumerator, a library function's value through its wrapper (`library_value`),
// or a declaration by the name it is bound to
def private dump_decl_ref(var d : Dumper; js : JsonValue?; t : int; at : CirLoc) : CirExpr? {
    if ((js?["referencedDecl"]?["kind"] ?? "") == "EnumConstantDecl") {
        let item = js?["referencedDecl"]?["name"] ?? ""
        let ref = d.enum_ref_by_loc?[node_key(d, js)] ?? ClangEnumRef()
        if (ref.item != item) {
            fail(d, "enum constant `{item}`: libclang reports no reference at this location", at)
            return null
        }
        let owner = enum_type(d, tagged_spelling(d, ref.enum_spelling), at)
        if (owner < 0) {
            return null
        }
        return new CirExpr(e = "enum_ref", t = t, enum_t = owner, item = item)
    }
    let referenced = js?["referencedDecl"]?["name"] ?? ""
    if (!d.dumping_callee && (js?["referencedDecl"]?["kind"] ?? "") == "FunctionDecl" && key_exists(d.library_results, referenced)) {
        return library_value(d, referenced, t, at)
    }
    return new CirExpr(e = "ref", t = t, name = bound_name(d, js?["referencedDecl"]), vol = is_volatile_spelling(js))
}

// the nodes whose value is their one child's
let VALUE_WRAPPERS <- {"ParenExpr", "ConstantExpr", "PredefinedExpr", "ExprWithCleanups", "MaterializeTemporaryExpr"}

def private dump_expr_node(var d : Dumper; js : JsonValue?) : CirExpr? {
    let at = loc_of(d, js)
    let kind = node_kind(js)
    if (key_exists(VALUE_WRAPPERS, kind)) {
        // clang wraps a constant item of a file-scope initializer in `ConstantExpr`, whose
        // value is its child's; `__func__` and `__PRETTY_FUNCTION__` are a `PredefinedExpr` over
        // the string literal of the function's name; a member of a record a call returns
        // (`f().a`) reads a `MaterializeTemporaryExpr` of the call under an `ExprWithCleanups`
        // that ends the full expression, both their child's value in C
        if (child_count(js) == 0) {
            fail(d, "empty parentheses", at)
            return null
        }
        var inner = child_expr(d, js?["inner"], 0)
        if (inner != null && kind == "ParenExpr") {
            // the source's own parentheses all count; a macro body's only around a shift or a
            // bitwise operator, whose precedence against its neighbours a reader misreads
            // (`((t) | ((v) << 4))`), not around an argument, a unary or a comparison
            inner.paren = !is_present(js?["range"]?["begin"]?["expansionLoc"]) || (inner.e == "bin" && key_exists(BIT_OPS, inner.op))
        }
        return inner
    }
    d.expr_key = empty(d.shared_tags) ? "" : begin_key(d, js)
    d.type_operand = kind == "VAArgExpr"
    let t = node_type(d, js, at)
    d.type_operand = false
    d.expr_key = ""
    if (t < 0) {
        return null
    }
    if (kind == "IntegerLiteral" || kind == "CharacterLiteral" || kind == "FloatingLiteral" || kind == "StringLiteral") {
        return dump_literal(d, js, kind, t, at)
    }
    if (kind == "DeclRefExpr") {
        return dump_decl_ref(d, js, t, at)
    }
    if (kind == "ImplicitCastExpr" || kind == "CStyleCastExpr") {
        return dump_cast(d, js, t, at)
    }
    if (kind == "UnaryOperator") {
        return marked_volatile(dump_unary(d, js, t, at), js)
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
        return marked_volatile(dump_subscript(d, js, t, at), js)
    }
    if (kind == "MemberExpr") {
        return marked_volatile(dump_member(d, js, t, at), js)
    }
    if (kind == "InitListExpr") {
        return dump_init_list(d, js, t, at)
    }
    if (kind == "CompoundLiteralExpr") {
        return dump_compound_literal(d, js, t, at)
    }
    if (key_exists(TYPE_OPERATOR_KINDS, kind)) {
        return dump_type_operator(d, js, kind, t, at)
    }
    if (kind == "TypeTraitExpr") {
        return dump_folded(d, js, t, at, TYPES_COMPATIBLE)
    }
    if (kind == "ChooseExpr") {
        return dump_choose(d, js, at)
    }
    fail(d, "unsupported expression `{kind}`", at)
    return null
}

// whether clang's spelling of node `js`'s type is volatile at the top level: `volatile int`,
// `int *volatile`, `void (*volatile)(char *)`, a typedef through its desugared spelling; the
// qualifier of a pointer's pointee (`volatile int *`) and of a function type's parameter
// (`void (*)(int *volatile)`) is not the node's own
def is_volatile_spelling(js : JsonValue?) : bool {
    let ty = js?["type"]
    let desugared = ty?["desugaredQualType"] ?? ""
    return own_volatile(empty(desugared) ? ty?["qualType"] ?? "" : desugared)
}

// whether type spelling `spelled` qualifies its own top level `volatile`: the qualifiers after the
// last `*` of the innermost declarator group (`(*volatile)` of `int (*volatile)(int *)`), the
// part before an array's bounds, or the specifiers when no `*` is left. clang's name of an
// anonymous record (`struct (unnamed struct at x.c:3:10)`) is no group, and a function type's
// own qualifiers are its return value's, never the function's
def own_volatile(spelled : string) : bool {
    var lo = 0
    var hi = length(spelled)
    var of_function = false
    peek_data(spelled) $(bytes) {
        var open = first_group(bytes, lo, hi)
        while (open >= 0) {
            let close = group_end(bytes, open, hi)
            let paren = int(bytes[open]) == '('
            if (paren && close > open && names_record(spelled, lo, open)) {
                open = first_group(bytes, close + 1, hi)
            } elif (paren && close > open && opens_pointer(bytes, open + 1, close)) {
                lo = open + 1
                hi = close
                open = first_group(bytes, lo, hi)
            } else {
                of_function = paren
                hi = open
                open = -1
            }
        }
    }
    if (of_function) {
        return false
    }
    let own = slice(spelled, lo, hi)
    let star = rfind(own, "*")
    for (word in split(star < 0 ? own : slice(own, star + 1), " ")) {
        if (word == "volatile") {
            return true
        }
    }
    return false
}

// the first `(` or `[` of `bytes` in `[lo, hi)`, -1 for none
def private first_group(bytes : array<uint8>#; lo, hi : int) : int {
    for (i in range(lo, hi)) {
        let c = int(bytes[i])
        if (c == '(' || c == '[') {
            return i
        }
    }
    return -1
}

// the index of the bracket closing the one at `open` in `bytes` before `hi`, -1 when unbalanced
def private group_end(bytes : array<uint8>#; open, hi : int) : int {
    var depth = 0
    for (i in range(open, hi)) {
        let c = int(bytes[i])
        if (c == '(' || c == '[') {
            depth++
        } elif (c == ')' || c == ']') {
            depth--
            if (depth == 0) {
                return i
            }
        }
    }
    return -1
}

// whether the text of `spelled` in `[lo, open)` ends in `struct `, `union ` or `enum `: the group
// at `open` is clang's name of an anonymous record, no declarator
def private names_record(spelled : string; lo, open : int) : bool {
    let before = slice(spelled, lo, open)
    return ends_with(before, "struct ") || ends_with(before, "union ") || ends_with(before, "enum ")
}

// whether the first character of `bytes` in `[lo, hi)` past the spaces is a `*`: a declarator
// group, where a parameter list starts with a type
def private opens_pointer(bytes : array<uint8>#; lo, hi : int) : bool {
    for (i in range(lo, hi)) {
        let c = int(bytes[i])
        if (c != ' ') {
            return c == '*'
        }
    }
    return false
}

// `x` marked volatile when it is an lvalue node of a volatile-qualified type
def private marked_volatile(var x : CirExpr?; js : JsonValue?) : CirExpr? {
    if (x != null && (x.e == "member" || x.e == "index" || (x.e == "un" && x.op == "deref"))) {
        x.vol = is_volatile_spelling(js)
    }
    return x
}

let TYPE_OPERATOR_KINDS <- {"UnaryExprOrTypeTraitExpr", "OffsetOfExpr", "VAArgExpr"}

// the expressions the language spells as operators over a type: `sizeof`, `offsetof`, `va_arg`
def private dump_type_operator(var d : Dumper; js : JsonValue?; kind : string; t : int; at : CirLoc) : CirExpr? {
    if (kind == "UnaryExprOrTypeTraitExpr") {
        return dump_sizeof(d, js, t, at)
    }
    if (kind == "OffsetOfExpr") {
        return dump_offsetof(d, js, t, at)
    }
    // clang gives a `VAArgExpr` its list as the one child
    var list = child_expr(d, js?["inner"], 0)
    if (list == null) {
        return null
    }
    return new CirExpr(e = "va_arg", t = t, list = list, arg_t = t)
}

let EXPR_KINDS <- {"IntegerLiteral", "CharacterLiteral", "FloatingLiteral", "StringLiteral", "DeclRefExpr", "ImplicitCastExpr", "CStyleCastExpr", "UnaryOperator", "BinaryOperator", "CompoundAssignOperator", "ConditionalOperator", "CallExpr", "ArraySubscriptExpr", "UnaryExprOrTypeTraitExpr", "ParenExpr", "MemberExpr", "InitListExpr", "OffsetOfExpr", "VAArgExpr", "CompoundLiteralExpr", "ExprWithCleanups", "TypeTraitExpr", "ChooseExpr"}

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

// `want` when no hoisted static, file-scope name of the unit, or parameter or local of the
// function takes it, else `<want>1` and up
def private free_fn_name(d : Dumper; want : string) : string {
    var name = want
    var n = 1
    while (key_exists(d.hoisted_names, name) || key_exists(d.file_scope_names, name) || key_exists(d.fn_all_locals, name)) {
        name = "{want}{n}"
        n++
    }
    return name
}

// the C-IR name of a parameter or local: its own, or a free one when a block-scope `extern` or
// prototype of the function names it, since that declaration's references spell the
// program-wide name and must not bind to the local
def private local_name(var d : Dumper; c_name : string) : string {
    if (!key_exists(d.fn_extern_names, c_name)) {
        return c_name
    }
    let name = free_fn_name(d, c_name)
    d.fn_all_locals |> insert(name)
    return name
}

// a block-scope `extern` declaration or function prototype declares the program-wide entity: one
// declared before binds to that declaration (one outside the program by its file-scope name, as a
// reference does), and the first is the unit-level declaration it would be at file scope, placed
// before the function
def private dump_block_extern(var d : Dumper; js : JsonValue?) : bool {
    let previous = js?["previousDecl"] ?? ""
    if (key_exists(d.library_decls, previous) && !has_child_kind(js, "BuiltinAttr")) {
        fail(d, "`{js?["name"] ?? ""}` redeclared in a block with another type than the C library's is not lowered (C99 6.2.7)", loc_of(d, js))
        return false
    }
    if (!empty(previous)) {
        d.decl_names[js?["id"] ?? ""] = d.decl_names?[previous] ?? linkage_name(d, js?["name"] ?? "")
        return true
    }
    var cd = dump_decl(d, js)
    if (cd == null) {
        return false
    }
    d.tu.decls |> push(cd)
    return true
}

// a local `static` is a module global named `<fn>_<name>` (docs/c-feature-matrix.md section 2):
// the dumper hoists it into `decls` with `from_func` and the body refers to the hoisted name
def private hoist_static(var d : Dumper; js : JsonValue?; at : CirLoc; t : int) : bool {
    let c_name = js?["name"] ?? ""
    // `<fn>_<name>` first, numbered past another hoisted static, a file-scope name of the unit and
    // a parameter or local of the function
    let hoisted = free_fn_name(d, "{d.current_fn}_{c_name}")
    d.hoisted_names |> insert(hoisted)
    d.decl_names[js?["id"] ?? ""] = hoisted
    var ok = true
    let init = initializer_of(d, js, at, ok)
    if (!ok) {
        return false
    }
    var g = new CirDecl(k = "global", name = hoisted, c_name = c_name, t = t, is_static = true, from_func = d.current_fn, loc = at)
    if (!enum_dims(d, node_key(d, js), t, at, g.dims)) {
        delete_decl(g)
        return false
    }
    if (init >= 0) {
        g.init = dump_expr(d, (js?["inner"] as _array)[init])
        if (g.init == null) {
            delete_decl(g)
            return false
        }
    }
    d.tu.decls |> push(g)
    return true
}

def private dump_var(var d : Dumper; js : JsonValue?; at : CirLoc) : CirStmt? {
    let spelling = type_spelling(d, js?["type"])
    if (has_variable_dimension(spelling) && find(spelling, "(") < 0) {
        // the declaration as C spells it, the name before the first bracket
        let open = find(spelling, "[")
        fail(d, "`{strip(slice(spelling, 0, open))} {js?["name"] ?? ""}{slice(spelling, open)}`: a variable-length array is not lowered (out of scope in v1)", at)
        return null
    }
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
    if ((js?["storageClass"] ?? "") == "extern") {
        return dump_block_extern(d, js) ? new CirStmt(s = "null", loc = at) : null
    }
    var ok = true
    let init = initializer_of(d, js, at, ok)
    if (!ok) {
        return null
    }
    var st = new CirStmt(s = "decl", name = local_name(d, js?["name"] ?? ""), t = t, loc = at)
    d.decl_names[js?["id"] ?? ""] = st.name
    if (!enum_dims(d, node_key(d, js), t, at, st.dims)) {
        delete_stmt(st)
        return null
    }
    if (init >= 0) {
        st.init = dump_expr(d, (js?["inner"] as _array)[init])
        if (st.init == null) {
            delete_stmt(st)
            return null
        }
    }
    return st
}

// a GotoStmt names its label by declaration id, and a label may follow its goto, so a
// function's labels are read before its body
def private collect_labels(var d : Dumper; js : JsonValue?) {
    if (node_kind(js) == "LabelStmt") {
        d.label_names[js?["declId"] ?? ""] = js?["name"] ?? ""
    }
    for (idx in range(child_count(js))) {
        collect_labels(d, (js?["inner"] as _array)[idx])
    }
}

// the variables of one DeclStmt, each as its own `decl` (or hoisted when static)
def private dump_decl_stmt(var d : Dumper; js : JsonValue?; var into : array<CirStmt?>) : bool {
    loc_of(d, js)
    let vars = js?["inner"]
    into |> reserve(length(into) + child_count(js))
    for (vidx in range(child_count(js))) {
        let v = (vars as _array)[vidx]
        if (node_kind(v) == "RecordDecl" || node_kind(v) == "EnumDecl" || node_kind(v) == "TypedefDecl") {
            d.lone_tag_decl = child_count(js) == 1
            let ok = dump_type_decl(d, v)
            d.lone_tag_decl = false
            if (!ok) {
                return false
            }
            continue
        }
        if (node_kind(v) == "FunctionDecl") {
            if (!dump_block_extern(d, v)) {
                return false
            }
            continue
        }
        // clang has checked a `_Static_assert`: it leaves nothing to run
        if (node_kind(v) == "StaticAssertDecl") {
            continue
        }
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

// a block: its tag scope open while its statements are dumped
def private dump_compound(var d : Dumper; js : JsonValue?; at : CirLoc) : CirStmt? {
    d.tag_scopes |> emplace(table<string; int>())
    var st = dump_block(d, js, at)
    d.tag_scopes |> pop()
    return st
}

def private dump_block(var d : Dumper; js : JsonValue?; at : CirLoc) : CirStmt? {
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
        if (key_exists(MARKER_KINDS, node_kind(child))) {
            if (!dump_case(d, child, st.body)) {
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

// the GNU statement forms: an asm statement and a statement that carries attributes
let GNU_STMT_KINDS <- {"GCCAsmStmt", "AttributedStmt"}

// an asm statement: a compiler barrier is the empty statement; any other fails closed with the
// reason the libclang pass gave it
[arch(at="ARCHITECTURE_DUMPER.md#attributes-and-asm")]
def private dump_asm(var d : Dumper; js : JsonValue?; at : CirLoc) : CirStmt? {
    let key = node_key(d, js)
    if (!key_exists(d.asm_by_loc, key)) {
        fail(d, "inline asm: libclang reports no statement at this location", at)
        return null
    }
    let reason = d.asm_by_loc?[key] ?? ""
    if (empty(reason)) {
        return new CirStmt(s = "null", loc = at)
    }
    fail(d, reason, at)
    return null
}

def private dump_gnu_stmt(var d : Dumper; js : JsonValue?; kind : string; at : CirLoc) : CirStmt? =>
    kind == "GCCAsmStmt" ? dump_asm(d, js, at) : dump_attributed(d, js, at)

// a statement that carries attributes (`__attribute__((fallthrough));`, `[[fallthrough]];`) is
// its statement: `check_attributes` judged the attributes with the declaration around it
def private dump_attributed(var d : Dumper; js : JsonValue?; at : CirLoc) : CirStmt? {
    for (idx in range(child_count(js))) {
        let kid = (js?["inner"] as _array)[idx]
        if (!(node_kind(kid) |> ends_with("Attr"))) {
            return dump_stmt(d, kid)
        }
    }
    fail(d, "an attributed statement without a statement", at)
    return null
}

// the attributes the dumper drops, each changing nothing a das run observes: optimizer and
// inlining hints, diagnostics, a symbol's visibility or section, a defined symbol's weakness,
// `mode`, whose type clang has already given the declaration, and `may_alias`, since das has no
// strict-aliasing rule for it to relax; `noclone`, `noipa`, `optimize` and
// `scalar_storage_order` reach no node at all, clang ignoring them
let DROPPED_ATTRIBUTES <- {"NoInlineAttr", "UnusedAttr", "UsedAttr", "C11NoReturnAttr", "ConstAttr", "PureAttr", "AlwaysInlineAttr", "NoThrowAttr", "ColdAttr", "HotAttr", "VisibilityAttr", "FormatAttr", "NonNullAttr", "RestrictAttr", "WarnUnusedResultAttr", "DeprecatedAttr", "WeakAttr", "MayAliasAttr", "SectionAttr", "LeafAttr", "NoInstrumentFunctionAttr", "AllocSizeAttr", "ReturnsNonNullAttr", "NoDebugAttr", "FallThroughAttr", "GNUInlineAttr", "CXX11NoReturnAttr", "ModeAttr"}

// `musttail` on a `return f(...)`: the call converts as a plain call whose value the function
// returns, which computes the same value but guarantees no tail call, so each such call takes
// stack until the chain returns (wasm3's threaded ops)
let TAIL_CALL_ATTRIBUTES <- {"MustTailAttr"}

// the attributes the conversion reads: `aligned` (the typedef pass, the record layout check)
// and `packed` and `#pragma pack` (clang's record layout, which the layout law places or the
// sidecar marshals)
let READ_ATTRIBUTES <- {"AlignedAttr", "PackedAttr", "MaxFieldAlignmentAttr"}

//! An attribute's spelling from its node kind, a word break before each capital that follows no
//! capital: `TransparentUnionAttr` is `transparent_union`, `CXX11NoReturnAttr` `cxx11_no_return`.
def attribute_spelling(kind : string) : string {
    let base = kind |> ends_with("Attr") ? slice(kind, 0, length(kind) - 4) : kind
    return build_string() $(writer) {
        var after_capital = true
        for (ch in base) {
            let capital = ch >= 'A' && ch <= 'Z'
            if (capital) {
                if (!after_capital) {
                    writer |> write_char('_')
                }
                writer |> write_char(ch - 'A' + 'a')
            } else {
                writer |> write_char(ch)
            }
            after_capital = capital
        }
    }
}

// every attribute a program declaration carries, at any depth (a local's, a field's, a
// statement's), against the deliberate lists: one clang wrote itself (`implicit`) or carried
// from an earlier declaration (`inherited`) was judged there or is the library's; a dropped one
// passes, `weak` only on a name the program defines; any other fails the conversion naming it
[arch(at="ARCHITECTURE_DUMPER.md#attributes-and-asm")]
def private check_attributes(var d : Dumper; js : JsonValue?; owner : string = "") : bool {
    let kind = node_kind(js)
    if (kind |> ends_with("Attr") && !(js?["implicit"] ?? false) && !(js?["inherited"] ?? false)) {
        let dropped = key_exists(DROPPED_ATTRIBUTES, kind) && (kind != "WeakAttr" || key_exists(d.defined_names, owner))
        if (!dropped && !key_exists(READ_ATTRIBUTES, kind) && !key_exists(TAIL_CALL_ATTRIBUTES, kind)) {
            let what = kind == "WeakAttr" ? "`weak` on `{owner}`, which the unit never defines," : "the attribute `{attribute_spelling(kind)}`"
            fail(d, "{what} is not lowered (the dumper drops only the attributes that change nothing for a run)", loc_of(d, js))
            return false
        }
    }
    let name = kind |> ends_with("Decl") ? js?["name"] ?? owner : owner
    for (idx in range(child_count(js))) {
        if (!check_attributes(d, (js?["inner"] as _array)[idx], name)) {
            return false
        }
    }
    return true
}

// the names every parameter and variable declared under `js` takes
def private local_names(js : JsonValue?) : table<string> {
    var names : table<string>
    collect_local_names(js, names)
    return <- names
}

def private collect_local_names(js : JsonValue?; var names : table<string>) {
    for (idx in range(child_count(js))) {
        let kid = (js?["inner"] as _array)[idx]
        let kind = node_kind(kid)
        if (kind == "VarDecl" || kind == "ParmVarDecl") {
            names |> insert(kid?["name"] ?? "")
        }
        collect_local_names(kid, names)
    }
}

// the names the block-scope `extern` declarations and function prototypes under `js` declare
def private collect_block_externs(js : JsonValue?; var names : table<string>) {
    for (idx in range(child_count(js))) {
        let kid = (js?["inner"] as _array)[idx]
        let kind = node_kind(kid)
        if (kind == "FunctionDecl" || (kind == "VarDecl" && (kid?["storageClass"] ?? "") == "extern")) {
            names |> insert(kid?["name"] ?? "")
        }
        collect_block_externs(kid, names)
    }
}

// the names the program's top-level declarations define: a function with a body, a variable
// that is not `extern` or carries an initializer
def private collect_defined_names(var d : Dumper; js : JsonValue?) {
    // a block-scope `extern` names a unit-level entity a hoisted static must not take; the walk
    // covers the whole AST, so it meets the top-level declarations the loop below adds again
    collect_block_externs(js, d.file_scope_names)
    for (idx in range(child_count(js))) {
        let decl = (js?["inner"] as _array)[idx]
        let kind = node_kind(decl)
        if (kind == "FunctionDecl" || kind == "VarDecl") {
            d.file_scope_names |> insert(decl?["name"] ?? "")
        }
        let extern_var = kind == "VarDecl" && (decl?["storageClass"] ?? "") == "extern" && !is_present(decl?["init"])
        let body = kind == "FunctionDecl" && has_child_kind(decl, "CompoundStmt")
        if (body || (kind == "VarDecl" && !extern_var)) {
            d.defined_names |> insert(decl?["name"] ?? "")
        }
    }
}

def private has_child_kind(js : JsonValue?; kind : string) : bool {
    for (idx in range(child_count(js))) {
        if (node_kind((js?["inner"] as _array)[idx]) == kind) {
            return true
        }
    }
    return false
}

// a decimal integer as clang's JSON spells one, optionally negative
def private parse_int64(text : string) : int64 {
    var v = 0l
    var negative = false
    for (ch in text) {
        if (ch == '-') {
            negative = true
        } elif (is_number(ch)) {
            v = v * 10l + int64(ch - '0')
        }
    }
    return negative ? -v : v
}

let FOLD_BINARY <- {"+" => 0, "-" => 1, "*" => 2, "/" => 3, "%" => 4, "<<" => 5, ">>" => 6, "&" => 7, "|" => 8, "^" => 9}

// the value of a constant expression as the dump spells it, folded here since clang's JSON
// writes a `ConstantExpr` without its value: the literals, the arithmetic and bitwise
// operators, parentheses, casts and enumerators; false with `error` set for anything else
def private fold_constant(var d : Dumper; js : JsonValue?; var v : int64&) : bool {
    let at = loc_of(d, js)
    let kind = node_kind(js)
    if (kind == "IntegerLiteral") {
        v = parse_int64(js?["value"] ?? "0")
        return true
    }
    if (kind == "CharacterLiteral") {
        v = js?["value"] ?? 0l
        return true
    }
    if (kind == "ConstantExpr" || kind == "ParenExpr" || kind == "ImplicitCastExpr" || kind == "CStyleCastExpr") {
        return child_count(js) > 0 && fold_constant(d, (js?["inner"] as _array)[0], v)
    }
    if (kind == "DeclRefExpr" && (js?["referencedDecl"]?["kind"] ?? "") == "EnumConstantDecl") {
        var ref = dump_expr(d, js)
        if (ref == null) {
            return false
        }
        for (it in d.tu.types[ref.enum_t].items) {
            if (it.name == ref.item) {
                v = it.v
            }
        }
        delete_expr(ref)
        return true
    }
    if (kind == "UnaryOperator" && child_count(js) > 0) {
        return fold_unary(d, js, v)
    }
    if (kind == "BinaryOperator" && child_count(js) == 2) {
        return fold_binary(d, js, at, v)
    }
    fail(d, "a case value spelled by `{kind}` is not folded", at)
    return false
}

def private fold_unary(var d : Dumper; js : JsonValue?; var v : int64&) : bool {
    var a = 0l
    if (!fold_constant(d, (js?["inner"] as _array)[0], a)) {
        return false
    }
    let opcode = js?["opcode"] ?? ""
    v = opcode == "-" ? -a : opcode == "~" ? ~a : opcode == "!" ? (a == 0l ? 1l : 0l) : a
    return opcode == "-" || opcode == "~" || opcode == "!" || opcode == "+"
}

def private fold_binary(var d : Dumper; js : JsonValue?; at : CirLoc; var v : int64&) : bool {
    var a, b : int64
    if (!fold_constant(d, (js?["inner"] as _array)[0], a) || !fold_constant(d, (js?["inner"] as _array)[1], b)) {
        return false
    }
    let op = FOLD_BINARY?[js?["opcode"] ?? ""] ?? -1
    if (op < 0 || ((op == 3 || op == 4) && b == 0l)) {
        fail(d, "a case value with `{js?["opcode"] ?? ""}` is not folded", at)
        return false
    }
    v = op == 0 ? a + b : op == 1 ? a - b : op == 2 ? a * b : op == 3 ? a / b : op == 4 ? a % b : op == 5 ? a << b : op == 6 ? a >> b : op == 7 ? (a & b) : op == 8 ? (a | b) : (a ^ b)
    return true
}

let MARKER_KINDS <- {"CaseStmt", "DefaultStmt", "LabelStmt"}

// `case v:`, `default:` and `name:` are markers in the statement list, each followed by the
// statement clang nests under it; clang nests shared labels (`case 2: case 3: s`) one under
// the other
// whether a case label's constant is a character literal under clang's wrappers
def private is_char_literal(js : JsonValue?) : bool {
    let kind = node_kind(js)
    if (kind == "ConstantExpr" || kind == "ParenExpr" || kind == "ImplicitCastExpr") {
        return child_count(js) > 0 && is_char_literal((js?["inner"] as _array)[0])
    }
    return kind == "CharacterLiteral"
}

// value `v` as integer type `t` holds it: wrapped to its width, sign-extended when it is signed
// (a 64-bit type keeps the bits)
def private held_in(t : CirType; v : int64) : int64 {
    if (t.k != "int" || t.w >= 64) {
        return v
    }
    let low = v & ((1l << int64(t.w)) - 1l)
    return t.is_signed && (low >> int64(t.w - 1)) != 0l ? low - (1l << int64(t.w)) : low
}

def private dump_case(var d : Dumper; js : JsonValue?; var into : array<CirStmt?>) : bool {
    let at = loc_of(d, js)
    let kind = node_kind(js)
    let kids = js?["inner"]
    let nkids = child_count(js)
    if (kind == "LabelStmt") {
        into |> push(new CirStmt(s = "label", label_name = js?["name"] ?? "", loc = at))
    } elif (kind == "CaseStmt") {
        // a GNU range's children are its two ends, then the statement
        let is_range = js?["isGNURange"] ?? false
        var v = 0l
        var hi = 0l
        if (nkids < 1 || !fold_constant(d, (kids as _array)[0], v) || (is_range && (nkids < 3 || !fold_constant(d, (kids as _array)[1], hi)))) {
            return false
        }
        var empty_range = false
        if (is_range) {
            // clang converts both ends to the controlling type, which is each end's own type here
            let cond_t = node_type(d, (kids as _array)[0], at)
            if (cond_t < 0) {
                return false
            }
            v = held_in(d.tu.types[cond_t], v)
            hi = held_in(d.tu.types[cond_t], hi)
            let unsigned64 = d.tu.types[cond_t].k == "int" && !d.tu.types[cond_t].is_signed && d.tu.types[cond_t].w >= 64
            empty_range = unsigned64 ? uint64(v) > uint64(hi) : v > hi
        }
        // an empty range labels nothing: its statement stays, reached by falling into it
        if (!empty_range) {
            let is_char = is_char_literal((kids as _array)[0]) && (!is_range || is_char_literal((kids as _array)[1]))
            into |> push(new CirStmt(s = "case", v = v, is_char = is_char, is_range = is_range, hi = hi, loc = at))
        }
    } else {
        into |> push(new CirStmt(s = "default", loc = at))
    }
    let sub = (kids as _array)[nkids - 1]
    let sub_kind = node_kind(sub)
    if (key_exists(MARKER_KINDS, sub_kind)) {
        return dump_case(d, sub, into)
    }
    if (sub_kind == "DeclStmt") {
        return dump_decl_stmt(d, sub, into)
    }
    var st = dump_stmt(d, sub)
    if (st == null) {
        return false
    }
    into |> push(st)
    return true
}

def dump_stmt(var d : Dumper; js : JsonValue?) : CirStmt? {
    var st = dump_stmt_node(d, js)
    // an expression statement's marks are its expression's (`dump_expr`)
    if (st != null && st.s != "expr") {
        get(d.fn_macros.fn_marks, unsafe(reinterpret<uint64>(js))) $(uses) {
            for (u in uses) {
                st.fn_macro |> push_clone(u)
            }
        }
    }
    return st
}

def private dump_stmt_node(var d : Dumper; js : JsonValue?) : CirStmt? {
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
    if (key_exists(GNU_STMT_KINDS, kind)) {
        return dump_gnu_stmt(d, js, kind, at)
    }
    if (kind == "IfStmt" || kind == "WhileStmt" || kind == "DoStmt") {
        return dump_loop_or_if(d, js, kind, at)
    }
    if (kind == "SwitchStmt") {
        let kids = js?["inner"]
        var ok = true
        var st = new CirStmt(s = "switch", loc = at)
        st.cond = child_count(js) > 1 ? slot_expr(d, kids, 0, ok) : null
        st.body_s = child_count(js) > 1 ? slot_stmt(d, kids, 1, ok) : null
        if (!ok || st.cond == null || st.body_s == null) {
            fail(d, "switch without a condition or a body", at)
            delete_stmt(st)
            return null
        }
        return st
    }
    if (kind == "GotoStmt") {
        let target = d.label_names?[js?["targetLabelDeclId"] ?? ""] ?? ""
        if (empty(target)) {
            fail(d, "goto to a label the function does not declare", at)
            return null
        }
        return new CirStmt(s = "goto", label_name = target, loc = at)
    }
    if (kind == "IndirectGotoStmt") {
        fail(d, "a computed goto through a label address is outside the dialect", at)
        return null
    }
    if (key_exists(MARKER_KINDS, kind)) {
        // a marker directly as a body, `switch (x) case 1: s;` or `if (c) name: s;`
        var wrapped = new CirStmt(s = "compound", loc = at)
        if (!dump_case(d, js, wrapped.body)) {
            delete_stmt(wrapped)
            return null
        }
        return wrapped
    }
    if (kind == "ForStmt") {
        // a `for`'s declarations, a tag's definition among them, end with the statement
        d.tag_scopes |> emplace(table<string; int>())
        var st = dump_for(d, js, at)
        d.tag_scopes |> pop()
        return st
    }
    if (key_exists(EXPR_KINDS, kind) || kind == "StmtExpr") {
        // a bare statement expression `({ ... });` is no expression kind: `dump_expr_stmt` takes it
        return dump_expr_stmt(d, js, at)
    }
    fail(d, "unsupported statement `{kind}`", at)
    return null
}

// an expression statement: a statement block (`is_statement_block`) as its block, any other
// expression as the `expr` statement
def private dump_expr_stmt(var d : Dumper; js : JsonValue?; at : CirLoc) : CirStmt? {
    if (is_statement_block(js)) {
        return dump_statement_block(d, js, at)
    }
    var e = dump_expr(d, js)
    if (e == null) {
        return null
    }
    return new CirStmt(s = "expr", e = e, loc = at)
}

// whether `js` is a GNU statement expression `({ ... })` that an expression statement evaluates for
// its effect alone, through parentheses, `__extension__` and a cast to `void`
def private is_statement_block(js : JsonValue?) : bool {
    let kind = node_kind(js)
    if (child_count(js) != 1) {
        return false
    }
    if (kind == "StmtExpr") {
        return node_kind((js?["inner"] as _array)[0]) == "CompoundStmt"
    }
    let unwraps = kind == "ParenExpr" || (kind == "UnaryOperator" && (js?["opcode"] ?? "") == "__extension__") || (kind == "CStyleCastExpr" && (js?["castKind"] ?? "") == "ToVoid")
    return unwraps && is_statement_block((js?["inner"] as _array)[0])
}

// the block of a statement expression `is_statement_block` accepts, as a compound statement
def private dump_statement_block(var d : Dumper; js : JsonValue?; at : CirLoc) : CirStmt? {
    let inner = (js?["inner"] as _array)[0]
    return node_kind(js) == "StmtExpr" ? dump_compound(d, inner, at) : dump_statement_block(d, inner, at)
}

// a record's definition: nested records first, since a field's type precedes the field; a
// forward declaration adds nothing; the slot comes from the libclang layout at this location
def private dump_record_decl(var d : Dumper; js : JsonValue?) : bool {
    let at = loc_of(d, js)
    // a forward declaration adds nothing, and neither does glibc's tag, which a file that includes
    // no header defines itself: every spelling of it is the opaque `jmp_buf` record
    // (`jmp_buf_type`), so its fields name nothing
    let complete = js?["completeDefinition"] ?? false
    if (!complete && !empty(d.tag_scopes) && !is_present(js?["previousDecl"])) {
        // `struct T;` in a block, or a first `struct T *p`, declares a new incomplete type there,
        // which a definition elsewhere would be read as: refused for `struct T;` alone, and for
        // a tag defined more than once; a first `struct W *p` of a tag defined once is that
        // definition, as it always was
        let spelling = "{js?["tagUsed"] ?? "struct"} {js?["name"] ?? ""}"
        if (key_exists(d.shared_tags, spelling) || (d.lone_tag_decl && key_exists(d.record_by_spelling, spelling))) {
            fail(d, "`{spelling}` declared in a block hides its definitions elsewhere in this file with a new incomplete type; not lowered yet", at)
            return false
        }
    }
    if (!complete || (js?["name"] ?? "") == "__jmp_buf_tag") {
        return true
    }
    for (idx in range(child_count(js))) {
        let kid = (js?["inner"] as _array)[idx]
        if ((node_kind(kid) == "RecordDecl" || node_kind(kid) == "EnumDecl") && !dump_type_decl(d, kid)) {
            return false
        }
    }
    return anchor_type(d, js, at, false)
}

// the anchor of a record or enum definition: the type from the libclang entry at the node's
// location, pushed as its `record` or `enumdef` declaration
def private anchor_type(var d : Dumper; js : JsonValue?; at : CirLoc; is_enum : bool) : bool {
    let key = node_key(d, js)
    let idx = is_enum ? (d.enum_by_loc?[key] ?? -1) : (d.record_by_loc?[key] ?? -1)
    if (idx < 0) {
        fail(d, "libclang reports no {is_enum ? "enum" : "record"} definition at this location", at)
        return false
    }
    if (!is_enum && !empty(d.tag_scopes) && key_exists(d.shared_tags, d.records[idx].c_spelling)) {
        // the block's definition hides an outer one of its tag from here to the block's end
        d.tag_scopes[length(d.tag_scopes) - 1][d.records[idx].c_spelling] = idx
    }
    let t = is_enum ? enum_type(d, d.enums[idx].spelling, at) : record_type(d, d.records[idx].spelling, at)
    if (t < 0) {
        return false
    }
    d.tu.decls |> push(new CirDecl(k = is_enum ? "enumdef" : "record", name = d.tu.types[t].name, c_name = d.tu.types[t].name, t = t, loc = at))
    return true
}

// a typedef is transparent (every node type is desugared) but keeps its slot for readable
// emission and names the type `offsetof` spells
def private dump_typedef_decl(var d : Dumper; js : JsonValue?) : bool {
    let at = loc_of(d, js)
    let to = node_type(d, js, at)
    if (to < 0) {
        return false
    }
    let name = js?["name"] ?? ""
    var t = CirType(k = "typedef", name = name, to = to)
    let idx = intern(d, "typedef:{name}", t)
    d.tu.decls |> push(new CirDecl(k = "typedefdecl", name = name, c_name = name, t = idx, loc = at))
    return true
}

// an enum's definition: the type from the libclang entry at this location, and its anchor; a
// forward declaration (`enum E;`, no enumerators) adds nothing
def private dump_enum_decl(var d : Dumper; js : JsonValue?) : bool {
    let at = loc_of(d, js)
    if (child_count(js) == 0) {
        return true
    }
    return anchor_type(d, js, at, true)
}

def private dump_type_decl(var d : Dumper; js : JsonValue?) : bool {
    let kind = node_kind(js)
    return kind == "RecordDecl" ? dump_record_decl(d, js) : kind == "EnumDecl" ? dump_enum_decl(d, js) : dump_typedef_decl(d, js)
}

// the child index of a variable's initializer, the last child that is no attribute (`visibility`
// adds one) and no doc comment (`FullComment`); -1 when it has none. An alignment the variable
// asks for (`_Alignas`, `aligned`) fails closed into `ok`, since das places a variable by its type
def private initializer_of(var d : Dumper; js : JsonValue?; at : CirLoc; var ok : bool&) : int {
    var init = -1
    for (idx in range(child_count(js))) {
        let kid = (js?["inner"] as _array)[idx]
        let kind = node_kind(kid)
        if (kind == "AlignedAttr") {
            fail(d, "`{js?["name"] ?? ""}`: an alignment on a variable (`_Alignas`, `aligned`) is not lowered yet", at)
            ok = false
        } elif (!(kind |> ends_with("Attr")) && kind != "FullComment") {
            init = idx
        }
    }
    return init
}

// a function's parameters and body into `fn`; the parameters of a definition (`defines`) are
// locals of the function being dumped
def private dump_fn_children(var d : Dumper; js : JsonValue?; var fn : CirDecl?; defines : bool) : bool {
    let kids = js?["inner"]
    for (idx in range(child_count(js))) {
        let child = (kids as _array)[idx]
        let ck = node_kind(child)
        if (ck == "ParmVarDecl") {
            let pat = loc_of(d, child)
            let pt = node_type(d, child, pat)
            if (pt < 0) {
                return false
            }
            let pname = defines ? local_name(d, child?["name"] ?? "") : child?["name"] ?? ""
            fn.params |> push(CirParam(name = pname, t = pt))
            d.decl_names[child?["id"] ?? ""] = pname
        } elif (ck == "CompoundStmt") {
            d.label_names |> clear()
            collect_labels(d, child)
            fn.body = dump_stmt(d, child)
            if (fn.body == null) {
                return false
            }
        } elif (ck |> ends_with("Attr") || ck == "FullComment") {
            continue // attributes: `check_attributes`; a doc comment changes nothing
        } else {
            fail(d, "unsupported child `{ck}` of function `{fn.c_name}`", loc_of(d, child))
            return false
        }
    }
    return true
}

def dump_decl(var d : Dumper; js : JsonValue?) : CirDecl? {
    let at = loc_of(d, js)
    let kind = node_kind(js)
    let c_name = js?["name"] ?? ""
    let storage = js?["storageClass"] ?? ""
    // a declaration without `static` after a `static` one keeps its internal linkage (C11 6.2.2p4)
    let is_static = storage == "static" || key_exists(d.linkage_names, c_name)
    if (is_static) {
        d.linkage_names[c_name] = "{d.tu_prefix}__{c_name}"
    }
    let name = linkage_name(d, c_name)
    d.decl_names[js?["id"] ?? ""] = name
    if (kind == "FunctionDecl") {
        let t = node_type(d, js, at)
        if (t < 0) {
            return null
        }
        var fn = new CirDecl(k = "func", name = name, c_name = c_name, t = t, is_static = is_static, loc = at)
        // a prototype (a block-scope one among them) leaves the function being dumped alone
        let defines = has_child_kind(js, "CompoundStmt")
        if (defines) {
            d.current_fn = c_name
            d.fn_all_locals <- local_names(js)
            d.fn_extern_names |> clear()
            collect_block_externs(js, d.fn_extern_names)
        }
        if (!dump_fn_children(d, js, fn, defines)) {
            delete_decl(fn)
            return null
        }
        return fn
    }
    if (kind == "VarDecl") {
        let t = node_type(d, js, at)
        if (t < 0) {
            return null
        }
        var ok = true
        let init = initializer_of(d, js, at, ok)
        if (!ok) {
            return null
        }
        var g = new CirDecl(k = "global", name = name, c_name = c_name, t = t, is_static = is_static, is_extern = storage == "extern" && init < 0, loc = at)
        if (!enum_dims(d, node_key(d, js), t, at, g.dims)) {
            delete_decl(g)
            return null
        }
        if (init >= 0) {
            g.init = dump_expr(d, (js?["inner"] as _array)[init])
            if (g.init == null) {
                delete_decl(g)
                return null
            }
        }
        return g
    }
    fail(d, kind == "FileScopeAsmDecl" ? "a file-scope asm is machine code outside any function; no emulation exists in the das runtime" : "unsupported declaration `{kind}`", at)
    return null
}

def private clang_version(clang : string) : string {
    var out : string
    run_and_capture([clang, "--version"], out, 30.0)
    let first = split(out, "\n")[0]
    let at = find(first, "clang version ")
    return at < 0 ? first : split(slice(first, at + length("clang version ")), " ")[0]
}

// one record or enum definition as the layout guard compares it: `key` names it across two parses
// of the unit (its tag, the path through its owner for an unnamed record nested in a record, else
// its place), `loc` is its `cursor_key`, `signature` everything of its layout
struct LayoutEntry {
    key : string
    loc : string
    signature : string
}

// the definitions of one parse of the unit, by place and by key, and how often each tag is defined
struct LayoutSet {
    entries : array<LayoutEntry>
    by_loc : table<string; int>
    by_key : table<string; int>
    tag_count : table<string; int>
}

// a record or an enum the dump lays out: its `cursor_key`, its spelling and its place
struct LaidOut {
    loc : string
    name : string
    at : CirLoc
}

let private TAG_KEY = "tag "

// the brackets of a definition's place inside a signature, until its key takes the place
let private PLACE_OPEN = "<<"
let private PLACE_CLOSE = ">>"

// what stands before an enum's underlying type in its signature
let private ENUM_OF = ", of "

// `spelling` with the place of every unnamed record or enum it names cut out: `(unnamed at
// f:l:c)` and `(anonymous at f:l:c)` are `(unnamed)`, so a spelling reads alike wherever the
// definition stands
def private placeless(spelling : string) : string {
    var cut_from, cut_to : array<int>
    for (opening in ["(unnamed ", "(anonymous "]) {
        var at = find(spelling, opening)
        while (at >= 0) {
            let close = find(spelling, ")", at)
            break if (close < 0)
            cut_from |> push(at)
            cut_to |> push(close)
            at = find(spelling, opening, close)
        }
    }
    if (empty(cut_from)) {
        return spelling
    }
    return build_string() $(var w) {
        for (i, ch in count(), spelling) {
            var inside = false
            for (from, to in cut_from, cut_to) {
                inside ||= i >= from && i <= to
                if (i == from) {
                    w |> write("(unnamed)")
                }
            }
            if (!inside) {
                w |> write_char(ch)
            }
        }
    }
}

// the first named field record `c` makes visible, through its anonymous members; "" for none
def private visible_field(var c : CXCursor) : string {
    var name : string
    clang_visitChildren(c) $(var fc, _fp) {
        let kind = clang_getCursorKind(fc)
        if (kind == CXCursorKind.FieldDecl) {
            name = string(clang_getCursorSpelling(fc))
        } elif ((kind == CXCursorKind.StructDecl || kind == CXCursorKind.UnionDecl) && clang_Cursor_isAnonymousRecordDecl(fc) != 0u) {
            name = visible_field(fc)
        }
        return empty(name) ? CXChildVisitResult.Continue : CXChildVisitResult.Break
    }
    return name
}

// one member of record `owner` in its signature: an anonymous member its bit offset, by a name
// it makes visible; a field its name, bit offset, bitfield width, canonical type, and the size
// and alignment of that type
def private member_signature(var d : Dumper; var owner : CXType; var fc : CXCursor) : string {
    if (clang_getCursorKind(fc) != CXCursorKind.FieldDecl) {
        let name = visible_field(fc)
        var inner = clang_getCursorType(fc)
        let outer_off = empty(name) ? -1l : clang_Type_getOffsetOf(owner, name)
        let inner_off = empty(name) ? 0l : clang_Type_getOffsetOf(inner, name)
        return "(anonymous)@{outer_off < 0l ? -1l : outer_off - inner_off}"
    }
    let name = string(clang_getCursorSpelling(fc))
    let bit_off = clang_Cursor_getOffsetOfField(fc)
    let width = clang_Cursor_isBitField(fc) != 0u ? ":{clang_getFieldDeclBitWidth(fc)}" : ""
    var canonical = clang_getCanonicalType(clang_getCursorType(fc))
    let raw = string(clang_getTypeSpelling(canonical))
    let spelling = placeless(raw)
    let size = clang_Type_getSizeOf(canonical)
    let align = clang_Type_getAlignOf(canonical)
    // an unnamed record or enum as the type, an array's element or a pointer's target: which one, by the place of its definition until
    // `name_unnamed_types` puts its key there
    var which : string
    if (spelling != raw) {
        // through arrays and pointers, to the type that has a declaration
        var element = canonical
        var through = true
        while (through) {
            if (element.kind == CXTypeKind.ConstantArray || element.kind == CXTypeKind.IncompleteArray) {
                element = clang_getCanonicalType(clang_getArrayElementType(element))
            } elif (element.kind == CXTypeKind.Pointer) {
                element = clang_getCanonicalType(clang_getPointeeType(element))
            } else {
                through = false
            }
        }
        var declared = clang_getTypeDeclaration(element)
        // a function type that names an unnamed record has no declaration of its own
        if (clang_getCursorKind(declared) != CXCursorKind.NoDeclFound) {
            which = "{PLACE_OPEN}{cursor_key(d, declared)}{PLACE_CLOSE}"
        }
    }
    return "{name}@{bit_off}{width} `{spelling}`{which} {size}/{align}"
}

// every place `member_signature` left in a signature of `layouts` replaced by the key of the
// definition there, so an unnamed record as a member's type is signed by the record it is
def private name_unnamed_types(var layouts : LayoutSet) {
    for (entry in layouts.entries) {
        var open = find(entry.signature, PLACE_OPEN)
        continue if (open < 0)
        entry.signature = build_string() $(var w) {
            var from = 0
            while (open >= 0) {
                let close = find(entry.signature, PLACE_CLOSE, open)
                let place = slice(entry.signature, open + length(PLACE_OPEN), close)
                let named = layouts.by_loc?[place] ?? -1
                w |> write(slice(entry.signature, from, open))
                w |> write(named < 0 ? " = nowhere" : " = {layouts.entries[named].key}")
                from = close + length(PLACE_CLOSE)
                open = find(entry.signature, PLACE_OPEN, from)
            }
            w |> write(slice(entry.signature, from))
        }
    }
}

// adds the definition at `c` to `layouts` under `key`
def private add_layout(var layouts : LayoutSet; key, loc, signature : string) {
    let idx = length(layouts.entries)
    layouts.entries |> push(LayoutEntry(key = key, loc = loc, signature = signature))
    layouts.by_loc[loc] = idx
    layouts.by_key[key] = idx
    if (key |> starts_with(TAG_KEY)) {
        layouts.tag_count[key]++
    }
}

// every record and enum definition under `c` into `layouts`, external headers' included; `owner`
// is the key of the record `c` is, "" when it is none
[arch(at="ARCHITECTURE_DUMPER_MACROS.md#layout-guard")]
def private collect_layouts(var d : Dumper; var c : CXCursor; owner : string; var layouts : LayoutSet) {
    var nested = 0
    clang_visitChildren(c) $(var kid, _parent) {
        let kind = clang_getCursorKind(kid)
        let is_record = kind == CXCursorKind.StructDecl || kind == CXCursorKind.UnionDecl
        if ((!is_record && kind != CXCursorKind.EnumDecl) || clang_isCursorDefinition(kid) == 0u) {
            collect_layouts(d, kid, "", layouts)
            return CXChildVisitResult.Continue
        }
        let spelling = own_spelling(d, kid, kind == CXCursorKind.EnumDecl ? "enum" : kind == CXCursorKind.UnionDecl ? "union" : "struct")
        let unnamed = find(spelling, "(anonymous ") >= 0 || find(spelling, "(unnamed ") >= 0
        // the ordinal counts the owner's unnamed records alone: a named one beside them has its tag
        let ordinal = nested
        nested += is_record && unnamed ? 1 : 0
        let loc = cursor_key(d, kid)
        if (key_exists(layouts.by_loc, loc)) {
            // met before, as its owner's member or under a statement
            return CXChildVisitResult.Continue
        }
        var ct = clang_getCursorType(kid)
        let size = clang_Type_getSizeOf(ct)
        let align = clang_Type_getAlignOf(ct)
        let key = !unnamed ? TAG_KEY + spelling : is_record && !empty(owner) ? "{owner}/{ordinal}" : "at {loc}"
        if (!is_record) {
            var underlying = clang_getEnumDeclIntegerType(kid)
            let of_type = string(clang_getTypeSpelling(clang_getCanonicalType(underlying)))
            add_layout(layouts, key, loc, "size {size}, align {align}{ENUM_OF}`{of_type}`")
            return CXChildVisitResult.Continue
        }
        var inscope members : array<string>
        clang_visitChildren(kid) $(var fc, _fp) {
            let fk = clang_getCursorKind(fc)
            let anonymous = (fk == CXCursorKind.StructDecl || fk == CXCursorKind.UnionDecl) && clang_Cursor_isAnonymousRecordDecl(fc) != 0u
            if (fk == CXCursorKind.FieldDecl || anonymous) {
                members |> push(member_signature(d, ct, fc))
            }
            return CXChildVisitResult.Continue
        }
        add_layout(layouts, key, loc, "size {size}, align {align}, members {join(members, ", ")}")
        collect_layouts(d, kid, key, layouts)
        return CXChildVisitResult.Continue
    }
}

// whether two enum signatures agree in all that stands before the underlying type
def private same_but_enum_type(ours, theirs : string) : bool {
    let at = find(ours, ENUM_OF)
    return at >= 0 && at == find(theirs, ENUM_OF) && slice(ours, 0, at) == slice(theirs, 0, at)
}

// the entry of `theirs` that is `ours`'s twin: by key when the tag the key starts with is defined
// once in each parse, else by place; -1 for none
def private twin_layout(layouts, theirs : LayoutSet; ours : LayoutEntry) : int {
    let slash = find(ours.key, "/")
    let root = slash < 0 ? ours.key : slice(ours.key, 0, slash)
    let once = root |> starts_with(TAG_KEY) && (layouts.tag_count?[root] ?? 0) == 1 && (theirs.tag_count?[root] ?? 0) == 1
    return once ? theirs.by_key?[ours.key] ?? -1 : theirs.by_loc?[ours.loc] ?? -1
}

//! The refusal of a unit of `definitions` records and enums whose second parse, with clang's own
//! predefined macros back, gave a translation unit or (`has_unit` false) none: "" when it gave
//! one, and when the first pass laid nothing out, so that nothing was to compare (a main file
//! clang cannot open: the dump's own clang run names it).
def second_parse_refusal(has_unit : bool; definitions : int; c_path : string) : string =>
    has_unit || definitions == 0 ? "" : "{c_path}: the layout guard's parse with clang's own predefined macros gave no translation unit, so none of {definitions} layouts can be compared"

// The layout guard: every record the dump lays out, an external header's the program holds by
// value included, and every enum it defines has one layout under `frontend`, the dumper's flags,
// and with clang's own predefined macros back (`frontend` less `-undef`, then `inputs`). A
// definition whose signature differs, or that the second parse lacks, fails the dump: a layout
// attribute behind a test of a name the table does not hold would otherwise be lost with no error.
[arch(at="ARCHITECTURE_DUMPER_MACROS.md#layout-guard")]
def private check_layouts(var d : Dumper; frontend : array<string>; inputs : array<string>) {
    var args <- [for (flag in frontend); flag; where flag != "-undef"]
    args |> push_from(inputs)
    var inscope theirs : LayoutSet
    var stopped : string
    var idx = clang_createIndex(0, 0)
    var unit = clang_parseTranslationUnit(idx, d.c_path, unsafe(addr(args[0])), length(args), null, 0u, 0u)
    if (unit != null) {
        for (i in urange(clang_getNumDiagnostics(unit))) {
            var diag = clang_getDiagnostic(unit, i)
            let severity = clang_getDiagnosticSeverity(diag)
            if (empty(stopped) && (severity == CXDiagnosticSeverity.Error || severity == CXDiagnosticSeverity.Fatal)) {
                stopped = string(clang_formatDiagnostic(diag, clang_defaultDiagnosticDisplayOptions()))
            }
            clang_disposeDiagnostic(diag)
        }
        collect_layouts(d, clang_getTranslationUnitCursor(unit), "", theirs)
        name_unnamed_types(theirs)
        clang_disposeTranslationUnit(unit)
    }
    clang_disposeIndex(idx)
    d.error = second_parse_refusal(unit != null, length(d.records) + length(d.enums), d.c_path)
    if (!empty(d.error)) {
        return
    }
    let hint = "a sidecar `defines` entry selects the arm for both"
    // records, then enums, each in the order the first pass met them: the first refusal is the same every run
    var inscope laid_out : array<LaidOut>
    laid_out |> resize(length(d.records) + length(d.enums))
    for (loc, ridx in keys(d.record_by_loc), values(d.record_by_loc)) {
        laid_out[ridx] = LaidOut(loc = loc, name = d.records[ridx].c_spelling, at = d.records[ridx].at)
    }
    for (loc, eidx in keys(d.enum_by_loc), values(d.enum_by_loc)) {
        laid_out[length(d.records) + eidx] = LaidOut(loc = loc, name = d.enums[eidx].spelling, at = d.enum_ats?[loc] ?? CirLoc())
    }
    for (item in laid_out) {
        // a record met twice has one place; clang's own builtin record (`__va_list_tag`) stands in
        // no file and is the same under any macros
        continue if (empty(item.loc) || empty(item.at.file))
        let mine = d.layouts.by_loc?[item.loc] ?? -1
        if (mine < 0) {
            fail(d, "`{item.name}`: the layout guard found no definition at its place", item.at)
            continue
        }
        assume ours = d.layouts.entries[mine]
        let twin = twin_layout(d.layouts, theirs, ours)
        if (twin < 0) {
            let why = empty(stopped) ? "" : " (that pass met an error: {stopped})"
            fail(d, "`{item.name}` is defined under the dialect's predefined macros and not under clang's own{why}; {hint}", item.at)
        } elif (theirs.entries[twin].signature != ours.signature) {
            // an enum of one size and alignment differs in its underlying type alone
            let type_alone = same_but_enum_type(ours.signature, theirs.entries[twin].signature)
            let what = type_alone ? "its underlying type, and with it the sign of its values, changes behind a compiler test" : "a layout attribute behind a compiler test"
            fail(d, "`{item.name}` is laid out as [{ours.signature}] under the dialect's predefined macros and as [{theirs.entries[twin].signature}] under clang's own: {what}; {hint}", item.at)
        }
    }
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
            if (prev.is_extern && !cd.is_extern) {
                // the definition's type completes an `extern` one's (`extern const char s[];`)
                prev.t = cd.t
                prev.dims <- cd.dims
            }
            prev.is_extern = prev.is_extern && cd.is_extern
            return false
        }
    }
    return true
}

//! The pinned clang: the libclang archive's own binary when `PATH_TO_LIBCLANG` is set
//! (`scripts/env.sh`), else whatever `clang` is on PATH.
def default_clang : string =>
    has_env_variable("PATH_TO_LIBCLANG") ? get_env_variable("PATH_TO_LIBCLANG") + "/bin/clang" : "clang"

//! The flags of every clang run of the dumper's frontend besides the target, the macros and the
//! include path: plain `char` is unsigned under both dialects, and no warning is read.
let DUMPER_FLAGS <- ["-funsigned-char", "-w"]

//! The file of the predefined-macro table `target` is dumped under, its dialect's.
def predefined_table(target : CirTarget) : string => predefined_path(is_msvc(target) ? "msvc" : "linux")

//! The flags every clang run of the dumper's frontend starts with: `target`'s triple,
//! `DUMPER_FLAGS`, `-undef`, which drops clang's own predefined macros, the entries of the
//! predefined-macro table file `table_path` as `-D<entry>` each in the table's order, then
//! `-nostdinc` and the own libc headers' folder `include_dir`, canonical, as the one `-isystem`
//! directory. `error` names a table that is missing or malformed, or a folder that is missing.
[arch(at="ARCHITECTURE_DUMPER_MACROS.md#predefined")]
def frontend_flags(target : CirTarget; table_path, include_dir : string; var error : string&) : array<string> {
    var flags : array<string>
    let entries <- read_predefined(table_path, error)
    if (!empty(error)) {
        return <- flags
    }
    if (!stat(include_dir).is_dir) {
        error = "{include_dir}: no such folder of the own libc headers"
        return <- flags
    }
    let headers = get_full_file_name(include_dir)
    flags |> push_from(["-target", target.triple], DUMPER_FLAGS, ["-undef"])
    flags |> push_from([for (entry in entries); "-D{entry}"], ["-nostdinc", "-isystem", headers])
    return <- flags
}

//! The environment variables clang reads include folders from, `-nostdinc` or not, and searches
//! before the `-isystem` folder.
let INCLUDE_VARIABLES <- ["CPATH", "C_INCLUDE_PATH"]

//! Why a clang run of the dumper is refused when the environment variable `name` holds `value`:
//! "" for an empty one; else the folders it names would be searched before the own libc headers,
//! and a host libc found there would replace them with no error.
def include_variable_refusal(name, value : string) : string =>
    empty(value) ? "" : "the environment variable {name} is set ({value}): clang would search its folders before the own libc headers; unset it and name a program's include folders in the sidecar's `include_dirs`"

//! `frontend_flags` of `target` over its dialect's table and the own libc headers' folder;
//! `error` also names a set variable of `INCLUDE_VARIABLES`.
[arch(at="ARCHITECTURE_DUMPER.md#file-policy")]
def dumper_frontend_flags(target : CirTarget; var error : string&) : array<string> {
    for (name in INCLUDE_VARIABLES) {
        error = include_variable_refusal(name, has_env_variable(name) ? get_env_variable(name) : "")
        if (!empty(error)) {
            return <- array<string>()
        }
    }
    return <- frontend_flags(target, predefined_table(target), own_include_dir(), error)
}

// the sidecar's `defines`, `include_dirs` and `include_files` as clang flags, `-D<entry>`, `-I<dir>`
// and `-include <file>` each
def private input_flags(inputs : DumpInputs) : array<string> {
    var flags <- [for (entry in inputs.defines); "-D{entry}"]
    flags |> push_from([for (dir in inputs.include_dirs); "-I{dir}"])
    flags |> reserve(length(flags) + 2 * length(inputs.include_files))
    for (file in inputs.include_files) {
        flags |> push("-include")
        flags |> push(file)
    }
    return <- flags
}

// the top-level declarations of the dump `js` the program owns, dumped into `d.tu.decls`; a `.c`
// file outside the program root fails the dump naming it
def private dump_top_level(var d : Dumper; js : JsonValue?) {
    let top = js?["inner"]
    // clang declares a library function implicitly where the unit first names it, a block-scope
    // declaration's after the function holding it
    for (idx in range(child_count(js))) {
        let decl = (top as _array)[idx]
        if ((decl?["isImplicit"] ?? false) && node_kind(decl) == "FunctionDecl" && has_child_kind(decl, "BuiltinAttr")) {
            d.library_decls[decl?["id"] ?? ""] = decl?["type"]?["qualType"] ?? ""
        }
    }
    for (idx in range(child_count(js))) {
        let decl = (top as _array)[idx]
        let at = loc_of(d, decl)
        if (decl?["isImplicit"] ?? false) {
            continue
        }
        if (!in_program(d, at.file)) {
            if (at.file |> ends_with(".c")) {
                fail(d, "{at.file} is a C file outside the program root {d.program_dir}: its definitions would stay external; the sidecar's `program_root` widens the root", at)
                break
            }
            continue
        }
        break if (!note_library_redeclaration(d, decl, at) || !check_attributes(d, decl))
        let kind = node_kind(decl)
        if (kind == "RecordDecl" || kind == "EnumDecl" || kind == "TypedefDecl") {
            break if (!dump_type_decl(d, decl))
            continue
        }
        // a file-scope `;` (`;;`, or the `;` after a function's `}`) declares nothing, and a
        // `_Static_assert` clang has already checked (wasm3's table sizes) leaves nothing to run
        if (kind == "EmptyDecl" || kind == "StaticAssertDecl") {
            continue
        }
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
}

// a declaration of a library function clang knows (`strlen`) whose type is not the library's
// (C99 6.2.7 leaves it undefined; clang calls the library function): another integer result, not
// `_Bool`, is recorded, so a call converts the library's result as clang's does; any other
// difference fails closed, a K&R declaration (`int strlen();`) differing in its result alone. A
// definition of the name makes it the program's function
def private note_library_redeclaration(var d : Dumper; decl : JsonValue?; at : CirLoc) : bool {
    let name = decl?["name"] ?? ""
    if (node_kind(decl) != "FunctionDecl") {
        return true
    }
    if (has_child_kind(decl, "CompoundStmt")) {
        d.library_results |> erase(name)
        return true
    }
    let library = d.library_decls?[decl?["previousDecl"] ?? ""] ?? ""
    if (empty(library) || has_child_kind(decl, "BuiltinAttr")) {
        return true
    }
    let own_spelling = type_spelling(d, decl?["type"])
    let lib_t = type_from_qual(d, library, at)
    let own_t = type_from_qual(d, own_spelling, at)
    if (lib_t < 0 || own_t < 0) {
        return false
    }
    assume lib = d.tu.types[lib_t]
    assume own = d.tu.types[own_t]
    // `int strlen()` declares no parameters, so only the result tells it from the library's
    let prototyped = !(own_spelling |> ends_with("()"))
    if (prototyped && (own.variadic != lib.variadic || length(own.params) != length(lib.params) || has_value([for (p, q in own.params, lib.params); !library_parameter(d, p, q)], true))) {
        fail(d, "`{name}` declared with other parameters than the C library's `{library}` is not lowered (C99 6.2.7)", at)
        return false
    }
    if (own.ret != lib.ret) {
        if (!library_integer(d, own.ret) || !library_integer(d, lib.ret)) {
            fail(d, "`{name}` declared with another result than the C library's `{library}`, other than one integer for another, is not lowered (C99 6.2.7)", at)
            return false
        }
        d.library_results[name] = lib.ret
        if (!prototyped) {
            d.library_unprototyped |> insert(name)
        }
    }
    return true
}

// a parameter a redeclaration may give a library function's: its own type, or a data pointer for
// one (`const char *` for `memcmp`'s `const void *`, gcc-torture 20050502-2), passed alike
def private library_parameter(d : Dumper; own, lib : int) : bool {
    if (own == lib) {
        return true
    }
    let own_k = d.tu.types[own].k
    let lib_k = d.tu.types[lib].k
    return own_k == "ptr" && lib_k == "ptr" && d.tu.types[d.tu.types[own].to].k != "func" && d.tu.types[d.tu.types[lib].to].k != "func"
}

// an integer result a redeclared library function converts, `_Bool` excluded
def private library_integer(d : Dumper; t : int) : bool => d.tu.types[t].k == "int" && d.tu.types[t].spell != "_Bool" && d.tu.types[t].spell != "bool"

// the value of a library function the unit redeclares with another result
// (`note_library_redeclaration`): a static wrapper of the declared type, `<name>__fn`, made once,
// whose body converts the library's result as a direct call does
def private library_value(var d : Dumper; name : string; t : int; at : CirLoc) : CirExpr? {
    if (key_exists(d.library_unprototyped, name)) {
        fail(d, "the value of `{name}`, declared without a prototype and with another result than the C library's, is not lowered", at)
        return null
    }
    if (!key_exists(d.library_wrappers, name)) {
        let ret_t = d.tu.types[t].ret
        let c_name = free_name(d.file_scope_names, "{name}__fn")
        let wrapper = "{d.tu_prefix}__{c_name}"
        d.library_wrappers[name] = wrapper
        var fn = new CirDecl(k = "func", name = wrapper, c_name = c_name, t = t, is_static = true, loc = at)
        var call = new CirExpr(e = "call", t = d.library_results?[name] ?? -1, fn = new CirExpr(e = "ref", t = t, name = name))
        fn.params |> reserve(length(d.tu.types[t].params))
        call.args |> reserve(length(d.tu.types[t].params))
        for (idx in range(length(d.tu.types[t].params))) {
            let p = d.tu.types[t].params[idx]
            fn.params |> push(CirParam(name = "a{idx}", t = p))
            call.args |> push(new CirExpr(e = "ref", t = p, name = "a{idx}"))
        }
        var body = new CirStmt(s = "compound", loc = at)
        var ret = new CirStmt(s = "return", loc = at, e = new CirExpr(e = "cast", t = ret_t, cast_kind = "IntegralCast", a = call))
        body.body |> push(ret)
        fn.body = body
        d.tu.decls |> push(fn)
    }
    return new CirExpr(e = "ref", t = t, name = d.library_wrappers?[name] ?? "")
}

//! What a unit is dumped under beyond its file and dialect: the sidecar's `defines` (`-D<entry>`
//! each), its `include_dirs` (`-I<dir>` each, both passes), its `include_files` (`-include <file>`
//! each) and its `program_root` ("" for the main
//! file's folder).
struct DumpInputs {
    defines : array<string>
    include_dirs : array<string>
    include_files : array<string>
    program_root : string
}

//! Runs clang on `c_path` under the dialect `target` and `inputs`, and normalizes the dump into
//! `d`, a fresh `Dumper` the caller holds (about 3 KiB: on the heap where the caller runs under
//! das's default stack); `d.error` names the first unsupported construct, and the dump is then
//! partial.
def dump_tu(var d : Dumper; c_path : string; target : CirTarget; clang : string; inputs : DumpInputs) {
    d.tu.cir = CIR_VERSION
    d.tu.target = target
    d.tu.tu = base_name(c_path)
    d.c_path = c_path
    d.cur_file = c_path
    let root = empty(inputs.program_root) ? dir_name(get_full_file_name(c_path)) : get_full_file_name(inputs.program_root)
    if (empty(root)) {
        d.error = "the program root `{inputs.program_root}` is no folder"
        return
    }
    d.program_dir = root |> ends_with("/") ? root : root + "/"
    d.va_names |> insert(VA_BUILTIN)
    d.tu_prefix = ident_of(slice(d.tu.tu, 0, max(find(d.tu.tu, "."), 0)))
    d.tu.producer = "c2das-dumper-a 0.1 / clang {clang_version(clang)}"
    let frontend <- dumper_frontend_flags(target, d.error)
    if (!empty(d.error)) {
        return
    }
    d.own_headers_dir = get_full_file_name(own_include_dir()) + "/"
    if (!in_program(d, c_path)) {
        d.error = "the main file {get_full_file_name(c_path)} is no file of the program: it lies outside the program root {d.program_dir} or under the own libc headers' folder {d.own_headers_dir}"
        return
    }
    let flags <- input_flags(inputs)
    collect_records(d, frontend, flags)
    if (!empty(d.error)) {
        return
    }
    check_layouts(d, frontend, flags)
    if (!empty(d.error)) {
        return
    }
    var out : string
    var dump_args <- [clang, "-Xclang", "-ast-dump=json", "-fsyntax-only"]
    dump_args |> push_from(frontend, flags, [c_path])
    let rc = run_and_capture(dump_args, out, 120.0)
    if (rc != 0) {
        d.error = "clang exited {rc}:\n{out}"
        return
    }
    d.json_bytes = long_length(out)
    var err : string
    var js = read_json(out, err)
    // the dump's text, the largest string of the conversion, freed once parsed: the string heap
    // keeps every other string until the process ends
    unsafe(delete_string(out))
    if (js == null) {
        d.error = "clang dump is not JSON: {err}"
        return
    }
    var last : LocState
    complete_locs(js, last)
    collect_va_ids(d, js)
    collect_aligned_typedefs(d, js)
    collect_convention_macros(d, js)
    collect_defined_names(d, js)
    find_macro_sites(d.fn_macros, d.canonical_files, js)
    dump_top_level(d, js)
    d.tu.macros <- d.fn_macros.macros
    delete_json(js)
    if (empty(d.error)) {
        check_enum_anchors(d)
        check_offsetof_counts(d)
    }
}

// a key whose `offsetof`s the dump's walk met a different number of times than libclang's (one in
// an array dimension or a designator's index, which the dump keeps only in a type or drops) paired
// its nodes with the wrong cursors unless every `offsetof` there is alike
def private check_offsetof_counts(var d : Dumper) {
    for (key, taken in keys(d.offsetof_taken), values(d.offsetof_taken)) {
        var mismatch = false
        get(d.offsetofs_by_loc, key) $(offs) {
            mismatch = length(offs) != taken && !offsetofs_alike(offs)
        }
        if (mismatch) {
            fail(d, "offsetof: one macro expansion spells `offsetof`s of different members, one of them where clang's dump keeps no expression (an array dimension, a designator's index); not lowered", d.offsetof_at?[key] ?? CirLoc(file = d.c_path))
            return
        }
    }
}

// an enum the walk never anchored was defined inside an expression (a `sizeof` or cast
// operand), where the dump's walk does not go: it would reach the text undeclared
def private check_enum_anchors(var d : Dumper) {
    var anchored : table<int>
    for (decl in d.tu.decls) {
        if (decl.k == "enumdef") {
            anchored |> insert(decl.t)
        }
    }
    for (idx in range(length(d.tu.types))) {
        if (d.tu.types[idx].k == "enum" && !key_exists(anchored, idx)) {
            fail(d, "`{d.tu.types[idx].spell}` is defined inside an expression; such an enum is not lowered yet", CirLoc(file = d.c_path))
        }
    }
}
