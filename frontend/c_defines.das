options gen2

module c_defines public

require strings
require daslib/strings_boost
require daslib/fio
require daslib/rtti

//! The macro definitions a C program is preprocessed under, before its first line
//! (`frontend/ARCHITECTURE.md` section 3): the one parser of an entry `NAME`, `NAME=value` or
//! `NAME(params)=value`, which a sidecar's `defines` and a dialect's predefined-macro table are
//! both spelled in, and the reader of such a table.

//! One macro definition: `NAME` alone has the value `1`, as `-DNAME` gives it; `params` are those
//! of a function-like macro, `...` the last when it is variadic.
struct Define {
    name : string
    fn_like : bool
    params : array<string>
    value : string
}

//! The dialects a predefined-macro table exists for, as `--target` names them.
let DIALECTS <- ["linux", "msvc"]

let private TABLE_DIR = "predefined"

let private TABLE_EXT = ".defs"

let private INCLUDE_DIR = "include"

//! The table entries no clang predefines: the converter's own statement that it lowers no
//! variable-length array (C11 6.10.8.3).
let CONVERTER_ENTRIES <- ["__STDC_NO_VLA__=1"]

let private COMMENT = "#"

let private VARIADIC = "..."

//! Whether `name` is a C identifier.
def is_identifier(name : string) : bool {
    if (empty(name)) {
        return false
    }
    for (idx, ch in count(), name) {
        if (!(ch == '_' || is_alpha(ch) || (idx > 0 && is_number(ch)))) {
            return false
        }
    }
    return true
}

//! `entry` read as a macro definition into `parsed`: `NAME`, `NAME=value`, or a function-like
//! `NAME(params)=value` whose params are identifiers separated by commas, `...` last. False, with
//! `parsed` in no defined state, for any other text.
def parse_define(entry : string; var parsed : Define) : bool {
    let eq = find(entry, "=")
    let head = eq < 0 ? entry : slice(entry, 0, eq)
    let paren = find(head, "(")
    parsed.value = eq < 0 ? "1" : slice(entry, eq + 1)
    parsed.fn_like = paren >= 0
    parsed.name = paren < 0 ? head : slice(head, 0, paren)
    parsed.params |> clear()
    if (!is_identifier(parsed.name) || (parsed.fn_like && (eq < 0 || !(head |> ends_with(")"))))) {
        return false
    }
    let inside = parsed.fn_like ? strip(slice(head, paren + 1, length(head) - 1)) : ""
    if (empty(inside)) {
        return true
    }
    let params <- split(inside, ",")
    for (idx, param in count(), params) {
        let name = strip(param)
        if (!is_identifier(name) && !(name == VARIADIC && idx == length(params) - 1)) {
            return false
        }
        parsed.params |> push(name)
    }
    return true
}

//! Whether `entry` is a macro definition `parse_define` reads.
def is_define(entry : string) : bool {
    var parsed : Define
    return parse_define(entry, parsed)
}

// this module's folder: relative when the running script was named by a relative path, so it
// holds while the working directory does
def private module_dir : string {
    let at = get_line_info()
    return dir_name(string(at.fileInfo.name))
}

//! The file of the predefined-macro table of `dialect`, beside this module wherever the converter
//! runs from.
def predefined_path(dialect : string) : string => path_join(path_join(module_dir(), TABLE_DIR), dialect + TABLE_EXT)

//! The folder of the own libc headers (`include/ARCHITECTURE.md`), beside this module wherever the
//! converter runs from.
def own_include_dir : string => path_join(module_dir(), INCLUDE_DIR)

//! The entries of the table text `text`, in its order: one entry a line as written, an empty line
//! and a line starting with `#` skipped. `error` names `path` and the line of the first line that
//! is no entry (one with a blank at either end included) or that defines a name a line above
//! defines; the entries are then not to be used.
def parse_predefined(text, path : string; var error : string&) : array<string> {
    var entries : array<string>
    var line_of : table<string; int>
    var parsed : Define
    for (line, line_no in split(text, "\n"), count(1)) {
        if (empty(line) || line |> starts_with(COMMENT)) {
            continue
        }
        if (line != strip(line) || !parse_define(line, parsed)) {
            error = "{path}:{line_no}: `{line}` is no entry `NAME`, `NAME=value` or `NAME(params)=value`"
            return <- entries
        }
        if (key_exists(line_of, parsed.name)) {
            error = "{path}:{line_no}: `{parsed.name}` is defined at line {line_of?[parsed.name] ?? 0} already"
            return <- entries
        }
        line_of |> insert(parsed.name, line_no)
        entries |> push(line)
    }
    return <- entries
}

//! The entries of the table file `path` (`parse_predefined`); `error` names a file that is
//! missing or holds no entry.
def read_predefined(path : string; var error : string&) : array<string> {
    if (!fexist(path)) {
        error = "{path}: no such predefined-macro table"
        return <- array<string>()
    }
    var entries <- parse_predefined(fread(path), path, error)
    if (empty(error) && empty(entries)) {
        error = "{path}: the predefined-macro table holds no entry"
    }
    return <- entries
}
