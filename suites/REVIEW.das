options gen2

require strings
require daslib/strings_boost
require daslib/fio
require dastest/review_gate
require suite_files
require ../converter/cir.das
require ../metrics/readability_file.das

// The mechanical half of suites/REVIEW.md (contract: REVIEW_COMMON.md at the repo root).
// Run from the repo root: daslang suites/REVIEW.das - exit 0 clean, 1 with findings.

def private check_suite(suite : string) {
    let pass_path = "suites/{suite}/expected_pass.txt"
    let skip_path = "suites/{suite}/skip.txt"
    var passing : table<string>
    var previous = ""
    for (id in read_lines(pass_path)) {
        if (id <= previous) {
            gate_finding(pass_path, "`{id}` after `{previous}`: the ratchet is kept sorted and unique")
        }
        previous = id
        passing |> insert(id)
    }
    for (line in read_lines(skip_path)) {
        var inscope fields <- split(line, "\t")
        if (length(fields) != 4 || !(fields[3] |> starts_with("P") || fields[3] == "never")) {
            gate_finding(skip_path, "`{line}`: a skip line is id, feature, reason, ledger row id (P<n>.<m>, or never for a construct the dialect excludes or clang rejects), tab-separated")
            continue
        }
        if (key_exists(passing, fields[0])) {
            gate_finding(skip_path, "`{fields[0]}` is skipped and in the ratchet at once")
        }
    }
}

// a csmith id is the seed csmith takes, a decimal number, in the ratchet and the ledger alike
def private check_seeds(suite : string) {
    for (file in fixed_array("expected_pass.txt", "skip.txt")) {
        let path = "suites/{suite}/{file}"
        for (line in read_lines(path)) {
            let seed = split(line, "\t")[0]
            if (!is_digit_run(seed, 0)) {
                gate_finding(path, "`{seed}`: a csmith id is a decimal seed")
            }
        }
    }
}

// the readability capture measures every id the ratchets list: a diff to a ratchet re-records it
def private check_readability_inputs {
    let capture_path = "metrics/readability_linux.json"
    for (finding in check_input_keys(fexist(capture_path) ? fread(capture_path) : "\{\}", expected_input_keys())) {
        gate_finding(capture_path, finding)
    }
}

[export]
def main : int {
    check_suite("c_testsuite")
    check_suite("gcc_torture")
    check_suite("csmith")
    check_seeds("csmith")
    gate_untracked(["suites/*/fetch", "suites/*/work"], "a suite's fetch/ or work/ folder is never committed")
    check_readability_inputs()
    return gate_verdict("suites")
}
