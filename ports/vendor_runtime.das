options gen2

require strings
require daslib/strings_boost
require daslib/fio

//! The runtime a converted program runs on, copied out of the repository so a folder of converted
//! code runs without a c2das-re checkout: the `c_runtime` das modules and the sources of the native
//! `crt` module (`dasCRuntime/`), each with its module descriptor, under `<into>/c_runtime/` and
//! `<into>/dasCRuntime/`, and the commit they came from in `<into>/c2das-re.commit`. The copy builds
//! `crt` with cmake against any built daScript (`-DDASLANG_ROOT=`) and loads both folders with
//! `-load_module`. Run from the repository root:
//! `daslang ports/vendor_runtime.das -- <into>`.

//! the file `vendor_runtime` stamps with the commit the runtime came from
let RUNTIME_STAMP = "c2das-re.commit"

// the runtime's own folders and the files of each a copy takes: the c_runtime modules, dasCRuntime's
// C++ sources; tests, documents, build trees, built modules and daslang's manifests stay out
let private SOURCE_DIRS <- [("c_runtime/c_runtime", ".das"), ("dasCRuntime/src", ".cpp"), ("dasCRuntime/src", ".h")]
let private FIXED_FILES <- ["c_runtime/.das_module", "dasCRuntime/.das_module", "dasCRuntime/CMakeLists.txt"]

//! The runtime's files under `root`, relative to it and sorted: both module descriptors,
//! dasCRuntime's `CMakeLists.txt`, every `.das` of `c_runtime/c_runtime/` and every `.cpp` and `.h`
//! of `dasCRuntime/src/`.
def runtime_files(root : string) : array<string> {
    var files := FIXED_FILES
    for (source in SOURCE_DIRS) {
        dir(path_join(root, source._0)) $(name) {
            if (name |> ends_with(source._1)) {
                files |> push("{source._0}/{name}")
            }
        }
    }
    sort(files)
    return <- files
}

// the files under `into`'s runtime folders a copy of `files` would not write: a module dropped
// from the repository since the last copy
def private stale_files(into : string; files : array<string>) : array<string> {
    var stale : array<string>
    for (source in SOURCE_DIRS) {
        dir(path_join(into, source._0)) $(name) {
            let rel = "{source._0}/{name}"
            if (name |> ends_with(source._1) && !has_value(files, rel) && !has_value(stale, rel)) {
                stale |> push(rel)
            }
        }
    }
    return <- stale
}

//! Copies the runtime's files from `root` into `into`, then writes `stamp` into
//! `into/c2das-re.commit`. Refuses before the first write when `into` holds a runtime source file
//! the copy would not write (removing a file is left to the folder's owner), naming each in `error`.
def vendor_runtime(root, into, stamp : string; var error : string&) : bool {
    let files <- runtime_files(root)
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

// the commit of the repository at `root` as `<full sha> <git describe --tags --always --dirty>`
def private commit_stamp(root : string) : string {
    var sha, describe : string
    if (run_and_capture(["git", "-C", root, "rev-parse", "HEAD"], sha, 60.0) != 0 || run_and_capture(["git", "-C", root, "describe", "--tags", "--always", "--dirty"], describe, 60.0) != 0) {
        return ""
    }
    return "{strip(sha)} {strip(describe)}"
}

[export]
def main : int {
    let args <- get_command_line_arguments()
    let at = find_index(args, "--")
    if (at < 0 || at + 2 != length(args)) {
        to_log(LOG_ERROR, "usage: daslang ports/vendor_runtime.das -- <into>\n")
        return 2
    }
    let into = args[at + 1]
    let stamp = commit_stamp(".")
    if (empty(stamp)) {
        to_log(LOG_ERROR, "vendor_runtime: run it from a c2das-re checkout (git cannot name its commit)\n")
        return 1
    }
    var error : string
    if (!vendor_runtime(".", into, stamp, error)) {
        to_log(LOG_ERROR, "vendor_runtime: {error}\n")
        return 1
    }
    print("vendor_runtime: {length(runtime_files("."))} files into {into}, {stamp}\n")
    return 0
}
