options gen2

module _daslang_child public

require daslib/fio

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
