options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../layout/layout_oracle.das
require ../../frontend/c_layout.das
require ../../converter/cir.das
require ../../converter/dumper_a.das

//! `compare/layout/layout_oracle.das`: clang's text AST dump read for the records' attributes, the
//! two record lists matched, a record described and compared, and units through the pinned clang:
//! the rule fixtures with no difference, refusals and a failing unit counted apart.

// a dump of a packed record under `#pragma pack(2)` with an `aligned(8)` member, a field named
// like a flag, an implicit anonymous member, a nested bare `aligned` union, an implicit record,
// an `ms_struct` record with an `_Alignas(type)` member, and a declaration that is no definition
let DUMP = "TranslationUnitDecl 0x1 <<invalid sloc>> <invalid sloc>
|-RecordDecl 0x2 <<invalid sloc>> <invalid sloc> implicit struct __NSConstantString_tag definition
| `-FieldDecl 0x3 <<invalid sloc>> <invalid sloc> isa 'const int *'
|-RecordDecl 0x4 <a.c:2:1, col:60> col:8 struct S definition
| |-MaxFieldAlignmentAttr 0x5 <<invalid sloc>> Implicit 16
| |-PackedAttr 0x6 <col:23>
| |-FieldDecl 0x7 <col:12, col:17> col:17 referenced used 'int'
| | `-AlignedAttr 0x8 <col:33, col:42> aligned
| |   `-ConstantExpr 0x9 <col:41> 'int'
| |     |-value: Int 8
| |     `-IntegerLiteral 0xa <col:41> 'int' 8
| |-FieldDecl 0xb <col:20, col:27> col:24 'int'
| | `-PackedAttr 0xc <col:40>
| |-RecordDecl 0xd <line:3:3, col:30> col:3 union definition
| | |-AlignedAttr 0xe <col:20> aligned
| | | `-<<<NULL>>>
| | `-FieldDecl 0xf <col:11, col:15> col:15 c 'char'
| `-FieldDecl 0x10 <col:3> col:3 implicit referenced 'union S::(anonymous at a.c:3:3)'
|-RecordDecl 0x11 <line:5:1, col:40> col:8 struct M definition
| |-MSStructAttr 0x12 <col:20>
| `-FieldDecl 0x13 <col:12, col:17> col:17 m 'int'
|   `-AlignedAttr 0x14 <col:3, col:17> _Alignas 'double'
`-RecordDecl 0x15 <line:7:1, col:8> col:8 struct F
"

[test(description = "the dump's record definitions come in order with their attributes and their members' names and attributes; clang's implicit records and declarations are left out")]
def test_dump_records(t : T?) {
    let records <- dump_records(DUMP)
    t |> equal(length(records), 3)
    t |> equal("{records[0].is_union} {records[0].packed} {records[0].pack} {records[0].aligned} {records[0].ms_struct}", "false true 2 0 false")
    t |> equal(join([for (m in records[0].members); "{m.name}/{m.packed}/{m.aligned}"], " "), "used/false/8 /true/0 /false/0")
    t |> equal("{records[1].is_union} {records[1].aligned} {join([for (m in records[1].members); m.name], ",")}", "true 16 c")
    t |> equal("{records[2].ms_struct} {records[2].members[0].name} {records[2].members[0].alignas_type}", "true m true")
    let tail <- dump_records("`-RecordDecl 0x1 <a.c:1:1, col:9> col:8 struct T definition\n  `-AlignedAttr 0x2 <col:3> aligned\n    `-ConstantExpr 0x3 <col:4> 'int'\n      |-value: Int 4\n")
    t |> equal(tail[0].aligned, 4)
    let typed <- dump_records("`-RecordDecl 0x1 <a.c:1:1, col:9> col:8 struct T definition\n  `-AlignedAttr 0x2 <col:3> _Alignas 'long'\n")
    t |> success(typed[0].alignas_type)
}

def private laid_record(names : array<string>; is_union : bool = false) : LaidRecord {
    return <- LaidRecord(is_union = is_union, size = 4l, align = 4l, at = "a.c:1:8",
                         members <- [for (name in names); LaidMember(name = name, size = 4l, align = 4, off = 0l)])
}

def private dump_record(names : array<string>; is_union : bool = false) : DumpRecord =>
    <- DumpRecord(is_union = is_union, members <- [for (name in names); DumpMember(name = name)])

[test(description = "the two lists are matched by kind and member names in order, a record the dump lacks within the window matched to none")]
def test_match_records(t : T?) {
    let ours <- [laid_record(["a"]), laid_record(["x"]), laid_record(["b"], true), laid_record(["c"])]
    let theirs <- [dump_record(["a"]), dump_record(["b"]), dump_record(["skipped"]), dump_record(["b"], true), dump_record(["c"])]
    t |> equal(join([for (m in match_records(ours, theirs, 16)); "{m}"], " "), "0 -1 3 4")
    t |> equal(join([for (m in match_records(ours, theirs, 1)); "{m}"], " "), "0 -1 -1 -1")
}

[test(description = "a record is described from libclang's members and the dump's attributes, or not at all with the reason")]
def test_describe_record(t : T?) {
    var rec = laid_record(["a", ""])
    var dump = dump_record(["a", ""])
    dump.pack = 2
    dump.members[1].aligned = 8
    var desc : CLayoutRecord
    var required : table<string; int>
    t |> equal(describe_record(rec, dump, "linux", required, desc), "")
    t |> equal("{desc.dialect} {desc.pack} {desc.at} {length(desc.members)} {desc.members[1].aligned}", "linux 2 a.c:1:8 2 8")
    rec.members[0].typedef_required = true
    rec.members[0].desugared_align = 8
    rec.members[1].record_key = "k"
    required["k"] = 16
    t |> equal(describe_record(rec, dump, "linux", required, desc), "")
    t |> equal("{desc.members[0].align} {desc.members[0].required_align} {desc.members[1].required_align}", "4 4 16")
    t |> equal(describe_record(rec, dump, "msvc", required, desc), "")
    t |> equal("{desc.dialect} {desc.members[0].align} {desc.members[0].required_align}", "msvc 8 4")
    rec.members[1].record_key = "missing"
    t |> equal(describe_record(rec, dump, "msvc", required, desc), "a member's record has no layout of ours")
    rec.members[1].record_key = ""
    rec.size = -2l
    t |> equal(describe_record(rec, dump, "linux", required, desc), "clang gives the record no layout")
    rec.size = 4l
    dump.alignas_type = true
    t |> equal(describe_record(rec, dump, "linux", required, desc), "an `_Alignas(type)` on the record")
    dump.members |> push(DumpMember(name = "extra"))
    dump.alignas_type = false
    t |> equal(describe_record(rec, dump, "linux", required, desc), "libclang and the dump count its members apart")
    dump.members |> pop()
    dump.alignas_type = true
    dump.alignas_type = false
    dump.members[0].alignas_type = true
    t |> equal(describe_record(rec, dump, "linux", required, desc), "an `_Alignas(type)` on a member")
    dump.members[0].alignas_type = false
    rec.members[1].off = -1l
    t |> equal(describe_record(rec, dump, "linux", required, desc), "an anonymous member that makes no name visible")
}

[test(description = "a difference in size, alignment or any member's offset is one line each")]
def test_layout_differences(t : T?) {
    let rec = laid_record(["a", ""])
    var layout = CRecordLayout(size = 4l, align = 4)
    layout.offsets |> push_from([0l, 0l])
    t |> equal(length(layout_differences(rec, layout)), 0)
    layout.size = 8l
    layout.align = 8
    layout.offsets[0] = 32l
    layout.offsets[1] = 8l
    t |> equal(join(layout_differences(rec, layout), "; "), "size clang 4 ours 8; align clang 4 ours 8; a at bit clang 0 ours 32; (unnamed) at bit clang 0 ours 8")
}

[test(description = "the rule fixtures agree with clang on every record, the three one macro expansion defines and a typedef of an array under msvc among them; a refused record, an undescribed one (listed), a header's record met twice and a unit clang rejects are counted apart", timeout = 1200)]
def test_units(t : T?) {
    var error : string
    let flags <- dumper_frontend_flags(target_lp64_linux(), error)
    t |> equal(error, "")
    var rules = LayoutTotals()
    var seen : table<string; string>
    let corpus <- layout_corpus(".", "rules", "linux", error)
    for (unit in corpus.units) {
        compare_layout_unit(unit, "linux", flags, seen, rules)
    }
    t |> equal(describe_layout_totals("rules", rules), "rules: 3 units (0 clang failures), 72 records (0 compared again under another description): 72 agree, 0 differ, 0 refused, 0 undescribed []; not compared: 0 units clang rejects, 0 undescribed records")
    let msvc_flags <- dumper_frontend_flags(target_llp64_msvc(), error)
    var msvc_rules = LayoutTotals()
    var msvc_seen : table<string; string>
    let msvc_corpus <- layout_corpus(".", "rules", "msvc", error)
    for (unit in msvc_corpus.units) {
        compare_layout_unit(unit, "msvc", msvc_flags, msvc_seen, msvc_rules)
    }
    t |> equal(describe_layout_totals("rules", msvc_rules), "rules: 5 units (0 clang failures), 100 records (0 compared again under another description): 100 agree, 0 differ, 0 refused, 0 undescribed []; not compared: 0 units clang rejects, 0 undescribed records")
    let dir = test_temp_dir()
    let header = path_join(dir, "shared.h")
    fwrite(header, "struct H \{ char c; int i; \};\n")
    let first = path_join(dir, "first.c")
    fwrite(first, "#include \"shared.h\"\ntypedef int v4 __attribute__((vector_size(16)));\nstruct V \{ v4 v; \};\nstruct __attribute__((ms_struct)) W \{ int a; \};\nstruct B \{ int x : 3; \} __attribute__((aligned));\ntypedef struct Fwd Fwd;\nstruct Fwd \{ int a; \};\nstruct UsesFwd \{ Fwd f; \};\n")
    let second = path_join(dir, "second.c")
    fwrite(second, "#include \"shared.h\"\nstruct Anon \{ struct \{ int : 3; \}; int b; \};\n")
    let broken = path_join(dir, "broken.c")
    fwrite(broken, "int broken = ;\n")
    var totals = LayoutTotals()
    var seen_here : table<string; string>
    var with_dir <- clone_to_move(flags)
    with_dir |> push("-I{dir}")
    for (unit in fixed_array(first, second, broken)) {
        compare_layout_unit(unit, "linux", with_dir, seen_here, totals)
    }
    t |> equal(describe_layout_totals("set", totals), "set: 3 units (1 clang failures), 8 records (0 compared again under another description): 5 agree, 0 differ, 2 refused, 1 undescribed [1 an `ms_struct` record is not laid out; 1 an anonymous member that makes no name visible; 1 member `v` has a vector type, which the C-IR has no type for]; not compared: 1 units clang rejects, 1 undescribed records")
    t |> success(length(totals.lines) == 2 && find(totals.lines[0], "undescribed: an anonymous member that makes no name visible") >= 0 && find(totals.lines[1], "broken.c: clang: ") >= 0, join(totals.lines, "\n"))
}

[test(description = "a corpus is known by name and found under the root, never empty by absence; a run over an unknown one fails")]
def test_corpora(t : T?) {
    var error : string
    let unknown <- layout_corpus(".", "nothing", "linux", error)
    t |> equal(error, "unknown corpus 'nothing': rules, c-testsuite, gcc-torture, lua or doom")
    for (name in fixed_array("c-testsuite", "gcc-torture", "lua", "doom")) {
        error = ""
        let missing <- layout_corpus("/no/such/root", name, "linux", error)
        t |> success(error |> starts_with("corpus {name}: /no/such/root/") && error |> ends_with(" is missing"), error)
    }
    let root = test_temp_dir()
    let torture = path_join(root, "suites/gcc_torture/fetch/gcc/gcc/testsuite/gcc.c-torture/execute")
    mkdir_rec(torture)
    mkdir_rec(path_join(root, "lua/fetch/lua-5.4.8/src"))
    mkdir_rec(path_join(root, "doom/fetch/PureDOOM/src/DOOM"))
    fwrite(path_join(root, "suites/gcc_torture/expected_pass.txt"), "# head\n\nb-1\na-2\n")
    error = ""
    let listed <- layout_corpus(root, "gcc-torture", "linux", error)
    t |> equal(error, "")
    t |> equal(join([for (u in listed.units); base_name(u)], " "), "b-1.c a-2.c")
    let lua <- layout_corpus(root, "lua", "linux", error)
    t |> equal(join(lua.extra, " "), "-DLUA_USE_JUMPTABLE=0")
    let doom <- layout_corpus(root, "doom", "linux", error)
    t |> success(doom.extra[0] |> starts_with("-I") && length(doom.extra) == 7)
    t |> equal(run_layout_oracle(LayoutArgs(corpus <- ["nothing"])), 1)
    t |> equal(run_layout_oracle(LayoutArgs(corpus <- ["rules"], dialect = "win")), 1)
}

[test(description = "a header's record is compared again in a unit whose defines or pack describe it otherwise, and only then", timeout = 1200)]
def test_header_redescribed(t : T?) {
    var error : string
    let flags <- dumper_frontend_flags(target_lp64_linux(), error)
    let dir = test_temp_dir()
    fwrite(path_join(dir, "packed.h"), "struct P \{ char c; int i; \};\n")
    let plain_unit = path_join(dir, "plain.c")
    fwrite(plain_unit, "#include \"packed.h\"\n")
    let again = path_join(dir, "again.c")
    fwrite(again, "#include \"packed.h\"\n")
    let packed_unit = path_join(dir, "packed.c")
    fwrite(packed_unit, "#pragma pack(1)\n#include \"packed.h\"\n")
    var with_dir <- clone_to_move(flags)
    with_dir |> push("-I{dir}")
    var seen : table<string; string>
    var totals = LayoutTotals()
    for (unit in fixed_array(plain_unit, again, packed_unit)) {
        compare_layout_unit(unit, "linux", with_dir, seen, totals)
    }
    t |> equal("{totals.records} {totals.agreed} {totals.redescribed}", "2 2 1")
}


[test(description = "a field or a record named `implicit` is not clang's `implicit` flag, which stands before an anonymous member's type or a record's kind")]
def test_implicit_names(t : T?) {
    let named <- dump_records("`-RecordDecl 0x1 <a.c:1:1, col:26> col:8 struct K definition\n  `-FieldDecl 0x2 <col:12, col:16> col:16 implicit 'int'\n")
    t |> equal(join([for (m in named[0].members); "<{m.name}>"], ""), "<implicit>")
    let anonymous <- dump_records("`-RecordDecl 0x1 <a.c:1:1, col:40> col:8 struct N definition\n  |-RecordDecl 0x2 <col:12, col:30> col:12 union definition\n  | `-FieldDecl 0x3 <col:20, col:24> col:24 y 'int'\n  `-FieldDecl 0x4 <col:12> col:12 implicit 'union N::(anonymous at a.c:1:12)'\n")
    t |> equal(join([for (m in anonymous[0].members); "<{m.name}>"], ""), "<>")
    let record <- dump_records("`-RecordDecl 0x1 <a.c:1:1, col:26> col:8 struct implicit definition\n  `-FieldDecl 0x2 <col:21, col:25> col:25 a 'int'\n")
    t |> equal(length(record), 1)
}

// Dumper A's clang flags for `dialect`
def private flags_of(dialect : string) : array<string> {
    var error : string
    return <- dumper_frontend_flags(target_by_name(dialect), error)
}

// unit `text` written as `name` under a fresh folder and compared under `dialect` with `flags`:
// the totals line, then each printed line
def private compared(name, text, dialect : string; flags : array<string>) : string {
    let unit = path_join(test_temp_dir(), name)
    fwrite(unit, text)
    var seen : table<string; string>
    var totals = LayoutTotals()
    compare_layout_unit(unit, dialect, flags, seen, totals)
    let lines <- [for (line in totals.lines); slice(line, find(line, name))]
    return join([describe_layout_totals(name, totals)], "") + (empty(lines) ? "" : " | " + join(lines, " | "))
}

[test(description = "the arms no fixture reaches: a differing record counted and printed, records named `implicit`, a nested anonymous member, 128-bit and ext-vector members refused, msvc requirements through arrays and typedefs, a unit libclang cannot open", timeout = 1200)]
def test_unit_outcomes(t : T?) {
    t |> run("msvc's numbers against the linux layout: one record differs, printed with each difference") @(t : T?) {
        t |> equal(compared("mismatch.c", "struct MS \{ char a : 3; int b : 5; \};\n", "linux", flags_of("msvc")),
                   "mismatch.c: 1 units (0 clang failures), 1 records (0 compared again under another description): 0 agree, 1 differ, 0 refused, 0 undescribed []; not compared: 0 units clang rejects, 0 undescribed records | mismatch.c:1:8: `struct MS`: size clang 8 ours 4; b at bit clang 32 ours 3")
    }
    t |> run("linux: `implicit` names, a nested anonymous member agree; __int128 and ext_vector_type refused") @(t : T?) {
        t |> equal(compared("lin.c", "struct K \{ int implicit; \};\nstruct implicit \{ int a; \};\nstruct N \{ int a; union \{ struct \{ int y; \}; \}; \};\nstruct Wide128 \{ char c; __int128 w; \};\ntypedef float f4 __attribute__((ext_vector_type(4)));\nstruct Ext \{ f4 v; \};\n", "linux", flags_of("linux")),
                   "lin.c: 1 units (0 clang failures), 7 records (0 compared again under another description): 5 agree, 0 differ, 2 refused, 0 undescribed [1 member `v` has a vector type, which the C-IR has no type for; 1 member `w` has a 128-bit integer type, which the C-IR has no type for]; not compared: 0 units clang rejects, 0 undescribed records")
    }
    t |> run("msvc under pack(1): a requirement through an array of a typedef, a typedef of a typedef and an array of a required record") @(t : T?) {
        t |> equal(compared("ms.c", "typedef long long ll_a8 __attribute__((aligned(8)));\ntypedef int int_a8 __attribute__((aligned(8)));\ntypedef int_a8 wrap8;\nstruct __declspec(align(16)) Declspec \{ int a; \};\n#pragma pack(1)\nstruct ArrayOfTypedef \{ char c; ll_a8 x[2]; \};\nstruct Wrap \{ char c; wrap8 x; \};\nstruct ArrayOfRequired \{ char c; struct Declspec d[2]; \};\n#pragma pack()\n", "msvc", flags_of("msvc")),
                   "ms.c: 1 units (0 clang failures), 4 records (0 compared again under another description): 4 agree, 0 differ, 0 refused, 0 undescribed []; not compared: 0 units clang rejects, 0 undescribed records")
    }
    t |> run("a unit libclang gives no translation unit for is a clang failure") @(t : T?) {
        let missing = path_join(test_temp_dir(), "no_such_unit.c")
        var seen : table<string; string>
        var totals = LayoutTotals()
        compare_layout_unit(missing, "linux", flags_of("linux"), seen, totals)
        t |> equal(totals.clang_failures, 1)
        t |> equal(join(totals.lines, "|"), "{missing}: clang: libclang gave no translation unit")
    }
}

// `compare/layout/run.das` with `args` as a child process, `env` before it; its exit code, the output in `out`
def private run_das(env : array<string>; args : array<string>; var out : string&) : int {
    var argv <- ["env"]
    argv |> push_from(env, [get_das_root() + "/bin/daslang", "-load_module", get_full_file_name("dasCRuntime"), "-load_module", get_full_file_name("c_runtime")])
    if (stat("fetch/dasFlex").is_dir) {
        argv |> push_from(["-load_module", get_full_file_name("fetch/dasFlex")])
    }
    argv |> push_from(["compare/layout/run.das", "--"], args)
    return run_and_capture(argv, out, 600.0)
}

[test(description = "the run's exit code: 0 over the rule fixtures, 1 when a record differs (another --target than the layout's), 1 with CPATH set; run.das as a child prints the totals", timeout = 1200)]
def test_run_exit(t : T?) {
    t |> equal(run_layout_oracle(LayoutArgs(corpus <- ["rules"])), 0)
    t |> equal(run_layout_oracle(LayoutArgs(corpus <- ["rules"], flag <- ["--target=x86_64-pc-windows-msvc"])), 1)
    var out : string
    let plain = run_das(array<string>(), ["--corpus", "rules"], out)
    t |> equal(plain, 0, out)
    t |> success(out |> contains("linux rules: 3 units (0 clang failures), 72 records"), out)
    let with_cpath = run_das(["CPATH=/tmp"], ["--corpus", "rules"], out)
    t |> equal(with_cpath, 1, out)
    t |> success(out |> contains("the environment variable CPATH is set"), out)
}
