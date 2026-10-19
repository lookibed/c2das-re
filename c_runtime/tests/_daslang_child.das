options gen2

module _daslang_child public

require daslib/fio
require strings
require dastest/testing_boost

//! A daslang child process for the c_runtime tests, with `c_runtime` and `dasCRuntime` loaded
//! (`probes/_daslang_child.das` is the bare twin the probes use).

//! The exit code and output of `daslang <source>`, or of `daslang -compile-only <source>`; the
//! source is written to a temporary file named after `name`.
def daslang_child(name, source : string; compile_only : bool) : tuple<rc : int; out : string> {
    let path = "{temp_directory_result() as value}/c2das_c_runtime_{name}.das"
    fopen(path, "wb") $(f) {
        fwrite(f, source)
    }
    var out : string
    let daslang = get_das_root() + "/bin/daslang"
    let rc = run_and_capture(compile_only ? [daslang, "-load_module", "dasCRuntime", "-load_module", "c_runtime", "-compile-only", path] : [daslang, "-load_module", "dasCRuntime", "-load_module", "c_runtime", path], out, 60.0)
    remove(path)
    return (rc, out)
}

//! A struct source a test compiles with its parts filled in: `ANNOTATION`, `KIND` (`struct` or
//! `class`), `FIELDS` and `AFTER` in `text`; the temporary file is named after `prefix`.
struct StructSource {
    prefix : string
    text : string
}

//! The compiler's verdict on `src` with the annotation, the fields, the declarations after the
//! struct and the keyword filled in.
def compile_struct(src : StructSource; name, annotation, fields, after, kind : string) : tuple<rc : int; out : string> {
    let source = src.text |> replace("ANNOTATION", annotation) |> replace("FIELDS", fields) |> replace("AFTER", after) |> replace("KIND", kind)
    return daslang_child("{src.prefix}_{name}", source, true)
}

//! A control: `src` so filled in is rejected and the compiler's message carries `needle`.
def struct_rejected(t : T?; src : StructSource; name, annotation, needle, fields, after, kind : string) {
    let r = compile_struct(src, name, annotation, fields, after, kind)
    t |> equal(r.rc != 0, true, "{name} compiled")
    t |> equal(r.out |> find(needle) >= 0, true, "{name}: {r.out}")
}
