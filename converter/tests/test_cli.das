options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../tiers.das

let FIXTURE = "converter/tests/fixtures/p4_param_writes.c"
// the copy prologue of the stepped int parameter, absent in place
let COPY_NEEDLE = "def private p4_param_writes__count_down(n_in : int) : int \{\n    var n = n_in\n"

// `converter/main.das -- <FIXTURE> --out <dir>/<mode> --target linux --param-writes <mode>` as a
// child process; a fresh folder per mode, since a stale module cache can mask a change
def run_main(dir, mode : string; var out : string&) : int {
    var argv <- daslang_cmd(CONVERTED_MODULES)
    argv |> push_from(["converter/main.das", "--", FIXTURE, "--out", path_join(dir, mode), "--target", "linux", "--param-writes", mode])
    return run_and_capture(argv, out, 300.0)
}

def converted_text(dir, mode : string) : string => fread(path_join(path_join(dir, mode), "p4_param_writes.das"))

[test]
def test_cli_param_writes(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_cli", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    t |> run("--param-writes copy opens a written parameter's body with its copy") @(t : T?) {
        var out : string
        t |> equal(run_main(dir, "copy", out), 0, out)
        let text = converted_text(dir, "copy")
        t |> success(text |> contains(COPY_NEEDLE), text)
    }
    t |> run("--param-writes in-place writes the parameter itself") @(t : T?) {
        var out : string
        t |> equal(run_main(dir, "in-place", out), 0, out)
        let text = converted_text(dir, "in-place")
        t |> success(text |> contains("def private p4_param_writes__count_down(var n : int) : int \{\n"), text)
        t |> success(!(text |> contains("n_in")), text)
    }
    t |> run("--param-writes local is a usage error before any conversion") @(t : T?) {
        var out : string
        t |> equal(run_main(dir, "local", out), 2, out)
        t |> success(out |> contains("--param-writes is in-place or copy, not `local`"), out)
        t |> success(!fexist(path_join(path_join(dir, "local"), "p4_param_writes.das")), out)
    }
    rmdir_rec(dir)
}
