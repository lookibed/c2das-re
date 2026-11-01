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
// keyed by its canonical spelling (`struct X`, `struct (unnamed at f:l:c)`) and its location
struct ClangRecord {
    spelling : string
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
    // clang's resource directory and the system include directories, canonical with a trailing
    // `/`: a file under one is external though it lies under `program_dir`
    system_dirs : array<string>
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
    // every file-scope name the unit's dump declares (a system header's included, so a libc
    // function the unit calls), and every parameter and local of the function being dumped: a
    // hoisted local static's name passes both
    file_scope_names : table<string>
    fn_all_locals : table<string>
    // the names of the current function's locals declared so far
    fn_locals : table<string>
    records : array<ClangRecord>
    record_by_spelling : table<string; int>
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
    // clang's answer to each `__builtin_constant_p` call by its key (`register_constant_p`): 1 or
    // 0, or `CONSTANT_P_NESTED` or `CONSTANT_P_SPLIT` for a call the conversion refuses
    constant_p_by_loc : table<string; int>
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
    // the bytes of clang's JSON dump
    json_bytes : int64
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
    var rec = ClangRecord(spelling = tagged ? raw : (is_union ? "union " : "struct ") + raw, is_union = is_union, size = clang_Type_getSizeOf(ct), align = clang_Type_getAlignOf(ct))
    if (key_exists(d.record_by_spelling, rec.spelling)) {
        // an unnamed record is spelled by its expansion location, which a macro shares
        let unnamed = find(rec.spelling, "(anonymous ") >= 0 || find(rec.spelling, "(unnamed ") >= 0
        fail(d, unnamed ? "anonymous records from one macro expansion are not dumped yet" : "`{rec.spelling}` is defined more than once in this file; same-tag block-scoped records are not dumped yet", cursor_loc(c))
        return
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
    d.record_by_spelling[rec.spelling] = idx
    d.record_by_loc[key] = idx
    d.record_hash[key] = clang_hashCursor(c)
    d.records |> emplace(rec)
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
// outside the system directories; every other file (a system header's) is external
[arch(at="ARCHITECTURE_DUMPER.md#file-policy")]
def private in_program(var d : Dumper; name : string) : bool {
    let full = canonical_file(d, name)
    return full |> starts_with(d.program_dir) && !under_system_dir(d, name)
}

// whether file `name` lies under clang's resource directory or a system include directory
def private under_system_dir(var d : Dumper; name : string) : bool {
    let full = canonical_file(d, name)
    for (dir in d.system_dirs) {
        if (full |> starts_with(dir)) {
            return true
        }
    }
    return false
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
        if (kind != CXCursorKind.TypedefDecl && !in_program(d, cursor_loc(kid).file)) {
            return CXChildVisitResult.Continue
        }
        if ((kind == CXCursorKind.StructDecl || kind == CXCursorKind.UnionDecl) && clang_isCursorDefinition(kid) != 0u) {
            register_record(d, kid)
        } elif (kind == CXCursorKind.EnumDecl && clang_isCursorDefinition(kid) != 0u) {
            register_enum(d, kid)
        } elif (kind == CXCursorKind.VarDecl) {
            register_dims(d, kid)
            // a variable of an external record (`struct tm ts;`) needs its layout
            register_external_type(d, clang_getCursorType(kid))
            walk_records(d, kid)
        } elif (kind == CXCursorKind.MemberRefExpr || kind == CXCursorKind.UnaryExpr) {
            register_external_use(d, kid)
            walk_records(d, kid)
        } elif (kind == CXCursorKind.UnexposedExpr) {
            register_offsetof(d, kid)
            walk_records(d, kid)
        } elif (kind == CXCursorKind.CallExpr) {
            register_constant_p(d, kid)
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

def private collect_records(var d : Dumper; triple : string; resource_dir : string; inputs : array<string>) {
    // libclang finds no resource directory of its own, so the builtin headers (`stddef.h`, whose
    // `size_t` a libc prototype spells) come from the pinned clang's
    var args <- ["-target", triple, "-funsigned-char", "-w", NO_CTYPE_MACROS, "-resource-dir", resource_dir]
    args |> push_from(inputs)
    var idx = clang_createIndex(0, 0)
    var unit = clang_parseTranslationUnit(idx, d.c_path, unsafe(addr(args[0])), length(args), null, 0u, 0u)
    if (unit != null) {
        // an error libclang meets (a header the resource directory lacks) leaves records and
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
        clang_disposeTranslationUnit(unit)
    }
    clang_disposeIndex(idx)
    for (ridx in range(length(d.records))) {
        for (fidx in range(length(d.records[ridx].fields))) {
            d.records[ridx].fields[fidx].spelling = tagged_spelling(d, d.records[ridx].fields[fidx].spelling)
        }
    }
    let names <- [for (name in keys(d.typedef_spellings)); name]
    for (name in names) {
        d.typedef_spellings[name] = tagged_spelling(d, d.typedef_spellings[name])
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
    let inside = strip(slice(qt, paren + 1, length(qt) - 1))
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

def type_from_qual(var d : Dumper; qual : string; at : CirLoc) : int {
    let special = special_type(d, qual, at)
    if (special != -2) {
        return special
    }
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
        return record_type(d, unscoped_spelling(qt), at)
    }
    if (qt |> starts_with("enum ")) {
        return enum_type(d, qt, at)
    }
    return -2
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
    for (f in d.records[ridx].fields) {
        let ft = type_from_qual(d, f.spelling, at)
        if (ft < 0) {
            return -1
        }
        var fld = CirField(name = f.name, t = ft, off = int(f.bit_off / 8l), bit_off = int(f.bit_off), bit_w = f.bit_w, is_bitfield = f.is_bitfield)
        if (!enum_dims(d, f.loc_key, ft, at, fld.dims)) {
            return -1
        }
        fields |> emplace(fld)
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
    var x = new CirExpr(e = "call", t = t)
    x.fn = child_expr(d, kids, 0)
    if (x.fn == null || !dump_args(d, kids, 1, nkids, x)) {
        delete_expr(x)
        return null
    }
    return x
}

// the name a callee references through its decay and parentheses, "" for any other callee
def private callee_name(js : JsonValue?) : string {
    let kind = node_kind(js)
    if (child_count(js) > 0 && (kind == "ImplicitCastExpr" || kind == "ParenExpr")) {
        return callee_name((js?["inner"] as _array)[0])
    }
    return kind == "DeclRefExpr" ? js?["referencedDecl"]?["name"] ?? "" : ""
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
// an expression's type, with clang's value; GNU `__alignof__` (`__alignof`) is no dialect trait
def private dump_sizeof(var d : Dumper; js : JsonValue?; t : int; at : CirLoc) : CirExpr? {
    let trait = js?["name"] ?? ""
    if (trait != "sizeof" && trait != "alignof") {
        fail(d, "`{trait}` is not dumped yet", at)
        return null
    }
    var of_t = -1
    let arg_type = js?["argType"]
    if (is_present(arg_type)) {
        of_t = type_from_qual(d, type_spelling(d, arg_type), at)
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
        continue if (node_kind(kid) == "ImplicitValueInitExpr")
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
    if (kind == "ParenExpr" || kind == "ConstantExpr") {
        // clang wraps a constant item of a file-scope initializer in `ConstantExpr`, whose
        // value is its child's
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
        if (d.tu.types[t].k == "array" && d.tu.types[t].count < 0) {
            // the object's definition, later in the unit, gives the count the reference lacks
            fail(d, "a reference to `{js?["referencedDecl"]?["name"] ?? ""}` before a definition gives its array a length (`extern int a[];`) is not lowered yet", at)
            return null
        }
        return new CirExpr(e = "ref", t = t, name = bound_name(d, js?["referencedDecl"]), vol = is_volatile_spelling(js))
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

let EXPR_KINDS <- {"IntegerLiteral", "CharacterLiteral", "FloatingLiteral", "StringLiteral", "DeclRefExpr", "ImplicitCastExpr", "CStyleCastExpr", "UnaryOperator", "BinaryOperator", "CompoundAssignOperator", "ConditionalOperator", "CallExpr", "ArraySubscriptExpr", "UnaryExprOrTypeTraitExpr", "ParenExpr", "MemberExpr", "InitListExpr", "OffsetOfExpr", "VAArgExpr", "CompoundLiteralExpr"}

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
    // `<fn>_<name>` first, numbered past another hoisted static, a file-scope name of the unit and
    // a parameter or local of the function
    let want = "{d.current_fn}_{c_name}"
    var hoisted = want
    var n = 1
    while (key_exists(d.hoisted_names, hoisted) || key_exists(d.file_scope_names, hoisted) || key_exists(d.fn_all_locals, hoisted)) {
        hoisted = "{want}{n}"
        n++
    }
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
        // a block-scope `extern` declares no object: its references bind to the file-scope
        // entity it redeclares
        let bound = d.decl_names?[js?["previousDecl"] ?? ""] ?? ""
        if (key_exists(d.fn_locals, bound)) {
            // the C-IR names the file-scope entity and the local alike, so the reference
            // would bind to the local
            fail(d, "a block-scope `extern` declaration of `{bound}`, which a local of the function also names, is not lowered yet", at)
            return null
        }
        if (empty(bound)) {
            fail(d, "a block-scope `extern` declaration of `{js?["name"] ?? ""}` with no file-scope declaration before it is not lowered yet", at)
            return null
        }
        d.decl_names[js?["id"] ?? ""] = bound
        return new CirStmt(s = "null", loc = at)
    }
    var ok = true
    let init = initializer_of(d, js, at, ok)
    if (!ok) {
        return null
    }
    var st = new CirStmt(s = "decl", name = js?["name"] ?? "", t = t, loc = at)
    d.decl_names[js?["id"] ?? ""] = st.name
    d.fn_locals |> insert(st.name)
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
            if (!dump_type_decl(d, v)) {
                return false
            }
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
        if (!dropped && !key_exists(READ_ATTRIBUTES, kind)) {
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

// the names the program's top-level declarations define: a function with a body, a variable
// that is not `extern` or carries an initializer
def private collect_defined_names(var d : Dumper; js : JsonValue?) {
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
def private dump_case(var d : Dumper; js : JsonValue?; var into : array<CirStmt?>) : bool {
    let at = loc_of(d, js)
    let kind = node_kind(js)
    let kids = js?["inner"]
    let nkids = child_count(js)
    if (kind == "LabelStmt") {
        into |> push(new CirStmt(s = "label", label_name = js?["name"] ?? "", loc = at))
    } elif (kind == "CaseStmt") {
        if (js?["isGNURange"] ?? false) {
            fail(d, "a GNU case range is outside the dialect", at)
            return false
        }
        var v = 0l
        if (nkids < 1 || !fold_constant(d, (kids as _array)[0], v)) {
            return false
        }
        into |> push(new CirStmt(s = "case", v = v, loc = at))
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

// a record's definition: nested records first, since a field's type precedes the field; a
// forward declaration adds nothing; the slot comes from the libclang layout at this location
def private dump_record_decl(var d : Dumper; js : JsonValue?) : bool {
    let at = loc_of(d, js)
    // a forward declaration adds nothing, and neither does glibc's tag, which a file that includes
    // no header defines itself: every spelling of it is the opaque `jmp_buf` record
    // (`jmp_buf_type`), so its fields name nothing
    if (!(js?["completeDefinition"] ?? false) || (js?["name"] ?? "") == "__jmp_buf_tag") {
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
// adds one); -1 when it has none. An alignment the variable asks for (`_Alignas`, `aligned`) fails
// closed into `ok`, since das places a variable by its type
def private initializer_of(var d : Dumper; js : JsonValue?; at : CirLoc; var ok : bool&) : int {
    var init = -1
    for (idx in range(child_count(js))) {
        let kid = (js?["inner"] as _array)[idx]
        let kind = node_kind(kid)
        if (kind == "AlignedAttr") {
            fail(d, "`{js?["name"] ?? ""}`: an alignment on a variable (`_Alignas`, `aligned`) is not lowered yet", at)
            ok = false
        } elif (!(kind |> ends_with("Attr"))) {
            init = idx
        }
    }
    return init
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
        d.current_fn = c_name
        d.fn_locals |> clear()
        d.fn_all_locals <- local_names(js)
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
                d.decl_names[child?["id"] ?? ""] = child?["name"] ?? ""
                d.fn_locals |> insert(child?["name"] ?? "")
            } elif (ck == "CompoundStmt") {
                d.label_names |> clear()
                collect_labels(d, child)
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

// the pinned clang's resource directory, "" when it reports none
def private clang_resource_dir(clang : string) : string {
    var out : string
    let rc = run_and_capture([clang, "-print-resource-dir"], out, 30.0)
    return rc == 0 ? strip(out) : ""
}

// the resource directory and the directories clang searches for `<...>` under `triple`, as its
// `-v` lists them but those `CPATH` and `C_INCLUDE_PATH` name, each canonical with a trailing `/`
// (a main file in `/root` holds the default `/root/libclang`'s resource headers under its own
// directory)
[arch(at="ARCHITECTURE_DUMPER.md#file-policy")]
def private system_dirs(clang, triple, resource_dir : string) : array<string> {
    var dirs : array<string>
    dirs |> push(get_full_file_name(resource_dir) + "/")
    var out : string
    if (run_and_capture([clang, "-target", triple, "-E", "-x", "c", "-v", "/dev/null", "-o", "/dev/null"], out, 30.0) != 0) {
        return <- dirs
    }
    let user_dirs <- user_path_dirs()
    var listing = false
    for (text in split(out, "\n")) {
        let entry = strip(text)
        if (entry |> starts_with("#include <...> search starts here")) {
            listing = true
        } elif (entry |> starts_with("End of search list")) {
            listing = false
        } elif (listing && !empty(entry)) {
            let full = get_full_file_name(entry)
            let dir = full |> ends_with("/") ? full : full + "/"
            if (!empty(full) && !has_value(user_dirs, dir)) {
                dirs |> push(dir)
            }
        }
    }
    return <- dirs
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

// glibc's <ctype.h> spells `isalpha(c)` as a macro indexing its locale table (`__ctype_b_loc`)
// unless `__NO_CTYPE` is defined: with it each is the libc function the crt module binds
let NO_CTYPE_MACROS = "-D__NO_CTYPE"

// the sidecar's `defines` and `include_dirs` as clang flags, `-D<entry>` and `-I<dir>` each
def private input_flags(defines, include_dirs : array<string>) : array<string> {
    var flags <- [for (entry in defines); "-D{entry}"]
    flags |> push_from([for (dir in include_dirs); "-I{dir}"])
    return <- flags
}

// the folders `CPATH` and `C_INCLUDE_PATH` name, canonical with a trailing `/`: clang's `-v` lists
// them with its own `<...>` folders, yet they hold the user's headers, never the system's
def private user_path_dirs : array<string> {
    var dirs : array<string>
    for (name in ["CPATH", "C_INCLUDE_PATH"]) {
        if (has_env_variable(name)) {
            for (entry in split(get_env_variable(name), ":")) {
                let full = empty(entry) ? "" : get_full_file_name(entry)
                if (!empty(full)) {
                    dirs |> push(full |> ends_with("/") ? full : full + "/")
                }
            }
        }
    }
    return <- dirs
}

// the top-level declarations of the dump `js` the program owns, dumped into `d.tu.decls`; a `.c`
// file outside the program root and the system directories fails the dump naming it
def private dump_top_level(var d : Dumper; js : JsonValue?) {
    let top = js?["inner"]
    for (idx in range(child_count(js))) {
        let decl = (top as _array)[idx]
        let at = loc_of(d, decl)
        if (decl?["isImplicit"] ?? false) {
            continue
        }
        if (!in_program(d, at.file)) {
            if (at.file |> ends_with(".c") && !under_system_dir(d, at.file)) {
                fail(d, "{at.file} is a C file outside the program root {d.program_dir}: its definitions would stay external; the sidecar's `program_root` widens the root", at)
                break
            }
            continue
        }
        break if (!check_attributes(d, decl))
        let kind = node_kind(decl)
        if (kind == "RecordDecl" || kind == "EnumDecl" || kind == "TypedefDecl") {
            break if (!dump_type_decl(d, decl))
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

//! What a unit is dumped under beyond its file and dialect: the sidecar's `defines` (`-D<entry>`
//! each), its `include_dirs` (`-I<dir>` each, both passes) and its `program_root` ("" for the main
//! file's folder).
struct DumpInputs {
    defines : array<string>
    include_dirs : array<string>
    program_root : string
}

//! Runs clang on `c_path` under the dialect `target` and `inputs`, and normalizes the dump;
//! `d.error` names the first unsupported construct, and the dump is then partial.
def dump_tu(c_path : string; target : CirTarget; clang : string; inputs : DumpInputs) : Dumper {
    var d : Dumper
    d.tu.cir = CIR_VERSION
    d.tu.target = target
    d.tu.tu = base_name(c_path)
    d.c_path = c_path
    d.cur_file = c_path
    let root = empty(inputs.program_root) ? dir_name(get_full_file_name(c_path)) : get_full_file_name(inputs.program_root)
    if (empty(root)) {
        d.error = "the program root `{inputs.program_root}` is no folder"
        return <- d
    }
    d.program_dir = root |> ends_with("/") ? root : root + "/"
    d.va_names |> insert(VA_BUILTIN)
    d.tu_prefix = ident_of(slice(d.tu.tu, 0, max(find(d.tu.tu, "."), 0)))
    d.tu.producer = "c2das-dumper-a 0.1 / clang {clang_version(clang)}"
    let resource_dir = clang_resource_dir(clang)
    if (empty(resource_dir)) {
        d.error = "`{clang} -print-resource-dir` gave no resource directory; libclang needs it for the builtin headers"
        return <- d
    }
    d.system_dirs <- system_dirs(clang, target.triple, resource_dir)
    if (!in_program(d, c_path)) {
        d.error = "the main file {get_full_file_name(c_path)} is no file of the program: it lies outside the program root {d.program_dir} or under a folder clang searches for system headers"
        return <- d
    }
    let flags <- input_flags(inputs.defines, inputs.include_dirs)
    collect_records(d, target.triple, resource_dir, flags)
    if (!empty(d.error)) {
        return <- d
    }
    var out : string
    var dump_args <- [clang, "-Xclang", "-ast-dump=json", "-fsyntax-only", "-w", "-funsigned-char", NO_CTYPE_MACROS, "-target", target.triple]
    dump_args |> push_from(flags, [c_path])
    let rc = run_and_capture(dump_args, out, 120.0)
    if (rc != 0) {
        d.error = "clang exited {rc}:\n{out}"
        return <- d
    }
    d.json_bytes = long_length(out)
    var err : string
    var js = read_json(out, err)
    if (js == null) {
        d.error = "clang dump is not JSON: {err}"
        return <- d
    }
    var last : LocState
    complete_locs(js, last)
    collect_va_ids(d, js)
    collect_aligned_typedefs(d, js)
    collect_defined_names(d, js)
    dump_top_level(d, js)
    delete_json(js)
    if (empty(d.error)) {
        check_enum_anchors(d)
        check_offsetof_counts(d)
    }
    return <- d
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
