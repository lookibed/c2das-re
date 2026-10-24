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
let CIR_SHA = "0fc98ecbfd57f8acb5f340ca4b934f85c84b624ec962c1262aaf488bb92e9bca"
let DAS_SHA = "1f238e3ca2636142b340de2cf454e45db460ae0136137498b4ce0ee0e59d5fc2"

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
        t |> equal(res.cir_text |> find("\"cir\": \"0.1\"") >= 0, true)
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
