options gen2
// the pipeline parses clang's JSON dump below its own frames
options stack = 1048576
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../convert_check.das
require ../../converter/pipeline.das
require ../../converter/sidecar.das
require ../../converter/tiers.das

//! The conversion checks of `run.das --convert` and `--compile-check` over a stand-in program:
//! two units that link, one the dumper refuses, staged from a folder and a host outside it; the
//! classification of first lines into the blocker table.

// a fresh scratch folder, "" when none can be made
def private scratch(name : string) : string {
    var error : string
    let dir = create_temp_directory(name, error)
    return empty(error) ? dir : ""
}

// the stand-in: `src/` holding `DOOM.h` and the units `a` (calls `b`), `b` and `bad` (a
// file-scope asm), and `host/doom_main.c` including `DOOM.h` by its path into `src/`
def private write_stand_in(root : string) {
    mkdir_rec(path_join(root, "src"))
    mkdir_rec(path_join(root, "host"))
    fwrite(path_join(root, "src/DOOM.h"), "int b(void);\nint a(void);\n")
    fwrite(path_join(root, "src/a.c"), "#include \"DOOM.h\"\nint a(void) \{ return b() + 1; \}\n")
    fwrite(path_join(root, "src/b.c"), "#include \"DOOM.h\"\nint b(void) \{ return 2; \}\n")
    fwrite(path_join(root, "src/bad.c"), "int bad(void) \{ return 0; \}\nasm(\"nop\");\n")
    fwrite(path_join(root, "host/doom_main.c"), "#include \"../src/DOOM.h\"\nint main(void) \{ return a() - 3; \}\n")
}

// the stand-in written under a fresh `root` and staged into `<root>/work/src`: its C files
def private staged_stand_in(var root : string&) : array<string> {
    root = scratch("doom_convert")
    write_stand_in(root)
    var error : string
    return <- stage_program(path_join(root, "src"), path_join(root, "host/doom_main.c"), path_join(root, "work/src"), ["a", "b", "bad"], error)
}

[test]
def test_stage(t : T?) {
    var root : string
    let c_paths <- staged_stand_in(root)
    t |> equal(length(c_paths), 4)
    t |> success(fexist(path_join(root, "work/src/DOOM.h")))
    t |> success(fread(path_join(root, "work/src/doom_main.c")) |> starts_with("#include \"DOOM.h\"\n"))
}

[test]
def test_units_alone(t : T?) {
    var root : string
    let c_paths <- staged_stand_in(root)
    let verdicts <- convert_units(c_paths, Sidecar())
    t |> equal(length(verdicts), 4)
    t |> equal(verdicts[0].name, "a")
    t |> success(verdicts[0].error |> starts_with(LINK_BOUND), verdicts[0].error)
    t |> equal(verdicts[1].error, "")
    t |> success(verdicts[2].error |> contains("a file-scope asm is machine code"), verdicts[2].error)
    t |> success(verdicts[3].error |> starts_with(LINK_BOUND), verdicts[3].error)
    let rows <- blocker_table(verdicts)
    t |> equal(length(rows), 2)
    t |> success(rows[0] |> starts_with("2  a function or an array another unit defines"), rows[0])
    t |> success(rows[1] |> starts_with("1  a file-scope asm statement  (bad)"), rows[1])
}

[test]
def test_units_alone_arrays(t : T?) {
    let root = scratch("doom_arrays")
    fwrite(path_join(root, "use.c"), "extern int tbl[];\nint use(int k) \{ return tbl[k]; \}\n")
    fwrite(path_join(root, "tbl.c"), "int tbl[] = \{1, 2\};\n")
    fwrite(path_join(root, "lone.c"), "extern int nowhere[];\nint lone(int k) \{ return nowhere[k]; \}\n")
    let verdicts <- convert_units([for (stem in ["use", "tbl", "lone"]); path_join(root, "{stem}.c")], Sidecar())
    // an array another unit defines is the link's; one no unit defines is the unit's own error
    t |> success(verdicts[0].error |> starts_with(LINK_BOUND), verdicts[0].error)
    t |> success(verdicts[0].error |> contains("`tbl` is an array of unknown length"), verdicts[0].error)
    t |> equal(verdicts[1].error, "")
    t |> success(verdicts[2].error |> starts_with("emitter: "), verdicts[2].error)
    t |> success(verdicts[2].error |> contains("`nowhere` is an array of unknown length"), verdicts[2].error)
}

[test]
def test_program_modules(t : T?) {
    var root : string
    let c_paths <- staged_stand_in(root)
    let out = path_join(root, "work/source")
    let res <- convert_program([c_paths[0], c_paths[1], c_paths[3]], out, TARGET, "", "", "", "", "main", "source")
    t |> equal(res.error, "")
    let verdicts <- compile_modules(out, CONVERTED_MODULES, 300.0)
    t |> success(length(verdicts) >= 3)
    t |> equal(length([for (v in verdicts); v; where !empty(v.error)]), 0)
}

[test]
def test_module_failure(t : T?) {
    let out = scratch("doom_broken")
    fwrite(path_join(out, "x.das"), "options gen2\ndef f : int \{\n    return undefined_name\n\}\n")
    fwrite(path_join(out, MODULE_LIST), "x.das\nx.das.inc\n")
    let verdicts <- compile_modules(out, CONVERTED_MODULES, 300.0)
    t |> equal(length(verdicts), 1)
    t |> success(verdicts[0].error |> contains("error"), verdicts[0].error)
}

[test]
def test_classify(t : T?) {
    t |> run("a known construct is named, an unknown one is its line without stage and location") @(t : T?) {
        t |> equal(classify("dumper: /x/i_asm.c:1:2: a file-scope asm is machine code outside any function; no emulation exists in the das runtime"), "a file-scope asm statement")
        t |> equal(classify("emitter: /x/r_data.c:1:2: an array of the marshal-only record `mappatch_t` is not lowered yet"), "an array of a marshal record, `maptexture_t.patches` (finding 2)")
        t |> equal(classify("emitter: /x/f_finale.c:602:5: pointer into array field `patch_t.columnofs` of a marshal-only record; not lowered yet (P6.3e)"), "a pointer into an array field of a marshal record, `patch_t.columnofs` (P6.3e)")
        t |> equal(classify("emitter: /x/y.c:1:2: something odd"), "new: something odd")
        t |> equal(unlocated("emitter: /x/doomdata.h:179:9: field `f`: why"), "field `f`: why")
    }
    t |> run("the first error line, else the first line") @(t : T?) {
        t |> equal(first_error_line("\nnote: a\nerror[1]: b\n"), "error[1]: b")
        t |> equal(first_error_line("\n  only line\n"), "only line")
        t |> equal(first_error_line(""), "")
    }
}
