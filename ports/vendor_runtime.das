options gen2

require strings
require daslib/strings_boost
require daslib/fio

//! The runtime a converted program runs on, copied out of the repository so a folder of converted
//! code runs without a c2das-re checkout: the `c_runtime` das modules and the sources of the native
//! `crt` module (`dasCRuntime/`), each with its module descriptor, under `<into>/c_runtime/` and
//! `<into>/dasCRuntime/` under the repository's `LICENSE`, and the commit they came from in
//! `<into>/c2das-re.commit`. Only files git tracks are copied. The copy builds `crt` with cmake
//! against any built daScript (`-DDASLANG_ROOT=`) and loads both folders with `-load_module`. Run
//! from the repository root: `daslang ports/vendor_runtime.das -- <into>`.

//! the file `vendor_runtime` stamps with the commit the runtime came from
let RUNTIME_STAMP = "c2das-re.commit"

// a file git tracks at this path under the root of a c2das-re checkout and of no ports folder
let private ROOT_MARKER = "converter/main.das"

let private FIXED_FILES <- [
    "LICENSE", "c_runtime/.das_module", "dasCRuntime/.das_module", "dasCRuntime/.das_package",
    "dasCRuntime/CMakeLists.txt"
]

// a folder of runtime sources and the extensions of its files: the c_runtime modules, dasCRuntime's
// C++ sources; tests, documents, build trees, built modules and daslang's manifests lie outside
struct private SourceDir {
    folder : string
    extensions : array<string>
}

def private source_dirs : array<SourceDir> {
    return <- [
        SourceDir(folder = "c_runtime/c_runtime", extensions <- [".das"]),
        SourceDir(folder = "dasCRuntime/src", extensions <- [".cpp", ".h"])
    ]
}

def private is_source(source : SourceDir; name : string) : bool {
    for (extension in source.extensions) {
        if (name |> ends_with(extension)) {
            return true
        }
    }
    return false
}

// the paths git tracks under `root` among the marker, the fixed files and the source folders,
// relative to `root`; `error` when `root` is in no git checkout
def private tracked_files(root : string; var error : string&) : array<string> {
    var argv <- ["git", "-C", root, "-c", "core.quotePath=false", "ls-files", "--", ROOT_MARKER]
    argv |> push_from(FIXED_FILES, [for (source in source_dirs()); source.folder])
    var listing : string
    if (run_and_capture(argv, listing, 60.0) != 0) {
        error = "{root} is no git checkout of c2das-re (git ls-files: {strip(listing)})"
        return <- array<string>()
    }
    return <- split(strip(listing), "\n")
}

//! The runtime's files of the c2das-re checkout at `root`, relative to it and sorted: the
//! repository's `LICENSE` (MIT, the runtime's), both module descriptors, dasCRuntime's package,
//! `CMakeLists.txt`, every `.das` of `c_runtime/c_runtime/` and every `.cpp` and `.h` of
//! `dasCRuntime/src/`, each as git tracks it. Empty with `error` set when `root` is not the root of
//! a c2das-re checkout, when one of those files is untracked or gone from the working tree, when a
//! source folder tracks no file, or when one tracks a subfolder or a file of another extension.
def runtime_files(root : string; var error : string&) : array<string> {
    var files : array<string>
    let tracked <- tracked_files(root, error)
    if (!empty(error)) {
        return <- files
    }
    if (!has_value(tracked, ROOT_MARKER)) {
        error = "{root} is not the root of a c2das-re checkout (git tracks no {ROOT_MARKER} there): run it from the repository root; nothing is copied"
        return <- files
    }
    var problems : array<string>
    for (fixed in FIXED_FILES) {
        if (has_value(tracked, fixed)) {
            files |> push(fixed)
        } else {
            problems |> push("git tracks no {fixed}")
        }
    }
    for (source in source_dirs()) {
        var sources = 0
        for (rel in tracked) {
            if (!(rel |> starts_with("{source.folder}/"))) {
                continue
            }
            let name = slice(rel, length(source.folder) + 1)
            if (name |> contains("/") || !is_source(source, name)) {
                problems |> push("{rel} is no {join(source.extensions, " or ")} file of {source.folder}/, and the copy takes no other")
            } else {
                files |> push(rel)
                sources++
            }
        }
        if (sources == 0) {
            problems |> push("git tracks no source under {source.folder}/")
        }
    }
    for (rel in files) {
        if (!stat(path_join(root, rel)).is_reg) {
            problems |> push("{rel} is gone from the working tree")
        }
    }
    if (!empty(problems)) {
        error = "the runtime under {root} is not whole, nothing is copied: " + join(problems, "; ")
        files |> clear()
        return <- files
    }
    sort(files)
    return <- files
}

// the files under `into`'s runtime folders a copy of `files` would not write: a module dropped
// from the repository since the last copy
def private stale_files(into : string; files : array<string>) : array<string> {
    var stale : array<string>
    for (source in source_dirs()) {
        dir(path_join(into, source.folder)) $(name) {
            let rel = "{source.folder}/{name}"
            if (is_source(source, name) && !has_value(files, rel)) {
                stale |> push(rel)
            }
        }
    }
    sort(stale)
    return <- stale
}

//! Copies the runtime's files from the c2das-re checkout at `root` into `into`, then writes `stamp`
//! into `into/c2das-re.commit`. Refuses before the first write, with the reason in `error`, when
//! `runtime_files` refuses `root` or when `into` holds a runtime source file the copy would not
//! write (removing a file is left to the folder's owner).
def vendor_runtime(root, into, stamp : string; var error : string&) : bool {
    let files <- runtime_files(root, error)
    if (!empty(error)) {
        return false
    }
    let stale <- stale_files(into, files)
    if (!empty(stale)) {
        error = "{into} holds runtime files the repository no longer has; remove them first: " + join(stale, ", ")
        return false
    }
    for (rel in files) {
        let target = path_join(into, rel)
        mkdir_rec(dir_name(target))
        if (!fwrite(target, fread(path_join(root, rel)))) {
            error = "cannot write {target}"
            return false
        }
    }
    let stamp_path = path_join(into, RUNTIME_STAMP)
    if (!fwrite(stamp_path, "{stamp}\n")) {
        error = "cannot write {stamp_path}"
        return false
    }
    return true
}

// the commit of the repository at `root` as `<full sha> <git describe --tags --always --dirty>`,
// "" when git names none
def private commit_stamp(root : string) : string {
    var sha, describe : string
    if (run_and_capture(["git", "-C", root, "rev-parse", "HEAD"], sha, 60.0) != 0) {
        return ""
    }
    let described = run_and_capture(["git", "-C", root, "describe", "--tags", "--always", "--dirty"], describe, 60.0)
    return described == 0 ? "{strip(sha)} {strip(describe)}" : ""
}

//! `main` over the checkout at `root` and the process's arguments `args`: 0 after a copy, 2 on a
//! command line that is not `-- <into>`, 1 on a refusal.
def vendor_main(root : string; args : array<string>) : int {
    let at = find_index(args, "--")
    if (at < 0 || at + 2 != length(args)) {
        to_log(LOG_ERROR, "usage: daslang ports/vendor_runtime.das -- <into>\n")
        return 2
    }
    let into = args[at + 1]
    let stamp = commit_stamp(root)
    if (empty(stamp)) {
        to_log(LOG_ERROR, "vendor_runtime: run it from the root of a c2das-re checkout (git names no commit here); nothing is copied\n")
        return 1
    }
    var error : string
    if (!vendor_runtime(root, into, stamp, error)) {
        to_log(LOG_ERROR, "vendor_runtime: {error}\n")
        return 1
    }
    print("vendor_runtime: the runtime into {into}, {stamp}\n")
    return 0
}

[export]
def main : int {
    let args <- get_command_line_arguments()
    return vendor_main(".", args)
}
