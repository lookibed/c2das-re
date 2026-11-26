options gen2
// the pipeline parses clang's JSON dump below the test's own frames
options stack = 1048576
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../../frontend/c_defines.das
require ../../frontend/tests/_own_header_names.das
require ../cir.das
require ../dumper_a.das
require ../pipeline.das
require ../tiers.das

//! Dumper A over the own libc headers (`converter/ARCHITECTURE_DUMPER.md`, the program's files):
//! every header of `frontend/include/` compiles under the dumper's frontend flags, a `<...>`
//! header the folder lacks fails the dump naming it, the folder's declarations stay external
//! wherever the program root lies, and a program that includes libc converts under both dialects.

let private FIXTURES = "converter/tests/fixtures"

// what clang prints for `source` checked under the dumper's frontend flags of `dialect`, "" when
// it takes the file silently
def private frontend_check(dir, name, dialect, source : string) : string {
    let c_path = path_join(dir, "{name}.c")
    fwrite(c_path, source)
    var error : string
    var argv <- [default_clang(), "-fsyntax-only"]
    argv |> push_from(dumper_frontend_flags(target_by_name(dialect), error), [c_path])
    if (!empty(error)) {
        return error
    }
    var out : string
    let rc = run_and_capture(argv, out, 60.0)
    return rc == 0 && empty(out) ? "" : "exit {rc}: {out}"
}

[test(description = "every own header alone, and all of them together, compiles under the dumper's frontend flags of each dialect", timeout = 1200)]
def test_headers_compile(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_own_headers", dir_error)
    t |> equal(dir_error, "")
    t |> run("the folder's headers are found, those of its subfolders included") @(t : T?) {
        let names <- header_names()
        t |> success(length(names) >= 24 && has_value(names, "sys/stat.h") && has_value(names, "bits/gnuc_va_list.h"), join(names, " "))
    }
    for (dialect in DIALECTS) {
        t |> run("{dialect}: each header alone, with no other included before it") @(t : T?) {
            for (name in header_names()) {
                t |> equal(frontend_check(dir, "alone", dialect, "#include <{name}>\n"), "", "{dialect}: <{name}>")
            }
        }
        t |> run("{dialect}: all headers in one unit, each twice") @(t : T?) {
            let all = join([for (name in header_names()); "#include <{name}>\n"], "")
            t |> equal(frontend_check(dir, "together", dialect, all + all), "", dialect)
        }
    }
    rmdir_rec(dir)
}

// a source that includes libc and prints through it, and its output under each dialect: `long`
// is the dialect's
let private LIBC_SOURCE = "#include <stdio.h>\n#include <string.h>\n#include <stdlib.h>\n#include <ctype.h>\nint main(void) \{ char text[8]; strcpy(text, \"own\"); printf(\"%s %d %d %d\\n\", text, (int) strlen(text), (int) sizeof(long), isalpha(text[0]) != 0); return abs(-3) - 3; \}\n"

[test(description = "a program over the own headers: both dialects convert it, an unknown header fails naming it, the folder stays external under any program root", timeout = 1200)]
def test_dump_over_own_headers(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_own_headers_dump", dir_error)
    t |> equal(dir_error, "")
    let c_path = path_join(dir, "libc.c")
    fwrite(c_path, LIBC_SOURCE)
    t |> run("a program that includes libc converts and runs under both dialects, `long` the dialect's") @(t : T?) {
        for (dialect, line in DIALECTS, ["own 3 8 1\n", "own 3 4 1\n"]) {
            let conv <- convert(c_path, path_join(dir, dialect), dialect)
            t |> equal(conv.ok, true, "{dialect}: {conv.error}")
            var output : string
            t |> equal(run_tier(conv.das_path, "interp", dir, output, CONVERTED_MODULES), 0, output)
            t |> equal(output, line, dialect)
        }
    }
    t |> run("a header's declarations stay out of the C-IR: only what the program names binds, by name") @(t : T?) {
        let conv <- convert(c_path, path_join(dir, "external"), "linux")
        t |> equal(conv.ok, true, conv.error)
        t |> success(conv.cir_text |> contains("\"strcpy\""), conv.cir_text)
        for (unused in ["\"fopen\"", "\"strcat\"", "\"malloc\"", "\"size_t\"", "\"_IO_FILE\"", "\"toupper\""]) {
            t |> success(!(conv.cir_text |> contains(unused)), "{unused} of an own header is in the C-IR")
        }
    }
    t |> run("an `#include <...>` of a header the folder does not hold fails the dump naming it, a system's own included") @(t : T?) {
        for (header in ["wchar.h", "sys/param.h", "c2das_no_such.h"]) {
            let missing = path_join(dir, "missing.c")
            fwrite(missing, "#include <{header}>\nint main(void) \{ return 0; \}\n")
            let conv <- convert(missing, path_join(dir, "missing"), "linux")
            t |> equal(conv.ok, false, conv.das_text)
            t |> success(conv.error |> contains("'{header}' file not found"), conv.error)
        }
    }
    t |> run("a program root that holds the own headers' folder leaves them external: the same C-IR as under the file's own folder") @(t : T?) {
        let fixture = "{FIXTURES}/p9_libc_more.c"
        let plain <- convert(fixture, path_join(dir, "plain"), "linux")
        t |> equal(plain.ok, true, plain.error)
        let side = path_join(dir, "wide.c2das")
        fwrite(side, "\{\"program_root\": \"{get_full_file_name(".")}\"\}\n")
        let wide <- convert(fixture, path_join(dir, "wide"), "linux", "", side)
        t |> equal(wide.ok, true, wide.error)
        t |> equal(wide.cir_text, plain.cir_text)
    }
    t |> run("a main file under the own headers' folder is no file of the program") @(t : T?) {
        let conv <- convert(path_join(own_include_dir(), "stddef.h"), path_join(dir, "header_main"), "linux")
        t |> equal(conv.ok, false, conv.das_text)
        t |> success(conv.error |> contains("is no file of the program") && conv.error |> contains("under the own libc headers' folder {get_full_file_name(own_include_dir())}/"), conv.error)
    }
    rmdir_rec(dir)
}

[test(description = "the frontend flags: the target, the dumper's own, `-undef`, the table as -D, then `-nostdinc` and the own headers as the one system folder; a missing folder is named")]
def test_frontend_flags(t : T?) {
    for (dialect in DIALECTS) {
        let target = target_by_name(dialect)
        var error : string
        var inscope flags <- dumper_frontend_flags(target, error)
        t |> equal(error, "")
        var table_error : string
        var inscope entries <- read_predefined(predefined_path(dialect), table_error)
        var inscope expected <- ["-target", target.triple]
        expected |> push_from(DUMPER_FLAGS, ["-undef"])
        expected |> push_from([for (entry in entries); "-D{entry}"], ["-nostdinc", "-isystem", get_full_file_name(own_include_dir())])
        t |> equal(join(flags, "\n"), join(expected, "\n"))
    }
    let missing = path_join(test_temp_dir(), "no_such_include")
    var error : string
    let linux = target_by_name("linux")
    let flags <- frontend_flags(linux, predefined_table(linux), missing, error)
    t |> equal(error, "{missing}: no such folder of the own libc headers")
    t |> equal(length(flags), 0)
}

// a record whose attribute `attr` stands behind `#ifdef <guard>`, and a `main` that uses it
def private guarded_record(guard, attr : string) : string =>
    "#ifdef {guard}\n#define ATTR __attribute__(({attr}))\n#else\n#define ATTR\n#endif\nstruct rec \{ char c; int v; \} ATTR;\nint main(void) \{ struct rec r; r.v = 1; return r.v - 1; \}\n"

// `source` converted under `linux` as `<dir>/<name>.c`, `sidecar` beside it when given
def private guard_convert(dir, name, source, sidecar : string) : ConvertResult {
    let c_path = path_join(dir, "{name}.c")
    fwrite(c_path, source)
    if (!empty(sidecar)) {
        fwrite(path_join(dir, "{name}.c2das"), sidecar)
    }
    return <- convert(c_path, path_join(dir, name), "linux")
}

[test(description = "the layout guard: a record laid out one way under the table and another under clang's own macros, or defined under the table alone, fails the dump; a sidecar define selects the arm", timeout = 1200)]
def test_layout_guard(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_layout_guard", dir_error)
    t |> equal(dir_error, "")
    t |> run("`packed` behind `__clang__` is refused, naming the record, its place and both layouts") @(t : T?) {
        let conv <- guard_convert(dir, "clang_packed", guarded_record("__clang__", "packed"), "")
        t |> equal(conv.ok, false, conv.das_text)
        t |> success(conv.error |> contains("clang_packed.c:6:8: `struct rec` is laid out as [size 8, align 4, members c@0 `char` 1/1, v@32 `int` 4/4] under the dialect's predefined macros and as [size 5, align 1, members c@0 `char` 1/1, v@8 `int` 4/4] under clang's own"), conv.error)
        t |> success(conv.error |> contains("a sidecar `defines` entry selects the arm for both"), conv.error)
    }
    t |> run("`aligned` behind `__clang__` is refused: the alignment and the size differ") @(t : T?) {
        let conv <- guard_convert(dir, "clang_aligned", guarded_record("__clang__", "aligned(16)"), "")
        t |> equal(conv.ok, false, conv.das_text)
        t |> success(conv.error |> contains("as [size 16, align 16, members c@0 `char` 1/1, v@32 `int` 4/4] under clang's own"), conv.error)
    }
    t |> run("each part of a signature is compared alone: the alignment, a field's offset, a bitfield's width, an anonymous member's offset, a field's storage, its type at one size") @(t : T?) {
        let attr = "#ifdef __clang__\n#define ATTR __attribute__((\{0\}))\n#else\n#define ATTR\n#endif\n"
        let parts <- [
            (name = "align_only", source = "{replace(attr, "\{0\}", "aligned(16)")}struct rec \{ char c[16]; \} ATTR;\nint main(void) \{ return 0; \}\n",
                ours = "[size 16, align 1, members c@0 `char[16]` 16/1]", theirs = "[size 16, align 16, members c@0 `char[16]` 16/1]"),
            (name = "offset_only", source = "{replace(attr, "\{0\}", "aligned(2)")}struct rec \{ int i; char a; char b ATTR; \};\nint main(void) \{ return 0; \}\n",
                ours = "[size 8, align 4, members i@0 `int` 4/4, a@32 `char` 1/1, b@40 `char` 1/1]", theirs = "[size 8, align 4, members i@0 `int` 4/4, a@32 `char` 1/1, b@48 `char` 1/1]"),
            (name = "width_only", source = "#ifdef __clang__\n#define W 5\n#else\n#define W 4\n#endif\nstruct rec \{ unsigned a : 3; unsigned b : W; \};\nint main(void) \{ return 0; \}\n",
                ours = "[size 4, align 4, members a@0:3 `unsigned int` 4/4, b@3:4 `unsigned int` 4/4]", theirs = "[size 4, align 4, members a@0:3 `unsigned int` 4/4, b@3:5 `unsigned int` 4/4]"),
            // the anonymous member moves from byte 4 to byte 1; the outer record's named fields stay
            (name = "anonymous_only", source = "{replace(attr, "\{0\}", "packed")}struct rec \{ char c; struct \{ int x; \}; long y __attribute__((aligned(8))); \} ATTR;\nint main(void) \{ return 0; \}\n",
                ours = "[size 16, align 8, members c@0 `char` 1/1, (anonymous)@32, y@64 `long` 8/8]", theirs = "[size 16, align 8, members c@0 `char` 1/1, (anonymous)@8, y@64 `long` 8/8]"),
            // a packed enum is one byte inside a union of the same size
            (name = "storage_only", source = "{replace(attr, "\{0\}", "packed")}enum small \{ S0, S1 \} ATTR;\nstruct rec \{ enum small x; int pad[3]; long y; \};\nint main(void) \{ return 0; \}\n",
                ours = "[size 24, align 8, members x@0 `enum small` 4/4, pad@32 `int[3]` 12/4, y@128 `long` 8/8]", theirs = "[size 24, align 8, members x@0 `enum small` 1/1, pad@32 `int[3]` 12/4, y@128 `long` 8/8]"),
            (name = "type_only", source = "#ifdef __clang__\ntypedef float num;\n#else\ntypedef int num;\n#endif\nstruct rec \{ num v; \};\nint main(void) \{ return 0; \}\n",
                ours = "[size 4, align 4, members v@0 `int` 4/4]", theirs = "[size 4, align 4, members v@0 `float` 4/4]")]
        for (part in parts) {
            let conv <- guard_convert(dir, part.name, part.source, "")
            t |> equal(conv.ok, false, "{part.name}: {conv.das_text}")
            t |> success(conv.error |> contains("`struct rec` is laid out as {part.ours} under the dialect's predefined macros and as {part.theirs} under clang's own"), "{part.name}: {conv.error}")
        }
    }
    rmdir_rec(dir)
}

[test(description = "the layout guard's set and keys: enums, an external header's record held by value, one definition in each arm, a tag defined twice, the converter's own macro, the second pass's errors", timeout = 1200)]
def test_layout_guard_keys(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_layout_guard_keys", dir_error)
    t |> equal(dir_error, "")
    t |> run("an enum the dump defines is compared too: `packed` behind `__clang__` is refused") @(t : T?) {
        let conv <- guard_convert(dir, "enum_packed", "#ifdef __clang__\n#define ATTR __attribute__((packed))\n#else\n#define ATTR\n#endif\nenum small \{ S0, S1 \} ATTR;\nint main(void) \{ enum small e = S1; return e - 1; \}\n", "")
        t |> equal(conv.ok, false, conv.das_text)
        t |> success(conv.error |> contains("`enum small` is laid out as [size 4, align 4, of `unsigned int`] under the dialect's predefined macros and as [size 1, align 1, of `unsigned char`] under clang's own"), conv.error)
    }
    t |> run("a record of a header outside the program root that the program holds by value is compared like its own") @(t : T?) {
        let headers = path_join(dir, "outside")
        mkdir(headers)
        fwrite(path_join(headers, "api.h"), "#ifdef __clang__\n#define ATTR __attribute__((packed))\n#else\n#define ATTR\n#endif\nstruct api \{ char c; int x; \} ATTR;\n")
        mkdir(path_join(dir, "inside"))
        let conv <- guard_convert(path_join(dir, "inside"), "uses_api", "#include <api.h>\nint main(void) \{ struct api s; s.x = 0; return s.x; \}\n", "\{\"include_dirs\": [\"{headers}\"]\}\n")
        t |> equal(conv.ok, false, conv.das_text)
        t |> success(conv.error |> contains("api.h:6:8: `struct api` is laid out as [size 8, align 4,") && conv.error |> contains("as [size 5, align 1,"), conv.error)
    }
    t |> run("one definition in each arm is one record: a tag, a typedef's name, an unnamed record through its owner; an unnamed one with no owner is found by its place alone") @(t : T?) {
        let arms = "#ifdef __clang__\n\{0\}\n#else\n\{0\}\n#endif\n"
        for (name, decl in ["tagged", "typedef_named", "through_owner"], ["struct twin \{ int x; \};\ntypedef struct twin T;", "typedef struct \{ int x; \} T;", "typedef struct \{ int a; struct \{ int x; \} in; \} T;"]) {
            let conv <- guard_convert(dir, name, "{replace(arms, "\{0\}", decl)}int main(void) \{ T v; return (int) sizeof(v) - (int) sizeof(v); \}\n", "")
            t |> equal(conv.ok, true, "{name}: {conv.error}")
        }
        // fail closed: nothing names such a record across the arms
        let placed <- guard_convert(dir, "by_place", "{replace(arms, "\{0\}", "static struct \{ int x; \} v;")}int main(void) \{ v.x = 0; return v.x; \}\n", "")
        t |> equal(placed.ok, false, placed.das_text)
        t |> success(placed.error |> contains("is defined under the dialect's predefined macros and not under clang's own"), placed.error)
    }
    rmdir_rec(dir)
}

[test(description = "the layout guard's finer shapes: nested anonymous members, a tag one parse defines twice, an enum of one arm or of both, clang's builtin record", timeout = 1200)]
def test_layout_guard_shapes(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_layout_guard_shapes", dir_error)
    t |> equal(dir_error, "")
    t |> run("an anonymous member's offset is found through an anonymous member inside it, and is the member's, not the visible field's") @(t : T?) {
        let attr = "#ifdef __clang__\n#define ATTR __attribute__((packed))\n#else\n#define ATTR\n#endif\n"
        let nested <- guard_convert(dir, "anonymous_nested", "{attr}struct rec \{ char c; struct \{ struct \{ int x; \}; \}; long y __attribute__((aligned(8))); \} ATTR;\nint main(void) \{ return 0; \}\n", "")
        t |> equal(nested.ok, false, nested.das_text)
        t |> success(nested.error |> contains("`struct rec` is laid out as [size 16, align 8, members c@0 `char` 1/1, (anonymous)@32, y@64 `long` 8/8] under the dialect's predefined macros and as [size 16, align 8, members c@0 `char` 1/1, (anonymous)@8, y@64 `long` 8/8]"), nested.error)
        // the visible `x` stands 32 bits into the member: the member is at 32 and 8, `x` at 64 and 40
        let inside <- guard_convert(dir, "anonymous_inside", "{attr}struct rec \{ char c; struct \{ int : 8; int x; \}; long y __attribute__((aligned(8))); \} ATTR;\nint main(void) \{ return 0; \}\n", "")
        t |> equal(inside.ok, false, inside.das_text)
        t |> success(inside.error |> contains("members c@0 `char` 1/1, (anonymous)@32, y@128 `long` 8/8] under the dialect's predefined macros and as [size 24, align 8, members c@0 `char` 1/1, (anonymous)@8, y@128"), inside.error)
    }
    t |> run("a tag defined twice in either parse is found by place: a block's definition under `#ifndef __clang__` is refused, one more under `#ifdef __clang__` changes nothing") @(t : T?) {
        let ours_twice <- guard_convert(dir, "tag_twice_ours", "static int one(void) \{ struct s \{ int a; \} v; v.a = 1; return v.a; \}\n#ifndef __clang__\nstatic int two(void) \{ struct s \{ int a; \} v; v.a = 1; return v.a; \}\n#else\nstatic int two(void) \{ return 1; \}\n#endif\nint main(void) \{ return one() - two(); \}\n", "")
        t |> equal(ours_twice.ok, false, ours_twice.das_text)
        t |> success(ours_twice.error |> contains("tag_twice_ours.c:3:31: `struct s` is defined under the dialect's predefined macros and not under clang's own"), ours_twice.error)
        let theirs_twice <- guard_convert(dir, "tag_twice_theirs", "static int one(void) \{ struct s \{ int a; \} v; v.a = 1; return v.a; \}\n#ifdef __clang__\nstatic int two(void) \{ struct s \{ char a; \} v; v.a = 1; return v.a; \}\n#else\nstatic int two(void) \{ return 1; \}\n#endif\nint main(void) \{ return one() - two(); \}\n", "")
        t |> equal(theirs_twice.ok, true, theirs_twice.error)
    }
    t |> run("an enum under `#ifndef __clang__` is refused; one definition of an enum in each arm is one enum") @(t : T?) {
        let only <- guard_convert(dir, "enum_only", "#ifndef __clang__\nenum only \{ V \};\n#endif\nint main(void) \{ return 0; \}\n", "")
        t |> equal(only.ok, false, only.das_text)
        t |> success(only.error |> contains("enum_only.c:2:6: `enum only` is defined under the dialect's predefined macros and not under clang's own"), only.error)
        let both <- guard_convert(dir, "enum_both", "#ifdef __clang__\nenum e \{ A \};\n#else\nenum e \{ A \};\n#endif\nint main(void) \{ enum e v = A; return v; \}\n", "")
        t |> equal(both.ok, true, both.error)
    }
    rmdir_rec(dir)
}

[test(description = "the layout guard's signatures and keys, finer: an enum's underlying type, an unnamed record as a field's type, the ordinal of an owner's unnamed record, no second unit, clang's builtin record", timeout = 1200)]
def test_layout_guard_finer(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_layout_guard_finer", dir_error)
    t |> equal(dir_error, "")
    t |> run("an enum's underlying type is in its signature: `unsigned int` against `int` at one size is refused") @(t : T?) {
        let conv <- guard_convert(dir, "enum_signed", "#ifdef __clang__\nenum e : unsigned int \{ A = 1 \};\n#else\nenum e : int \{ A = 1 \};\n#endif\nint main(void) \{ enum e v = A; return v - 1; \}\n", "")
        t |> equal(conv.ok, false, conv.das_text)
        t |> success(conv.error |> contains("`enum e` is laid out as [size 4, align 4, of `int`] under the dialect's predefined macros and as [size 4, align 4, of `unsigned int`] under clang's own"), conv.error)
    }
    t |> run("an unnamed record as a field's type is signed by the record it is: `__typeof__` of one variable against another's, alike in size, is refused") @(t : T?) {
        let conv <- guard_convert(dir, "typeof_unnamed", "static struct \{ int a; \} gx;\nstatic struct \{ float a; \} gy;\n#ifdef __clang__\nstruct s \{ __typeof__(gx) f; \};\n#else\nstruct s \{ __typeof__(gy) f; \};\n#endif\nint main(void) \{ struct s v; gx.a = 0; gy.a = 0; return (int) sizeof(v) - 4; \}\n", "")
        t |> equal(conv.ok, false, conv.das_text)
        t |> success(conv.error |> contains("typeof_unnamed.c:6:8: `struct s` is laid out as [size 4, align 4, members f@0 `struct (unnamed)` = at ") && conv.error |> contains("typeof_unnamed.c:36 4/4] under the dialect's predefined macros") && conv.error |> contains("typeof_unnamed.c:7 4/4] under clang's own"), conv.error)
        // the same variable's type in both arms is one record: nothing differs
        let same <- guard_convert(dir, "typeof_same", "static struct \{ int a; \} gx;\n#ifdef __clang__\nstruct s \{ __typeof__(gx) f; \};\n#else\nstruct s \{ __typeof__(gx) f; \};\n#endif\nint main(void) \{ struct s v; gx.a = 0; return (int) sizeof(v) - 4; \}\n", "")
        t |> equal(same.ok, true, same.error)
    }
    t |> run("an owner's unnamed record is counted among its unnamed records alone: a named one clang's macros add before it changes nothing") @(t : T?) {
        let conv <- guard_convert(dir, "named_beside", "struct o \{\n#ifdef __clang__\n    struct helper \{ int z; \};\n#endif\n    struct \{ int y; \} v;\n\};\nint main(void) \{ struct o x; x.v.y = 0; return x.v.y; \}\n", "")
        t |> equal(conv.ok, true, conv.error)
    }
    t |> run("a second parse that gave no unit is one refusal naming the file") @(t : T?) {
        t |> equal(no_second_parse("dir/unit.c"), "dir/unit.c: the layout guard's parse with clang's own predefined macros gave no translation unit, so no layout can be compared")
    }
    t |> run("clang's builtin `__va_list_tag`, which a variadic function's `va_list` reaches, stands in no file and is not compared") @(t : T?) {
        let conv <- guard_convert(dir, "va_builtin", "#include <stdarg.h>\nstatic int sum(int n, ...) \{ va_list ap; va_start(ap, n); int s = 0; for (int i = 0; i < n; i++) s += va_arg(ap, int); va_end(ap); return s; \}\nint main(void) \{ return sum(2, 1, 2) - 3; \}\n", "")
        t |> equal(conv.ok, true, conv.error)
    }
    t |> run("a tag two blocks define is found by its place: both definitions stand in both passes") @(t : T?) {
        let conv <- guard_convert(dir, "block_tags", "static int one(void) \{ struct s \{ int a; \} v; v.a = 1; return v.a; \}\nstatic int two(void) \{ struct s \{ char c; \} v; v.c = 1; return v.c; \}\nint main(void) \{ return one() - two(); \}\n", "")
        t |> equal(conv.ok, true, conv.error)
    }
    t |> run("a record under the converter's own `__STDC_NO_VLA__`, which no clang defines, is a record of both passes") @(t : T?) {
        let conv <- guard_convert(dir, "no_vla_record", "#ifdef __STDC_NO_VLA__\nstruct fixed \{ int v[4]; \};\n#endif\nint main(void) \{ struct fixed f; f.v[0] = 0; return f.v[0]; \}\n", "")
        t |> equal(conv.ok, true, conv.error)
    }
    t |> run("`packed` behind `__GNUC__` holds under both: the dump keeps the packed record") @(t : T?) {
        let conv <- guard_convert(dir, "gnu_packed", guarded_record("__GNUC__", "packed"), "\{\"marshal\": [\"rec\"]\}\n")
        t |> success(!(conv.error |> contains("laid out as")), conv.error)
        t |> success(conv.cir_text |> contains("\"size\": 5"), conv.cir_text)
    }
    t |> run("a sidecar define of the tested name gives both passes one arm") @(t : T?) {
        let conv <- guard_convert(dir, "defined_packed", guarded_record("__clang__", "packed"), "\{\"defines\": [\"__clang__\"], \"marshal\": [\"rec\"]\}\n")
        t |> success(!(conv.error |> contains("laid out as")), conv.error)
        t |> success(conv.cir_text |> contains("\"size\": 5"), conv.cir_text)
    }
    t |> run("a record defined under the table and not under clang's macros is refused; one defined under clang's alone is no record of the program") @(t : T?) {
        let table_only <- guard_convert(dir, "table_only", "#ifndef __clang__\nstruct only \{ int v; \};\n#endif\nint main(void) \{ return 0; \}\n", "")
        t |> equal(table_only.ok, false, table_only.das_text)
        t |> success(table_only.error |> contains("table_only.c:2:8: `struct only` is defined under the dialect's predefined macros and not under clang's own"), table_only.error)
        let clang_only <- guard_convert(dir, "clang_only", "#ifdef __clang__\nstruct never \{ char c; int v; \} __attribute__((packed));\n#endif\nstruct both \{ int v; \};\nint main(void) \{ struct both b; b.v = 0; return b.v; \}\n", "")
        t |> equal(clang_only.ok, true, clang_only.error)
    }
    t |> run("an error the second pass meets is quoted beside a record it does not define") @(t : T?) {
        let conv <- guard_convert(dir, "stopped", "#ifdef __clang__\n#include <c2das_no_such.h>\n#else\nstruct late \{ int v; \};\n#endif\nint main(void) \{ return 0; \}\n", "")
        t |> equal(conv.ok, false, conv.das_text)
        t |> success(conv.error |> contains("`struct late` is defined under the dialect's predefined macros and not under clang's own (that pass met an error: ") && conv.error |> contains("'c2das_no_such.h' file not found"), conv.error)
    }
    t |> run("an `#error` of the second pass is quoted, and of two errors the first") @(t : T?) {
        let conv <- guard_convert(dir, "two_errors", "#ifdef __clang__\n#error the clang arm\n#error a later line\n#else\nstruct late \{ int v; \};\n#endif\nint main(void) \{ return 0; \}\n", "")
        t |> equal(conv.ok, false, conv.das_text)
        t |> success(conv.error |> contains("not under clang's own (that pass met an error: ") && conv.error |> contains("the clang arm"), conv.error)
        t |> success(!(conv.error |> contains("a later line")), conv.error)
    }
    rmdir_rec(dir)
}
