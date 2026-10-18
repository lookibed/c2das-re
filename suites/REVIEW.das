options gen2

require strings
require daslib/strings_boost
require daslib/fio
require dastest/review_gate

// The mechanical half of suites/REVIEW.md (contract: REVIEW_COMMON.md at the repo root).
// Run from the repo root: daslang suites/REVIEW.das - exit 0 clean, 1 with findings.

def private lines_of(path : string) : array<string> {
    var out : array<string>
    fopen(path, "rb") $(f) {
        if (f != null) {
            for (line in split(fread(f), "\n")) {
                let trimmed = strip(line)
                if (!empty(trimmed) && !(trimmed |> starts_with("#"))) {
                    out |> push(trimmed)
                }
            }
        }
    }
    return <- out
}

def private check_suite(suite : string) {
    let pass_path = "suites/{suite}/expected_pass.txt"
    let skip_path = "suites/{suite}/skip.txt"
    var passing : table<string>
    var previous = ""
    for (id in lines_of(pass_path)) {
        if (id <= previous) {
            gate_finding(pass_path, "`{id}` after `{previous}`: the ratchet is kept sorted and unique")
        }
        previous = id
        passing |> insert(id)
    }
    for (line in lines_of(skip_path)) {
        var inscope fields <- split(line, "\t")
        if (length(fields) != 4 || !(fields[3] |> starts_with("P"))) {
            gate_finding(skip_path, "`{line}`: a skip line is id, feature, reason, phase (P<n>), tab-separated")
            continue
        }
        if (key_exists(passing, fields[0])) {
            gate_finding(skip_path, "`{fields[0]}` is skipped and in the ratchet at once")
        }
    }
}

// a suite's fetched inputs and work tree are regenerated, never tracked: `.gitignore` keeps
// them out of `git add`, and this check catches a forced add
def private check_untracked_folders {
    var listed : string
    run_and_capture(["git", "ls-files", "suites/*/fetch", "suites/*/work"], listed, 60.0)
    for (path in split(strip(listed), "\n")) {
        if (!empty(path)) {
            gate_finding(path, "a suite's fetch/ or work/ folder is never committed")
        }
    }
}

[export]
def main : int {
    check_suite("c_testsuite")
    check_untracked_folders()
    return gate_verdict("suites")
}
