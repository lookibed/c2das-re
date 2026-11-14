options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../vendor_runtime.das

//! `ports/vendor_runtime.das` over a scratch c2das-re root (the runtime's folders with a module, a
//! source and the files a copy leaves out) and over this repository's own runtime.

// a scratch root holding a runtime with one c_runtime module and one dasCRuntime source, and the
// test, document, build-tree and built-module files the copy leaves out; "" when no temporary
// directory could be made
def private scratch_root(name : string) : string {
    var dir_error : string
    let root = create_temp_directory(name, dir_error)
    if (!empty(dir_error)) {
        return ""
    }
    for (folder in ["c_runtime/c_runtime", "c_runtime/tests", "dasCRuntime/src", "dasCRuntime/_build", "dasCRuntime/tests"]) {
        mkdir_rec(path_join(root, folder))
    }
    for (file in ["LICENSE", "README.md", "c_runtime/.das_module", "c_runtime/c_runtime/printf.das", "c_runtime/c_runtime/notes.txt", "c_runtime/tests/test_printf.das", "c_runtime/ARCHITECTURE.md", "c_runtime/.das_module.manifest", "dasCRuntime/.das_module", "dasCRuntime/CMakeLists.txt", "dasCRuntime/src/dasCRuntime.cpp", "dasCRuntime/src/dasCRuntime.h", "dasCRuntime/_build/CMakeCache.txt", "dasCRuntime/dasModuleCRuntime.shared_module", "dasCRuntime/tests/test_crt.das"]) {
        fwrite(path_join(root, file), "{file}\n")
    }
    return root
}

let SCRATCH_FILES <- ["LICENSE", "c_runtime/.das_module", "c_runtime/c_runtime/printf.das", "dasCRuntime/.das_module", "dasCRuntime/CMakeLists.txt", "dasCRuntime/src/dasCRuntime.cpp", "dasCRuntime/src/dasCRuntime.h"]

[test]
def test_runtime_files(t : T?) {
    t |> run("the license, the descriptors, the build file, the modules and the sources; tests, documents, build trees and built modules stay out") @(t : T?) {
        let root = scratch_root("vendor_files")
        t |> success(!empty(root))
        t |> equal(runtime_files(root), SCRATCH_FILES)
        rmdir_rec(root)
    }
    t |> run("this repository's runtime: every module its descriptor registers") @(t : T?) {
        let files <- runtime_files(".")
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
}

[test]
def test_vendor_runtime(t : T?) {
    t |> run("a copy writes each runtime file as it is and stamps the commit") @(t : T?) {
        let root = scratch_root("vendor_root")
        var dir_error : string
        let into = create_temp_directory("vendor_into", dir_error)
        var error : string
        t |> success(vendor_runtime(root, into, "abc v1", error), error)
        for (file in SCRATCH_FILES) {
            t |> equal(fread(path_join(into, file)), "{file}\n")
        }
        t |> equal(fread(path_join(into, RUNTIME_STAMP)), "abc v1\n")
        t |> success(!fexist(path_join(into, "c_runtime/tests/test_printf.das")) && !fexist(path_join(into, "dasCRuntime/_build")))
        rmdir_rec(root)
        rmdir_rec(into)
    }
    t |> run("a runtime file the repository no longer has refuses the copy before it writes anything") @(t : T?) {
        let root = scratch_root("vendor_root")
        var dir_error : string
        let into = create_temp_directory("vendor_into", dir_error)
        mkdir_rec(path_join(into, "c_runtime/c_runtime"))
        fwrite(path_join(into, "c_runtime/c_runtime/dropped.das"), "old\n")
        var error : string
        t |> success(!vendor_runtime(root, into, "abc v1", error))
        t |> success(error |> contains("c_runtime/c_runtime/dropped.das"), error)
        t |> success(!fexist(path_join(into, "c_runtime/c_runtime/printf.das")) && !fexist(path_join(into, RUNTIME_STAMP)))
        rmdir_rec(root)
        rmdir_rec(into)
    }
}
