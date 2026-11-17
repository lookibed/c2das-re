options gen2

require daslib/json
require daslib/json_boost
require daslib/fio
require daslib/clargs
require strings
require daslib/strings_boost

//! The reference of the quakegeneric page (web/ARCHITECTURE.md section 7): the `frame[i]=v` lines of
//! the expected stdout of the Rust repository's case `quakegeneric-demo1-std`, the native entry's
//! 100 frame hashes, written one a line.
//! usage: daslang web/quake/expected_frames.das -- <cases.json> <out>

[export]
def main : int {
    let args <- get_user_args()
    if (length(args) != 2) {
        to_log(LOG_ERROR, "usage: expected_frames.das -- <cases.json> <out>\n")
        return 2
    }
    var error : string
    var root = read_json(fread(args[0]), error)
    if (root == null) {
        to_log(LOG_ERROR, "expected_frames: {args[0]}: {error}\n")
        return 1
    }
    // {"cases": [...]}: the case whose id names the quakegeneric demo
    var text = ""
    let cases = root?["cases"]
    if (cases != null && cases.value is _array) {
        for (c in cases.value as _array) {
            if ((c?["id"] ?? "") == "quakegeneric-demo1-std") {
                text = c?["expected"]?["stdout"] ?? ""
            }
        }
    }
    var lines : array<string>
    for (line in split(text, "\n")) {
        if (starts_with(line, "frame[")) {
            lines |> push(line)
        }
    }
    if (length(lines) != 100) {
        to_log(LOG_ERROR, "expected_frames: {args[0]} holds {length(lines)} frame lines for quakegeneric-demo1-std, not 100\n")
        return 1
    }
    fwrite(args[1], join(lines, "\n") + "\n")
    return 0
}
