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
let PROGRAM_KEYS <- ["marshal", "stack", "alloca_limit", "defines", "over_indexed", "padded", "flat_indexed", "include_dirs", "include_files", "program_root", "no_fold"]

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

//! the tiers a variant's speed is measured on, in the tables' order
let SPEED_TIERS <- ["interp", "jit", "exe", "aot"]

//! the keys of `results` and of each of its sections
let RESULTS_KEYS <- ["criteria", "speed", "lines", "notes"]
let CRITERIA_RESULT_KEYS <- ["total", "row", "commit", "date", "command"]
let SPEED_RESULT_KEYS <- ["x_native", "over", "commit", "date", "box", "command", "quiet"]
let LINES_RESULT_KEYS <- ["das", "luaV_execute", "commit"]

//! The criteria total a variant's search measured: the total in percent, the criteria row it is
//! (`metrics/criteria_linux.json`, "" for a row the capture does not hold), the c2das-re commit and
//! date it was measured at, and the command that reproduces it.
struct CriteriaResult {
    total : double
    row : string
    commit : string
    date : string
    command : string
}

//! The speed a variant's search measured: per tier of `SPEED_TIERS` the das time over the native
//! build's (a tier the search did not measure or that does not run is absent), what the ratio is
//! over, the commit, date and box, the command, and that the exclusive run found the machine quiet.
struct SpeedResult {
    x_native : table<string; double>
    over : string
    commit : string
    date : string
    box : string
    command : string
    quiet : bool
}

//! The line counts a variant's search recorded: the das lines of the converted tree, Lua's
//! `luaV_execute` (0 for another program), and the commit converted.
struct LinesResult {
    das : int
    lua_v_execute : int
    commit : string
}

//! The numbers a variant's search recorded, each section with its own provenance; a section the
//! file leaves out has its `has_` false.
struct VariantResults {
    has_criteria : bool
    criteria : CriteriaResult
    has_speed : bool
    speed : SpeedResult
    has_lines : bool
    lines : LinesResult
    notes : string
}

//! A variant read from its file: the program and the variant (`<program>.<variant>.json`), its knobs
//! in the file's order, and the `results` its search recorded.
struct Variant {
    program : string
    name : string
    knobs : array<VariantKnob>
    results : VariantResults
}

//! The path of `program`'s variant `name`.
def variant_path(program, name : string) : string => path_join(VARIANTS_DIR, "{program}.{name}.json")

// a string member `key` of the object `js` into `out`; an error naming it when present and no
// string; nothing once `error` is set
def private string_member(js : JsonValue?; path, scope, key : string; var out : string&; var error : string&) {
    if (!empty(error) || !key_exists(js, key)) {
        return
    }
    let value = js?[key]
    if (!(value is _string)) {
        error = "{path}: `{scope}.{key}` is a string, not {write_json(value)}"
        return
    }
    out = value ?? ""
}

// a number member `key` of the object `js` into `out`; an error naming it when present and no
// number above 0, unless `null_ok` and it is null (left 0); nothing once `error` is set
def private number_member(js : JsonValue?; path, scope, key : string; null_ok : bool; var out : double&; var error : string&) {
    if (!empty(error) || !key_exists(js, key)) {
        return
    }
    let value = js?[key]
    if (null_ok && value != null && value.value is _null) {
        return
    }
    // an integer reads as a long integer, a number with a point or an exponent as a double
    let number = value is _longint ? double(value.value as _longint) : value is _number ? value.value as _number : 0.0lf
    if (number > 0.0lf) {
        out = number
    } else {
        error = "{path}: `{scope}.{key}` is a number above 0{null_ok ? " or null" : ""}, not {write_json(value)}"
    }
}

// the members `required` of the object `js`, each named in `error` when missing
def private required_members(js : JsonValue?; path, scope : string; required : array<string>; var error : string&) {
    for (key in required) {
        if (empty(error) && !key_exists(js, key)) {
            error = "{path}: `{scope}` has no `{key}`"
        }
    }
}

// whether `results` holds the section `key`, an object of `known` keys; false with `error` set when
// it is present and no such object
def private has_section(results : JsonValue?; path, key : string; known : array<string>; var error : string&) : bool {
    if (!empty(error) || !key_exists(results, key)) {
        return false
    }
    let section = results?[key]
    if (!(section is _object)) {
        error = "{path}: `results.{key}` is an object, not {write_json(section)}"
        return false
    }
    unknown_key(section, path, "results.{key}.", known, error)
    return true
}

//! Reads the `results` object `js` of the variant file `path` into `into`: `criteria` (`total`,
//! `commit` and `date` required), `speed` (`x_native` over `SPEED_TIERS`, `over`, `commit`, `date`,
//! `box`, `command` required, `quiet` true, since only an exclusive run that found the machine quiet
//! is quoted), `lines` (`das` and `commit` required, `luaV_execute` for Lua) and `notes`, each
//! optional; `error` names a key outside them or a member of the wrong shape.
[arch(at="ARCHITECTURE_VARIANTS.md#variant-results")]
def read_results(js : JsonValue?; path : string; var into : VariantResults; var error : string&) {
    if (!(js is _object)) {
        error = "{path}: `results` is an object, not {write_json(js)}"
        return
    }
    unknown_key(js, path, "results.", RESULTS_KEYS, error)
    string_member(js, path, "results", "notes", into.notes, error)
    if (has_section(js, path, "criteria", CRITERIA_RESULT_KEYS, error)) {
        let criteria = js?["criteria"]
        into.has_criteria = true
        required_members(criteria, path, "results.criteria", ["total", "commit", "date"], error)
        number_member(criteria, path, "results.criteria", "total", false, into.criteria.total, error)
        string_member(criteria, path, "results.criteria", "row", into.criteria.row, error)
        string_member(criteria, path, "results.criteria", "commit", into.criteria.commit, error)
        string_member(criteria, path, "results.criteria", "date", into.criteria.date, error)
        string_member(criteria, path, "results.criteria", "command", into.criteria.command, error)
    }
    if (has_section(js, path, "speed", SPEED_RESULT_KEYS, error)) {
        let speed = js?["speed"]
        into.has_speed = true
        required_members(speed, path, "results.speed", ["x_native", "over", "commit", "date", "box", "command", "quiet"], error)
        let tiers = empty(error) ? speed?["x_native"] : null
        if (empty(error) && !(tiers is _object)) {
            error = "{path}: `results.speed.x_native` is an object of tiers, not {write_json(tiers)}"
        }
        if (empty(error)) {
            unknown_key(tiers, path, "results.speed.x_native.", SPEED_TIERS, error)
        }
        for (tier in SPEED_TIERS) {
            var ratio = 0.0lf
            number_member(tiers, path, "results.speed.x_native", tier, true, ratio, error)
            if (ratio > 0.0lf) {
                into.speed.x_native[tier] = ratio
            }
        }
        string_member(speed, path, "results.speed", "over", into.speed.over, error)
        string_member(speed, path, "results.speed", "commit", into.speed.commit, error)
        string_member(speed, path, "results.speed", "date", into.speed.date, error)
        string_member(speed, path, "results.speed", "box", into.speed.box, error)
        string_member(speed, path, "results.speed", "command", into.speed.command, error)
        let quiet = empty(error) ? speed?["quiet"] : null
        if (empty(error) && !(quiet is _bool && (quiet ?? false))) {
            error = "{path}: `results.speed.quiet` is true, an exclusive run that found the machine quiet, not {write_json(quiet)}"
        }
        into.speed.quiet = empty(error)
    }
    if (has_section(js, path, "lines", LINES_RESULT_KEYS, error)) {
        let lines = js?["lines"]
        into.has_lines = true
        required_members(lines, path, "results.lines", ["das", "commit"], error)
        var das, execute = 0.0lf
        number_member(lines, path, "results.lines", "das", false, das, error)
        number_member(lines, path, "results.lines", "luaV_execute", false, execute, error)
        string_member(lines, path, "results.lines", "commit", into.lines.commit, error)
        into.lines.das = int(das)
        into.lines.lua_v_execute = int(execute)
    }
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
//! `VARIANT_KNOBS` keys each `{value, reason, numbers}` with a reason, and `results` (`read_results`);
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
    if (empty(error) && key_exists(js, "results")) {
        read_results(js?["results"], path, v.results, error)
    }
    // the readable variant keeps das's checks: it is the one to debug a C bug in
    for (k in v.knobs) {
        if (empty(error) && v.name == "readable" && k.key == "checks" && k.value != "\"safe\"") {
            error = "{path}: the readable variant keeps `checks` safe, not {k.value}: it is the variant to debug in"
        }
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
