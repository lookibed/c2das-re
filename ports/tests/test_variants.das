options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require daslib/json_boost
require ../variants.das
require ../../converter/sidecar.das
require ../../compare/projects.das
require ../../compare/rust_translator.das

//! The variant files: every sidecar key classed as a knob or a fact of the program, both variants of
//! every published program reading clean, the refusals of a malformed file, and the sidecar a
//! variant converts under and publishes.

// a scratch folder for the test's files; "" when none could be made
def private scratch(t : T?; name : string) : string {
    var error : string
    let dir = create_temp_directory(name, error)
    if (!empty(error)) {
        t |> failure("no scratch folder: {error}")
    }
    return dir
}

// `text` written as the variant file `<dir>/<file>` and read back; the read's error
def private refusal_of(dir, file, text : string) : string {
    let path = path_join(dir, file)
    fwrite(path, text)
    var error : string
    read_variant(path, error)
    return error
}

let ONE_KNOB = "\{\"knobs\": \{\"fn_macros\": \{\"value\": \"expand\", \"reason\": \"the JIT\", \"numbers\": \"1.04 -> 1.00\"\}\}\}"

[test]
def test_knob_classes(t : T?) {
    t |> run("every sidecar key is a knob a variant sets or a fact of the program, never both") @(t : T?) {
        for (key in SIDECAR_KEYS) {
            t |> success(has_value(VARIANT_KNOBS, key) != has_value(PROGRAM_KEYS, key), key)
        }
        t |> equal(length(VARIANT_KNOBS) + length(PROGRAM_KEYS), length(SIDECAR_KEYS))
    }
}

[test]
def test_committed_variants(t : T?) {
    t |> run("every published program has both variants, each setting every knob with a reason, and the sidecar of each reads") @(t : T?) {
        var programs <- ["lua", "puredoom"]
        programs |> push_from([for (p in project_table(rust_checkout())); p.name])
        let dir = scratch(t, "c2das_variants")
        for (program in programs) {
            for (name in VARIANT_NAMES) {
                var error : string
                let v <- read_variant(variant_path(program, name), error)
                t |> equal(error, "", "{program}.{name}")
                t |> equal(v.program, program)
                t |> equal(v.name, name)
                t |> equal(length(v.knobs), length(VARIANT_KNOBS), "{program}.{name} sets every knob")
                let base = program == "lua" ? "lua/lua.c2das" : program == "puredoom" ? "doom/doom.c2das" : ""
                if (!empty(base)) {
                    t |> success(variant_sidecar(v, base, path_join(dir, "{program}.{name}.c2das"), error), error)
                }
            }
        }
        rmdir_rec(dir)
    }
}

[test]
def test_refusals(t : T?) {
    t |> run("a malformed variant file is refused naming what is wrong") @(t : T?) {
        let dir = scratch(t, "c2das_variant_refusals")
        t |> success(refusal_of(dir, "lua.quick.json", ONE_KNOB) |> contains("a variant file is named <program>.<variant>.json, the variant readable or fast"))
        t |> success(refusal_of(dir, "lua.json", ONE_KNOB) |> contains("named <program>.<variant>.json"))
        t |> success(!empty(refusal_of(dir, "lua.fast.json", "\{")))
        t |> success(refusal_of(dir, "lua.fast.json", "[]") |> contains("a variant file is a JSON object"))
        t |> success(refusal_of(dir, "lua.fast.json", "\{\"knobs\": \{\}, \"why\": 1\}") |> contains("`why` is no key here (knobs, results)"))
        t |> success(refusal_of(dir, "lua.fast.json", "\{\}") |> contains("`knobs` is an object of sidecar keys"))
        t |> success(refusal_of(dir, "lua.fast.json", "\{\"knobs\": \{\"defines\": \{\"value\": [], \"reason\": \"r\"\}\}\}") |> contains("`knobs.defines` is no knob a variant sets"))
        t |> success(refusal_of(dir, "lua.fast.json", "\{\"knobs\": \{\"checks\": \"off\"\}\}") |> contains("`knobs.checks` is an object \{value, reason, numbers\}"))
        t |> success(refusal_of(dir, "lua.fast.json", "\{\"knobs\": \{\"checks\": \{\"value\": \"off\", \"reason\": \"r\", \"why\": \"\"\}\}\}") |> contains("`knobs.checks.why` is no key here"))
        t |> success(refusal_of(dir, "lua.fast.json", "\{\"knobs\": \{\"checks\": \{\"reason\": \"r\"\}\}\}") |> contains("`knobs.checks` has no `value`"))
        t |> success(refusal_of(dir, "lua.fast.json", "\{\"knobs\": \{\"checks\": \{\"value\": \"off\", \"reason\": 1\}\}\}") |> contains("`knobs.checks.reason` is a string, not 1"))
        t |> success(refusal_of(dir, "lua.fast.json", "\{\"knobs\": \{\"checks\": \{\"value\": \"off\", \"numbers\": \"\"\}\}\}") |> contains("`knobs.checks` has no `reason`"))
        t |> success(refusal_of(dir, "lua.fast.json", "\{\"knobs\": \{\}, \"results\": 3\}") |> contains("`results` is an object, not 3"))
        t |> equal(refusal_of(dir, "lua.fast.json", "\{\"knobs\": \{\}, \"results\": \{\"commit\": \"abc\"\}\}"), "")
        rmdir_rec(dir)
    }
}

[test]
def test_variant_sidecar(t : T?) {
    t |> run("the knobs set over the program's sidecar, its paths made absolute, the layout mode into the cut's object; the published text keeps the paths") @(t : T?) {
        let dir = scratch(t, "c2das_variant_sidecar")
        let base = path_join(dir, "prog.c2das")
        fwrite(base, "\{\"defines\": [\"A=1\"], \"layout\": \{\"profile\": \"prog.profile.json\"\}, \"include_dirs\": [\"inc\", \"/abs\"], \"include_files\": [\"cfg.h\"], \"program_root\": \"src\"\}\n")
        fwrite(path_join(dir, "prog.fast.json"), "\{\"knobs\": \{\"layout\": \{\"value\": \"single\", \"reason\": \"r\"\}, \"fn_macros\": \{\"value\": \"expand\", \"reason\": \"r\"\}, \"checks\": \{\"value\": \"off\", \"reason\": \"r\"\}\}\}")
        var error : string
        let v <- read_variant(path_join(dir, "prog.fast.json"), error)
        t |> equal(error, "")
        let into = path_join(dir, "work/prog.c2das")
        t |> success(variant_sidecar(v, base, into, error), error)
        let side <- read_sidecar(into, error)
        t |> equal(error, "")
        t |> equal(side.layout, "single")
        t |> equal(side.fn_macros, "expand")
        t |> equal(side.checks, "off")
        t |> equal(side.layout_profile, get_full_file_name(path_join(dir, "prog.profile.json")))
        t |> equal(side.include_dirs[0], get_full_file_name(path_join(dir, "inc")))
        t |> equal(side.include_dirs[1], "/abs")
        t |> equal(side.include_files[0], get_full_file_name(path_join(dir, "cfg.h")))
        t |> equal(side.program_root, get_full_file_name(path_join(dir, "src")))
        t |> equal(length(side.defines), 1)
        let text = published_sidecar(v, fread(base), error)
        t |> equal(error, "")
        t |> success(text |> contains("\"profile\" : \"prog.profile.json\""), text)
        t |> success(text |> contains("\"mode\" : \"single\""), text)
        t |> success(text |> contains("\"program_root\" : \"src\""), text)
        rmdir_rec(dir)
    }
    t |> run("a knob's value the converter refuses is refused, naming the variant and the key; a base that does not read is refused") @(t : T?) {
        let dir = scratch(t, "c2das_variant_sidecar_refusal")
        let base = path_join(dir, "prog.c2das")
        fwrite(base, "\{\}\n")
        fwrite(path_join(dir, "prog.readable.json"), "\{\"knobs\": \{\"fn_macros\": \{\"value\": \"fast\", \"reason\": \"r\"\}\}\}")
        var error : string
        let v <- read_variant(path_join(dir, "prog.readable.json"), error)
        t |> success(!variant_sidecar(v, base, path_join(dir, "out.c2das"), error))
        t |> success(error |> starts_with("prog.readable: ") && error |> contains("`fn_macros` is \"fold\" or \"expand\""), error)
        error = ""
        t |> success(!variant_sidecar(v, path_join(dir, "none.c2das"), path_join(dir, "out.c2das"), error))
        t |> success(!empty(error))
        fwrite(base, "[1]\n")
        error = ""
        t |> success(!variant_sidecar(v, base, path_join(dir, "out.c2das"), error))
        t |> success(error |> contains("a sidecar is a JSON object"), error)
        error = ""
        t |> equal(published_sidecar(v, "[1]", error), "")
        t |> success(error |> contains("a sidecar is a JSON object"), error)
        rmdir_rec(dir)
    }
}
