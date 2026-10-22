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

struct Dumper {
    tu : CirTu
    layout : LayoutMemo
    error : string
    cur_file : string
    cur_line : int
    type_index : table<string; int>
    tu_prefix : string
    c_path : string
    linkage_names : table<string; string>
    current_fn : string
    // the C-IR name of every declaration of the main file by clang's declaration id: a reference
    // binds by the id clang resolved, never by its spelling, so a local hiding a static keeps
    // its own binding (`docs/probe-findings.md` F47)
    decl_names : table<string; string>
    // the hoisted names of static locals taken so far
    hoisted_names : table<string>
    // the names of the current function's locals declared so far
    fn_locals : table<string>
    records : array<ClangRecord>
    record_by_spelling : table<string; int>
    record_by_loc : table<string; int>
    record_hash : table<string; uint>
    typedef_spellings : table<string; string>
    source_lines : array<string>
    anon_spellings : table<string; string>
    enums : array<ClangEnum>
    enum_by_spelling : table<string; int>
    enum_by_loc : table<string; int>
    enum_ref_by_loc : table<string; ClangEnumRef>
    enum_dims_by_loc : table<string; array<ClangEnumRef>>
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

// clang omits `file` and `line` from a location that repeats the previous node's: the dumper
// carries them forward in tree order, which is the order clang assigned them in
def private loc_of(var d : Dumper; js : JsonValue?) : CirLoc {
    let given = has_loc(js) ? js?["loc"] : js?["range"]?["begin"]
    let at = is_present(given?["expansionLoc"]) ? given?["expansionLoc"] : given
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

// every node of a subtree the dumper does not visit still advances the location carry, since
// clang omitted the lines that repeat these nodes' lines
def private touch_locs(var d : Dumper; js : JsonValue?) {
    for (idx in range(child_count(js))) {
        let kid = (js?["inner"] as _array)[idx]
        loc_of(d, kid)
        touch_locs(d, kid)
    }
}

// the record definitions of the main file through libclang, nested ones included, under the
// same target and dialect flags as the JSON dump; the pass is the layout read-out of
// docs/very-detailed-plan.md section 4.1
def private register_record(var d : Dumper; var c : CXCursor) {
    let key = cursor_key(c)
    if (key_exists(d.record_by_loc, key)) {
        // a block-scoped record is visited under its statement and again under the variable's
        // type; another cursor at the same key is a second record one macro expansion made
        if ((d.record_hash?[key] ?? 0u) != clang_hashCursor(c)) {
            fail(d, "anonymous records from one macro expansion are not dumped yet", cursor_loc(d, c))
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
        fail(d, unnamed ? "anonymous records from one macro expansion are not dumped yet" : "`{rec.spelling}` is defined more than once in this file; same-tag block-scoped records are not dumped yet", cursor_loc(d, c))
        return
    }
    if (!tagged) {
        d.anon_spellings[raw] = rec.spelling
    }
    clang_visitChildren(c) $(var fc, _fp) {
        let fk = clang_getCursorKind(fc)
        if ((fk == CXCursorKind.StructDecl || fk == CXCursorKind.UnionDecl) && clang_isCursorDefinition(fc) != 0u) {
            register_record(d, fc)
            let inner = d.record_by_loc?[cursor_key(fc)] ?? -1
            if (inner >= 0 && clang_Cursor_isAnonymousRecordDecl(fc) != 0u) {
                // an anonymous member: libclang visits its record, never the implicit field
                let bit_off = anonymous_offset(d, ct, inner)
                if (bit_off < 0l) {
                    fail(d, "anonymous member of `{rec.spelling}` exposes no field name; not dumped yet", cursor_loc(d, fc))
                }
                var canonical = clang_getCanonicalType(clang_getCursorType(fc))
                rec.fields |> push(ClangField(loc_key = cursor_key(fc), spelling = string(clang_getTypeSpelling(canonical)), bit_off = bit_off))
            }
        } elif (fk == CXCursorKind.EnumDecl && clang_isCursorDefinition(fc) != 0u) {
            register_enum(d, fc)
        } elif (fk == CXCursorKind.FieldDecl) {
            register_dims(d, fc)
            var declared = clang_getCursorType(fc)
            var canonical = clang_getCanonicalType(declared)
            let is_bf = clang_Cursor_isBitField(fc) != 0u
            // a `va_list` field is known by its declaration chain, which the msvc canonical
            // `char *` loses
            let va = type_holds_va(declared)
            let spelling = va == VA_EXACT ? VA_BUILTIN : string(clang_getTypeSpelling(canonical))
            if (va == VA_INSIDE) {
                fail(d, "`{string(clang_getTypeSpelling(declared))}`: a pointer to a `va_list` or an array of them is not lowered yet", cursor_loc(d, fc))
            }
            rec.fields |> push(ClangField(name = string(clang_getCursorSpelling(fc)), loc_key = cursor_key(fc), spelling = spelling, bit_off = clang_Cursor_getOffsetOfField(fc), bit_w = is_bf ? clang_getFieldDeclBitWidth(fc) : 0, is_bitfield = is_bf))
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

// a cursor's location as the dump reports it: the main file, the expansion line and column
def private cursor_loc(d : Dumper; var c : CXCursor) : CirLoc {
    var file : CXFile
    var line, column, offset : uint
    clang_getExpansionLocation(clang_getCursorLocation(c), safe_addr(file), safe_addr(line), safe_addr(column), safe_addr(offset))
    return CirLoc(file = d.c_path, line = int(line), col = int(column))
}

// the key that joins a libclang cursor to the JSON dump's node for it: the byte offsets of the
// expansion site and of the spelling (the two differ for a macro-produced token, and are the
// token's own otherwise); the offset, unlike the line, is on every JSON location, where clang
// omits a line that repeats its last one. The file is left out: the dump omits a `file` that
// repeats the last one, and every keyed cursor is the main file's
def private cursor_key(var c : CXCursor) : string {
    var file : CXFile
    var line, column, offset, spelled : uint
    var loc = clang_getCursorLocation(c)
    clang_getExpansionLocation(loc, safe_addr(file), safe_addr(line), safe_addr(column), safe_addr(offset))
    clang_getSpellingLocation(loc, safe_addr(file), safe_addr(line), safe_addr(column), safe_addr(spelled))
    return "{int(offset)}:{int(spelled)}"
}

def private node_key(js : JsonValue?) : string {
    let given = has_loc(js) ? js?["loc"] : js?["range"]?["begin"]
    let at = is_present(given?["expansionLoc"]) ? given?["expansionLoc"] : given
    let spelled = is_present(given?["spellingLoc"]) ? given?["spellingLoc"] : given
    return "{int(at?["offset"] ?? -1l)}:{int(spelled?["offset"] ?? -1l)}"
}

// an enum definition with clang's evaluated values; a typedef-named anonymous enum takes its
// tag back the way a record does
def private register_enum(var d : Dumper; var c : CXCursor) {
    // a block-scoped enum is visited under its statement and again under the variable's type
    if (key_exists(d.enum_by_loc, cursor_key(c))) {
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
    d.enum_by_loc[cursor_key(c)] = idx
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
        d.enum_dims_by_loc[cursor_key(c)] <- dims
    }
}

def private walk_records(var d : Dumper; var c : CXCursor) {
    clang_visitChildren(c) $(var kid, _parent) {
        let kind = clang_getCursorKind(kid)
        if (kind != CXCursorKind.TypedefDecl && clang_Location_isFromMainFile(clang_getCursorLocation(kid)) == 0) {
            return CXChildVisitResult.Continue
        }
        if ((kind == CXCursorKind.StructDecl || kind == CXCursorKind.UnionDecl) && clang_isCursorDefinition(kid) != 0u) {
            register_record(d, kid)
        } elif (kind == CXCursorKind.EnumDecl && clang_isCursorDefinition(kid) != 0u) {
            register_enum(d, kid)
        } elif (kind == CXCursorKind.VarDecl) {
            register_dims(d, kid)
            walk_records(d, kid)
        } elif (kind == CXCursorKind.DeclRefExpr) {
            // a reference to an enum constant resolves by its location, since C scopes let
            // two enums of one file spell the same constant name
            let ref = enum_constant_of(kid)
            if (is_constant(ref)) {
                d.enum_ref_by_loc[cursor_key(kid)] = ref
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

def private collect_records(var d : Dumper; triple : string; resource_dir : string; defines : array<string>) {
    // libclang finds no resource directory of its own, so the builtin headers (`stddef.h`, whose
    // `size_t` a libc prototype spells) come from the pinned clang's
    var args <- ["-target", triple, "-funsigned-char", "-w", "-resource-dir", resource_dir]
    args |> push_from(define_flags(defines))
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
    // the scope starts at the first `::`; an anonymous member's own scope is parenthesized
    // (`union N::(anonymous struct)::(anonymous at f:l:c)`)
    let start = rfind(slice(spelling, 0, find(spelling, "::")), " ") + 1
    return slice(spelling, 0, start) + slice(spelling, scope + 2)
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
    // `(**)` is a pointer to the pointer, one level per extra star; a `const` on the pointer
    // (`(* const)`, a member read through a const record) changes nothing das spells
    let between = strip(slice(qt, star + 2, close) |> replace("const", "")) |> replace(" ", "")
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
// outside the main file (a libc function, `stderr`) by its file-scope name
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
        let align = type_align(d.tu, of_t)
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
    if (k != "struct" && k != "array") {
        fail(d, "`{k}` initializer lists are not dumped yet", at)
        return null
    }
    let filled = is_present(js?["array_filler"])
    let entries = filled ? js?["array_filler"] : js?["inner"]
    let count = entries != null && entries is _array ? length(entries as _array) : 0
    let first = filled ? 1 : 0
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

def private source_line(var d : Dumper; line : int) : string {
    if (empty(d.source_lines)) {
        d.source_lines <- split(fread(d.c_path), "\n")
    }
    return line >= 1 && line <= length(d.source_lines) ? d.source_lines[line - 1] : ""
}

// clang's JSON carries neither the components nor the value of `offsetof(T, f)`
// (docs/probe-findings.md F20): the dumper reads `T, f` from the macro's own text at its
// expansion site, a direct field of a record only
def private dump_offsetof(var d : Dumper; t : int; at : CirLoc) : CirExpr? {
    let text = slice(source_line(d, at.line), max(at.col - 1, 0))
    let open = find(text, "(")
    let comma = find(text, ",")
    let close = find(text, ")")
    if (!(text |> starts_with("offsetof") || text |> starts_with("__builtin_offsetof")) || open < 0 || comma < open || close < comma) {
        fail(d, "offsetof: cannot read `type, member` at the expansion site", at)
        return null
    }
    let type_text = strip(slice(text, open + 1, comma))
    let member = strip(slice(text, comma + 1, close))
    let of_t = type_from_qual(d, type_text, at)
    if (of_t < 0) {
        return null
    }
    let field = member_index(d, of_t, member, -1)
    if (field < 0) {
        fail(d, "offsetof: `{member}` is not a direct field of `{type_text}`", at)
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
            let ref = d.enum_ref_by_loc?[node_key(js)] ?? ClangEnumRef()
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
        return new CirExpr(e = "ref", t = t, name = bound_name(d, js?["referencedDecl"]))
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
    if (kind == "MemberExpr") {
        return dump_member(d, js, t, at)
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

let TYPE_OPERATOR_KINDS <- {"UnaryExprOrTypeTraitExpr", "OffsetOfExpr", "VAArgExpr"}

// the expressions the language spells as operators over a type: `sizeof`, `offsetof`, `va_arg`
def private dump_type_operator(var d : Dumper; js : JsonValue?; kind : string; t : int; at : CirLoc) : CirExpr? {
    if (kind == "UnaryExprOrTypeTraitExpr") {
        return dump_sizeof(d, js, t, at)
    }
    if (kind == "OffsetOfExpr") {
        return dump_offsetof(d, t, at)
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
    // two static locals of one name in one function take numbered names
    let hoisted = free_name(d.hoisted_names, "{d.current_fn}_{c_name}")
    d.decl_names[js?["id"] ?? ""] = hoisted
    var g = new CirDecl(k = "global", name = hoisted, c_name = c_name, t = t, is_static = true, from_func = d.current_fn, loc = at)
    if (!enum_dims(d, node_key(js), t, at, g.dims)) {
        delete_decl(g)
        return false
    }
    if (child_count(js) > 0) {
        g.init = dump_expr(d, (js?["inner"] as _array)[child_count(js) - 1])
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
    var st = new CirStmt(s = "decl", name = js?["name"] ?? "", t = t, loc = at)
    d.decl_names[js?["id"] ?? ""] = st.name
    d.fn_locals |> insert(st.name)
    if (!enum_dims(d, node_key(js), t, at, st.dims)) {
        delete_stmt(st)
        return null
    }
    if (child_count(js) > 0) {
        st.init = dump_expr(d, (js?["inner"] as _array)[child_count(js) - 1])
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
    if (!(js?["completeDefinition"] ?? false)) {
        return true
    }
    if ((js?["name"] ?? "") == "__jmp_buf_tag") {
        // glibc's tag, which a file that includes no header defines itself: every spelling of it
        // is the opaque `jmp_buf` record (`jmp_buf_type`), so its fields name nothing
        touch_locs(d, js)
        return true
    }
    for (idx in range(child_count(js))) {
        let kid = (js?["inner"] as _array)[idx]
        if (node_kind(kid) == "RecordDecl" || node_kind(kid) == "EnumDecl") {
            if (!dump_type_decl(d, kid)) {
                return false
            }
        } else {
            loc_of(d, kid)
            touch_locs(d, kid)
        }
    }
    return anchor_type(d, js, at, false)
}

// the anchor of a record or enum definition: the type from the libclang entry at the node's
// location, pushed as its `record` or `enumdef` declaration
def private anchor_type(var d : Dumper; js : JsonValue?; at : CirLoc; is_enum : bool) : bool {
    let key = node_key(js)
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
    touch_locs(d, js)
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
    touch_locs(d, js)
    if (child_count(js) == 0) {
        return true
    }
    return anchor_type(d, js, at, true)
}

def private dump_type_decl(var d : Dumper; js : JsonValue?) : bool {
    let kind = node_kind(js)
    return kind == "RecordDecl" ? dump_record_decl(d, js) : kind == "EnumDecl" ? dump_enum_decl(d, js) : dump_typedef_decl(d, js)
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
    d.decl_names[js?["id"] ?? ""] = name
    if (kind == "FunctionDecl") {
        let t = node_type(d, js, at)
        if (t < 0) {
            return null
        }
        var fn = new CirDecl(k = "func", name = name, c_name = c_name, t = t, is_static = is_static, loc = at)
        d.current_fn = c_name
        d.fn_locals |> clear()
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
        var g = new CirDecl(k = "global", name = name, c_name = c_name, t = t, is_static = is_static, is_extern = storage == "extern" && child_count(js) == 0, loc = at)
        if (!enum_dims(d, node_key(js), t, at, g.dims)) {
            delete_decl(g)
            return null
        }
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

// a file stem as an identifier: every other character an underscore, a leading digit kept
// behind one, since `00099__f` is not a name
def private ident_of(name : string) : string {
    let ident = build_string() $(var w) {
        for (ch in name) {
            w |> write(is_alnum(ch) ? to_char(ch) : "_")
        }
    }
    return !empty(ident) && is_number(first_character(ident)) ? "_" + ident : ident
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
def default_clang : string =>
    has_env_variable("PATH_TO_LIBCLANG") ? get_env_variable("PATH_TO_LIBCLANG") + "/bin/clang" : "clang"

// the sidecar's `defines` as clang flags, `-D<entry>` each
def private define_flags(defines : array<string>) : array<string> => <- [for (entry in defines); "-D{entry}"]

//! Runs clang on `c_path` under the dialect `target`, with `-D<entry>` for each of `defines`,
//! and normalizes the dump; `d.error` names the first unsupported construct, and the dump is
//! then partial.
def dump_tu(c_path : string; target : CirTarget; clang : string; defines : array<string>) : Dumper {
    var d : Dumper
    d.tu.cir = CIR_VERSION
    d.tu.target = target
    d.tu.tu = base_name(c_path)
    d.c_path = c_path
    d.cur_file = c_path
    d.va_names |> insert(VA_BUILTIN)
    d.tu_prefix = ident_of(slice(d.tu.tu, 0, max(find(d.tu.tu, "."), 0)))
    d.tu.producer = "c2das-dumper-a 0.1 / clang {clang_version(clang)}"
    let resource_dir = clang_resource_dir(clang)
    if (empty(resource_dir)) {
        d.error = "`{clang} -print-resource-dir` gave no resource directory; libclang needs it for the builtin headers"
        return <- d
    }
    collect_records(d, target.triple, resource_dir, defines)
    if (!empty(d.error)) {
        return <- d
    }
    var out : string
    var dump_args <- [clang, "-Xclang", "-ast-dump=json", "-fsyntax-only", "-w", "-funsigned-char", "-target", target.triple]
    dump_args |> push_from(define_flags(defines), [c_path])
    let rc = run_and_capture(dump_args, out, 120.0)
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
    collect_va_ids(d, js)
    let top = js?["inner"]
    for (idx in range(child_count(js))) {
        let decl = (top as _array)[idx]
        let at = loc_of(d, decl)
        if ((decl?["isImplicit"] ?? false) || at.file != c_path) {
            touch_locs(d, decl)
            continue
        }
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
    delete_json(js)
    if (empty(d.error)) {
        check_enum_anchors(d)
    }
    return <- d
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
