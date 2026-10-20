options gen2

require daslib/fio
require dastest/review_gate
require readability_file
require ../suites/suite_files.das

// The mechanical half of metrics/REVIEW.md (contract: REVIEW_COMMON.md at the repo root).
// Run from the repo root: daslang metrics/REVIEW.das - exit 0 clean, 1 with findings.

let CAPTURE = "metrics/readability_linux.json"

def private check_capture_file {
    if (!fexist(CAPTURE)) {
        gate_finding(CAPTURE, "the committed capture is missing: run scripts/run_readability.sh --update")
        return
    }
    let text = fread(CAPTURE)
    for (finding in check_capture(text)) {
        gate_finding(CAPTURE, finding)
    }
    for (finding in check_input_keys(text, expected_input_keys())) {
        gate_finding(CAPTURE, finding)
    }
}

[export]
def main : int {
    check_capture_file()
    gate_untracked(["metrics/work"], "metrics/work/ is converted output, never committed")
    return gate_verdict("metrics")
}
