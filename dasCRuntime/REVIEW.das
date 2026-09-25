options gen2

require strings
require daslib/fio
require daslib/strings_boost
require dastest/review_gate

// The mechanical half of dasCRuntime/REVIEW.md (contract: REVIEW_COMMON.md at the repo root).
// Run from the repo root: daslang dasCRuntime/REVIEW.das - exit 0 clean, 1 with findings.

let MODULE_CPP = "dasCRuntime/src/dasCRuntime.cpp"
let TEST_DAS = "dasCRuntime/tests/test_crt.das"

def private quoted_after(line : string; marker : string) : string {
    let at = find(line, marker)
    if (at < 0) {
        return ""
    }
    let from = at + length(marker)
    let to = find(line, "\"", from)
    return to < 0 ? "" : slice(line, from, to)
}

def private bound_names(cpp : string) : array<string> {
    var names : array<string>
    for (line in split(cpp, "\n")) {
        if (find(line, "addExtern<") >= 0) {
            let name = quoted_after(line, "lib, \"")
            if (!empty(name)) {
                names |> push(name)
            }
        } elif (find(line, "addConstant(") >= 0) {
            let name = quoted_after(line, "*this, \"")
            if (!empty(name)) {
                names |> push(name)
            }
        }
    }
    return <- names
}

[export]
def main : int {
    if (!fexist(MODULE_CPP) || !fexist(TEST_DAS)) {
        gate_finding(MODULE_CPP, "the module source or its test is missing")
        return gate_verdict("dasCRuntime")
    }
    let test = fread(TEST_DAS)
    for (name in bound_names(fread(MODULE_CPP))) {
        if (find(test, "crt::{name}") < 0) {
            gate_finding(MODULE_CPP, "binds `{name}` but {TEST_DAS} never calls `crt::{name}` - every bind ships an arm asserting a value the C standard fixes")
        }
    }
    return gate_verdict("dasCRuntime")
}
