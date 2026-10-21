options gen2

module suite_files public

require strings
require daslib/strings_boost
require daslib/fio
require dastest/review_gate

//! The files the suites and the readability metric agree on: a ratchet and its ledger as lines,
//! the C files of a folder by id, and the input keys the readability capture must hold. It needs
//! no module folder, so the `REVIEW.das` gates require it as they run, standalone.

//! the suites whose `expected_pass.txt` the readability metric converts, sorted
let RATCHET_SUITES <- ["c_testsuite", "csmith", "gcc_torture"]

//! the folder of the perf kernels, from the repository root
let KERNELS = "perf/kernels"

//! The text before the first `sep` in `text`, all of it when there is none.
def text_before(text, sep : string) : string {
    let at = find(text, sep)
    return at < 0 ? text : slice(text, 0, at)
}

//! The first line of `text`.
def first_line(text : string) : string => text_before(text, "\n")

//! The lines of `path`, stripped, blank lines and `#` comments dropped; none when it is missing.
def read_lines(path : string) : array<string> {
    var lines : array<string>
    if (!fexist(path)) {
        return <- lines
    }
    for (line in split(fread(path), "\n")) {
        let trimmed = strip(line)
        if (!empty(trimmed) && !(trimmed |> starts_with("#"))) {
            lines |> push(trimmed)
        }
    }
    return <- lines
}

//! The ratchet and the ledger as a run reads them: the ids `expected_pass.txt` lists, as read and
//! as a set, and the ids `skip.txt` lists.
struct Ratchet {
    expected : array<string>
    expected_set : table<string>
    skips : table<string>
}

def read_ratchet(expected_pass, skip_ledger : string) : Ratchet {
    var r : Ratchet
    for (line in read_lines(skip_ledger)) {
        r.skips |> insert(split(line, "\t")[0])
    }
    r.expected <- read_lines(expected_pass)
    for (id in r.expected) {
        r.expected_set |> insert(id)
    }
    return <- r
}

//! The ids of the `.c` files directly under `dir` whose name holds `filter`, sorted.
def c_file_ids(dir_path, filter : string) : array<string> {
    var ids : array<string>
    dir(dir_path) $(name) {
        if (name |> ends_with(".c") && (empty(filter) || find(name, filter) >= 0)) {
            ids |> push(slice(name, 0, length(name) - 2))
        }
    }
    ids |> sort()
    return <- ids
}

//! The suffix of a kernel's input key converted under `--param-writes copy` (`perf/blit@copy`).
let COPY_KEY_SUFFIX = "@copy"

//! Every input key (`<group>/<id>`) the readability metric converts, sorted: each ratchet
//! suite's listed ids less its ledgered ones, and every kernel under both parameter write
//! modes.
def expected_input_keys : array<string> {
    let kernels <- c_file_ids(KERNELS, "")
    var keys <- [for (name in kernels); "perf/{name}"]
    keys |> push_from([for (name in kernels); "perf/{name}{COPY_KEY_SUFFIX}"])
    for (suite in RATCHET_SUITES) {
        var inscope r <- read_ratchet("suites/{suite}/expected_pass.txt", "suites/{suite}/skip.txt")
        keys |> reserve(length(keys) + length(r.expected))
        for (id in r.expected) {
            if (!key_exists(r.skips, id)) {
                keys |> push("{suite}/{id}")
            }
        }
    }
    keys |> sort()
    return <- keys
}

//! A gate finding, `message`, per tracked file under `pathspecs`: the folders it names hold
//! regenerated files, which `.gitignore` keeps out of `git add` and a forced add gets past.
def gate_untracked(pathspecs : array<string>; message : string) {
    var listed : string
    var argv <- ["git", "ls-files"]
    argv |> push_from(pathspecs)
    run_and_capture(argv, listed, 60.0)
    for (path in split(strip(listed), "\n")) {
        if (!empty(path)) {
            gate_finding(path, message)
        }
    }
}
