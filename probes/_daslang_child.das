options gen2

module _daslang_child public

require daslib/fio
require strings
require daslib/strings_boost
require dastest/testing_boost

//! A daslang child process for the probes and the c_runtime tests: `daslang_run` writes a source
//! to a temporary file and runs it with the given modules loaded; the probes run bare
//! (`daslang_child`), the c_runtime tests with `dasCRuntime` and `c_runtime` (`runtime_child`).

//! The modules a c_runtime test's child loads.
let RUNTIME_MODULES = fixed_array("dasCRuntime", "c_runtime")

//! The exit code and output of `daslang -load_module <m>... <flags> <source>`; the source is
//! written to a temporary file named after `prefix` and `name`.
def daslang_run(name, source : string; flags : array<string>; modules : array<string>; prefix : string) : tuple<rc : int; out : string> {
    let no_args : array<string>
    return daslang_run(name, source, flags, modules, prefix, no_args)
}

//! The same with `args` after the source path (`utils/aot/main.das -- -ctx <in> <out>`).
def daslang_run(name, source : string; flags : array<string>; modules : array<string>; prefix : string; args_after : array<string>) : tuple<rc : int; out : string> {
    let path = "{temp_directory_result() as value}/{prefix}_{name}.das"
    fwrite(path, source)
    var out : string
    // the JIT reports itself at `info`; a run under it carries the line `jit_ran` reads
    let jit = flags |> has_value("-jit")
    let level = get_env_variable("DAS_LOG_LEVEL")
    if (jit) {
        set_env_variable("DAS_LOG_LEVEL", "info")
    }
    var args <- [get_das_root() + "/bin/daslang"]
    args |> reserve(2 + 2 * length(modules) + length(flags) + length(args_after))
    for (m in modules) {
        args |> push("-load_module")
        args |> push(m)
    }
    args |> push_from(flags)
    args |> push(path)
    args |> push_from(args_after)
    let rc = run_and_capture(args, out, 60.0)
    if (jit) {
        set_env_variable("DAS_LOG_LEVEL", level)
    }
    remove(path)
    return (rc, out)
}

def private compile_flags(compile_only : bool) : array<string> {
    var flags : array<string>
    if (compile_only) {
        flags |> push("-compile-only")
    }
    return <- flags
}

//! A bare child: `daslang <source>`, or `daslang -compile-only <source>`.
def daslang_child(name, source : string; compile_only : bool) : tuple<rc : int; out : string> =>
    daslang_run(name, source, compile_flags(compile_only), array<string>(), "c2das_probe")

//! A bare child under `flags`.
def daslang_child_flags(name, source : string; flags : array<string>) : tuple<rc : int; out : string> =>
    daslang_run(name, source, flags, array<string>(), "c2das_probe")

//! A child with `dasCRuntime` and `c_runtime` loaded.
def runtime_child(name, source : string; compile_only : bool) : tuple<rc : int; out : string> =>
    daslang_run(name, source, compile_flags(compile_only), [for (m in RUNTIME_MODULES); m], "c2das_c_runtime")

//! A child with `dasCRuntime` and `c_runtime` loaded, under `flags`.
def runtime_child_flags(name, source : string; flags : array<string>) : tuple<rc : int; out : string> =>
    daslang_run(name, source, flags, [for (m in RUNTIME_MODULES); m], "c2das_c_runtime")

//! The flags that run a child under the JIT, compiling afresh rather than from the DLL cache.
def jit_flags : array<string> => <- ["-jit", "-jit-no-cache"]

//! Whether a child's output shows the JIT compiled the program.
def jit_ran(out : string) : bool => find(out, "LLVM JIT:") >= 0

//! A child's output without the runtime's `info` lines.
def program_output(out : string) : string => join([for (ln in split(out, "\n")); ln; where !(ln |> starts_with("[I] "))], "\n")

//! A control: the child `r` was rejected and its output carries `needle`.
def child_rejects(t : T?; name : string; r : tuple<rc : int; out : string>; needle : string) {
    t |> equal(r.rc != 0, true, "{name} compiled")
    t |> equal(r.out |> find(needle) >= 0, true, "{name}: {r.out}")
}

//! A struct source a test compiles with its parts filled in: `ANNOTATION`, `KIND` (`struct` or
//! `class`), `FIELDS` and `AFTER` in `text`; the temporary file is named after `prefix`.
struct StructSource {
    prefix : string
    text : string
}

//! The compiler's verdict on `src` with the annotation, the fields, the declarations after the
//! struct and the keyword filled in, with the c_runtime modules loaded.
def compile_struct(src : StructSource; name, annotation, fields, after, kind : string) : tuple<rc : int; out : string> {
    let source = src.text |> replace("ANNOTATION", annotation) |> replace("FIELDS", fields) |> replace("AFTER", after) |> replace("KIND", kind)
    return runtime_child("{src.prefix}_{name}", source, true)
}

//! A control: `src` so filled in is rejected and the compiler's message carries `needle`.
def struct_rejected(t : T?; src : StructSource; name, annotation, needle, fields, after, kind : string) {
    child_rejects(t, name, compile_struct(src, name, annotation, fields, after, kind), needle)
}

//! The pinned clang for a child C program: the libclang archive's own binary when
//! `PATH_TO_LIBCLANG` is set (`scripts/env.sh`), else whatever `clang` is on PATH. The converter
//! has its own, `default_clang` in `converter/dumper_a.das`, which this folder does not require.
def battery_clang : string =>
    has_env_variable("PATH_TO_LIBCLANG") ? get_env_variable("PATH_TO_LIBCLANG") + "/bin/clang" : "clang"

//! The output of the C program `source`, built by the pinned clang with `-w` and `flags` and
//! run once: the native side of a byte-for-byte battery. A build failure returns the compiler's
//! text after `clang failed:`.
def native_battery(stem : string; flags : array<string>; source : string) : string {
    let dir = "{temp_directory_result() as value}"
    let c_path = "{dir}/{stem}.c"
    let bin = "{dir}/{stem}"
    fwrite(c_path, source)
    var args <- [battery_clang(), "-w"]
    args |> push_from(flags, ["-o", bin, c_path])
    var out : string
    let crc = run_and_capture(args, out, 120.0)
    remove(c_path)
    if (crc != 0) {
        return "clang failed:\n{out}"
    }
    var native : string
    run_and_capture([bin], native, 60.0)
    remove(bin)
    return native
}

//! A child with `dasCRuntime` and `c_runtime` loaded under the JIT (`tier` "jit") or built as an
//! executable (`tier` "exe", into `ir` with `_exe` after it), the module's LLVM IR written to `ir`
//! (`--jit-dump-to`, docs/probe-findings.md F82).
def runtime_child_ir(name, source, tier, ir : string) : tuple<rc : int; out : string> {
    var after <- tier == "jit" ? array<string>() : ["-output", "{ir}_exe"]
    after |> push_from(["--", "--jit-dump", "--jit-dump-to", ir])
    let flags <- tier == "jit" ? jit_flags() : ["-exe"]
    return daslang_run(name, source, flags, [for (m in RUNTIME_MODULES); m], "c2das_c_runtime", after)
}

//! The lines of the IR function the JIT compiled for the das function `name` of `arity` arguments.
def ir_function(dump, name : string; arity : int) : array<string> {
    var body : array<string>
    var inside = false
    for (l in split(dump, "\n")) {
        inside = inside || (l |> starts_with("define ") && l |> contains("`{name} {arity}`"))
        if (inside) {
            body |> push(l)
            if (l == "\}") {
                break
            }
        }
    }
    return <- body
}

//! The lines of an IR function that carry `needle`.
def ir_count(lines : array<string>; needle : string) : int => length([for (l in lines); l; where l |> contains(needle)])

//! The calls of an IR function but a null check's `jit_exception`.
def ir_calls(lines : array<string>) : int => length([for (l in lines); l; where l |> contains(" call ") && !(l |> contains("@jit_exception"))])

//! The volatile accesses of an IR function in order, `S` a store and `L` a load.
def ir_volatile_order(lines : array<string>) : string => join([for (l in lines); l |> contains("store volatile") ? "S" : "L"; where l |> contains(" volatile ")], "")
