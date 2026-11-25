options gen2

require strings
require daslib/fio
require daslib/strings_boost
require dastest/review_gate

// The mechanical half of frontend/REVIEW.md (contract: REVIEW_COMMON.md at the repo root).
// Run from the repo root: daslang frontend/REVIEW.das - exit 0 clean, 1 with findings.

let private ROOT = "frontend"

let CLANG_MODULE = "cbind"

let SPAWNERS <- ["popen", "popen_binary", "popen_timeout", "popen_argv", "popen_argv_pipe", "run_and_capture", "system"]

def private is_name_char(ch : int) : bool => is_alpha(ch) || is_number(ch) || ch == '_'

// whether `line` calls `name`: the name, not the tail of a longer one, then `(`
def private calls(line, name : string) : bool {
    var found = false
    peek_data(line) $(text) {
        var at = find(line, "{name}(")
        while (at >= 0 && !found) {
            found = at == 0 || !is_name_char(int(text[at - 1]))
            at = find(line, "{name}(", at + 1)
        }
    }
    return found
}

// the file a `require` of `target` in a file of folder `folder` names by path or as a sibling
// module, "" when a module folder or daslib resolves it
def private required_file(folder, target : string) : string {
    let file = path_join(folder, target |> ends_with(".das") ? target : "{target}.das")
    return fexist(file) ? file : ""
}

def private das_files(folder : string; var files : array<string>) {
    var inscope entries : array<string>
    dir(folder) $(entry) {
        entries |> push(clone_string(entry))
    }
    sort(entries)
    for (entry in entries) {
        let path = path_join(folder, entry)
        if (entry |> ends_with(".das")) {
            files |> push(path)
        } elif (entry != "." && entry != ".." && stat(path).is_dir) {
            das_files(path, files)
        }
    }
}

//! Findings of the file `path` and of every file it requires by path or as a sibling module, each
//! named with `via`, the file under `frontend/` the chain starts at: a `require` of the clang
//! binding and a call of a function that starts a process.
def check_file(path, via : string; var checked : table<string>) {
    let canonical = get_full_file_name(path)
    if (key_exists(checked, canonical)) {
        return
    }
    checked |> insert(canonical)
    let reached = path == via ? "" : " (required from {via})"
    var inscope lines <- split(fread(path), "\n")
    for (text, line_no in lines, count(1)) {
        let line = strip(text)
        if (line |> starts_with("//")) {
            continue
        }
        if (line |> starts_with("require ")) {
            let target = split(slice(line, 8), " ")[0]
            if (target == CLANG_MODULE || target |> starts_with("{CLANG_MODULE}/")) {
                gate_finding(path, line_no, "requires `{target}`{reached}: nothing under {ROOT}/ needs clang")
            }
            let file = required_file(dir_name(path), target)
            if (!empty(file)) {
                check_file(file, via, checked)
            }
            continue
        }
        for (spawner in SPAWNERS) {
            if (calls(line, spawner)) {
                gate_finding(path, line_no, "calls `{spawner}`{reached}: nothing under {ROOT}/ starts a process")
            }
        }
    }
}

[export]
def main : int {
    var inscope files : array<string>
    das_files(ROOT, files)
    for (file in files) {
        var inscope checked : table<string>
        check_file(file, file, checked)
    }
    return gate_verdict(ROOT)
}
