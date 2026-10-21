options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require ../sidecar.das

// the sidecar `text` written to a fresh `.c2das` file under `dir`, read back
def read_text(dir, name, text : string; var error : string&) : Sidecar {
    let path = path_join(dir, "{name}.c2das")
    fwrite(path, text)
    return <- read_sidecar(path, error)
}

[test]
def test_sidecar_defines(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_sidecar", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    t |> run("`defines` is a list of strings, each `NAME` or `NAME=value`, kept in order") @(t : T?) {
        var error : string
        let side <- read_text(dir, "good", "\{\"defines\": [\"FOO=2\", \"BAR\"]\}\n", error)
        t |> equal(error, "")
        t |> equal(length(side.defines), 2)
        t |> equal(side.defines[0], "FOO=2")
        t |> equal(side.defines[1], "BAR")
    }
    t |> run("a sidecar without `defines` defines nothing") @(t : T?) {
        var error : string
        let side <- read_text(dir, "absent", "\{\"stack\": 65536\}\n", error)
        t |> equal(error, "")
        t |> equal(length(side.defines), 0)
    }
    t |> run("`defines` that is no list is refused, naming the key and the value") @(t : T?) {
        var error : string
        let side <- read_text(dir, "string", "\{\"defines\": \"FOO=2\"\}\n", error)
        t |> success(error |> ends_with("string.c2das: `defines` is a list of strings `NAME` or `NAME=value`, not \"FOO=2\""), error)
        t |> equal(length(side.defines), 0)
    }
    t |> run("an entry that is no string is refused, naming the entry") @(t : T?) {
        var error : string
        let side <- read_text(dir, "number", "\{\"defines\": [\"FOO=2\", 3]\}\n", error)
        t |> success(error |> ends_with("number.c2das: `defines` holds strings `NAME` or `NAME=value`, not 3"), error)
    }
    rmdir_rec(dir)
}
