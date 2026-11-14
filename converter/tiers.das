options gen2

module tiers public

require strings
require daslib/strings_boost
require daslib/fio
require cir
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

// `name` with every other character an underscore and a leading digit left bare, unlike cir's
// `ident_of`: the names the AOT and exe builds give their outputs
def private bare_ident_of(name : string) : string {
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

//! The binary the `exe` tier builds for `das_path` in `work_dir`: `<stem>_exe`.
def exe_binary(das_path, work_dir : string) : string => path_join(work_dir, file_stem(das_path) + "_exe")

// daslang's `-exe` build of `das_path` into `bin` under `flags`
def private exe_build_command(das_path, bin : string; module_dirs : array<string>; flags : array<string>) : array<string> {
    var cmd <- daslang_cmd(module_dirs)
    cmd |> push_from(flags, ["-exe", "{das_path}", "-output", "{bin}"])
    return <- cmd
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
def aot_binary(das_path, work_dir : string) : string => path_join(path_join(work_dir, "ctx"), bare_ident_of(file_stem(das_path)) + "_aot")

//! The AOT host's C++ source for the context of `das_path`: it hands its command line to the
//! runtime (`das::setCommandLineArguments`, as `daslang` and an `-exe` binary do), so the program
//! reads its arguments after `--` (`get_user_args`), then creates the context, runs `main` inside
//! the context's `runWithCatch` and returns its code; an unhandled exception prints `EXCEPTION:
//! <text>` on stderr and exits -2 (254), daslang's `DAS_PANIC_EXIT_CODE`, as `daslang` and an `-exe`
//! binary do, where it would otherwise trap.
def aot_host_source(das_path : string) : string {
    let prefix = bare_ident_of(file_stem(das_path))
    return build_string() $(var w) {
        w |> write("#include \"{base_name(das_path)}.h\"\n#include \"daScript/simulate/simulate.h\"\n#include <cstdio>\n")
        w |> write("namespace das \{ void setCommandLineArguments(int argc, char * argv[]); \}\n")
        w |> write("int main(int argc, char * argv[]) \{\n    das::setCommandLineArguments(argc, argv);\n")
        w |> write("    {prefix}_ctx * ctx = {prefix}_create();\n    if (!ctx) return 125;\n")
        // the generated context class derives from das::Context alone, so the handle is one
        w |> write("    das::Context * context = (das::Context *) ctx;\n    int rc = 0;\n")
        w |> write("    if (!context->runWithCatch([&]() \{ rc = {prefix}_main(ctx); \})) \{\n")
        w |> write("        const char * text = context->getException();\n")
        w |> write("        fprintf(stderr, \"EXCEPTION: %s\\n\", text ? text : \"unknown\");\n        return -2;\n    \}\n")
        w |> write("    {prefix}_destroy(ctx);\n    return rc;\n\}\n")
    }
}

// the context generation of `das_path` into `ctx_dir`
def private aot_context_command(das_path, ctx_dir : string; module_dirs : array<string>) : array<string> {
    var cmd <- daslang_cmd(module_dirs)
    cmd |> push_from([get_das_root() + "/utils/aot/main.das", "--", "-ctx", "{das_path}", ctx_dir + "/"])
    return <- cmd
}

// the AOT host of `das_path` beside its context in `ctx_dir`, one per stem
def private aot_host_path(das_path, ctx_dir : string) : string => path_join(ctx_dir, bare_ident_of(file_stem(das_path)) + "_host.cpp")

//! The binary `build_tier` builds or reuses: `rc` the build's exit code, 0 when `bin` holds the
//! binary, and `reused` true when an earlier build's binary stood and nothing was built.
struct TierBinary {
    rc : int
    bin : string
    reused : bool
}

//! The binary `tier`, `exe` or `aot`, builds for `das_path` in `work_dir`: `exe_binary` or `aot_binary`.
def tier_binary(das_path, tier, work_dir : string) : string => tier == "aot" ? aot_binary(das_path, work_dir) : exe_binary(das_path, work_dir)

// `line` with the word after `require` or `include` that opens it, "" for any other line
def private required_name(line, keyword : string) : string {
    let text = strip(line)
    if (!(text |> starts_with(keyword + " "))) {
        return ""
    }
    return split(strip(slice(text, length(keyword) + 1)), " ")[0]
}

// the das files the program of `das_path` is made of, `das_path` first: every file a `require` or
// `include` names that sits where the name resolves from the naming file's folder, followed in turn;
// a name resolving to no file (daslib, a module folder's, a native module) is not followed
def private program_files(das_path : string) : array<string> {
    var files <- [das_path]
    var seen <- {das_path}
    var i = 0
    while (i < length(files)) {
        let file = files[i]
        i++
        let dir = dir_name(file)
        for (line in split(fread(file), "\n")) {
            let required = required_name(line, "require")
            let included = required_name(line, "include")
            var path = ""
            if (!empty(required)) {
                path = path_join(dir, required |> ends_with(".das") ? required : required + ".das")
            } elif (!empty(included)) {
                path = path_join(dir, included)
            }
            if (!empty(path) && !seen |> key_exists(path) && stat(path).is_reg) {
                seen |> insert(path)
                files |> push(path)
            }
        }
    }
    return <- files
}

// the files of the module folder `dir` a build reads, sorted: every file but daslang's own
// `.das_module.manifest`, which loading the folder writes, and those of a hidden, `tests`, `build`
// or `_build` folder
def private module_files(dir : string; var files : array<string>) {
    var names : array<string>
    dir(dir) $(name) {
        if (name != "." && name != "..") {
            names |> push(name)
        }
    }
    sort(names)
    for (name in names) {
        let path = path_join(dir, name)
        if (!stat(path).is_dir) {
            if (name != ".das_module.manifest") {
                files |> push(path)
            }
        } elif (!(name |> starts_with(".")) && name != "tests" && name != "build" && name != "_build") {
            module_files(path, files)
        }
    }
}

// one key line per file: its path and size, then its mtime when `stamped`, else its text's hash
def private file_line(path : string; stamped : bool) : string {
    let st = stat(path)
    let mark = stamped ? "{st.mtime}" : "{hash(fread(path))}"
    return "{path} {int64(st.size)} {mark}"
}

// the daslang checkout a build runs under: its commit, and the size and mtime of its binary, its
// static libraries and its AOT generator, which a rebuild at the same commit changes
def private daslang_identity() : array<string> {
    let root = get_das_root()
    let head = strip(fread(root + "/.git/HEAD"))
    let ref = head |> starts_with("ref: ") ? root + "/.git/" + slice(head, 5) : ""
    var lines <- ["daslang {empty(ref) || !fexist(ref) ? head : strip(fread(ref))}"]
    lines |> push_from([for (file in ["bin/daslang", "lib/liblibDaScript.a", "lib/liblibDaScript_runtime.a", "lib/liblibUriParser.a", "utils/aot/main.das"]); file_line(path_join(root, file), true)])
    return <- lines
}

//! The inputs of the `exe` or `aot` build of `das_path` in `work_dir`, one per line: the tier, the
//! daslang checkout (its commit and its binaries), the build's commands (and the AOT host's text),
//! and every file of the program (`require` and `include` followed from `das_path`) and of
//! `module_dirs` with its size and its text's hash (a native library's mtime). Two builds with the
//! same key build the same binary.
def build_key(das_path, tier, work_dir : string; module_dirs : array<string>; flags : array<string>) : string {
    let bin = tier_binary(das_path, tier, work_dir)
    var lines <- ["tier {tier}"]
    lines |> push_from(daslang_identity())
    if (tier == "aot") {
        let ctx_dir = path_join(work_dir, "ctx")
        lines |> push("command {join(aot_context_command(das_path, ctx_dir, module_dirs), " ")}")
        lines |> push("command {join(aot_link_command(ctx_dir, das_path, aot_host_path(das_path, ctx_dir), bin, module_dirs), " ")}")
        lines |> push("host {hash(aot_host_source(das_path))}")
    } else {
        lines |> push("command {join(exe_build_command(das_path, bin, module_dirs, flags), " ")}")
    }
    lines |> push_from([for (file in program_files(das_path)); file_line(file, false)])
    var files : array<string>
    for (dir in module_dirs) {
        module_files(dir, files)
    }
    lines |> push_from([for (file in files); file_line(file, file |> ends_with(".shared_module") || file |> ends_with(".so"))])
    return join(lines, "\n") + "\n"
}

// the build of `bin`: the context generation and the host's compile under `aot`, daslang's `-exe`
// under `exe` with `flags`; each step gets `timeout` seconds, and its log joins `output` only when
// it fails
def private build_binary(das_path, tier, work_dir, bin : string; var output : string&; module_dirs : array<string>; timeout : float; flags : array<string>) : int {
    var steps : array<array<string>>
    if (tier == "aot") {
        let ctx_dir = path_join(work_dir, "ctx")
        mkdir_rec(ctx_dir)
        let host = aot_host_path(das_path, ctx_dir)
        fwrite(host, aot_host_source(das_path))
        steps |> emplace(aot_context_command(das_path, ctx_dir, module_dirs))
        steps |> emplace(aot_link_command(ctx_dir, das_path, host, bin, module_dirs))
    } else {
        mkdir_rec(work_dir)
        steps |> emplace(exe_build_command(das_path, bin, module_dirs, flags))
    }
    var log : string
    var rc = 0
    for (step in steps) {
        rc = run(step, log, timeout)
        break if (rc != 0)
        log = ""
    }
    output += log
    return rc
}

//! The `exe` or `aot` binary of `das_path` in `work_dir` (`tier_binary`), built with `module_dirs`
//! and, under `exe`, `flags`: the binary an earlier build left is reused while the key file beside
//! it (`<binary>.key`) holds this build's `build_key` and the binary's own size and mtime (a binary
//! replaced since is not the one the key describes), else the binary is removed, built again and
//! the key written once the build succeeds, so a failed build leaves neither. Each build step gets `timeout` seconds; its log joins `output` only
//! when it fails.
[arch(at="ARCHITECTURE_TIERS.md#build-reuse")]
def build_tier(das_path, tier, work_dir : string; var output : string&; module_dirs : array<string>; timeout : float; flags : array<string>) : TierBinary {
    let bin = tier_binary(das_path, tier, work_dir)
    let key_path = bin + ".key"
    let key = build_key(das_path, tier, work_dir, module_dirs, flags)
    if (stat(bin).is_reg && fexist(key_path) && fread(key_path) == key + file_line(bin, true)) {
        return TierBinary(bin = bin, reused = true)
    }
    remove(key_path)
    remove(bin)
    let rc = build_binary(das_path, tier, work_dir, bin, output, module_dirs, timeout, flags)
    if (rc == 0 && stat(bin).is_reg) {
        fwrite(key_path, key + file_line(bin, true))
    }
    return TierBinary(rc = rc, bin = bin)
}

//! The command line that runs the binary `bin` of `tier` with `program_args`: after the binary
//! under `exe`, after `--` under `aot` (the host's own command line), when there are any.
def binary_argv(tier, bin : string; program_args : array<string>) : array<string> {
    var argv <- [bin]
    if (!empty(program_args)) {
        if (tier == "aot") {
            argv |> push("--")
        }
        argv |> push_from(program_args)
    }
    return <- argv
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

//! `flags` go to the interpreter, the JIT and the exe build before the script (`-no-module-cache`).
def run_tier(das_path : string; tier : string; work_dir : string; var output : string&; module_dirs : array<string>; timeout : float; flags : array<string>) : int {
    let no_args : array<string>
    return run_tier(das_path, tier, work_dir, output, module_dirs, timeout, flags, no_args)
}

//! `program_args` are the converted program's own arguments, its C `argv` after the name: after
//! `--` under the interpreter, the JIT and `aot` (the host's own command line), after the binary
//! under `exe`. `timeout` bounds every process the tier starts: the run, and
//! under `exe` and `aot` each build step as well.
def run_tier(das_path : string; tier : string; work_dir : string; var output : string&; module_dirs : array<string>; timeout : float; flags : array<string>; program_args : array<string>) : int {
    let no_wrapper : array<string>
    return run_tier(das_path, tier, work_dir, output, module_dirs, timeout, flags, program_args, no_wrapper)
}

//! `wrapper` goes before the program's own command line wherever the program runs: the
//! interpreter's or the JIT's `daslang`, or the binary `exe` and `aot` build (perf's `guarded`
//! prefix, which keeps a crash from dumping core); the build steps run bare. `exe` and `aot` run
//! the binary `build_tier` builds or reuses; a failed build's exit code is returned.
def run_tier(das_path : string; tier : string; work_dir : string; var output : string&; module_dirs : array<string>; timeout : float; flags : array<string>; program_args : array<string>; wrapper : array<string>) : int {
    if (tier == "interp" || tier == "jit") {
        var cmd := wrapper
        cmd |> push_from(daslang_cmd(module_dirs), flags)
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
    if (tier == "exe" || tier == "aot") {
        let built = build_tier(das_path, tier, work_dir, output, module_dirs, timeout, flags)
        if (built.rc != 0) {
            return built.rc
        }
        var argv := wrapper
        argv |> push_from(binary_argv(tier, built.bin, program_args))
        return run(argv, output, timeout)
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
def native_run(compiler : string; flags : array<string>; c_path, bin : string; timeout : float; program_args : array<string>) : NativeRun =>
    native_run(compiler, flags, [c_path], bin, timeout, program_args)

//! `native_run` of a program of several C files, `c_paths` in link order.
def native_run(compiler : string; flags : array<string>; c_paths : array<string>; bin : string; timeout : float; program_args : array<string>) : NativeRun {
    var res : NativeRun
    var args <- [compiler]
    args |> push_from(flags, ["-o", bin], c_paths)
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

