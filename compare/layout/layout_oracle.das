options gen2

module layout_oracle public

require strings
require math
require daslib/strings_boost
require daslib/fio
require daslib/safe_addr
require daslib/clargs
require cbind
require ../../frontend/c_layout.das
require ../../converter/cir.das
require ../../converter/dumper_a.das

//! The layout oracle of `frontend/c_layout.das` (`compare/layout/ARCHITECTURE.md`): every record a
//! unit defines, described from clang's own AST, laid out by the module and compared with clang's
//! layout of it.

//! A member's attributes as clang's text AST dump states them.
struct DumpMember {
    name : string
    packed : bool
    aligned : int
    alignas_type : bool     //!< `_Alignas(type)`, whose value the dump does not state
}

//! A record definition's attributes and members as clang's text AST dump states them.
struct DumpRecord {
    is_union : bool
    packed : bool
    aligned : int
    pack : int
    ms_struct : bool
    alignas_type : bool
    members : array<DumpMember>
}

//! A member as libclang states it: its type's size and alignment, its bitfield width and its
//! offset in bits (-1 when clang answers none).
struct LaidMember {
    name : string
    size : int64
    align : int
    is_bitfield : bool
    width : int
    is_flexible : bool
    type_class : CLayoutClass
    off : int64
    typedef_required : bool //!< a typedef with `aligned` names the type, which msvc keeps under any pack
    desugared_align : int   //!< the alignment of the type below its typedefs, which msvc lays the member out by
    record_key : string     //!< the key of the record the type is, through arrays; "" for none
}

//! A record definition as libclang states it: its place, spelling, layout and members.
struct LaidRecord {
    key : string            //!< the expansion file and byte offset, one per definition
    at : string             //!< `file:line:col`
    spelling : string
    is_union : bool
    size : int64
    align : int64
    members : array<LaidMember>
}

//! The counts of a set of units: records compared and agreeing, records the module refuses (by
//! reason), records the oracle cannot describe, and every difference.
struct LayoutTotals {
    units : int
    clang_failures : int
    records : int
    agreed : int
    differ : int
    refused : int
    undescribed : int
    redescribed : int       //!< records compared again in a later unit whose description of them differs
    reasons : table<string; int>
    lines : array<string>
}

let private ALIGNED_DEFAULT = 16

// the node kind of a text dump line and its depth: the tree prefix is two characters a level
def private dump_node(line : string; var depth : int&) : string {
    var at = 0
    peek_data(line) $(bytes) {
        while (at < length(bytes)) {
            let ch = int(bytes[at])
            break if (ch != ' ' && ch != '|' && ch != '`' && ch != '-')
            at++
        }
    }
    depth = at / 2
    let space = find(line, " ", at)
    return space < 0 ? slice(line, at) : slice(line, at, space)
}

// a field's name in its text dump line: the words between its location and its quoted type are
// clang's flags (`implicit`, then `used` or `referenced`) and the name; an implicit field, the
// anonymous member, and an unnamed bitfield, which nothing can reference, have none
def private dump_field_name(line : string) : string {
    let quote = find(line, " '")
    let head <- split(quote < 0 ? line : slice(line, 0, quote), " ")
    var tail : array<string>
    var at = length(head) - 1
    while (at >= 0 && find(head[at], ":") < 0 && !(head[at] |> ends_with(">"))) {
        tail |> push(head[at])
        at--
    }
    if (empty(tail) || tail[length(tail) - 1] == "implicit") {
        return ""
    }
    return tail[0]
}

// one open node of the walk: a record, a field or an `aligned` attribute waiting for its value
struct private OpenNode {
    depth : int
    rec : int
    member : int
    is_attr : bool
    valued : bool
    value : int
}

def private close_attr(var records : array<DumpRecord>; node : OpenNode) {
    if (node.member < 0) {
        records[node.rec].aligned = max(records[node.rec].aligned, node.value)
    } else {
        records[node.rec].members[node.member].aligned = max(records[node.rec].members[node.member].aligned, node.value)
    }
}

//! The record definitions of clang's text AST dump (`-Xclang -ast-dump`) in the dump's order,
//! clang's implicit ones left out, each with its attributes and its members' names and attributes.
def dump_records(dump : string) : array<DumpRecord> {
    var records : array<DumpRecord>
    var open : array<OpenNode>
    for (line in split(dump, "\n")) {
        var depth = 0
        let kind = dump_node(line, depth)
        while (!empty(open) && open[length(open) - 1].depth >= depth) {
            let node = open[length(open) - 1]
            if (node.is_attr) {
                close_attr(records, node)
            }
            open |> pop()
        }
        let top = empty(open) ? OpenNode(depth = -1, rec = -1, member = -1) : open[length(open) - 1]
        if (kind == "RecordDecl") {
            if (line |> ends_with(" definition") && find(line, " implicit ") < 0) {
                var inscope words <- split(line, " ")
                let n = length(words)
                let is_union = words[n - 2] == "union" || (n >= 3 && words[n - 3] == "union")
                records |> emplace(DumpRecord(is_union = is_union))
                open |> push(OpenNode(depth = depth, rec = length(records) - 1, member = -1))
            }
            continue
        }
        if (top.is_attr) {
            if (kind == "value:" && !top.valued) {
                var inscope words <- split(line, " ")
                open[length(open) - 1].value = to_int(words[length(words) - 1])
                open[length(open) - 1].valued = true
            }
            continue
        }
        continue if (top.rec < 0 || top.depth != depth - 1)
        if (kind == "FieldDecl" && top.member < 0) {
            records[top.rec].members |> emplace(DumpMember(name = dump_field_name(line)))
            open |> push(OpenNode(depth = depth, rec = top.rec, member = length(records[top.rec].members) - 1))
        } elif (kind == "PackedAttr") {
            if (top.member < 0) {
                records[top.rec].packed = true
            } else {
                records[top.rec].members[top.member].packed = true
            }
        } elif (kind == "MSStructAttr" && top.member < 0) {
            records[top.rec].ms_struct = true
        } elif (kind == "MaxFieldAlignmentAttr" && top.member < 0) {
            var inscope words <- split(line, " ")
            records[top.rec].pack = to_int(words[length(words) - 1]) / 8
        } elif (kind == "AlignedAttr") {
            if (find(line, "'") >= 0) {
                if (top.member < 0) {
                    records[top.rec].alignas_type = true
                } else {
                    records[top.rec].members[top.member].alignas_type = true
                }
            } else {
                open |> push(OpenNode(depth = depth, rec = top.rec, member = top.member, is_attr = true, value = ALIGNED_DEFAULT))
            }
        }
    }
    while (!empty(open)) {
        let node = open[length(open) - 1]
        if (node.is_attr) {
            close_attr(records, node)
        }
        open |> pop()
    }
    return <- records
}

// the place of cursor `c` as `file:line:col` of its expansion, and in `key` the record's identity
// across units: its expansion file and offset with its spelling file and offset, which part the
// records one macro expansion defines
def private cursor_place(var c : CXCursor; var key : string&) : string {
    var file, spelled_file : CXFile
    var line, column, offset, spelled_line, spelled_column, spelled : uint
    var loc = clang_getCursorLocation(c)
    clang_getExpansionLocation(loc, safe_addr(file), safe_addr(line), safe_addr(column), safe_addr(offset))
    clang_getSpellingLocation(loc, safe_addr(spelled_file), safe_addr(spelled_line), safe_addr(spelled_column), safe_addr(spelled))
    let name = file == null ? "" : string(clang_getFileName(file))
    let full = empty(name) ? "" : get_full_file_name(name)
    let spelled_name = spelled_file == null ? "" : string(clang_getFileName(spelled_file))
    let spelled_full = empty(spelled_name) ? "" : get_full_file_name(spelled_name)
    key = "{full}:{int(offset)}:{spelled_full}:{int(spelled)}"
    return "{name}:{int(line)}:{int(column)}"
}

def private is_record_cursor(var c : CXCursor) : bool {
    let kind = clang_getCursorKind(c)
    return kind == CXCursorKind.StructDecl || kind == CXCursorKind.UnionDecl
}

// the first named field record cursor `c` makes visible, through its anonymous members; "" for none
def private visible_name(var c : CXCursor) : string {
    var name : string
    clang_visitChildren(c) $(var fc, _fp) {
        if (clang_getCursorKind(fc) == CXCursorKind.FieldDecl) {
            name = string(clang_getCursorSpelling(fc))
        } elif (is_record_cursor(fc) && clang_Cursor_isAnonymousRecordDecl(fc) != 0u) {
            name = visible_name(fc)
        }
        return empty(name) ? CXChildVisitResult.Continue : CXChildVisitResult.Break
    }
    return name
}

// whether a typedef with an `aligned` attribute names type `t`, through arrays and typedefs
def private typedef_aligned(t : CXType) : bool {
    var at = t
    while (true) {
        if (at.kind == CXTypeKind.ConstantArray || at.kind == CXTypeKind.IncompleteArray) {
            at = clang_getArrayElementType(at)
        } elif (at.kind == CXTypeKind.Elaborated) {
            at = clang_Type_getNamedType(at)
        } elif (at.kind == CXTypeKind.Typedef) {
            var decl = clang_getTypeDeclaration(at)
            var found = false
            clang_visitChildren(decl) $(var kid, _fp) {
                found = found || clang_getCursorKind(kid) == CXCursorKind.AlignedAttr
                return CXChildVisitResult.Continue
            }
            return true if (found)
            at = clang_getTypedefDeclUnderlyingType(decl)
        } else {
            return false
        }
    }
    return false
}

// the key of the record type `t` is through arrays, "" when it is none
def private record_key_of(var t : CXType) : string {
    var at = clang_getCanonicalType(t)
    while (at.kind == CXTypeKind.ConstantArray || at.kind == CXTypeKind.IncompleteArray) {
        at = clang_getCanonicalType(clang_getArrayElementType(at))
    }
    if (at.kind != CXTypeKind.Record) {
        return ""
    }
    // the type's declaration can be a forward one; the key is the definition's
    var decl = clang_getCursorDefinition(clang_getTypeDeclaration(at))
    var key : string
    cursor_place(decl, key)
    return key
}

def private member_of_field(var fc : CXCursor) : LaidMember {
    var declared = clang_getCursorType(fc)
    let canonical = clang_getCanonicalType(declared)
    var m = LaidMember(name = string(clang_getCursorSpelling(fc)), off = clang_Cursor_getOffsetOfField(fc))
    m.is_bitfield = clang_Cursor_isBitField(fc) != 0u
    m.width = m.is_bitfield ? clang_getFieldDeclBitWidth(fc) : 0
    if (canonical.kind == CXTypeKind.Vector || canonical.kind == CXTypeKind.ExtVector) {
        m.type_class = CLayoutClass.vector
    } elif (canonical.kind == CXTypeKind.Int128 || canonical.kind == CXTypeKind.UInt128) {
        m.type_class = CLayoutClass.int128
    }
    if (canonical.kind == CXTypeKind.IncompleteArray) {
        m.is_flexible = true
        var elem = clang_getArrayElementType(declared)
        m.align = int(clang_Type_getAlignOf(elem))
    } else {
        m.size = clang_Type_getSizeOf(declared)
        m.align = int(clang_Type_getAlignOf(declared))
    }
    m.typedef_required = typedef_aligned(declared)
    m.record_key = record_key_of(declared)
    // the type below its top-level sugar alone, as clang's getUnqualifiedDesugaredType: a typedef of
    // an array is the array, whose element keeps its own typedef
    var top = declared
    while (top.kind == CXTypeKind.Elaborated || top.kind == CXTypeKind.Typedef) {
        top = top.kind == CXTypeKind.Elaborated ? clang_Type_getNamedType(top) : clang_getTypedefDeclUnderlyingType(clang_getTypeDeclaration(top))
    }
    m.desugared_align = m.is_flexible ? m.align : int(clang_Type_getAlignOf(top))
    return m
}

// the anonymous member record cursor `ac` makes, inside the record of type `owner`: its offset is
// that of a name it makes visible, less that name's offset inside it; -1 when it makes none visible
def private member_of_anonymous(var owner : CXType; var ac : CXCursor) : LaidMember {
    var inner = clang_getCursorType(ac)
    var key : string
    cursor_place(ac, key)
    var m = LaidMember(size = clang_Type_getSizeOf(inner), align = int(clang_Type_getAlignOf(inner)), off = -1l, record_key = key)
    let name = visible_name(ac)
    if (!empty(name)) {
        let outer_off = clang_Type_getOffsetOf(owner, name)
        let inner_off = clang_Type_getOffsetOf(inner, name)
        if (outer_off >= 0l && inner_off >= 0l) {
            m.off = outer_off - inner_off
        }
    }
    return m
}

def private clang_record(var c : CXCursor; key, at : string) : LaidRecord {
    var ct = clang_getCursorType(c)
    var rec = LaidRecord(key = key, at = at, spelling = string(clang_getTypeSpelling(ct)), is_union = clang_getCursorKind(c) == CXCursorKind.UnionDecl,
                          size = clang_Type_getSizeOf(ct), align = clang_Type_getAlignOf(ct))
    clang_visitChildren(c) $(var fc, _fp) {
        if (clang_getCursorKind(fc) == CXCursorKind.FieldDecl) {
            rec.members |> push(member_of_field(fc))
        } elif (is_record_cursor(fc) && clang_Cursor_isAnonymousRecordDecl(fc) != 0u) {
            rec.members |> push(member_of_anonymous(ct, fc))
        }
        return CXChildVisitResult.Continue
    }
    return <- rec
}

//! Every record definition of the unit at `unit` under `flags`, in libclang's order, each once;
//! `error` holds clang's first error when the parse fails or reports one.
def clang_records(unit : string; flags : array<string>; var error : string&) : array<LaidRecord> {
    var records : array<LaidRecord>
    var seen : table<string; bool>
    var args <- clone_to_move(flags)
    var idx = clang_createIndex(0, 0)
    var tu = clang_parseTranslationUnit(idx, unit, unsafe(addr(args[0])), length(args), null, 0u, 0u)
    if (tu == null) {
        error = "libclang gave no translation unit"
        clang_disposeIndex(idx)
        return <- records
    }
    for (i in urange(clang_getNumDiagnostics(tu))) {
        var diag = clang_getDiagnostic(tu, i)
        let severity = clang_getDiagnosticSeverity(diag)
        if (empty(error) && (severity == CXDiagnosticSeverity.Error || severity == CXDiagnosticSeverity.Fatal)) {
            error = string(clang_formatDiagnostic(diag, clang_defaultDiagnosticDisplayOptions()))
        }
        clang_disposeDiagnostic(diag)
    }
    if (empty(error)) {
        clang_visitChildren(clang_getTranslationUnitCursor(tu)) $(var c, _parent) {
            if (is_record_cursor(c) && clang_isCursorDefinition(c) != 0u) {
                var key : string
                let at = cursor_place(c, key)
                if (!key_exists(seen, key)) {
                    seen[key] = true
                    records |> emplace(clang_record(c, key, at))
                }
            }
            return CXChildVisitResult.Recurse
        }
    }
    clang_disposeTranslationUnit(tu)
    clang_disposeIndex(idx)
    return <- records
}

def private signature(rec : LaidRecord) : string => "{rec.is_union} {join([for (m in rec.members); m.name], ",")}"

def private signature(rec : DumpRecord) : string => "{rec.is_union} {join([for (m in rec.members); m.name], ",")}"

//! The index of the dump record each libclang record is, -1 for none: walked together in order,
//! a record whose kind and member names differ from the next dump record's matched to one of the
//! next `window` dump records, else to none.
def match_records(ours : array<LaidRecord>; theirs : array<DumpRecord>; window : int) : array<int> {
    var matched : array<int>
    matched |> reserve(length(ours))
    var next = 0
    for (rec in ours) {
        let sig = signature(rec)
        var found = -1
        for (j in range(next, min(next + window, length(theirs)))) {
            if (signature(theirs[j]) == sig) {
                found = j
                break
            }
        }
        matched |> push(found)
        if (found >= 0) {
            next = found + 1
        }
    }
    return <- matched
}

//! The description `c_record_layout` takes of a record under `dialect`: libclang's members, the
//! dump's attributes, and for a member of a record type that record's `required_align` from
//! `required` (by key). "" with `desc` set, or why the record cannot be described.
def describe_record(rec : LaidRecord; dump : DumpRecord; dialect : string; required : table<string; int>; var desc : CLayoutRecord) : string {
    if (rec.size < 0l || rec.align <= 0l) {
        return "clang gives the record no layout"
    }
    if (dump.alignas_type) {
        return "an `_Alignas(type)` on the record"
    }
    if (length(rec.members) != length(dump.members)) {
        return "libclang and the dump count its members apart"
    }
    var members : array<CLayoutMember>
    members |> reserve(length(rec.members))
    for (m, d in rec.members, dump.members) {
        if (d.alignas_type) {
            return "an `_Alignas(type)` on a member"
        }
        if (m.off < 0l) {
            return "an anonymous member that makes no name visible"
        }
        var needs = m.typedef_required ? m.align : 0
        // msvc lays a member out by its type below the typedefs and keeps a typedef's `aligned` as a requirement
        let align = dialect == "msvc" && m.typedef_required ? m.desugared_align : m.align
        if (!empty(m.record_key)) {
            if (!key_exists(required, m.record_key)) {
                return "a member's record has no layout of ours"
            }
            needs = max(needs, required?[m.record_key] ?? 0)
        }
        members |> push(CLayoutMember(name = m.name, size = m.size, align = align, is_bitfield = m.is_bitfield, width = m.width,
                                      is_flexible = m.is_flexible, packed = d.packed, aligned = d.aligned, required_align = needs,
                                      type_class = m.type_class, at = rec.at))
    }
    delete desc
    desc <- CLayoutRecord(dialect = dialect, is_union = rec.is_union, packed = dump.packed, aligned = dump.aligned, pack = dump.pack,
                          ms_struct = dump.ms_struct, at = rec.at, members <- members)
    return ""
}

//! The differences between clang's layout of `rec` and `layout`, one line each; none when they agree.
def layout_differences(rec : LaidRecord; layout : CRecordLayout) : array<string> {
    var diffs : array<string>
    if (layout.size != rec.size) {
        diffs |> push("size clang {rec.size} ours {layout.size}")
    }
    if (int64(layout.align) != rec.align) {
        diffs |> push("align clang {rec.align} ours {layout.align}")
    }
    for (m, off in rec.members, layout.offsets) {
        if (m.off != off) {
            let name = empty(m.name) ? "(unnamed)" : m.name
            diffs |> push("{name} at bit clang {m.off} ours {off}")
        }
    }
    return <- diffs
}

// the outcome of one record of a unit: its layout, or why it has none (`why`), and whether it was
// refused by the module rather than undescribed
struct private Outcome {
    state : int             // 0 not yet, 1 in progress, 2 done
    layout : CRecordLayout
    why : string
    refused : bool
    described : string      // the description the module laid out, as text; `why` for none
}

// description `d` as one text: what a later unit's description of the record must equal to be the
// same record under the same rules
def private description_text(d : CLayoutRecord) : string {
    let members = join([for (m in d.members); "{m.name}:{m.size}:{m.align}:{m.is_bitfield}:{m.width}:{m.is_flexible}:{m.packed}:{m.aligned}:{m.required_align}"], ",")
    return "{d.is_union} {d.packed} {d.aligned} {d.pack} {d.ms_struct} [{members}]"
}

// record `i` of the unit laid out into `outcomes`, after every record its members' types are (by
// key), so a member's record gives its `required_align`
def private lay_out(i : int; ours : array<LaidRecord>; theirs : array<DumpRecord>; matched : array<int>; dialect : string;
                    by_key : table<string; int>; var required : table<string; int>; var outcomes : array<Outcome>) {
    return if (outcomes[i].state != 0)
    outcomes[i].state = 1
    for (m in ours[i].members) {
        let j = by_key?[m.record_key] ?? -1
        if (j >= 0) {
            lay_out(j, ours, theirs, matched, dialect, by_key, required, outcomes)
        }
    }
    outcomes[i].state = 2
    if (matched[i] < 0) {
        outcomes[i].why = "no dump record matches it"
        outcomes[i].described = outcomes[i].why
        return
    }
    var desc : CLayoutRecord
    outcomes[i].why = describe_record(ours[i], theirs[matched[i]], dialect, required, desc)
    outcomes[i].described = empty(outcomes[i].why) ? description_text(desc) : outcomes[i].why
    return if (!empty(outcomes[i].why))
    outcomes[i].layout <- c_record_layout(desc)
    if (outcomes[i].layout.failed) {
        let err = outcomes[i].layout.err
        let colon = find(err, ": ")
        outcomes[i].why = colon < 0 ? err : slice(err, colon + 2)
        outcomes[i].refused = true
        return
    }
    required[ours[i].key] = outcomes[i].layout.required_align
}

//! One unit through both sides under `dialect` into `totals`; a record met in an earlier unit with
//! the same description (`seen`, by its place: a header's record under the same defines and pack)
//! is not counted again, one whose description differs is compared again.
def compare_layout_unit(unit, dialect : string; flags : array<string>; var seen : table<string; string>; var totals : LayoutTotals) {
    totals.units++
    var error : string
    let ours <- clang_records(unit, flags, error)
    if (!empty(error)) {
        totals.clang_failures++
        totals.lines |> push("{unit}: clang: {error}")
        return
    }
    var dump : string
    var argv <- [default_clang()]
    argv |> push_from(flags, ["-fsyntax-only", "-Xclang", "-ast-dump", unit])
    if (run_and_capture(argv, dump, 600.0) != 0) {
        totals.clang_failures++
        totals.lines |> push("{unit}: clang -ast-dump failed")
        return
    }
    let theirs <- dump_records(dump)
    let matched <- match_records(ours, theirs, 16)
    let by_key <- {for (rec, i in ours, count()); rec.key => i}
    var required : table<string; int>
    var outcomes : array<Outcome>
    outcomes |> resize(length(ours))
    for (i in range(length(ours))) {
        lay_out(i, ours, theirs, matched, dialect, by_key, required, outcomes)
    }
    for (rec, outcome in ours, outcomes) {
        continue if (key_exists(seen, rec.key) && (seen?[rec.key] ?? "") == outcome.described)
        if (key_exists(seen, rec.key)) {
            totals.redescribed++
        }
        seen[rec.key] = outcome.described
        totals.records++
        if (!empty(outcome.why)) {
            if (outcome.refused) {
                totals.refused++
            } else {
                totals.undescribed++
                totals.lines |> push("{rec.at}: `{rec.spelling}`: undescribed: {outcome.why}")
            }
            totals.reasons[outcome.why]++
            continue
        }
        var inscope diffs <- layout_differences(rec, outcome.layout)
        if (empty(diffs)) {
            totals.agreed++
        } else {
            totals.differ++
            totals.lines |> push("{rec.at}: `{rec.spelling}`: {join(diffs, "; ")}")
        }
    }
}

//! A corpus: its units and the clang flags they are read under besides the dialect's.
struct LayoutCorpus {
    name : string
    units : array<string>
    extra : array<string>
}

// the `.c` files directly in `folder`, sorted
def private c_files(folder : string) : array<string> {
    var units : array<string>
    dir(folder) $(name) {
        if (ends_with(name, ".c")) {
            units |> push(path_join(folder, name))
        }
    }
    sort(units)
    return <- units
}

//! The units of corpus `name` with the fetch trees under `root`: `rules` (`fixtures/`),
//! `c-testsuite`, `gcc-torture` (the ids of its `expected_pass.txt`), `lua`, `doom` (PureDOOM under
//! `doom/doom.c2das`'s defines). `error` names an unknown corpus or a missing folder.
def layout_corpus(root, name, dialect : string; var error : string&) : LayoutCorpus {
    var corpus = LayoutCorpus(name = name)
    if (name == "rules") {
        corpus.units <- c_files("compare/layout/fixtures")
        if (dialect == "msvc") {
            corpus.units |> push_from(c_files("compare/layout/fixtures/msvc"))
        }
        return <- corpus
    }
    let folders <- {"c-testsuite" => "suites/c_testsuite/fetch/c-testsuite/tests/single-exec",
                    "gcc-torture" => "suites/gcc_torture/fetch/gcc/gcc/testsuite/gcc.c-torture/execute",
                    "lua" => "lua/fetch/lua-5.4.8/src", "doom" => "doom/fetch/PureDOOM/src/DOOM"}
    let relative = folders?[name] ?? ""
    if (empty(relative)) {
        error = "unknown corpus '{name}': rules, c-testsuite, gcc-torture, lua or doom"
        return <- corpus
    }
    let folder = path_join(root, relative)
    if (!stat(folder).is_dir) {
        error = "corpus {name}: {folder} is missing"
        return <- corpus
    }
    if (name == "gcc-torture") {
        let listed = fread(path_join(root, "suites/gcc_torture/expected_pass.txt"))
        for (line in split(listed, "\n")) {
            let id = strip(line)
            continue if (empty(id) || id |> starts_with("#"))
            corpus.units |> push(path_join(folder, "{id}.c"))
        }
        return <- corpus
    }
    corpus.units <- c_files(folder)
    if (name == "lua") {
        corpus.extra <- ["-DLUA_USE_JUMPTABLE=0"]
    } elif (name == "doom") {
        corpus.extra <- ["-I{folder}", "-DDOOM_IMPLEMENT_PRINT", "-DDOOM_IMPLEMENT_MALLOC", "-DDOOM_IMPLEMENT_FILE_IO", "-DDOOM_IMPLEMENT_EXIT",
                         "-DDOOM_IMPLEMENT_GETENV", "-DDOOM_TIC_CHECKSUM"]
    }
    return <- corpus
}

//! One corpus's totals as a line.
def describe_layout_totals(name : string; t : LayoutTotals) : string {
    var reasons <- [for (k, v in keys(t.reasons), values(t.reasons)); "{v} {k}"]
    sort(reasons)
    return "{name}: {t.units} units ({t.clang_failures} clang failures), {t.records} records ({t.redescribed} compared again under another description): {t.agreed} agree, {t.differ} differ, {t.refused} refused, {t.undescribed} undescribed [{join(reasons, "; ")}]; not compared: {t.clang_failures} units clang rejects, {t.undescribed} undescribed records"
}

//! The command line of `run.das`.
[CommandLineArgs]
struct LayoutArgs {
    //! a corpus: rules, c-testsuite, gcc-torture, lua, doom (repeatable)
    corpus : array<string>
    //! the folder the fetch trees are under (`suites/`, `lua/`, `doom/`)
    root : string = "."
    //! the dialect: linux or msvc
    dialect : string = "linux"
}

//! Every corpus of `args` compared, its difference lines and totals printed; 0 when no record
//! differs and every corpus was found.
def run_layout_oracle(args : LayoutArgs) : int {
    if (args.dialect != "linux" && args.dialect != "msvc") {
        print("unknown dialect '{args.dialect}': linux or msvc\n")
        return 1
    }
    var frontend_error : string
    let flags <- dumper_frontend_flags(target_by_name(args.dialect), frontend_error)
    if (!empty(frontend_error)) {
        print("{frontend_error}\n")
        return 1
    }
    var differ = 0
    for (name in args.corpus) {
        var error : string
        let corpus <- layout_corpus(args.root, name, args.dialect, error)
        if (!empty(error)) {
            print("{error}\n")
            return 1
        }
        var inscope all_flags <- clone_to_move(flags)
        all_flags |> push_from(corpus.extra)
        var inscope seen : table<string; string>
        var totals : LayoutTotals
        for (unit in corpus.units) {
            compare_layout_unit(unit, args.dialect, all_flags, seen, totals)
        }
        for (line in totals.lines) {
            print("{line}\n")
        }
        let set_name = args.dialect + " " + name
        print("{describe_layout_totals(set_name, totals)}\n")
        differ += totals.differ
    }
    return differ == 0 ? 0 : 1
}
