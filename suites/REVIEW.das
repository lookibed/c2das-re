options gen2

require daslib/strings_boost
require daslib/fio
require dastest/review_gate
require suite_files
require gcc_torture/filter_rules
require ../converter/cir.das
require ../metrics/readability_file.das

// The mechanical half of suites/REVIEW.md (contract: REVIEW_COMMON.md at the repo root).
// Run from the repo root: daslang suites/REVIEW.das - exit 0 clean, 1 with findings.

def private check_suite(suite : string; highest_closed : int) {
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
        if (length(fields) != 4 || !phase_well_formed(fields[3])) {
            gate_finding(skip_path, "`{line}`: a skip line is id, feature, reason, ledger row id (P<n> or P<n>.<m>, the minor number may end in one lowercase letter) or never, tab-separated")
            continue
        }
        if (key_exists(passing, fields[0])) {
            gate_finding(skip_path, "`{fields[0]}` is skipped and in the ratchet at once")
        }
        if (names_closed_phase(fields[3], highest_closed)) {
            gate_finding(skip_path, "`{fields[0]}` names {fields[3]}, a closed phase (phases up to P{highest_closed} are closed): a skip line names a live row or never")
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

// every filter rule names a live ledger row id or never, as the skip lines it writes do
def private check_rule_phases(highest_closed : int) {
    for (rule in RULES) {
        if (!phase_well_formed(rule.phase) || names_closed_phase(rule.phase, highest_closed)) {
            gate_finding("suites/gcc_torture/filter_rules.das", "the rule for `{rule.feature}` names {rule.phase}: a rule's phase is a ledger row id of a phase above P{highest_closed} or never")
        }
    }
}

// the highest closed phase: the repository's `v0.<N>.0` tags, at least the floor
def private closed_phase : int {
    var listed : string
    run_and_capture(["git", "tag", "--list", "v0.*.0"], listed, 60.0)
    return highest_closed_phase(split(listed, "\n"))
}

[export]
def main : int {
    let highest_closed = closed_phase()
    check_suite("c_testsuite", highest_closed)
    check_suite("gcc_torture", highest_closed)
    check_suite("csmith", highest_closed)
    check_seeds("csmith")
    check_rule_phases(highest_closed)
    gate_untracked(["suites/*/fetch", "suites/*/work"], "a suite's fetch/ or work/ folder is never committed")
    check_readability_inputs()
    return gate_verdict("suites")
}
