options gen2

module sidecar public

require strings
require daslib/fio
require daslib/json_boost

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
}

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
    var text = ""
    fopen(path, "rb") $(f) {
        if (f != null) {
            text = fread(f)
        }
    }
    var js = read_json(text, error)
    if (js == null) {
        error = "{path}: {error}"
    }
    return js
}

//! Reads a sidecar file; `error` names a file that is not JSON or a key of the wrong shape.
def read_sidecar(path : string; var error : string&) : Sidecar {
    var side : Sidecar
    if (empty(path)) {
        return <- side
    }
    var js = read_json_file(path, error)
    if (js == null) {
        return <- side
    }
    let marshal = js?["marshal"]
    if (marshal != null && !(marshal is _array)) {
        error = "{path}: `marshal` is a list of type names"
    } elif (marshal != null) {
        for (name in marshal as _array) {
            side.marshal |> insert(name ?? "")
        }
    }
    side.stack = int(js?["stack"] ?? 0l)
    side.alloca_limit = int(js?["alloca_limit"] ?? 0l)
    delete_json(js)
    return <- side
}
