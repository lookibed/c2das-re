options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../vendor_runtime.das

//! `ports/vendor_runtime.das` over scratch c2das-re checkouts (git repositories holding the marker,
//! the runtime's folders with a module, a source and the files a copy leaves out) and over this
//! repository's own runtime.

let GIT_ID <- ["-c", "user.name=test", "-c", "user.email=test@example.invalid"]

let SCRATCH_FILES <- [
    "LICENSE", "c_runtime/.das_module", "c_runtime/c_runtime/printf.das", "dasCRuntime/.das_module",
    "dasCRuntime/CMakeLists.txt", "dasCRuntime/src/dasCRuntime.cpp", "dasCRuntime/src/dasCRuntime.h"
]

// what a scratch checkout holds beside the runtime's files: the marker, and the test, document,
// build-tree and built-module files the copy leaves out
let LEFT_OUT <- [
    "converter/main.das", "README.md", "c_runtime/tests/test_printf.das", "c_runtime/ARCHITECTURE.md",
    "c_runtime/.das_module.manifest", "dasCRuntime/_build/CMakeCache.txt",
    "dasCRuntime/dasModuleCRuntime.shared_module", "dasCRuntime/tests/test_crt.das"
]

var private scratch_count = 0

// a new empty folder under this run's temporary directory
def private scratch_dir(name : string) : string {
    let made = path_join(test_temp_dir(), "{name}_{scratch_count++}")
    mkdir_rec(made)
    return made
}

def private git(dir : string; argv : array<string>) : string {
    var full <- ["git", "-C", dir]
    full |> push_from(GIT_ID, argv)
    var out : string
    run_and_capture(full, out, 60.0)
    return strip(out)
}

def private write_file(root, file : string) {
    mkdir_rec(dir_name(path_join(root, file)))
    fwrite(path_join(root, file), "{file}\n")
}

// a folder holding `SCRATCH_FILES` and `LEFT_OUT`, each file's text its own path
def private scratch_tree(name : string) : string {
    let root = scratch_dir(name)
    for (file in SCRATCH_FILES) {
        write_file(root, file)
    }
    for (file in LEFT_OUT) {
        write_file(root, file)
    }
    return root
}

// `scratch_tree` as a git repository tracking every file of it
def private scratch_root(name : string) : string {
    let root = scratch_tree(name)
    git(root, ["init", "-q"])
    git(root, ["add", "-A"])
    return root
}

// `file` written under `root` and tracked
def private track(root, file : string) {
    write_file(root, file)
    git(root, ["add", file])
}

def private holds_no_file(folder : string) : bool {
    var files = 0
    dir_rec(folder) $(_name, is_dir) {
        if (!is_dir) {
            files++
        }
    }
    return files == 0
}

// `runtime_files` refuses `root` with `reason` in its error and names no file
def private refuses(t : T?; root, reason : string) {
    var error : string
    let files <- runtime_files(root, error)
    t |> success(empty(files), "files named beside the refusal `{error}`")
    t |> success(error |> contains(reason), "want `{reason}` in `{error}`")
}

[test]
def test_runtime_files(t : T?) {
    t |> run("the license, the descriptors, the build file, the modules and the sources; tests, documents, build trees and built modules stay out") @(t : T?) {
        var error : string
        t |> equal(runtime_files(scratch_root("files"), error), SCRATCH_FILES)
        t |> equal(error, "")
    }
    t |> run("a file git does not track stays out") @(t : T?) {
        let root = scratch_root("untracked")
        for (file in ["LICENSE.local", "c_runtime/c_runtime/local.das", "dasCRuntime/src/local.cpp", "dasCRuntime/src/local/deep.h"]) {
            write_file(root, file)
        }
        var error : string
        t |> equal(runtime_files(root, error), SCRATCH_FILES)
        t |> equal(error, "")
    }
    t |> run("a folder outside any git checkout is refused") @(t : T?) {
        refuses(t, scratch_tree("no_git"), "is no git checkout of c2das-re")
    }
    t |> run("a git checkout without the tracked marker is refused, whatever else it holds") @(t : T?) {
        let root = scratch_root("no_marker")
        git(root, ["rm", "-q", "--cached", "converter/main.das"])
        refuses(t, root, "is not the root of a c2das-re checkout")
    }
    t |> run("a fixed file git does not track is refused") @(t : T?) {
        let root = scratch_root("fixed_untracked")
        git(root, ["rm", "-q", "--cached", "dasCRuntime/CMakeLists.txt"])
        refuses(t, root, "git tracks no dasCRuntime/CMakeLists.txt")
    }
    t |> run("a tracked file gone from the working tree is refused") @(t : T?) {
        let root = scratch_root("gone")
        remove(path_join(root, "c_runtime/c_runtime/printf.das"))
        refuses(t, root, "c_runtime/c_runtime/printf.das is gone from the working tree")
    }
    t |> run("a source folder git tracks nothing under is refused") @(t : T?) {
        let root = scratch_root("no_sources")
        git(root, ["rm", "-q", "-r", "--cached", "dasCRuntime/src"])
        refuses(t, root, "git tracks no source under dasCRuntime/src/")
    }
    t |> run("a tracked subfolder of a source folder is refused") @(t : T?) {
        let root = scratch_root("subfolder")
        track(root, "dasCRuntime/src/detail/more.cpp")
        refuses(t, root, "dasCRuntime/src/detail/more.cpp is no .cpp or .h file of dasCRuntime/src/")
    }
    t |> run("a tracked file of another extension in a source folder is refused") @(t : T?) {
        let sources = scratch_root("extension_src")
        track(sources, "dasCRuntime/src/table.inc")
        refuses(t, sources, "dasCRuntime/src/table.inc is no .cpp or .h file of dasCRuntime/src/")
        let modules = scratch_root("extension_das")
        track(modules, "c_runtime/c_runtime/notes.txt")
        refuses(t, modules, "c_runtime/c_runtime/notes.txt is no .das file of c_runtime/c_runtime/")
    }
}

def private repository_files(t : T?) : array<string> {
    var error : string
    var files <- runtime_files(".", error)
    t |> equal(error, "")
    return <- files
}

[test]
def test_this_repository(t : T?) {
    t |> run("every module c_runtime's descriptor registers is copied") @(t : T?) {
        let files <- repository_files(t)
        let descriptor = fread("c_runtime/.das_module")
        let names_at = find(descriptor, "for (name in [")
        t |> success(names_at >= 0)
        let names = slice(descriptor, names_at + 14, find(descriptor, "]", names_at))
        var registered = 0
        for (quoted in split(names, ",")) {
            let name = strip(quoted) |> replace("\"", "")
            t |> success(has_value(files, "c_runtime/c_runtime/{name}.das"), "c_runtime registers {name}, the copy holds no {name}.das")
            registered++
        }
        t |> success(registered > 10)
    }
    t |> run("every source dasCRuntime's CMakeLists.txt builds is copied") @(t : T?) {
        let files <- repository_files(t)
        let cmake = fread("dasCRuntime/CMakeLists.txt")
        let library_at = find(cmake, "add_library(dasModuleCRuntime SHARED ")
        t |> success(library_at >= 0)
        var built = 0
        for (source in split(slice(cmake, library_at + 37, find(cmake, ")", library_at)), " ")) {
            t |> success(has_value(files, "dasCRuntime/{source}"), "CMakeLists.txt builds {source}, the copy holds no dasCRuntime/{source}")
            built++
        }
        t |> success(built > 0)
    }
    t |> run("every header a copied dasCRuntime source includes by a quoted name is copied, daScript's own aside") @(t : T?) {
        let files <- repository_files(t)
        var included = 0
        for (file in files) {
            if (!(file |> starts_with("dasCRuntime/src/"))) {
                continue
            }
            for (line in split(fread(file), "\n")) {
                if (!(line |> starts_with("#include \"")) || line |> starts_with("#include \"daScript/")) {
                    continue
                }
                let header = slice(line, 10, find(line, "\"", 10))
                t |> success(has_value(files, "dasCRuntime/src/{header}"), "{file} includes {header}, the copy holds no dasCRuntime/src/{header}")
                included++
            }
        }
        t |> success(included > 0)
    }
}

[test]
def test_vendor_runtime(t : T?) {
    t |> run("a copy writes each tracked runtime file as it is and stamps the commit") @(t : T?) {
        let root = scratch_root("copy")
        write_file(root, "c_runtime/c_runtime/local.das")
        let into = scratch_dir("into")
        var error : string
        t |> success(vendor_runtime(root, into, "abc v1", error), error)
        for (file in SCRATCH_FILES) {
            t |> equal(fread(path_join(into, file)), "{file}\n")
        }
        t |> equal(fread(path_join(into, RUNTIME_STAMP)), "abc v1\n")
        for (file in ["c_runtime/c_runtime/local.das", "c_runtime/tests/test_printf.das", "dasCRuntime/_build", "converter"]) {
            t |> success(!fexist(path_join(into, file)), "the copy holds {file}")
        }
    }
    t |> run("a runtime file the repository no longer has refuses the copy before it writes anything") @(t : T?) {
        let root = scratch_root("stale")
        let into = scratch_dir("into")
        write_file(into, "c_runtime/c_runtime/dropped.das")
        var error : string
        t |> success(!vendor_runtime(root, into, "abc v1", error))
        t |> success(error |> contains("c_runtime/c_runtime/dropped.das"), error)
        t |> success(!fexist(path_join(into, "c_runtime/c_runtime/printf.das")) && !fexist(path_join(into, RUNTIME_STAMP)))
    }
    t |> run("a runtime that is not whole refuses the copy before it writes anything") @(t : T?) {
        let root = scratch_root("not_whole")
        remove(path_join(root, "dasCRuntime/src/dasCRuntime.h"))
        let into = scratch_dir("into")
        var error : string
        t |> success(!vendor_runtime(root, into, "abc v1", error))
        t |> success(error |> contains("dasCRuntime/src/dasCRuntime.h is gone from the working tree"), error)
        t |> success(holds_no_file(into), "the refused copy wrote into {into}")
    }
    t |> run("a root that is no c2das-re checkout leaves a copied folder as it is and asks for no removal") @(t : T?) {
        let into = scratch_dir("into")
        var error : string
        t |> success(vendor_runtime(scratch_root("first"), into, "abc v1", error), error)
        let elsewhere = scratch_dir("elsewhere")
        write_file(elsewhere, "README.md")
        git(elsewhere, ["init", "-q"])
        git(elsewhere, ["add", "-A"])
        t |> success(!vendor_runtime(elsewhere, into, "def v2", error))
        t |> success(error |> contains("is not the root of a c2das-re checkout"), error)
        t |> success(!(error |> contains("remove")), error)
        for (file in SCRATCH_FILES) {
            t |> equal(fread(path_join(into, file)), "{file}\n")
        }
        t |> equal(fread(path_join(into, RUNTIME_STAMP)), "abc v1\n")
    }
    t |> run("a runtime file that cannot be written fails the copy, naming it") @(t : T?) {
        let into = scratch_dir("into")
        fwrite(path_join(into, "c_runtime"), "a file where the copy needs a folder\n")
        var error : string
        t |> success(!vendor_runtime(scratch_root("blocked"), into, "abc v1", error))
        t |> equal(error, "cannot write {path_join(into, "c_runtime/.das_module")}")
        t |> success(!fexist(path_join(into, RUNTIME_STAMP)))
    }
    t |> run("a stamp that cannot be written fails the copy, naming it") @(t : T?) {
        let into = scratch_dir("into")
        mkdir_rec(path_join(into, RUNTIME_STAMP))
        var error : string
        t |> success(!vendor_runtime(scratch_root("blocked_stamp"), into, "abc v1", error))
        t |> equal(error, "cannot write {path_join(into, RUNTIME_STAMP)}")
    }
}

[test]
def test_vendor_main(t : T?) {
    t |> run("a command line that is not `-- <into>` is a usage error and copies nothing") @(t : T?) {
        let root = scratch_root("usage")
        git(root, ["commit", "-q", "-m", "stand-in"])
        let into = scratch_dir("into")
        for (args in [["daslang", "vendor_runtime.das"], ["daslang", "vendor_runtime.das", "--"], ["daslang", "vendor_runtime.das", "--", into, into], ["daslang", "vendor_runtime.das", into]]) {
            t |> equal(vendor_main(root, args), 2)
        }
        t |> success(holds_no_file(into))
    }
    t |> run("a root git names no commit of is refused") @(t : T?) {
        let into = scratch_dir("into")
        t |> equal(vendor_main(scratch_tree("no_git"), ["daslang", "vendor_runtime.das", "--", into]), 1)
        t |> equal(vendor_main(scratch_root("no_commit"), ["daslang", "vendor_runtime.das", "--", into]), 1)
        t |> success(holds_no_file(into))
    }
    t |> run("a copy is stamped `<full sha> <git describe --tags --always --dirty>`") @(t : T?) {
        let root = scratch_root("stamped")
        git(root, ["commit", "-q", "-m", "stand-in"])
        git(root, ["tag", "v9.9.9"])
        let sha = git(root, ["rev-parse", "HEAD"])
        t |> equal(length(sha), 40)
        let into = scratch_dir("into")
        t |> equal(vendor_main(root, ["daslang", "vendor_runtime.das", "--", into]), 0)
        t |> equal(fread(path_join(into, RUNTIME_STAMP)), "{sha} v9.9.9\n")
        fwrite(path_join(root, "c_runtime/c_runtime/printf.das"), "edited\n")
        t |> equal(vendor_main(root, ["daslang", "vendor_runtime.das", "--", into]), 0)
        t |> equal(fread(path_join(into, RUNTIME_STAMP)), "{sha} v9.9.9-dirty\n")
        t |> equal(fread(path_join(into, "c_runtime/c_runtime/printf.das")), "edited\n")
    }
    t |> run("a refused copy exits 1 and leaves the stamp") @(t : T?) {
        let root = scratch_root("refused")
        git(root, ["commit", "-q", "-m", "stand-in"])
        let into = scratch_dir("into")
        t |> equal(vendor_main(root, ["daslang", "vendor_runtime.das", "--", into]), 0)
        let stamp = fread(path_join(into, RUNTIME_STAMP))
        write_file(into, "dasCRuntime/src/dropped.cpp")
        git(root, ["commit", "-q", "--allow-empty", "-m", "later"])
        t |> equal(vendor_main(root, ["daslang", "vendor_runtime.das", "--", into]), 1)
        t |> equal(fread(path_join(into, RUNTIME_STAMP)), stamp)
    }
}
