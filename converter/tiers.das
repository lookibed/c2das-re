options gen2

module tiers public

require strings
require daslib/strings_boost
require daslib/fio

//! Runs a converted module under one execution tier and returns the process exit code:
//! `interp` (the interpreter), `jit` (the LLVM JIT), `exe` (a native executable the JIT
//! links), `aot` (the C++ AOT context, a C host compiled against the static runtime).

let TIERS <- {"interp", "jit", "exe", "aot"}

def private daslang_bin : string {
    return get_das_root() + "/bin/daslang"
}

// the daslang invocation prefix: the binary plus one -load_module per module folder
def private daslang_cmd(module_dirs : array<string>) : array<string> {
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

def private file_stem(path : string) : string {
    let name = base_name(path)
    let dot = find(name, ".")
    return dot < 0 ? name : slice(name, 0, dot)
}

def private run(args : array<string>; var output : string&) : int {
    var out : string
    let rc = run_and_capture(args, out, 600.0)
    output = "{output}{out}"
    return rc
}

def private run_exe(das_path, work_dir : string; var output : string&) : int {
    let exe = path_join(work_dir, file_stem(das_path) + "_exe")
    let rc = run([daslang_bin(), "-exe", "{das_path}", "-output", "{exe}"], output)
    if (rc != 0) {
        return rc
    }
    let built = fexist(exe + ".exe") ? exe + ".exe" : exe
    return run(["{built}"], output)
}

def private run_aot(das_path, work_dir : string; var output : string&) : int {
    let ctx_dir = path_join(work_dir, "ctx")
    mkdir_rec(ctx_dir)
    let rc = run([daslang_bin(), get_das_root() + "/utils/aot/main.das", "--", "-ctx", "{das_path}", ctx_dir + "/"], output)
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
    let crc = run(["c++", "-std=gnu++17", "-O2", "-fno-rtti", "-fwrapv", "-fno-strict-aliasing", "-Wno-invalid-offsetof", "-DDAS_FUSION=2", "-DSIZE_OF_VOID_P=8", "-DDAS_NO_ASSERTIONS", "-DNDEBUG", "-I", "{ctx_dir}", "-I", root + "/include", "-I", root + "/3rdparty/fmt/include", "-I", root + "/build/include", "{host}", path_join(ctx_dir, base_name(das_path) + ".cpp"), root + "/lib/liblibDaScript.a", root + "/lib/liblibDaScript_runtime.a", root + "/lib/liblibUriParser.a", "-lpthread", "-ldl", "-o", "{bin}"], output)
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

def run_tier(das_path : string; tier : string; work_dir : string; var output : string&; module_dirs : array<string>) : int {
    if (tier == "interp") {
        var cmd <- daslang_cmd(module_dirs)
        cmd |> push(das_path)
        return run(cmd, output)
    }
    if (tier == "jit") {
        var cmd <- daslang_cmd(module_dirs)
        cmd |> push("-jit")
        cmd |> push(das_path)
        return run(cmd, output)
    }
    if (tier == "exe") {
        return run_exe(das_path, work_dir, output)
    }
    if (tier == "aot") {
        return run_aot(das_path, work_dir, output)
    }
    output += "unknown tier `{tier}`; one of interp, jit, exe, aot\n"
    return -1
}
