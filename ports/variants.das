options gen2

module variants public

require daslib/cmp
require strings
require daslib/strings_boost
require daslib/fio
require daslib/json_boost
require ../converter/sidecar.das

//! The two variants of a published program (`ARCHITECTURE_VARIANTS.md`): each a file
//! `ports/variants/<program>.<variant>.json` setting the converter's program-wide knobs, the
//! `.c2das` keys that change the converted text and not what the program computes, each value with
//! the reason and the numbers that chose it, and the numbers the variant's search recorded.

//! the variants every published program has
let VARIANT_NAMES <- ["readable", "fast"]

//! the folder of the variant files
let VARIANTS_DIR = "ports/variants"

//! The sidecar keys a variant sets: the converter's program-wide choices of spelling, layout and
//! checks (`converter/sidecar.das`). Every other key of `SIDECAR_KEYS` is a fact of the program
//! (`PROGRAM_KEYS`), which the program's own sidecar holds and no variant changes.
let VARIANT_KNOBS <- ["layout", "fn_macros", "inline_helpers", "switch_dispatch", "checks", "past_end", "param_writes", "loops", "first_member", "solid_context", "jit_whole_program", "strict_aliasing", "forms_off"]

//! The sidecar keys that are facts of the program: what it must be converted with, never a choice
//! between two spellings of the same program.
let PROGRAM_KEYS <- ["marshal", "stack", "alloca_limit", "defines", "over_indexed", "padded", "include_dirs", "include_files", "program_root", "no_fold"]

//! the keys of a variant file and of each knob
let VARIANT_FILE_KEYS <- ["knobs", "results"]
let KNOB_KEYS <- ["value", "reason", "numbers"]

//! One knob a variant sets: the sidecar key, its value as JSON text, the one-line reason and the
//! numbers that chose it ("" before a search).
struct VariantKnob {
    key : string
    value : string
    reason : string
    numbers : string
}

//! A variant read from its file: the program and the variant (`<program>.<variant>.json`), its knobs
//! in the file's order, and the `results` its search recorded, as JSON text ("" for none).
struct Variant {
    program : string
    name : string
    knobs : array<VariantKnob>
    results : string
}

//! The path of `program`'s variant `name`.
def variant_path(program, name : string) : string => path_join(VARIANTS_DIR, "{program}.{name}.json")

// a string member `key` of the object `js` into `out`; an error naming it when present and no string
def private string_member(js : JsonValue?; path, scope, key : string; var out : string&; var error : string&) {
    if (!key_exists(js, key)) {
        return
    }
    let value = js?[key]
    if (!(value is _string)) {
        error = "{path}: `{scope}.{key}` is a string, not {write_json(value)}"
        return
    }
    out = value ?? ""
}

// the keys of the object `js` outside `known`, the first named in `error`
def private unknown_key(js : JsonValue?; path, scope : string; known : array<string>; var error : string&) {
    for (key in keys(js as _object)) {
        if (!has_value(known, key)) {
            error = "{path}: `{scope}{key}` is no key here ({join(known, ", ")})"
            return
        }
    }
}

//! Reads the variant file `path`, named `<program>.<variant>.json`: `knobs`, an object of
//! `VARIANT_KNOBS` keys each `{value, reason, numbers}` with a reason, and `results`, an object;
//! `error` names a file that is not JSON, a variant outside `VARIANT_NAMES`, a key outside the
//! knobs or of the wrong shape. A knob's value is checked by the sidecar it makes
//! (`variant_sidecar`).
[arch(at="ARCHITECTURE_VARIANTS.md#variant-files")]
def read_variant(path : string; var error : string&) : Variant {
    var v : Variant
    let stem = trim_suffix(base_name(path), ".json")
    let dot = rfind(stem, ".")
    v.program = dot > 0 ? slice(stem, 0, dot) : ""
    v.name = dot > 0 ? slice(stem, dot + 1) : ""
    if (!has_value(VARIANT_NAMES, v.name)) {
        error = "{path}: a variant file is named <program>.<variant>.json, the variant {join(VARIANT_NAMES, " or ")}"
        return <- v
    }
    var js = read_json_file(path, error)
    if (js == null) {
        return <- v
    }
    if (!(js is _object)) {
        error = "{path}: a variant file is a JSON object, not {write_json(js)}"
    } else {
        unknown_key(js, path, "", VARIANT_FILE_KEYS, error)
    }
    let knobs = empty(error) ? js?["knobs"] : null
    if (empty(error) && !(knobs is _object)) {
        error = "{path}: `knobs` is an object of sidecar keys, not {write_json(knobs)}"
    }
    if (empty(error)) {
        for (key in keys(knobs as _object)) {
            let knob = knobs?[key]
            var k = VariantKnob(key = key)
            if (!has_value(VARIANT_KNOBS, key)) {
                error = "{path}: `knobs.{key}` is no knob a variant sets ({join(VARIANT_KNOBS, ", ")})"
            } elif (!(knob is _object)) {
                error = "{path}: `knobs.{key}` is an object \{value, reason, numbers\}, not {write_json(knob)}"
            } else {
                unknown_key(knob, path, "knobs.{key}.", KNOB_KEYS, error)
            }
            if (empty(error) && !key_exists(knob, "value")) {
                error = "{path}: `knobs.{key}` has no `value`"
            }
            if (empty(error)) {
                k.value = write_json(knob?["value"])
                string_member(knob, path, "knobs.{key}", "reason", k.reason, error)
                string_member(knob, path, "knobs.{key}", "numbers", k.numbers, error)
            }
            if (empty(error) && empty(k.reason)) {
                error = "{path}: `knobs.{key}` has no `reason`"
            }
            break if (!empty(error))
            v.knobs |> push(k)
        }
    }
    let results = empty(error) && key_exists(js, "results") ? js?["results"] : null
    if (results != null && !(results is _object)) {
        error = "{path}: `results` is an object, not {write_json(results)}"
    } elif (results != null) {
        v.results = write_json(results, true)
    }
    sort(v.knobs) <| cmp_by(_.key)
    delete_json(js)
    return <- v
}

// `name` read beside the sidecar at `path` made absolute, as the sidecar reads it
def private rebased(path, name : string) : string => is_absolute(name) ? name : get_full_file_name(path_join(dir_name(path), name))

// the paths of the sidecar object `js`, read from `path`, made absolute, so the object reads the
// same from another folder: `include_dirs`, `include_files`, `program_root` and `layout.profile`
def private rebase_paths(var js : JsonValue?; path : string) {
    for (key in ["include_dirs", "include_files"]) {
        let list = js?[key]
        if (key_exists(js, key) && list is _array) {
            (js as _object)[key] = JV([for (entry in list as _array); rebased(path, entry ?? "")])
        }
    }
    let root = js?["program_root"]
    if (key_exists(js, "program_root") && root is _string) {
        (js as _object)["program_root"] = JV(rebased(path, root ?? ""))
    }
    var layout = js?["layout"]
    let profile = layout?["profile"]
    if (layout is _object && key_exists(layout, "profile") && profile is _string) {
        (layout as _object)["profile"] = JV(rebased(path, profile ?? ""))
    }
}

//! The sidecar object `js` with every knob of `v` set: the knob's key to its value, the layout mode
//! into `layout.mode` when the program's `layout` is an object (the source-cut layout's cut).
def overlay_knobs(var js : JsonValue?; v : Variant) {
    for (k in v.knobs) {
        var error : string
        var value = read_json(k.value, error)
        var layout = js?["layout"]
        if (k.key == "layout" && layout is _object) {
            (layout as _object)["mode"] = value
        } else {
            (js as _object)[k.key] = value
        }
    }
}

//! The sidecar the variant `v` converts under: the program's sidecar `base` (a `.c2das` file) with
//! `v`'s knobs set (`overlay_knobs`), written to `into` with its paths made absolute, then read
//! back as the converter reads it, so a knob's value the converter refuses is refused here; false
//! with `error` set when `base` does not read or the result is refused.
[arch(at="ARCHITECTURE_VARIANTS.md#variant-sidecar")]
def variant_sidecar(v : Variant; base, into : string; var error : string&) : bool {
    var js = read_json_file(base, error)
    if (js == null) {
        return false
    }
    if (!(js is _object)) {
        error = "{base}: a sidecar is a JSON object"
        delete_json(js)
        return false
    }
    rebase_paths(js, base)
    overlay_knobs(js, v)
    mkdir_rec(dir_name(into))
    let written = fwrite(into, write_json(js, true) + "\n")
    delete_json(js)
    if (!written) {
        error = "cannot write {into}"
        return false
    }
    read_sidecar(into, error)
    if (!empty(error)) {
        error = "{v.program}.{v.name}: {error}"
    }
    return empty(error)
}

//! The text of the program's sidecar `base_text` with `v`'s knobs set and its paths as written, the
//! sidecar a variant's directory publishes; "" with `error` set when it is not a JSON object.
def published_sidecar(v : Variant; base_text : string; var error : string&) : string {
    var js = read_json(base_text, error)
    if (js == null || !(js is _object)) {
        error = empty(error) ? "a sidecar is a JSON object" : error
        delete_json(js)
        return ""
    }
    overlay_knobs(js, v)
    let text = write_json(js, true) + "\n"
    delete_json(js)
    return text
}
