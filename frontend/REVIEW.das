options gen2

require strings
require math
require daslib/fio
require daslib/strings_boost
require dastest/review_gate

// The mechanical half of frontend/REVIEW.md (contract: REVIEW_COMMON.md at the repo root).
// Run from the repo root: daslang frontend/REVIEW.das - exit 0 clean, 1 with findings.

let private ROOT = "frontend"

let CLANG_MODULE = "cbind"

let private REQUIRE = "require"

let INCLUDE = "include"

// the folder of the predefined-macro tables and their extension: text no daslang loads
let private TABLES = "predefined"

let private TABLE_EXT = ".defs"

let SPAWNERS <- ["popen", "popen_binary", "popen_timeout", "popen_argv", "popen_argv_pipe", "spawn_process", "spawn_argv", "with_process", "run_and_capture", "executable_on_path", "system"]

// the length of the character literal at `at` of `chars` (`'a'`, `'\\n'`), 0 when none starts there
def private char_literal_length(chars; at : int) : int {
    let count = length(chars)
    if (int(chars[at]) != '\'') {
        return 0
    }
    if (at + 3 < count && int(chars[at + 1]) == '\\' && int(chars[at + 3]) == '\'') {
        return 4
    }
    return at + 2 < count && int(chars[at + 2]) == '\'' ? 3 : 0
}

//! `text` with its comments and the characters of its string and character literals blanked, the
//! line breaks kept; the code inside a string's `\{...\}` stays, since it runs.
def code_of(text : string) : string {
    return build_string() $(var writer) {
        peek_data(text) $(chars) {
            let count = length(chars)
            // one entry per open string literal (true) and per open brace of code inside one (false)
            var inscope open : array<bool>
            var block_depth = 0
            var in_line_comment = false
            var at = 0
            while (at < count) {
                let ch = int(chars[at])
                let next = at + 1 < count ? int(chars[at + 1]) : 0
                let in_string = !empty(open) && open[length(open) - 1]
                var is_code = false
                var step = 1
                if (ch == '\n') {
                    in_line_comment = false
                } elif (in_line_comment) {
                    step = 1
                } elif (block_depth > 0) {
                    if (ch == '*' && next == '/') {
                        block_depth--
                        step = 2
                    } elif (ch == '/' && next == '*') {
                        block_depth++
                        step = 2
                    }
                } elif (in_string) {
                    if (ch == '\\') {
                        step = 2
                    } elif (ch == '"') {
                        open |> pop()
                    } elif (ch == '{') {
                        open |> push(false)
                    }
                } elif (ch == '/' && next == '/') {
                    in_line_comment = true
                } elif (ch == '/' && next == '*') {
                    block_depth = 1
                    step = 2
                } elif (ch == '"') {
                    open |> push(true)
                } elif (char_literal_length(chars, at) > 0) {
                    step = char_literal_length(chars, at)
                } elif (ch == '{' && !empty(open)) {
                    open |> push(false)
                } elif (ch == '}' && !empty(open)) {
                    open |> pop()
                } else {
                    is_code = true
                }
                for (offset in range(min(step, count - at))) {
                    let written = int(chars[at + offset])
                    writer |> write_char(is_code || written == '\n' ? written : ' ')
                }
                at += step
            }
        }
    }
}

// the file a `require` of `target` in a file of folder `folder` names by path or as a sibling
// module, "" when a module folder or daslib resolves it
def private required_file(folder, target : string) : string {
    let file = path_join(folder, target |> ends_with(".das") ? target : "{target}.das")
    return fexist(file) ? file : ""
}

// the files under `folder`, subfolders included, sorted
def private files_under(folder : string) : array<string> {
    var files : array<string>
    dir_rec(folder) $(name, is_dir) {
        if (!is_dir) {
            files |> push(path_join(folder, clone_string(name)))
        }
    }
    sort(files)
    return <- files
}

// whether `word` is spelled as a module of a `require` is: letters, digits, `_`, `.`, `/` and `-`
def private is_module_path(word : string) : bool {
    for (ch in word) {
        if (!is_alpha(ch) && !is_number(ch) && ch != '_' && ch != '.' && ch != '/' && ch != '-') {
            return false
        }
    }
    return !empty(word)
}

//! Findings of the file `path` and of every file it requires by path or as a sibling module, each
//! named with `via`, the file under `frontend/` the chain starts at. Outside comments and literals:
//! the name of a function that starts a process, as a whole identifier, called or not; an
//! `include`, since the gate follows no text include; and a line that holds `require` and names
//! the clang binding in any word, or is not `require <module>` with an optional `public`.
def check_file(path, via : string; var checked : table<string>) {
    let canonical = get_full_file_name(path)
    if (key_exists(checked, canonical)) {
        return
    }
    checked |> insert(canonical)
    let reached = path == via ? "" : " (required from {via})"
    var inscope lines <- split(code_of(fread(path)), "\n")
    for (line, line_no in lines, count(1)) {
        for (spawner in SPAWNERS) {
            if (contains_word(line, spawner)) {
                gate_finding(path, line_no, "names `{spawner}`{reached}: nothing under {ROOT}/ starts a process")
            }
        }
        if (contains_word(line, INCLUDE)) {
            gate_finding(path, line_no, "has an `{INCLUDE}`{reached}: the gate follows no text include, require a module instead")
        }
        if (!contains_word(line, REQUIRE)) {
            continue
        }
        var inscope parts <- [for (part in split_by_chars(line, " \t")); part; where !empty(part)]
        let is_plain = (length(parts) >= 2 && parts[0] == REQUIRE && is_module_path(parts[1])
            && (length(parts) == 2 || (length(parts) == 3 && parts[2] == "public")))
        if (contains_word(line, CLANG_MODULE)) {
            gate_finding(path, line_no, "requires `{CLANG_MODULE}`{reached}: nothing under {ROOT}/ needs clang")
        } elif (!is_plain) {
            gate_finding(path, line_no, "has a `{REQUIRE}` line{reached} that is not `{REQUIRE} <module>` or `{REQUIRE} <module> public`: the gate cannot name its module")
        } else {
            let file = required_file(dir_name(path), parts[1])
            if (!empty(file)) {
                check_file(file, via, checked)
            }
        }
    }
}

//! The gate over the folder `root`: every `.das` file is checked with what it requires; a `.h`
//! file, a `.md` file and a `.defs` table of `<root>/predefined/` hold no daslang; any other file
//! is a finding, since daslang can load it as source and the gate does not read it.
def check_tree(root : string) {
    var inscope files <- files_under(root)
    let tables = path_join(root, TABLES) + "/"
    for (file in files) {
        if (file |> ends_with(".das")) {
            var inscope checked : table<string>
            check_file(file, file, checked)
        } elif (!(file |> ends_with(".h")) && !(file |> ends_with(".md")) && !(file |> starts_with(tables) && file |> ends_with(TABLE_EXT))) {
            gate_finding(file, "is no .das, .h or .md file and no {TABLES}/*{TABLE_EXT} table: the gate reads no other source")
        }
    }
}

[export]
def main : int {
    check_tree(ROOT)
    return gate_verdict(ROOT)
}
