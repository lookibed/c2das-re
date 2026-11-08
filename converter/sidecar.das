options gen2

module sidecar public

require strings
require daslib/strings_boost
require daslib/fio
require daslib/json_boost
require cir

//! The per-project `.c2das` file: every judgment the pipeline cannot derive from the C source
//! (docs/very-detailed-plan.md section 4.4). JSON; a key the row that needs it adds.

struct Sidecar {
    // records read and written as bytes at clang's offsets, never laid out by das: the packed
    // disk types, by tag or typedef name
    marshal : table<string>
    // the module's `options stack` when a function calls alloca (0: the default), and the bytes
    // of each such function's arena (0: the default)
    stack : int
    alloca_limit : int
    // how the body writes a scalar or pointer parameter it assigns, steps or takes the address
    // of: `in-place` (the parameter itself) or `copy` (a local copy); "" when the key is absent
    param_writes : string
    // how a canonical counting `for` is spelled: `range` (a das range loop) or `while` (the
    // `while` form every other `for` takes); "" when the key is absent
    loops : string
    // how the address of a member at offset 0 is spelled: `addr` (`addr(p.f)`) or `reinterpret` (the
    // containing pointer reinterpreted, `reinterpret<F?>(p)`); "" when the key is absent
    first_member : string
    // how a dense switch is dispatched: `chain` (its cases tested in turn) or `goto` (a jump table of
    // das labels, `goto int(_cond) + base`); "" when the key is absent
    switch_dispatch : string
    // whether converted functions keep das's null and range checks: `safe` (they panic on a null
    // dereference or an index past its array) or `off` (`unsafe_deref` and
    // `hint(unsafe_range_check)` on every converted function); "" when the key is absent
    checks : string
    // the macros clang defines for the dump, each `NAME`, `NAME=value` or `NAME(params)=value`,
    // passed as `-D<entry>`
    defines : array<string>
    // the trailing array members the program indexes past their length (C89's `int a[1]` over a
    // larger allocation), each `Record.field`, by tag or typedef name: their accesses go through a
    // pointer with no range check
    over_indexed : array<string>
    // the array members the program indexes one element past either end, into the members on
    // either side of them (Doom's `visplane_t.top[-1]` is its `pad1`), each `Record.field`, by tag or
    // typedef name: their accesses go through a pointer with no range check
    padded : array<string>
    // how a program of several files lays out its modules: `source` (a module per C file, mutually
    // dependent files one module of fragments), `source-cut` (a module per C file, the cycles cut
    // by late binding) or `single` (one module); "" when the key is absent
    layout : string
    // the cycle cut of the `source-cut` layout (`converter/ARCHITECTURE_LAYOUT.md`): the weight
    // above which an edge is never cut (-1: none), the symbols never cut, the groups of units kept
    // in one module, the symbols always cut, and the profile of call counts (a path beside the
    // sidecar, "" for none)
    layout_threshold : int64 = -1l
    layout_keep_symbols : array<string>
    layout_keep_units : array<array<string>>
    layout_cut : array<string>
    layout_profile : string
    // the folders clang searches for `#include`, each passed as `-I<dir>` to both passes of the
    // dumper, in order; absolute (a relative entry is read beside the sidecar)
    include_dirs : array<string>
    // the headers clang reads before the main file, each passed as `-include <file>` to both passes
    // of the dumper, in order; absolute (a relative entry is read beside the sidecar)
    include_files : array<string>
    // the folder whose files are the program's (`converter/ARCHITECTURE_DUMPER.md`, the file
    // policy), absolute; "" for the main file's own folder
    program_root : string
    // whether every module of the program carries `options solid_context` (a global and a
    // function reached by index, never a lookup by name): false only for code another context
    // runs or a patch reloads, which the option forbids
    solid_context : bool = true
    // whether the entry module pins the cached JIT's build to one unit (`options
    // jit_split_modules = 0`, the piece `c_runtime/c_jit_build`), keeping inlining across modules
    jit_whole_program : bool = false
}

//! The keys a sidecar may hold; any other is refused naming it.
let SIDECAR_KEYS <- ["marshal", "stack", "alloca_limit", "param_writes", "loops", "first_member", "switch_dispatch", "layout", "defines", "over_indexed", "padded", "include_dirs", "include_files", "program_root", "solid_context", "checks", "jit_whole_program"]

//! The values of the `param_writes` key and of the converter's `--param-writes`.
let PARAM_WRITES <- ["in-place", "copy"]

//! Whether `mode` is a value of `param_writes`.
def is_param_writes(mode : string) : bool => has_value(PARAM_WRITES, mode)

//! The values of the `loops` key and of the converter's `--loops`.
let LOOPS <- ["range", "while"]

//! Whether `mode` is a value of `loops`.
def is_loops(mode : string) : bool => has_value(LOOPS, mode)

//! The values of the `first_member` key and of the converter's `--first-member`.
let FIRST_MEMBER <- ["addr", "reinterpret"]

//! Whether `mode` is a value of `first_member`.
def is_first_member(mode : string) : bool => has_value(FIRST_MEMBER, mode)

//! The values of the `switch_dispatch` key and of the converter's `--switch-dispatch`.
let SWITCH_DISPATCH <- ["chain", "goto"]

//! Whether `mode` is a value of `switch_dispatch`.
def is_switch_dispatch(mode : string) : bool => has_value(SWITCH_DISPATCH, mode)

//! The values of the `checks` key and of the converter's `--checks`.
let CHECKS <- ["safe", "off"]

//! Whether `mode` is a value of `checks`.
def is_checks(mode : string) : bool => has_value(CHECKS, mode)

//! The values of the `layout` key and of the converter's `--layout`.
let LAYOUTS <- ["source", "source-cut", "single"]

//! Whether `mode` is a value of `layout`.
def is_layout(mode : string) : bool => has_value(LAYOUTS, mode)

//! The sidecar a C file converts under: `given` when it is not empty, else `<stem>.c2das` beside the
//! file, else `.c2das` in its folder; "" when none exists.
def find_sidecar(c_path : string; given : string) : string {
    if (!empty(given)) {
        return given
    }
    let dir = dir_name(c_path)
    let name = base_name(c_path)
    let dot = find(name, ".")
    let own = path_join(dir, "{dot < 0 ? name : slice(name, 0, dot)}.c2das")
    if (fexist(own)) {
        return own
    }
    let folder_wide = path_join(dir, ".c2das")
    return fexist(folder_wide) ? folder_wide : ""
}

//! The JSON document in the file at `path`; null with `error` naming the path when the file
//! is missing, empty or not JSON.
def read_json_file(path : string; var error : string&) : JsonValue? {
    var js = read_json(fread(path), error)
    if (js == null) {
        error = "{path}: {error}"
    }
    return js
}

// whether `entry` is what `-D` takes as a macro: `NAME`, `NAME=value`, or a function-like
// `NAME(params)=value` whose params are identifiers separated by commas, `...` last
def private is_define(entry : string) : bool {
    let eq = find(entry, "=")
    let head = eq < 0 ? entry : slice(entry, 0, eq)
    let paren = find(head, "(")
    if (paren < 0) {
        return is_identifier(head)
    }
    if (eq < 0 || !(head |> ends_with(")")) || !is_identifier(slice(head, 0, paren))) {
        return false
    }
    let inside = slice(head, paren + 1, length(head) - 1)
    if (empty(strip(inside))) {
        return true
    }
    let params <- split(inside, ",")
    for (idx, param in count(), params) {
        let name = strip(param)
        if (!is_identifier(name) && !(name == "..." && idx == length(params) - 1)) {
            return false
        }
    }
    return true
}

//! The count a JSON value spells as one or more decimal digits, else -1.
def json_count(js : JsonValue?) : int64 {
    let text = write_json(js)
    return is_digit_run(text, 0) ? to_int64(text) : -1l
}

// the strings of the list `js` appended to `out`, else in `error` what `what` holds instead
def private strings_of(js : JsonValue?; what : string; var out : array<string>; var error : string&) {
    if (!(js is _array)) {
        error = "{what} is a list of strings, not {write_json(js)}"
        return
    }
    out |> reserve(length(out) + length(js as _array))
    for (item in js as _array) {
        if (!(item is _string) || empty(item ?? "")) {
            error = "{what} holds strings, not {write_json(item)}"
            return
        }
        out |> push(item ?? "")
    }
}

// the `layout` key: a mode, or an object with `mode`, `threshold`, `keep_together`, `cut` and
// `profile`
def private read_layout(js : JsonValue?; path : string; var side : Sidecar; var error : string&) {
    let modes = "\"source\", \"source-cut\" or \"single\""
    if (js is _string) {
        side.layout = js ?? ""
        if (!is_layout(side.layout)) {
            error = "{path}: `layout` is {modes}, or an object, not {write_json(js)}"
            side.layout = ""
        }
        return
    }
    if (!(js is _object)) {
        error = "{path}: `layout` is {modes}, or an object, not {write_json(js)}"
        return
    }
    for (key in keys(js as _object)) {
        if (!has_value(["mode", "threshold", "keep_together", "cut", "profile"], key)) {
            error = "{path}: `layout.{key}` is no key of `layout` (mode, threshold, keep_together, cut, profile)"
            return
        }
    }
    let mode = js?["mode"] ?? ""
    if (key_exists(js, "mode") && !is_layout(mode)) {
        error = "{path}: `layout.mode` is {modes}, not {write_json(js?["mode"])}"
        return
    }
    side.layout = mode
    if (key_exists(js, "threshold")) {
        let threshold = js?["threshold"]
        let count = json_count(threshold)
        if (count < 0l) {
            error = "{path}: `layout.threshold` is a count of 0 or more, not {write_json(threshold)}"
            return
        }
        side.layout_threshold = count
    }
    if (key_exists(js, "keep_together")) {
        let keep = js?["keep_together"]
        if (!(keep is _array)) {
            error = "{path}: `layout.keep_together` is a list of symbols and lists of file stems, not {write_json(keep)}"
            return
        }
        for (item in keep as _array) {
            if (item is _string && !empty(item ?? "")) {
                side.layout_keep_symbols |> push(item ?? "")
            } else {
                var inscope group : array<string>
                strings_of(item, "{path}: `layout.keep_together`'s group", group, error)
                if (!empty(error)) {
                    return
                }
                side.layout_keep_units |> emplace(group)
            }
        }
    }
    if (key_exists(js, "cut")) {
        strings_of(js?["cut"], "{path}: `layout.cut`", side.layout_cut, error)
        if (!empty(error)) {
            return
        }
    }
    if (key_exists(js, "profile")) {
        let profile = js?["profile"]
        if (!(profile is _string) || empty(profile ?? "")) {
            error = "{path}: `layout.profile` is a file name, not {write_json(profile)}"
            return
        }
        side.layout_profile = path_join(dir_name(path), profile ?? "")
    }
}

// `name` read beside the sidecar at `path`: itself when absolute
def private beside(path, name : string) : string => is_absolute(name) ? name : path_join(dir_name(path), name)

// why the sidecar document `js` at `path` is refused before its keys are read: it is no object, or
// it holds a key outside `SIDECAR_KEYS`; "" when neither
def private shape_error(js : JsonValue?; path : string) : string {
    if (!(js is _object)) {
        return "{path}: a sidecar is a JSON object, not {write_json(js)}"
    }
    for (key in keys(js as _object)) {
        if (!has_value(SIDECAR_KEYS, key)) {
            return "{path}: `{key}` is no sidecar key ({join(SIDECAR_KEYS, ", ")})"
        }
    }
    return ""
}

// the list of strings `Record.field` under key `key` into `out`; a value that is no list or an entry
// of another shape is refused naming the key
def private read_members(js : JsonValue?; path, key : string; var out : array<string>; var error : string&) {
    if (!key_exists(js, key)) {
        return
    }
    let list = js?[key]
    if (!(list is _array)) {
        error = "{path}: `{key}` is a list of strings `Record.field`, not {write_json(list)}"
        return
    }
    out |> reserve(length(out) + length(list as _array))
    for (entry in list as _array) {
        let name = entry is _string ? entry ?? "" : ""
        let dot = find(name, ".")
        if (dot <= 0 || dot == length(name) - 1 || find(name, ".", dot + 1) >= 0) {
            error = "{path}: `{key}` holds strings `Record.field`, not {write_json(entry)}"
            return
        }
        out |> push(name)
    }
}

// the `include_dirs`, `include_files` and `program_root` keys, each path read beside the sidecar at
// `path`
def private read_inputs(js : JsonValue?; path : string; var side : Sidecar; var error : string&) {
    if (key_exists(js, "include_dirs")) {
        var inscope dirs : array<string>
        strings_of(js?["include_dirs"], "{path}: `include_dirs`", dirs, error)
        side.include_dirs |> push_from([for (dir in dirs); beside(path, dir)])
    }
    if (key_exists(js, "include_files")) {
        var inscope files : array<string>
        strings_of(js?["include_files"], "{path}: `include_files`", files, error)
        side.include_files |> push_from([for (f in files); beside(path, f)])
    }
    if (key_exists(js, "program_root")) {
        let root = js?["program_root"]
        if (!(root is _string) || empty(root ?? "")) {
            error = "{path}: `program_root` is a folder name, not {write_json(root)}"
        } else {
            side.program_root = beside(path, root ?? "")
        }
    }
}

// the boolean `key` into `field` when present, else `field` kept; a value of another shape refused
// naming the key
def private read_flag(js : JsonValue?; path, key : string; var field : bool&; var error : string&) {
    let value = js?[key]
    if (key_exists(js, key) && !(value is _bool)) {
        error = "{path}: `{key}` is true or false, not {write_json(value)}"
    } elif (key_exists(js, key)) {
        field = value ?? field
    }
}

// a key whose value is one of `modes` into `field`, left "" when the key is absent
def private read_mode(js : JsonValue?; path, key : string; modes : array<string>; var field : string&; var error : string&) {
    let value = js?[key] ?? ""
    if (key_exists(js, key) && !has_value(modes, value)) {
        let quoted = join([for (m in modes); "\"{m}\""], " or ")
        error = "{path}: `{key}` is {quoted}, not {write_json(js?[key])}"
    } else {
        field = value
    }
}

//! Reads a sidecar file; `error` names a file that is not JSON, a key it does not know or a key of
//! the wrong shape.
def read_sidecar(path : string; var error : string&) : Sidecar {
    var side = Sidecar()
    if (empty(path)) {
        return <- side
    }
    var js = read_json_file(path, error)
    if (js == null) {
        return <- side
    }
    error = shape_error(js, path)
    if (!empty(error)) {
        delete_json(js)
        return <- side
    }
    // `?[]` of a missing key is json_boost's null sentinel, never null: `key_exists` tells
    let marshal = js?["marshal"]
    if (key_exists(js, "marshal") && !(marshal is _array)) {
        error = "{path}: `marshal` is a list of type names"
    } elif (key_exists(js, "marshal")) {
        for (name in marshal as _array) {
            side.marshal |> insert(name ?? "")
        }
    }
    side.stack = int(js?["stack"] ?? 0l)
    side.alloca_limit = int(js?["alloca_limit"] ?? 0l)
    read_mode(js, path, "param_writes", PARAM_WRITES, side.param_writes, error)
    read_mode(js, path, "loops", LOOPS, side.loops, error)
    read_mode(js, path, "first_member", FIRST_MEMBER, side.first_member, error)
    read_mode(js, path, "switch_dispatch", SWITCH_DISPATCH, side.switch_dispatch, error)
    read_mode(js, path, "checks", CHECKS, side.checks, error)
    if (key_exists(js, "layout")) {
        read_layout(js?["layout"], path, side, error)
    }
    let defines = js?["defines"]
    if (key_exists(js, "defines") && !(defines is _array)) {
        error = "{path}: `defines` is a list of strings `NAME`, `NAME=value` or `NAME(params)=value`, not {write_json(defines)}"
    } elif (key_exists(js, "defines")) {
        for (entry in defines as _array) {
            if (!(entry is _string) || !is_define(entry ?? "")) {
                error = "{path}: `defines` holds strings `NAME`, `NAME=value` or `NAME(params)=value`, not {write_json(entry)}"
                break
            }
            side.defines |> push(entry ?? "")
        }
    }
    read_flag(js, path, "solid_context", side.solid_context, error)
    read_flag(js, path, "jit_whole_program", side.jit_whole_program, error)
    read_inputs(js, path, side, error)
    read_members(js, path, "over_indexed", side.over_indexed, error)
    read_members(js, path, "padded", side.padded, error)
    delete_json(js)
    return <- side
}
