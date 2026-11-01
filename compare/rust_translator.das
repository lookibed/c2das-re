options gen2

module rust_translator public

require strings
require daslib/strings_boost
require daslib/fio
require ../converter/cir.das
require ../converter/tiers.das

//! The Rust translator lookibed/c2das as a child process: where its binary is, the commit it was
//! built at, a translation of one C file or of a compilation database, and a run of the
//! translation's entry module under one execution tier (`compare/ARCHITECTURE.md`).

let DEFAULT_CHECKOUT = "/root/c2das"
let BINARY_IN_CHECKOUT = "target/release/c2dascript-transpile"
let BANNER = "c2dascript-transpile v"

//! One translation: `ok` when the translator exited 0 and at most one module defines `main`;
//! `error` what went wrong otherwise; `exit_code` the translator's (`popen_timed_out` past the
//! timeout, -1 when it did not run); `files` every `.das` and `.das.inc` under `out_dir`, sorted;
//! `entry` the module daslang runs, "" when no file defines `main`; `seconds` the translator's wall
//! time.
struct RustTranslation {
    ok : bool
    error : string
    exit_code : int
    files : array<string>
    entry : string
    out_dir : string
    seconds : float
}

//! The checkout the Rust translator builds in: `$C2DAS_RUST`, else `/root/c2das`.
def rust_checkout : string {
    let dir = get_env_variable("C2DAS_RUST")
    return empty(dir) ? DEFAULT_CHECKOUT : dir
}

//! The Rust translator's binary: `$C2DAS_RUST_BIN`, else the release build in `rust_checkout()`.
def rust_binary : string {
    let bin = get_env_variable("C2DAS_RUST_BIN")
    return empty(bin) ? path_join(rust_checkout(), BINARY_IN_CHECKOUT) : bin
}

//! Whether `rust_binary()` is a file; `reason` names what is wrong when it is not.
def rust_available(var reason : string&) : bool {
    let bin = rust_binary()
    if (!fexist(bin)) {
        reason = "no Rust translator at {bin}: run scripts/build_c2das_rust.sh"
        return false
    }
    if (stat(bin).is_dir) {
        reason = "{bin} is a folder, not the Rust translator"
        return false
    }
    reason = ""
    return true
}

//! The commit of the lookibed/c2das checkout holding `bin`, the stamp a capture carries; "" with
//! `reason` set when `bin` sits in no git work tree or in one that is not a c2das checkout.
def rust_version(bin : string; var reason : string&) : string {
    var top : string
    if (run_and_capture(["git", "-C", dir_name(bin), "rev-parse", "--show-toplevel"], top, 60.0) != 0) {
        reason = "{bin} is in no git checkout"
        return ""
    }
    let root = strip(top)
    if (!fexist(path_join(root, "c2dascript-transpile/Cargo.toml"))) {
        reason = "{root} is not a lookibed/c2das checkout"
        return ""
    }
    var head : string
    run_and_capture(["git", "-C", root, "rev-parse", "HEAD"], head, 60.0)
    reason = ""
    return strip(head)
}

// a line of `text` opens the definition of `main`, the `[export]` wrapper `--libc std` writes
[arch(at="ARCHITECTURE.md#entry")]
def private defines_main(text : string) : bool {
    for (ln in split(text, "\n")) {
        if (ln |> starts_with("def main(")) {
            return true
        }
    }
    return false
}

// a line the translator prints on stdout as it goes, before any diagnostic
def private is_progress(line : string) : bool => line |> starts_with("Transpiling ") || line |> starts_with("Reading ") || line |> starts_with("Wrote ")

// the translator's `translation failed:` line, else the first line that is neither its banner nor
// progress, else the exit code
[arch(at="ARCHITECTURE.md#command-line")]
def private first_diagnostic(text : string; exit_code : int) : string {
    var other = ""
    for (ln in split(text, "\n")) {
        let line = strip(ln)
        if (line |> starts_with("translation failed:")) {
            return line
        }
        if (empty(other) && !empty(line) && !(line |> starts_with(BANNER)) && !is_progress(line)) {
            other = line
        }
    }
    return empty(other) ? "exit {exit_code}" : other
}

// whether `dir` exists and holds anything
def private has_entries(dir : string) : bool {
    var found = false
    if (fexist(dir)) {
        dir(dir) $(name) {
            found = found || (name != "." && name != "..")
        }
    }
    return found
}

// the module daslang runs for `file`, the one holding the wrapper: itself, or the cluster module a
// fragment `<stem>.das.inc` belongs to, `<stem>.das`
[arch(at="ARCHITECTURE.md#entry")]
def private entry_of(file : string) : string => file |> ends_with(".das") ? file : slice(file, 0, length(file) - length(".inc"))

// `argv` run with `timeout` seconds into `out_dir`, which must be absent or empty, the written
// files collected
[arch(at="ARCHITECTURE.md#entry")]
def private translate(argv : array<string>; out_dir : string; timeout : float) : RustTranslation {
    var t = RustTranslation(out_dir = out_dir, exit_code = -1)
    if (has_entries(out_dir)) {
        t.error = "the output folder {out_dir} is not empty: translate into a fresh folder"
        return <- t
    }
    mkdir_rec(out_dir)
    let started = ref_time_ticks()
    var text : string
    t.exit_code = run_and_capture(argv, text, timeout)
    t.seconds = float(double(get_time_nsec(started)) / 1000000000.0lf)
    t.ok = t.exit_code == 0
    if (t.exit_code == popen_timed_out) {
        t.error = "timed out after {timeout} s"
    } elif (!t.ok) {
        t.error = first_diagnostic(text, t.exit_code)
    }
    dir_rec(out_dir) $(name, _is_dir) {
        if (name |> ends_with(".das") || name |> ends_with(".das.inc")) {
            t.files |> push(path_join(out_dir, name))
        }
    }
    sort(t.files)
    let mains <- [for (f in t.files); f; where defines_main(fread(f))]
    if (length(mains) > 1) {
        t.ok = false
        t.error = "more than one module defines main: {join(mains, ", ")}"
    } elif (length(mains) == 1) {
        t.entry = entry_of(mains[0])
    }
    return <- t
}

//! `c_path` translated as a whole program (`--libc std --strict`) into `out_dir`; `flags` go to
//! the translator, `clang_args` to clang.
[arch(at="ARCHITECTURE.md#command-line")]
def translate_file(bin, c_path, out_dir : string; flags : array<string>; clang_args : array<string>; timeout : float) : RustTranslation {
    var argv <- [bin, "--file", c_path, "--libc", "std", "--strict", "--output-dir", out_dir]
    argv |> push_from(flags, clang_args)
    return <- translate(argv, out_dir, timeout)
}

//! The compilation database `db_path` translated as one program in the source layout into
//! `out_dir`, the shared runtime prelude as the module `runtime_module`.
[arch(at="ARCHITECTURE.md#command-line")]
def translate_db(bin, db_path, out_dir, runtime_module : string; flags : array<string>; timeout : float) : RustTranslation {
    var argv <- [bin, db_path, "--libc", "std", "--strict", "--module-layout", "source", "--runtime-module", runtime_module, "--output-dir", out_dir]
    argv |> push_from(flags)
    return <- translate(argv, out_dir, timeout)
}

struct private CompileCommand {
    directory : string
    file : string
    arguments : array<string>
}

// the clang command line of one file: compile only, the defines, the object named by the stem
def private compile_arguments(c_path : string; defines : array<string>) : array<string> {
    var args <- ["clang", "-c", c_path]
    args |> push_from([for (d in defines); "-D{d}"], ["-o", file_stem(c_path) + ".o"])
    return <- args
}

//! A compilation database at `path`: one `clang -c <file> -D<define>... -o <stem>.o` command per
//! file of `c_paths`, run in `directory`.
def write_compile_commands(path : string; c_paths : array<string>; defines : array<string>; directory : string) {
    let commands <- [for (c_path in c_paths); CompileCommand(directory = directory, file = c_path, arguments <- compile_arguments(c_path, defines))]
    fwrite(path, sprint_json(commands, true))
}

//! The entry module of `t` run under `tier` with no module folders, `work` holding what `exe`
//! and `aot` build; the exit code, -1 when `t` has no entry to run. `output` is the run's text.
[arch(at="ARCHITECTURE.md#entry")]
def run_translation(t : RustTranslation; tier : string; work : string; var output : string&; timeout : float; program_args : array<string>) : int {
    let no_flags : array<string>
    return run_translation(t, tier, work, output, timeout, no_flags, program_args)
}

//! `flags` go to the interpreter and the JIT before the module (`-no-module-cache`).
[arch(at="ARCHITECTURE.md#entry")]
def run_translation(t : RustTranslation; tier : string; work : string; var output : string&; timeout : float; flags : array<string>; program_args : array<string>) : int {
    output = ""
    if (!t.ok) {
        output = "the translation failed: {t.error}\n"
        return -1
    }
    if (empty(t.entry)) {
        output = "the translation defines no main in {t.out_dir}\n"
        return -1
    }
    let no_modules : array<string>
    mkdir_rec(work)
    return run_tier(t.entry, tier, work, output, no_modules, timeout, flags, program_args)
}
