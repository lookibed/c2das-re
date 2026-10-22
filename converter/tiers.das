options gen2

module tiers public

require strings
require daslib/strings_boost
require daslib/fio
require pipeline
require dumper_a

//! Runs a converted module under one execution tier and returns the process exit code:
//! `interp` (the interpreter), `jit` (the LLVM JIT), `exe` (a native executable the JIT
//! links), `aot` (the C++ AOT context, a C host compiled against the static runtime).

let TIERS <- {"interp", "jit", "exe", "aot"}

//! The module folders a converted program requires, as `-load_module` takes them from the
//! repository root.
let CONVERTED_MODULES <- ["c_runtime", "dasCRuntime"]

def private daslang_bin : string => get_das_root() + "/bin/daslang"

//! The daslang invocation prefix: the binary plus one `-load_module` per module folder.
def daslang_cmd(module_dirs : array<string>) : array<string> {
    var cmd <- [daslang_bin()]
    cmd |> reserve(1 + 2 * length(module_dirs) + 2)
    for (dir in module_dirs) {
        cmd |> push("-load_module")
        cmd |> push(dir)
    }
    return <- cmd
}

def private ident_of(name : string) : string {
    return build_string() $(var w) {
        for (ch in name) {
            w |> write(is_alnum(ch) ? to_char(ch) : "_")
        }
    }
}

def private run(args : array<string>; var output : string&; timeout : float = 600.0) : int {
    var out : string
    let rc = run_and_capture(args, out, timeout)
    output = "{output}{out}"
    return rc
}

// the build and the run each get `timeout` seconds
def private run_exe(das_path, work_dir : string; var output : string&; module_dirs : array<string>; program_args : array<string>; timeout : float) : int {
    let exe = path_join(work_dir, file_stem(das_path) + "_exe")
    var cmd <- daslang_cmd(module_dirs)
    cmd |> push_from(["-exe", "{das_path}", "-output", "{exe}"])
    let rc = run(cmd, output, timeout)
    if (rc != 0) {
        return rc
    }
    let built = fexist(exe + ".exe") ? exe + ".exe" : exe
    var bin <- ["{built}"]
    bin |> push_from(program_args)
    return run(bin, output, timeout)
}

// a native module folder (one holding src/*.cpp) joins the AOT host's compile: the generated
// context declares the module and includes its header, so the sources link in statically
def private native_module_sources(module_dirs : array<string>) : array<string> {
    var args : array<string>
    for (dir in module_dirs) {
        let src = path_join(dir, "src")
        if (!stat(src).is_dir) {
            continue
        }
        args |> push("-I")
        args |> push(src)
        dir(src) $(name) {
            if (name |> ends_with(".cpp")) {
                args |> push(path_join(src, name))
            }
        }
    }
    return <- args
}

//! The AOT host's compile and link command: `host` and the context generated in `ctx_dir` for
//! `das_path`, the module folders' native sources, the static runtime, out to `bin`.
def aot_link_command(ctx_dir, das_path, host, bin : string; module_dirs : array<string>) : array<string> {
    let root = get_das_root()
    // clang++ -O3 like the native perf lane, so the two lanes differ only in the program (perf/ARCHITECTURE.md section 2)
    var link <- [default_clang() + "++", "-std=gnu++17", "-O3", "-fno-rtti", "-fwrapv", "-fno-strict-aliasing", "-Wno-invalid-offsetof", "-DDAS_FUSION=2", "-DSIZE_OF_VOID_P=8", "-DDAS_NO_ASSERTIONS", "-DNDEBUG", "-I", "{ctx_dir}", "-I", root + "/include", "-I", root + "/3rdparty/fmt/include", "-I", root + "/build/include", "{host}", path_join(ctx_dir, base_name(das_path) + ".cpp")]
    link |> push_from(native_module_sources(module_dirs), [root + "/lib/liblibDaScript.a", root + "/lib/liblibDaScript_runtime.a", root + "/lib/liblibUriParser.a", "-lpthread", "-ldl", "-o", "{bin}"])
    return <- link
}

//! The binary the `aot` tier builds for `das_path` in `work_dir`: `ctx/<stem>_aot`, the stem
//! spelled as the context's C++ prefix.
def aot_binary(das_path, work_dir : string) : string => path_join(path_join(work_dir, "ctx"), ident_of(file_stem(das_path)) + "_aot")

// the context generation, the host's build and the run each get `timeout` seconds
def private run_aot(das_path, work_dir : string; var output : string&; module_dirs : array<string>; timeout : float) : int {
    let ctx_dir = path_join(work_dir, "ctx")
    mkdir_rec(ctx_dir)
    var cmd <- daslang_cmd(module_dirs)
    cmd |> push_from([get_das_root() + "/utils/aot/main.das", "--", "-ctx", "{das_path}", ctx_dir + "/"])
    let rc = run(cmd, output, timeout)
    if (rc != 0) {
        return rc
    }
    let prefix = ident_of(file_stem(das_path))
    let host = path_join(ctx_dir, "host.cpp")
    fwrite(host, "#include \"{base_name(das_path)}.h\"\nint main() \{\n    {prefix}_ctx * ctx = {prefix}_create();\n    if (!ctx) return 125;\n    const int rc = {prefix}_main(ctx);\n    {prefix}_destroy(ctx);\n    return rc;\n\}\n")
    let bin = aot_binary(das_path, work_dir)
    let crc = run(aot_link_command(ctx_dir, das_path, host, bin, module_dirs), output, timeout)
    if (crc != 0) {
        return crc
    }
    return run(["{bin}"], output, timeout)
}

//! `module_dirs` are the module folders the converted program requires, each passed as
//! `-load_module` to the interpreter and the JIT.
def run_tier(das_path : string; tier : string; work_dir : string; var output : string&) : int {
    let no_modules : array<string>
    return run_tier(das_path, tier, work_dir, output, no_modules)
}

def run_tier(das_path : string; tier : string; work_dir : string; var output : string&; module_dirs : array<string>; timeout : float = 600.0) : int {
    let no_flags : array<string>
    return run_tier(das_path, tier, work_dir, output, module_dirs, timeout, no_flags)
}

//! `flags` go to the interpreter and the JIT before the script (`-no-module-cache`).
def run_tier(das_path : string; tier : string; work_dir : string; var output : string&; module_dirs : array<string>; timeout : float; flags : array<string>) : int {
    let no_args : array<string>
    return run_tier(das_path, tier, work_dir, output, module_dirs, timeout, flags, no_args)
}

//! `program_args` are the converted program's own arguments, its C `argv` after the name: after
//! `--` under the interpreter and the JIT, after the binary under `exe`; the `aot` host passes
//! none, so the tier refuses them. `timeout` bounds every process the tier starts: the run, and
//! under `exe` and `aot` each build step as well.
def run_tier(das_path : string; tier : string; work_dir : string; var output : string&; module_dirs : array<string>; timeout : float; flags : array<string>; program_args : array<string>) : int {
    if (tier == "interp" || tier == "jit") {
        var cmd <- daslang_cmd(module_dirs)
        cmd |> push_from(flags)
        if (tier == "jit") {
            cmd |> push("-jit")
        }
        cmd |> push(das_path)
        if (!empty(program_args)) {
            cmd |> push("--")
            cmd |> push_from(program_args)
        }
        return run(cmd, output, timeout)
    }
    if (tier == "exe") {
        return run_exe(das_path, work_dir, output, module_dirs, program_args, timeout)
    }
    if (tier == "aot" && !empty(program_args)) {
        output += "the aot tier's host passes the program no arguments\n"
        return -1
    }
    if (tier == "aot") {
        return run_aot(das_path, work_dir, output, module_dirs, timeout)
    }
    output += "unknown tier `{tier}`; one of interp, jit, exe, aot\n"
    return -1
}

//! A C program built natively and run once: `built` false with the compiler's text in `output`,
//! else the run's exit code (`popen_timed_out` past `timeout`) and merged output.
struct NativeRun {
    built : bool
    rc : int
    output : string
}

//! `c_path` built by `compiler` with `flags` into `bin`, run with `timeout` seconds, the binary
//! removed afterwards: the native side of a differential test.
def native_run(compiler : string; flags : array<string>; c_path, bin : string; timeout : float) : NativeRun {
    let no_args : array<string>
    return native_run(compiler, flags, c_path, bin, timeout, no_args)
}

//! `native_run` with `program_args`, the program's C `argv` after its name.
def native_run(compiler : string; flags : array<string>; c_path, bin : string; timeout : float; program_args : array<string>) : NativeRun {
    var res : NativeRun
    var args <- [compiler]
    args |> push_from(flags, ["-o", bin, c_path])
    if (run_and_capture(args, res.output, 120.0) != 0) {
        return res
    }
    res.built = true
    res.output = ""
    var run_args <- [bin]
    run_args |> push_from(program_args)
    res.rc = run_and_capture(run_args, res.output, timeout)
    remove(bin)
    return res
}

