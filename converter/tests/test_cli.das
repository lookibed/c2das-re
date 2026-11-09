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

let FIRST_MEMBER_FIXTURE = "converter/tests/fixtures/p7_first_member.c"

// `converter/main.das -- <FIRST_MEMBER_FIXTURE> --out <dir>/first_member_<mode> --target linux
// --first-member <mode>` as a child process
def run_first_member(dir, mode : string; var out : string&) : int {
    var argv <- daslang_cmd(CONVERTED_MODULES)
    argv |> push_from(["converter/main.das", "--", FIRST_MEMBER_FIXTURE, "--out", path_join(dir, "first_member_{mode}"), "--target", "linux", "--first-member", mode])
    return run_and_capture(argv, out, 300.0)
}

[test]
def test_cli_first_member(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_cli_first_member", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    t |> run("--first-member addr spells the address of a first member as addr(...), --first-member reinterpret as its record's pointer reinterpreted") @(t : T?) {
        var out : string
        t |> equal(run_first_member(dir, "addr", out), 0, out)
        let kept = fread(path_join(path_join(dir, "first_member_addr"), "p7_first_member.das"))
        t |> success(kept |> contains("    return addr((base + a).val)\n"), kept)
        t |> equal(run_first_member(dir, "reinterpret", out), 0, out)
        let reinterpreted = fread(path_join(path_join(dir, "first_member_reinterpret"), "p7_first_member.das"))
        t |> success(reinterpreted |> contains("    return reinterpret<TValue?>(base + a)\n"), reinterpreted)
    }
    t |> run("--first-member offset is a usage error before any conversion") @(t : T?) {
        var out : string
        t |> equal(run_first_member(dir, "offset", out), 2, out)
        t |> success(out |> contains("--first-member is addr or reinterpret, not `offset`"), out)
        t |> success(!fexist(path_join(path_join(dir, "first_member_offset"), "p7_first_member.das")), out)
    }
    rmdir_rec(dir)
}

let DISPATCH_FIXTURE = "converter/tests/fixtures/p7_goto_dispatch.c"

// `converter/main.das -- <DISPATCH_FIXTURE> --out <dir>/dispatch_<mode> --target linux
// --switch-dispatch <mode>` as a child process
def run_switch_dispatch(dir, mode : string; var out : string&) : int {
    var argv <- daslang_cmd(CONVERTED_MODULES)
    argv |> push_from(["converter/main.das", "--", DISPATCH_FIXTURE, "--out", path_join(dir, "dispatch_{mode}"), "--target", "linux", "--switch-dispatch", mode])
    return run_and_capture(argv, out, 300.0)
}

[test]
def test_cli_switch_dispatch(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_cli_switch_dispatch", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    t |> run("--switch-dispatch goto gives a dense switch its jump table; any other value but chain is a usage error") @(t : T?) {
        var out : string
        t |> equal(run_switch_dispatch(dir, "goto", out), 0, out)
        let jumped = fread(path_join(path_join(dir, "dispatch_goto"), "p7_goto_dispatch.das"))
        t |> success(jumped |> contains("            goto int(_cond) + 2\n"), jumped)
        // the option wins over the sidecar's key
        let sidecar = path_join(dir, "goto.c2das")
        fwrite(sidecar, "\{\"switch_dispatch\": \"goto\"\}\n")
        var argv <- daslang_cmd(CONVERTED_MODULES)
        argv |> push_from(["converter/main.das", "--", DISPATCH_FIXTURE, "--out", path_join(dir, "dispatch_over"), "--target", "linux", "--sidecar", sidecar, "--switch-dispatch", "chain"])
        t |> equal(run_and_capture(argv, out, 300.0), 0, out)
        let kept = fread(path_join(path_join(dir, "dispatch_over"), "p7_goto_dispatch.das"))
        t |> success(!(kept |> contains("goto _cond")) && !(kept |> contains("goto int(_cond")), kept)
        t |> equal(run_switch_dispatch(dir, "table", out), 2, out)
        t |> success(out |> contains("--switch-dispatch is chain or goto, not `table`"), out)
    }
    rmdir_rec(dir)
}

let PAST_END_FIXTURE = "converter/tests/fixtures/p7_end_index.c"

// `converter/main.das -- <PAST_END_FIXTURE> --out <dir>/past_end_<mode> --target linux
// --past-end <mode>`, with `sidecar` when given, as a child process
def run_past_end(dir, mode : string; var out : string&; sidecar : string = "") : int {
    var argv <- daslang_cmd(CONVERTED_MODULES)
    argv |> push_from(["converter/main.das", "--", PAST_END_FIXTURE, "--out", path_join(dir, "past_end_{mode}"), "--target", "linux", "--past-end", mode])
    if (!empty(sidecar)) {
        argv |> push_from(["--sidecar", sidecar])
    }
    return run_and_capture(argv, out, 300.0)
}

[test]
def test_cli_past_end(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_cli_past_end", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    t |> run("--past-end inline spells a plain-load `&a[k]` as the conditional, call wins over the sidecar's inline; any other value is a usage error") @(t : T?) {
        var out : string
        t |> equal(run_past_end(dir, "inline", out), 0, out)
        let inline = fread(path_join(path_join(dir, "past_end_inline"), "p7_end_index.das"))
        t |> success(inline |> contains("    return k == 4 ? addr(p7_end_index__a[0]) + 4 : addr(p7_end_index__a[k])\n"), inline)
        let sidecar = path_join(dir, "inline.c2das")
        fwrite(sidecar, "\{\"past_end\": \"inline\"\}\n")
        t |> equal(run_past_end(dir, "call", out, sidecar), 0, out)
        let kept = fread(path_join(path_join(dir, "past_end_call"), "p7_end_index.das"))
        t |> success(kept |> contains("    return addr(p7_end_index__a[0]) + end_index(k, 4)\n"), kept)
        t |> equal(run_past_end(dir, "fast", out), 2, out)
        t |> success(out |> contains("--past-end is call or inline, not `fast`"), out)
    }
    rmdir_rec(dir)
}

[test]
def test_cli_checks(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_cli_checks", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    t |> run("--checks off puts both annotations on the converted function; any other value but safe is a usage error; the help names the risk") @(t : T?) {
        var out : string
        var inscope argv <- daslang_cmd(CONVERTED_MODULES)
        argv |> push_from(["converter/main.das", "--", "converter/tests/fixtures/ret42.c", "--out", path_join(dir, "off"), "--target", "linux", "--checks", "off"])
        t |> equal(run_and_capture(argv, out, 300.0), 0, out)
        let text = fread(path_join(path_join(dir, "off"), "ret42.das"))
        t |> success(text |> contains("\n[unsafe_deref, hint(unsafe_range_check)]\ndef c_main : int \{\n"), text)
        var inscope refused <- daslang_cmd(CONVERTED_MODULES)
        refused |> push_from(["converter/main.das", "--", "converter/tests/fixtures/ret42.c", "--out", path_join(dir, "fast"), "--target", "linux", "--checks", "fast"])
        t |> equal(run_and_capture(refused, out, 300.0), 2, out)
        t |> success(out |> contains("--checks is safe or off, not `fast`"), out)
        t |> success(!fexist(path_join(path_join(dir, "fast"), "ret42.das")), out)
        var inscope help <- daslang_cmd(CONVERTED_MODULES)
        help |> push_from(["converter/main.das", "--", "-?"])
        t |> equal(run_and_capture(help, out, 300.0), 0, out)
        t |> success(out |> contains("a wrong C program then reads garbage or dies by SIGSEGV instead of panicking"), out)
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
    t |> run("--edge-census writes the census of the cycles beside the partition's report") @(t : T?) {
        var out : string
        var argv <- daslang_cmd(CONVERTED_MODULES)
        argv |> push_from(["converter/main.das", "--", "{LAYOUT_FIXTURE}/main.c", "{LAYOUT_FIXTURE}/a.c", "{LAYOUT_FIXTURE}/b.c", "--out", path_join(dir, "census"), "--target", "linux", "--edge-census"])
        t |> equal(run_and_capture(argv, out, 600.0), 0, out)
        t |> success(fread(path_join(dir, "census/program.edges.txt")) |> starts_with("today: clusters 1\n  2 nodes, 2 units: a b\n"), out)
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
def test_cli_solid_context(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_cli_solid", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    t |> run("a module carries `options solid_context` by default, none with --no-solid-context") @(t : T?) {
        for (opt_out in [false, true]) {
            let at = path_join(dir, opt_out ? "off" : "on")
            var out : string
            var inscope argv <- daslang_cmd(CONVERTED_MODULES)
            argv |> push_from(["converter/main.das", "--", "converter/tests/fixtures/ret42.c", "--out", at, "--target", "linux"])
            if (opt_out) {
                argv |> push("--no-solid-context")
            }
            t |> equal(run_and_capture(argv, out, 300.0), 0, out)
            let text = fread(path_join(at, "ret42.das"))
            t |> equal(text |> contains("\noptions solid_context\n"), !opt_out, text)
        }
    }
    rmdir_rec(dir)
}

[test]
def test_cli_inline_helpers(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_cli_inline_helpers", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    t |> run("a pure helper's call stays by default and is its expression with --inline-helpers, as with the sidecar's inline_helpers") @(t : T?) {
        let sidecar = path_join(dir, "inline.c2das")
        fwrite(sidecar, "\{\"inline_helpers\": true\}\n")
        for (how in ["default", "flag", "sidecar"]) {
            let at = path_join(dir, how)
            var out : string
            var inscope argv <- daslang_cmd(CONVERTED_MODULES)
            argv |> push_from(["converter/main.das", "--", "converter/tests/fixtures/p7_inline_helpers.c", "--out", at, "--target", "linux"])
            if (how == "flag") {
                argv |> push("--inline-helpers")
            } elif (how == "sidecar") {
                argv |> push_from(["--sidecar", sidecar])
            }
            t |> equal(run_and_capture(argv, out, 300.0), 0, out)
            let text = fread(path_join(at, "p7_inline_helpers.das"))
            let inlined = text |> contains("    buf[0] = uint8(i > 255 ? 255 : (i < 0 ? 0 : i))\n")
            t |> equal(inlined, how != "default", text)
            t |> equal(text |> contains("    buf[0] = p7_inline_helpers__clamp8(i)\n"), how == "default", text)
        }
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
