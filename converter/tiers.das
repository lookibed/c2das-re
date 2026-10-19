options gen2

module tiers public

require strings
require daslib/strings_boost
require daslib/fio
require pipeline

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

def private run_exe(das_path, work_dir : string; var output : string&; module_dirs : array<string>) : int {
    let exe = path_join(work_dir, file_stem(das_path) + "_exe")
    var cmd <- daslang_cmd(module_dirs)
    cmd |> push_from(["-exe", "{das_path}", "-output", "{exe}"])
    let rc = run(cmd, output)
    if (rc != 0) {
        return rc
    }
    let built = fexist(exe + ".exe") ? exe + ".exe" : exe
    return run(["{built}"], output)
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

def private run_aot(das_path, work_dir : string; var output : string&; module_dirs : array<string>) : int {
    let ctx_dir = path_join(work_dir, "ctx")
    mkdir_rec(ctx_dir)
    var cmd <- daslang_cmd(module_dirs)
    cmd |> push_from([get_das_root() + "/utils/aot/main.das", "--", "-ctx", "{das_path}", ctx_dir + "/"])
    let rc = run(cmd, output)
    if (rc != 0) {
        return rc
    }
    let prefix = ident_of(file_stem(das_path))
    let host = path_join(ctx_dir, "host.cpp")
    fopen(host, "wb") $(f) {
        if (f != null) {
            fwrite(f, "#include \"{base_name(das_path)}.h\"\nint main() \{\n    {prefix}_ctx * ctx = {prefix}_create();\n    if (!ctx) return 125;\n    const int rc = {prefix}_main(ctx);\n    {prefix}_destroy(ctx);\n    return rc;\n\}\n")
        }
    }
    let root = get_das_root()
    let bin = path_join(ctx_dir, prefix + "_aot")
    var link <- ["c++", "-std=gnu++17", "-O2", "-fno-rtti", "-fwrapv", "-fno-strict-aliasing", "-Wno-invalid-offsetof", "-DDAS_FUSION=2", "-DSIZE_OF_VOID_P=8", "-DDAS_NO_ASSERTIONS", "-DNDEBUG", "-I", "{ctx_dir}", "-I", root + "/include", "-I", root + "/3rdparty/fmt/include", "-I", root + "/build/include", "{host}", path_join(ctx_dir, base_name(das_path) + ".cpp")]
    link |> push_from(native_module_sources(module_dirs), [root + "/lib/liblibDaScript.a", root + "/lib/liblibDaScript_runtime.a", root + "/lib/liblibUriParser.a", "-lpthread", "-ldl", "-o", "{bin}"])
    let crc = run(link, output)
    if (crc != 0) {
        return crc
    }
    return run(["{bin}"], output)
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
    if (tier == "interp") {
        var cmd <- daslang_cmd(module_dirs)
        cmd |> push_from(flags, [das_path])
        return run(cmd, output, timeout)
    }
    if (tier == "jit") {
        var cmd <- daslang_cmd(module_dirs)
        cmd |> push_from(flags, ["-jit", das_path])
        return run(cmd, output, timeout)
    }
    if (tier == "exe") {
        return run_exe(das_path, work_dir, output, module_dirs)
    }
    if (tier == "aot") {
        return run_aot(das_path, work_dir, output, module_dirs)
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
    var res : NativeRun
    var args <- [compiler]
    args |> push_from(flags, ["-o", bin, c_path])
    if (run_and_capture(args, res.output, 120.0) != 0) {
        return res
    }
    res.built = true
    res.output = ""
    res.rc = run_and_capture([bin], res.output, timeout)
    remove(bin)
    return res
}

