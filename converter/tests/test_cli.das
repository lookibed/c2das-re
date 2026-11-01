options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../tiers.das
require ../dumper_a.das

let FIXTURE = "converter/tests/fixtures/p4_param_writes.c"
// the copy prologue of the stepped int parameter, absent in place
let COPY_NEEDLE = "def private p4_param_writes__count_down(n_in : int) : int \{\n    var n = n_in\n"

// `converter/main.das -- <FIXTURE> --out <dir>/<mode> --target linux --param-writes <mode>` as a
// child process; a fresh folder per mode, since a stale module cache can mask a change
def run_main(dir, mode : string; var out : string&) : int {
    var argv <- daslang_cmd(CONVERTED_MODULES)
    argv |> push_from(["converter/main.das", "--", FIXTURE, "--out", path_join(dir, mode), "--target", "linux", "--param-writes", mode])
    return run_and_capture(argv, out, 300.0)
}

def converted_text(dir, mode : string) : string => fread(path_join(path_join(dir, mode), "p4_param_writes.das"))

let ARGS_FIXTURE = "converter/tests/fixtures/p4_main_args.c"

// the arguments the `main(argc, argv)` fixture gets, an empty one and one with a space among them
let PROGRAM_ARGS = fixed_array("one", "two words", "")

// `converter/main.das -- <ARGS_FIXTURE> --out <dir>/<tier> --target linux --run <tier>` with one
// `--arg` per program argument, as a child process: its exit code and output
def run_with_args(dir, tier : string; var out : string&) : int {
    var argv <- daslang_cmd(CONVERTED_MODULES)
    argv |> push_from(["converter/main.das", "--", ARGS_FIXTURE, "--out", path_join(dir, tier), "--target", "linux", "--run", tier])
    argv |> reserve(length(argv) + 2 * length(PROGRAM_ARGS))
    for (a in PROGRAM_ARGS) {
        argv |> push("--arg")
        argv |> push(a)
    }
    return run_and_capture(argv, out, 300.0)
}

// the native build of the fixture by the pinned clang, run with the same arguments: its exit
// code and output
def native_with_args(dir : string; var out : string&) : int {
    let bin = path_join(dir, "p4_main_args_native")
    var build : string
    if (run_and_capture([default_clang(), "-w", "-funsigned-char", "-o", bin, ARGS_FIXTURE], build, 120.0) != 0) {
        out = build
        return -1
    }
    var argv <- [bin]
    argv |> push_from(PROGRAM_ARGS)
    return run_and_capture(argv, out, 60.0)
}

// the program's own lines of a `--run` child's output, without the converter's `[I]` lines
def program_lines(out : string) : string => join([for (ln in split(out, "\n")); ln; where !(ln |> starts_with("[I] "))], "\n")

[test]
def test_cli_param_writes(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_cli", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    t |> run("--param-writes copy opens a written parameter's body with its copy") @(t : T?) {
        var out : string
        t |> equal(run_main(dir, "copy", out), 0, out)
        let text = converted_text(dir, "copy")
        t |> success(text |> contains(COPY_NEEDLE), text)
    }
    t |> run("--param-writes in-place writes the parameter itself") @(t : T?) {
        var out : string
        t |> equal(run_main(dir, "in-place", out), 0, out)
        let text = converted_text(dir, "in-place")
        t |> success(text |> contains("def private p4_param_writes__count_down(var n : int) : int \{\n"), text)
        t |> success(!(text |> contains("n_in")), text)
    }
    t |> run("--param-writes local is a usage error before any conversion") @(t : T?) {
        var out : string
        t |> equal(run_main(dir, "local", out), 2, out)
        t |> success(out |> contains("--param-writes is in-place or copy, not `local`"), out)
        t |> success(!fexist(path_join(path_join(dir, "local"), "p4_param_writes.das")), out)
    }
    rmdir_rec(dir)
}

let LOOPS_FIXTURE = "converter/tests/fixtures/p7_loops.c"

// `converter/main.das -- <LOOPS_FIXTURE> --out <dir>/loops_<mode> --target linux --loops <mode>`
// as a child process
def run_loops(dir, mode : string; var out : string&) : int {
    var argv <- daslang_cmd(CONVERTED_MODULES)
    argv |> push_from(["converter/main.das", "--", LOOPS_FIXTURE, "--out", path_join(dir, "loops_{mode}"), "--target", "linux", "--loops", mode])
    return run_and_capture(argv, out, 300.0)
}

[test]
def test_cli_loops(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_cli_loops", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    t |> run("--loops range spells a canonical counting loop as a range loop, --loops while as the while form") @(t : T?) {
        var out : string
        t |> equal(run_loops(dir, "range", out), 0, out)
        let ranged = fread(path_join(path_join(dir, "loops_range"), "p7_loops.das"))
        t |> success(ranged |> contains("    for (i in range(n)) \{\n"), ranged)
        t |> equal(run_loops(dir, "while", out), 0, out)
        let kept = fread(path_join(path_join(dir, "loops_while"), "p7_loops.das"))
        t |> success(!(kept |> contains("    for (i in range(n)) \{\n")), kept)
        t |> success(kept |> contains("        var i : int = 0\n        while (i < n) \{\n"), kept)
    }
    t |> run("--loops for is a usage error before any conversion") @(t : T?) {
        var out : string
        t |> equal(run_loops(dir, "for", out), 2, out)
        t |> success(out |> contains("--loops is range or while, not `for`"), out)
        t |> success(!fexist(path_join(path_join(dir, "loops_for"), "p7_loops.das")), out)
    }
    rmdir_rec(dir)
}

let LAYOUT_FIXTURE = "converter/tests/fixtures/p5_layout_cut"

// `converter/main.das -- <LAYOUT_FIXTURE>/{main,a,b}.c --out <dir>/layout_<mode> --target linux
// --layout <mode>` as a child process
def run_layout(dir, mode : string; var out : string&) : int {
    var argv <- daslang_cmd(CONVERTED_MODULES)
    argv |> push_from(["converter/main.das", "--", "{LAYOUT_FIXTURE}/main.c", "{LAYOUT_FIXTURE}/a.c", "{LAYOUT_FIXTURE}/b.c", "--out", path_join(dir, "layout_{mode}"), "--target", "linux", "--layout", mode])
    return run_and_capture(argv, out, 600.0)
}

[test]
def test_cli_layout(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_cli_layout", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    t |> run("--layout source-cut cuts the cycle through the link module, --layout source keeps it one module, --layout single writes one module") @(t : T?) {
        var out : string
        t |> equal(run_layout(dir, "source-cut", out), 0, out)
        t |> success(fexist(path_join(dir, "layout_source-cut/a.das")) && fexist(path_join(dir, "layout_source-cut/main_link.das")), out)
        t |> equal(run_layout(dir, "source", out), 0, out)
        t |> success(fexist(path_join(dir, "layout_source/a_cluster.das")) && !fexist(path_join(dir, "layout_source/main_link.das")), out)
        t |> equal(run_layout(dir, "single", out), 0, out)
        t |> success(fexist(path_join(dir, "layout_single/main.das")) && !fexist(path_join(dir, "layout_single/a.das")), out)
    }
    t |> run("--layout flat, and the old name scc, are a usage error before any conversion") @(t : T?) {
        var out : string
        t |> equal(run_layout(dir, "flat", out), 2, out)
        t |> success(out |> contains("--layout is source, source-cut or single, not `flat`"), out)
        t |> success(!fexist(path_join(dir, "layout_flat")), out)
        t |> equal(run_layout(dir, "scc", out), 2, out)
        t |> success(out |> contains("--layout is source, source-cut or single, not `scc`"), out)
    }
    rmdir_rec(dir)
}

[test]
def test_cli_program_args(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_cli_args", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    var native : string
    let native_rc = native_with_args(dir, native)
    t |> equal(native_rc, 4, native)
    t |> run("--arg reaches the C argv under the interpreter as the native build's arguments do") @(t : T?) {
        var out : string
        t |> equal(run_with_args(dir, "interp", out), native_rc, out)
        t |> equal(program_lines(out), native, out)
    }
    t |> run("--arg reaches the C argv under the JIT, after its `--`") @(t : T?) {
        var out : string
        t |> equal(run_with_args(dir, "jit", out), native_rc, out)
        t |> equal(program_lines(out), native, out)
    }
    t |> run("--arg reaches the C argv of the exe tier's binary") @(t : T?) {
        var out : string
        t |> equal(run_with_args(dir, "exe", out), native_rc, out)
        t |> success(out |> contains("argv[2] = 'two words' 9\nargv[3] = '' 0\nend 1\n"), out)
    }
    t |> run("--arg reaches the C argv of the aot tier's host, after its `--`") @(t : T?) {
        var out : string
        t |> equal(run_with_args(dir, "aot", out), native_rc, out)
        t |> success(out |> contains("argc 4 name 1\nargv[1] = 'one' 3\nargv[2] = 'two words' 9\nargv[3] = '' 0\nend 1\nwritten Xne\n"), out)
    }
    rmdir_rec(dir)
}
