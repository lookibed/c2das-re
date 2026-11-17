options gen2

require daslib/fio
require daslib/json_boost
require daslib/strings_boost
require strings

//! The translator page's Run (web/ARCHITECTURE.md section 9) gives the interpreter c2das-re's `c_runtime`
//! module folder (`-load_module`): this bundles a module folder's `.das_module` and the `.das` files of its
//! same-named subfolder (`c_runtime/c_runtime/`, the paths the `.das_module` registers) into one JSON
//! object, relative path to text.
//! usage: daslang web/translator/bundle.das -- <module folder> <out.json>

[export]
def main : int {
    let args <- get_command_line_arguments()
    let at = find_index(args, "--")
    if (at < 0 || length(args) - at - 1 != 2) {
        to_log(LOG_ERROR, "usage: bundle.das -- <folder> <out.json>\n")
        return 2
    }
    let folder = args[at + 1]
    if (!fexist(path_join(folder, ".das_module"))) {
        to_log(LOG_ERROR, "bundle: {folder} has no .das_module\n")
        return 1
    }
    let sub = base_name(folder)
    var names : array<string>
    dir(path_join(folder, sub)) $(name) {
        if (ends_with(name, ".das")) {
            names |> push("{sub}/{name}")
        }
    }
    if (empty(names)) {
        to_log(LOG_ERROR, "bundle: no .das file in {folder}/{sub}\n")
        return 1
    }
    names |> push(".das_module")
    sort(names)
    var fields : array<string>
    fields |> reserve(length(names))
    for (name in names) {
        fields |> push("{write_json(JV(name))}: {write_json(JV(fread(path_join(folder, name))))}")
    }
    if (!fwrite(args[at + 2], "\{{join(fields, ",\n")}\}\n")) {
        to_log(LOG_ERROR, "bundle: cannot write {args[at + 2]}\n")
        return 1
    }
    return 0
}
