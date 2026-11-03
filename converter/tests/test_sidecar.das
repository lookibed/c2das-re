options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
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
    t |> run("`defines` is a list of strings, each `NAME`, `NAME=value` or `NAME(params)=value`, kept in order") @(t : T?) {
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
        t |> success(error |> ends_with("string.c2das: `defines` is a list of strings `NAME`, `NAME=value` or `NAME(params)=value`, not \"FOO=2\""), error)
        t |> equal(length(side.defines), 0)
    }
    t |> run("an entry that is no string is refused, naming the entry") @(t : T?) {
        var error : string
        let side <- read_text(dir, "number", "\{\"defines\": [\"FOO=2\", 3]\}\n", error)
        t |> success(error |> ends_with("number.c2das: `defines` holds strings `NAME`, `NAME=value` or `NAME(params)=value`, not 3"), error)
    }
    t |> run("an entry whose head is no identifier is refused, naming the entry") @(t : T?) {
        for (bad in fixed_array("\"\"", "\"-UN\"", "\"=x\"", "\"1N\"", "\"A-B=1\"")) {
            var error : string
            let side <- read_text(dir, "bad", "\{\"defines\": [\"FOO=2\", {bad}]\}\n", error)
            t |> success(error |> ends_with("bad.c2das: `defines` holds strings `NAME`, `NAME=value` or `NAME(params)=value`, not {bad}"), error)
        }
    }
    t |> run("a function-like macro: identifier params separated by commas, `...` last, a value required") @(t : T?) {
        var error : string
        let side <- read_text(dir, "function_like", "\{\"defines\": [\"LUAI_THROW(L,c)=abort()\", \"LUAI_TRY(L, c, a)=\{ a \}\", \"NONE()=0\", \"LOG(fmt, ...)=f(fmt)\"]\}\n", error)
        t |> equal(error, "")
        t |> equal(length(side.defines), 4)
        t |> equal(side.defines[1], "LUAI_TRY(L, c, a)=\{ a \}")
        for (bad in fixed_array("\"F(x)\"", "\"F(1x)=0\"", "\"F(x,)=0\"", "\"F(..., x)=0\"", "\"F(x=0\"", "\"(x)=0\"", "\"F(x)y=0\"")) {
            var bad_error : string
            let refused <- read_text(dir, "bad_function_like", "\{\"defines\": [{bad}]\}\n", bad_error)
            t |> success(bad_error |> ends_with("bad_function_like.c2das: `defines` holds strings `NAME`, `NAME=value` or `NAME(params)=value`, not {bad}"), bad_error)
        }
    }
    t |> run("an identifier head takes any value, `=` and spaces included") @(t : T?) {
        var error : string
        let side <- read_text(dir, "values", "\{\"defines\": [\"_N1\", \"M=a=b c\", \"E=\"]\}\n", error)
        t |> equal(error, "")
        t |> equal(length(side.defines), 3)
    }
    rmdir_rec(dir)
}

[test]
def test_sidecar_over_indexed(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_sidecar_over", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    t |> run("`over_indexed` is a list of strings `Record.field`, kept in order") @(t : T?) {
        var error : string
        let side <- read_text(dir, "good", "\{\"over_indexed\": [\"patch.columnofs\", \"vis.cols\"]\}\n", error)
        t |> equal(error, "")
        t |> equal(length(side.over_indexed), 2)
        t |> equal(side.over_indexed[0], "patch.columnofs")
        t |> equal(side.over_indexed[1], "vis.cols")
    }
    t |> run("`over_indexed` that is no list is refused, naming the key and the value") @(t : T?) {
        var error : string
        let side <- read_text(dir, "string", "\{\"over_indexed\": \"patch.columnofs\"\}\n", error)
        t |> success(error |> ends_with("string.c2das: `over_indexed` is a list of strings `Record.field`, not \"patch.columnofs\""), error)
        t |> equal(length(side.over_indexed), 0)
    }
    t |> run("an entry that is no string or not `Record.field` is refused, naming the entry") @(t : T?) {
        for (bad in fixed_array("3", "\"columnofs\"", "\".columnofs\"", "\"patch.\"", "\"a.b.c\"")) {
            var error : string
            let side <- read_text(dir, "bad", "\{\"over_indexed\": [\"patch.columnofs\", {bad}]\}\n", error)
            t |> success(error |> ends_with("bad.c2das: `over_indexed` holds strings `Record.field`, not {bad}"), error)
        }
    }
    rmdir_rec(dir)
}

[test]
def test_sidecar_padded(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_sidecar_padded", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    t |> run("`padded` is a list of strings `Record.field`, kept in order, apart from `over_indexed`") @(t : T?) {
        var error : string
        let side <- read_text(dir, "good", "\{\"padded\": [\"visplane_t.top\", \"visplane_t.bottom\"]\}\n", error)
        t |> equal(error, "")
        t |> equal(length(side.padded), 2)
        t |> equal(side.padded[0], "visplane_t.top")
        t |> equal(side.padded[1], "visplane_t.bottom")
        t |> equal(length(side.over_indexed), 0)
    }
    t |> run("`padded` that is no list is refused, naming the key and the value") @(t : T?) {
        var error : string
        let side <- read_text(dir, "string", "\{\"padded\": \"visplane_t.top\"\}\n", error)
        t |> success(error |> ends_with("string.c2das: `padded` is a list of strings `Record.field`, not \"visplane_t.top\""), error)
        t |> equal(length(side.padded), 0)
    }
    t |> run("a `padded` entry that is not `Record.field` is refused, naming the key and the entry") @(t : T?) {
        var error : string
        let side <- read_text(dir, "bad", "\{\"padded\": [\"visplane_t.top\", \"top\"]\}\n", error)
        t |> success(error |> ends_with("bad.c2das: `padded` holds strings `Record.field`, not \"top\""), error)
    }
    rmdir_rec(dir)
}

[test]
def test_sidecar_loops(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_sidecar_loops", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    t |> run("`loops` is \"range\" or \"while\"; absent it is empty, the emitter's range default") @(t : T?) {
        for (mode in ["range", "while"]) {
            var error : string
            let side <- read_text(dir, mode, "\{\"loops\": \"{mode}\"\}\n", error)
            t |> equal(error, "")
            t |> equal(side.loops, mode)
        }
        var error : string
        let side <- read_text(dir, "no_loops", "\{\"stack\": 65536\}\n", error)
        t |> equal(error, "")
        t |> equal(side.loops, "")
    }
    t |> run("any other `loops` value is refused, naming the key and the value") @(t : T?) {
        var error : string
        let side <- read_text(dir, "bad_loops", "\{\"loops\": \"for\"\}\n", error)
        t |> success(error |> ends_with("bad_loops.c2das: `loops` is \"range\" or \"while\", not \"for\""), error)
        t |> equal(side.loops, "")
    }
    rmdir_rec(dir)
}

[test]
def test_sidecar_first_member(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_sidecar_first_member", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    t |> run("`first_member` is \"addr\" or \"reinterpret\"; absent it is empty, the emitter's addr default") @(t : T?) {
        for (mode in ["addr", "reinterpret"]) {
            var error : string
            let side <- read_text(dir, mode, "\{\"first_member\": \"{mode}\"\}\n", error)
            t |> equal(error, "")
            t |> equal(side.first_member, mode)
        }
        var error : string
        let side <- read_text(dir, "no_first_member", "\{\"stack\": 65536\}\n", error)
        t |> equal(error, "")
        t |> equal(side.first_member, "")
    }
    t |> run("any other `first_member` value is refused, naming the key and the value") @(t : T?) {
        var error : string
        let side <- read_text(dir, "bad_first_member", "\{\"first_member\": \"offset\"\}\n", error)
        t |> success(error |> ends_with("bad_first_member.c2das: `first_member` is \"addr\" or \"reinterpret\", not \"offset\""), error)
        t |> equal(side.first_member, "")
    }
    rmdir_rec(dir)
}

[test]
def test_sidecar_layout(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_sidecar_layout", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    t |> run("`layout` is \"source\", \"source-cut\" or \"single\"; absent it is empty, the converter's source default") @(t : T?) {
        for (mode in ["source", "source-cut", "single"]) {
            var error : string
            let side <- read_text(dir, mode, "\{\"layout\": \"{mode}\"\}\n", error)
            t |> equal(error, "")
            t |> equal(side.layout, mode)
        }
        var error : string
        let side <- read_text(dir, "no_layout", "\{\"stack\": 65536\}\n", error)
        t |> equal(error, "")
        t |> equal(side.layout, "")
        t |> equal(side.layout_threshold, -1l)
    }
    t |> run("`layout` as an object: its mode, the cut's threshold, the symbols and file groups kept together, the symbols cut, the profile beside the sidecar") @(t : T?) {
        var error : string
        let side <- read_text(dir, "object", "\{\"layout\": \{\"mode\": \"source-cut\", \"threshold\": 1000, \"keep_together\": [\"luaV_execute\", [\"ldo\", \"lvm\"]], \"cut\": [\"luaG_runerror\"], \"profile\": \"lua.profile.json\"\}\}\n", error)
        t |> equal(error, "")
        t |> equal(side.layout, "source-cut")
        t |> equal(side.layout_threshold, 1000l)
        t |> equal(join(side.layout_keep_symbols, " "), "luaV_execute")
        t |> equal(length(side.layout_keep_units), 1)
        t |> equal(join(side.layout_keep_units[0], " "), "ldo lvm")
        t |> equal(join(side.layout_cut, " "), "luaG_runerror")
        t |> equal(side.layout_profile, path_join(dir, "lua.profile.json"))
    }
    t |> run("any other `layout` value or key, and a key of the wrong shape, is refused naming it") @(t : T?) {
        let cases <- [
            ("flat", "\{\"layout\": \"flat\"\}", "`layout` is \"source\", \"source-cut\" or \"single\", or an object, not \"flat\""),
            ("old", "\{\"layout\": \"scc\"\}", "`layout` is \"source\", \"source-cut\" or \"single\", or an object, not \"scc\""),
            ("number", "\{\"layout\": 3\}", "`layout` is \"source\", \"source-cut\" or \"single\", or an object, not 3"),
            ("mode", "\{\"layout\": \{\"mode\": \"flat\"\}\}", "`layout.mode` is \"source\", \"source-cut\" or \"single\", not \"flat\""),
            ("key", "\{\"layout\": \{\"depth\": 1\}\}", "`layout.depth` is no key of `layout`"),
            ("threshold", "\{\"layout\": \{\"threshold\": 1.5\}\}", "`layout.threshold` is a count of 0 or more, not 1.5"),
            ("negative", "\{\"layout\": \{\"threshold\": -1\}\}", "`layout.threshold` is a count of 0 or more, not -1"),
            ("keep", "\{\"layout\": \{\"keep_together\": \"ldo\"\}\}", "`layout.keep_together` is a list of symbols and lists of file stems"),
            ("group", "\{\"layout\": \{\"keep_together\": [[1]]\}\}", "`layout.keep_together`'s group holds strings, not 1"),
            ("cut", "\{\"layout\": \{\"cut\": \"x\"\}\}", "`layout.cut` is a list of strings, not \"x\""),
            ("profile", "\{\"layout\": \{\"profile\": 2\}\}", "`layout.profile` is a file name, not 2")
        ]
        for (c in cases) {
            var error : string
            read_text(dir, "bad_{c._0}", c._1, error)
            t |> success(error |> contains("bad_{c._0}.c2das: {c._2}"), "{c._0}: `{c._2}` not in `{error}`")
        }
    }
    rmdir_rec(dir)
}

[test]
def test_sidecar_inputs(t : T?) {
    var dir_error : string
    let dir = create_temp_directory("c2das_sidecar_inputs", dir_error)
    if (!empty(dir_error)) {
        t |> failure("no temp directory: {dir_error}")
        return
    }
    t |> run("`include_dirs` is a list of folders and `program_root` a folder, each read beside the sidecar unless absolute") @(t : T?) {
        var error : string
        let side <- read_text(dir, "inputs", "\{\"include_dirs\": [\"inc\", \"/abs/inc\"], \"include_files\": [\"config.h\"], \"program_root\": \"..\"\}\n", error)
        t |> equal(error, "")
        t |> equal(join(side.include_dirs, " "), "{path_join(dir, "inc")} /abs/inc")
        t |> equal(join(side.include_files, " "), path_join(dir, "config.h"))
        t |> equal(side.program_root, path_join(dir, ".."))
        let plain <- read_text(dir, "no_inputs", "\{\}\n", error)
        t |> equal(length(plain.include_dirs), 0)
        t |> equal(plain.program_root, "")
    }
    t |> run("`include_dirs` or `program_root` of the wrong shape, an unknown key and a sidecar that is no object are refused naming them") @(t : T?) {
        let cases <- [
            ("dirs", "\{\"include_dirs\": \"inc\"\}", "`include_dirs` is a list of strings, not \"inc\""),
            ("dir", "\{\"include_dirs\": [2]\}", "`include_dirs` holds strings, not 2"),
            ("files", "\{\"include_files\": \"a.h\"\}", "`include_files` is a list of strings, not \"a.h\""),
            ("root", "\{\"program_root\": 3\}", "`program_root` is a folder name, not 3"),
            ("empty_root", "\{\"program_root\": \"\"\}", "`program_root` is a folder name, not \"\""),
            ("unknown", "\{\"includes\": []\}", "`includes` is no sidecar key (marshal, stack"),
            ("list", "[1]", "a sidecar is a JSON object, not ")
        ]
        for (c in cases) {
            var error : string
            read_text(dir, "bad_{c._0}", c._1, error)
            t |> success(error |> contains("bad_{c._0}.c2das: {c._2}"), "{c._0}: `{c._2}` not in `{error}`")
        }
    }
    rmdir_rec(dir)
}
