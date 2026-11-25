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

let SPAWNERS <- ["popen", "popen_binary", "popen_timeout", "popen_argv", "popen_argv_pipe", "run_and_capture", "system"]

// every character that is no part of an identifier
let private PUNCTUATION = " \t!\"#$%&'()*+,-./:;<=>?@[\\]^`\{|\}~"

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
//! binding, the word after `require` whatever blanks part them, and the name of a function that
//! starts a process as a whole identifier, called or not, outside comments and literals.
def check_file(path, via : string; var checked : table<string>) {
    let canonical = get_full_file_name(path)
    if (key_exists(checked, canonical)) {
        return
    }
    checked |> insert(canonical)
    let reached = path == via ? "" : " (required from {via})"
    var inscope lines <- split(code_of(fread(path)), "\n")
    for (line, line_no in lines, count(1)) {
        var inscope words <- split_by_chars(line, PUNCTUATION)
        for (word in words) {
            if (has_value(SPAWNERS, word)) {
                gate_finding(path, line_no, "names `{word}`{reached}: nothing under {ROOT}/ starts a process")
            }
        }
        var inscope spaced <- [for (word in split_by_chars(line, " \t;,()\{\}")); word; where !empty(word)]
        for (word, index in spaced, count()) {
            if (word != "require" || index + 1 >= length(spaced)) {
                continue
            }
            let target = spaced[index + 1]
            if (target == CLANG_MODULE || target |> starts_with("{CLANG_MODULE}/")) {
                gate_finding(path, line_no, "requires `{target}`{reached}: nothing under {ROOT}/ needs clang")
            }
            let file = required_file(dir_name(path), target)
            if (!empty(file)) {
                check_file(file, via, checked)
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
