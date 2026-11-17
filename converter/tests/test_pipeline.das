options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/sha_256
require ../pipeline.das
require ../emit.das
require ../tiers.das
require ../dumper_a.das
require daslib/strings_boost

let FIXTURE = "converter/tests/fixtures/ret42.c"
let CIR_SHA = "7f13cda1870244734d24272413ced89edf30ea57681357b3d9bf61746eef793d"
let DAS_SHA = "56ecb7d9a210e8d789de2f2e3df9c0292c80fefe22f6d416cb7095c833392225"

var res : ConvertResult
var out : string

[test]
def test_pipeline_ret42(t : T?) {
    if (!fexist(FIXTURE)) {
        t |> failure("run from the repository root: {FIXTURE} not found")
        return
    }
    var dir_error : string
    out = create_temp_directory("c2das_test", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    delete res
    res <- convert(FIXTURE, out, "msvc")
    t |> run("the P0 program converts, formats and compile-checks") @(t : T?) {
        t |> equal(res.ok, true, res.error)
        t |> equal(res.das_text |> find("def c_main : int \{\n    return 42\n\}") >= 0, true, res.das_text)
        t |> equal(res.das_text |> find("[export]\ndef main : int \{\n    return c_main()\n\}") >= 0, true, res.das_text)
        t |> equal(res.das_text |> starts_with(GENERATED_BANNER), true)
    }
    t |> run("the result carries clang's JSON size and each stage's seconds") @(t : T?) {
        t |> equal(res.json_bytes > 1000l, true, "{res.json_bytes}")
        t |> equal(res.dump_seconds > 0.0lf, true, "{res.dump_seconds}")
        t |> equal(res.emit_seconds > 0.0lf, true, "{res.emit_seconds}")
        t |> equal(res.check_seconds > 0.0lf, true, "{res.check_seconds}")
        t |> equal(res.c_functions, 0)
        t |> equal(res.function_count, 1)
    }
    t |> run("the C-IR carries the target, the interned types and the return") @(t : T?) {
        t |> equal(res.cir_text |> find("\"cir\": \"0.2\"") >= 0, true)
        t |> equal(res.cir_text |> find("\"triple\": \"x86_64-pc-windows-msvc\"") >= 0, true)
        t |> equal(res.cir_text |> find("\"k\": \"func\"") >= 0, true)
        t |> equal(res.cir_text |> find("\"e\": \"int_lit\"") >= 0, true)
        t |> equal(res.cir_text |> find("\"v\": \"42\"") >= 0, true)
        t |> equal(res.cir_text |> ends_with("\}\n"), true)
    }
    t |> run("golden hashes of the C-IR and the das text") @(t : T?) {
        t |> equal(sha256_hex(res.cir_text), CIR_SHA, "the C-IR bytes changed:\n{res.cir_text}")
        t |> equal(sha256_hex(res.das_text), DAS_SHA, "the das text changed:\n{res.das_text}")
    }
    for (tier in ["interp", "jit", "exe", "aot"]) {
        t |> run("the converted program exits 42 under {tier}") @(t : T?) {
            if (!res.ok) {
                t |> skip("conversion failed")
                return
            }
            var output : string
            t |> equal(run_tier(res.das_path, tier, out, output), 42, output)
        }
    }
    t |> run("the exe build takes the interpreter flags, and its log joins the output only when it fails") @(t : T?) {
        if (!res.ok) {
            t |> skip("conversion failed")
            return
        }
        let level = get_env_variable("DAS_LOG_LEVEL")
        set_env_variable("DAS_LOG_LEVEL", "info")
        var built : string
        t |> equal(run_tier(res.das_path, "exe", path_join(out, "flags"), built, CONVERTED_MODULES, 120.0, ["-no-module-cache"]), 42, built)
        t |> equal(built, "", "the build's info lines joined the output")
        set_env_variable("DAS_LOG_LEVEL", level)
        var refused : string
        t |> equal(run_tier(res.das_path, "exe", path_join(out, "bogus"), refused, CONVERTED_MODULES, 120.0, ["-bogus-flag"]) != 0, true, refused)
        t |> success(refused |> contains("unknown command line option bogus-flag"), refused)
    }
    t |> run("the timeout bounds the exe and aot builds as well as the run") @(t : T?) {
        if (!res.ok) {
            t |> skip("conversion failed")
            return
        }
        let no_modules : array<string>
        for (tier in ["exe", "aot"]) {
            var output : string
            t |> equal(run_tier(res.das_path, tier, path_join(out, "timeout"), output, no_modules, 0.05), popen_timed_out, "{tier}: {output}")
        }
    }
    rmdir_rec(out)
}

[test]
def test_aot_binary(t : T?) {
    t |> run("the AOT binary is named by the stem spelled as the context's C++ prefix") @(t : T?) {
        t |> equal(aot_binary("w/lua-all.das", "w"), "w/ctx/lua_all_aot")
    }
}

[test]
def test_aot_host_command(t : T?) {
    t |> run("the AOT host compiles with the pinned clang++ at -O3, the native perf lane's compiler and level") @(t : T?) {
        let dirs : array<string>
        let cmd <- aot_link_command("ctx", "m.das", "ctx/host.cpp", "ctx/m_aot", dirs)
        t |> equal(cmd[0], default_clang() + "++")
        t |> success(cmd |> has_value("-O3"), join(cmd, " "))
        t |> success(!(cmd |> has_value("-O2")), join(cmd, " "))
    }
}

[test]
def test_aot_host_exception(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_aot_throw", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    t |> run("an unhandled exception under aot exits 254 (`DAS_PANIC_EXIT_CODE`) with its text on stderr, as under exe, where it would trap") @(t : T?) {
        let das_path = path_join(dir, "throws.das")
        fwrite(das_path, "options gen2\n[export]\ndef main() : int \{\n    var a : array<int>\n    a |> resize(2)\n    print(\"before\\n\")\n    return a[length(a) + 3]\n\}\n")
        let no_modules : array<string>
        for (tier in ["exe", "aot"]) {
            var output : string
            t |> equal(run_tier(das_path, tier, path_join(dir, tier), output, no_modules), 254, "{tier}: {output}")
            t |> success(output |> contains("before\n"), "{tier}: {output}")
            t |> success(output |> contains("EXCEPTION: ") && output |> contains("index out of range"), "{tier}: {output}")
        }
    }
    rmdir_rec(dir)
}

// a program whose `#if FOO == 2` branch prints another value than its `#else`
let DEFINES_SOURCE = "int printf(const char *, ...);\n#ifndef FOO\n#define FOO 1\n#endif\n#if FOO == 2\nstruct pick \{ int a; int b; \};\nstatic int value(void) \{ struct pick p = \{ 20, 2 \}; return p.a + p.b; \}\n#else\nstatic int value(void) \{ return 11; \}\n#endif\nint main(void) \{ printf(\"FOO picks %d\\n\", value()); return 0; \}\n"

// `DEFINES_SOURCE` as `<dir>/<name>/defines.c`, with `sidecar` beside it when given, converted
// and run under the interpreter: its output, "" with a failure when it does not convert
def defines_run(t : T?; dir, name, sidecar : string) : string {
    let at = path_join(dir, name)
    mkdir_rec(at)
    let c_path = path_join(at, "defines.c")
    fwrite(c_path, DEFINES_SOURCE)
    if (!empty(sidecar)) {
        fwrite(path_join(at, "defines.c2das"), sidecar)
    }
    let conv <- convert(c_path, path_join(at, "out"), "linux")
    if (!conv.ok) {
        t |> failure(conv.error)
        return ""
    }
    var output : string
    let rc = run_tier(conv.das_path, "interp", at, output, CONVERTED_MODULES)
    t |> equal(rc, 0, output)
    return output
}

[test]
def test_sidecar_defines_select(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_defines", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    t |> run("the sidecar's `defines` reach clang as -D: `FOO=2` selects the `#if` branch the native build with -DFOO=2 takes") @(t : T?) {
        let defined = defines_run(t, dir, "defined", "\{\"defines\": [\"FOO=2\"]\}\n")
        let native = native_run(default_clang(), ["-w", "-funsigned-char", "-DFOO=2"], path_join(path_join(dir, "defined"), "defines.c"), path_join(dir, "defines_native"), 60.0)
        t |> equal(native.built, true, native.output)
        t |> equal(defined, native.output)
        t |> equal(defined, "FOO picks 22\n")
        // without the sidecar the `#else` branch converts
        t |> equal(defines_run(t, dir, "plain", ""), "FOO picks 11\n")
    }
    rmdir_rec(dir)
}

let WIDE = "converter/tests/fixtures/p8_include_dirs"

// `WIDE`'s main file converted into `<dir>/<name>` under `sidecar` ("" for the fixture's own)
def wide_convert(dir, name, sidecar : string) : ConvertResult => <- convert(path_join(WIDE, "app/main.c"), path_join(dir, name), "linux", "", sidecar)

// `text` as the sidecar `<dir>/<name>.c2das`: its path
def written_sidecar(dir, name, text : string) : string {
    let path = path_join(dir, "{name}.c2das")
    fwrite(path, text)
    return path
}

[test]
def test_include_dirs(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_include_dirs", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    let lib_dir = get_full_file_name(path_join(WIDE, "lib"))
    let root = get_full_file_name(WIDE)
    t |> run("`include_dirs` reach both clang passes and `program_root` makes a sibling folder's C file and a `../` header the program's") @(t : T?) {
        let res <- wide_convert(dir, "wide", "")
        t |> equal(res.ok, true, res.error)
        has_wide_program(t, res.das_text)
        let native = native_run(default_clang(), ["-w", "-funsigned-char", "-I{lib_dir}"], path_join(WIDE, "app/main.c"), path_join(dir, "wide_native"), 60.0)
        t |> equal(native.built, true, native.output)
        var output : string
        let rc = run_tier(res.das_path, "interp", dir, output, CONVERTED_MODULES)
        t |> equal(output, native.output)
        t |> equal(output, "sum 7 scaled 70\n")
        t |> equal(rc, native.rc)
    }
    t |> run("absolute `include_dirs` and `program_root` are taken as they are") @(t : T?) {
        let side = written_sidecar(dir, "absolute", "\{\"include_dirs\": [\"{lib_dir}\"], \"program_root\": \"{root}\"\}\n")
        let res <- wide_convert(dir, "absolute", side)
        t |> equal(res.ok, true, res.error)
        has_wide_program(t, res.das_text)
    }
    t |> run("a C file an include folder reaches outside the program root is refused, naming the file and the root") @(t : T?) {
        let side = written_sidecar(dir, "narrow", "\{\"include_dirs\": [\"{lib_dir}\"]\}\n")
        let res <- wide_convert(dir, "narrow", side)
        t |> equal(res.ok, false, res.das_text)
        t |> success(res.error |> contains("{lib_dir}/lib.c is a C file outside the program root {get_full_file_name(path_join(WIDE, "app"))}/"), res.error)
    }
    t |> run("without `include_dirs` clang finds no `lib.c`, and the conversion fails with its error") @(t : T?) {
        let side = written_sidecar(dir, "no_includes", "\{\"program_root\": \"{root}\"\}\n")
        let res <- wide_convert(dir, "no_includes", side)
        t |> equal(res.ok, false, res.das_text)
        t |> success(res.error |> contains("'lib.c' file not found"), res.error)
    }
    t |> run("a main file outside `program_root` is refused, naming it") @(t : T?) {
        let side = written_sidecar(dir, "outside", "\{\"include_dirs\": [\"{lib_dir}\"], \"program_root\": \"{lib_dir}\"\}\n")
        let res <- wide_convert(dir, "outside", side)
        t |> equal(res.ok, false, res.das_text)
        t |> success(res.error |> contains("the main file {root}/app/main.c is no file of the program"), res.error)
    }
    t |> run("`include_files` reach both clang passes as `-include`, read before the main file") @(t : T?) {
        let at = path_join(dir, "forced")
        mkdir_rec(at)
        fwrite(path_join(at, "forced.h"), "struct forced \{ int v; \};\n#define FORCED_VALUE 17\n")
        fwrite(path_join(at, "forced.c"), "int main(void) \{ struct forced f; f.v = FORCED_VALUE; return f.v; \}\n")
        let side = written_sidecar(at, "forced", "\{\"include_files\": [\"forced.h\"]\}\n")
        let res <- convert(path_join(at, "forced.c"), path_join(at, "out"), "linux", "", side)
        t |> equal(res.ok, true, res.error)
        // the forced header is the program's: its constant keeps its name (`let private`)
        t |> success(res.das_text |> contains("let private FORCED_VALUE = 17\n"), res.das_text)
        t |> success(res.das_text |> contains("f.v = FORCED_VALUE\n"), res.das_text)
    }
    t |> run("a folder `CPATH` names holds the user's headers, never the system's: the program in it converts") @(t : T?) {
        // a child converter under `env CPATH=<root>`, so this process's environment stays as it was
        var argv <- ["env", "CPATH={root}"]
        argv |> push_from(daslang_cmd(CONVERTED_MODULES), ["converter/main.das", "--", path_join(WIDE, "app/main.c"), "--out", path_join(dir, "cpath"), "--target", "linux"])
        var out : string
        t |> equal(run_and_capture(argv, out, 300.0), 0, out)
        has_wide_program(t, fread(path_join(path_join(dir, "cpath"), "main.das")))
    }
    rmdir_rec(dir)
}

// the declarations of all three files of `WIDE` in one module's text
def has_wide_program(t : T?; text : string) {
    for (needle in ["struct pair \{", "def make_pair(", "def pair_sum(", "def c_main"]) {
        t |> success(text |> contains(needle), "missing `{needle}` in:\n{text}")
    }
}

// a function with a goto into a block and a switch beside the loops of a composed perf kernel:
// the planning of labels, which runs once per function under `unshadow_locals` too
let STACK_SOURCE = "int printf(const char *, ...);\nstatic volatile int n = 1000;\nstatic int sum;\nstatic void kernel_run(void) \{ sum = 0; for (int i = 0; i < n; i++) sum += i & 3; sum = sum / 375; \}\nstatic int pick(int k) \{\n    int r = 0;\n    if (k > 2) goto inner;\n    switch (k) \{ case 0: r = 5; break; case 1: r = 7; break; default: r = 9; \}\n    \{\n        r += 1;\n    inner:\n        r += k;\n    \}\n    return r;\n\}\nint main(void) \{\n    for (;;) \{\n        kernel_run();\n        if (sum >= 0 || n >= 1000000000) break;\n    \}\n    printf(\"%d %d\\n\", sum, pick(3));\n    return 0;\n\}\n"

// the bytes of das's default 16 KiB context stack a conversion leaves free: a test that runs the
// converter in its own process without `options stack` (`compare/tests/test_perf_compare.das`)
// overflows once the converter's deepest frames reach within this many bytes of the stack's end
let STACK_SPARE = 4096

// `c_path` converted with `STACK_SPARE` bytes of the stack taken by this frame before the converter's
def private convert_with_spare(c_path, out_dir : string) : string {
    var spare : uint8[STACK_SPARE]
    spare[0] = 1u8
    let converted <- convert(c_path, out_dir, "linux")
    return converted.ok ? "" : converted.error
}

// the two-file `STACK_SOURCE` under `dir`, its kernel and switch in a unit of their own, converted
// in the source layout (`emit_program`) with `STACK_SPARE` bytes of the stack taken by this frame
def private convert_program_with_spare(dir : string) : string {
    var spare : uint8[STACK_SPARE]
    spare[0] = 1u8
    var inscope parts <- split(STACK_SOURCE, "int main(void) \{")
    let lib_path = path_join(dir, "stack_lib.c")
    let main_path = path_join(dir, "stack_main.c")
    fwrite(lib_path, replace(parts[0], "static ", ""))
    fwrite(main_path, "int printf(const char *, ...);\nextern volatile int n;\nextern int sum;\nvoid kernel_run(void);\nint pick(int k);\nint main(void) \{" + parts[1])
    let converted <- convert_program([lib_path, main_path], path_join(dir, "program"), "linux", "", "", "", "", "main", "source")
    return converted.ok ? "" : converted.error
}

[test]
def test_default_stack(t : T?) {
    t |> run("a program with labels and a switch converts in das's default stack with STACK_SPARE bytes to spare") @(t : T?) {
        let dir = test_temp_dir()
        let c_path = path_join(dir, "stack.c")
        fwrite(c_path, STACK_SOURCE)
        t |> equal(convert_with_spare(c_path, path_join(dir, "out")), "")
    }
    t |> run("the same program in two files converts in the source layout with STACK_SPARE bytes to spare") @(t : T?) {
        t |> equal(convert_program_with_spare(test_temp_dir()), "")
    }
}
