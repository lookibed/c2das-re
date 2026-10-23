options gen2

require strings
require daslib/strings_boost
require daslib/fio
require daslib/regex
require ../suite_files.das
require filter_rules

//! The torture import's filter (`daslang suites/gcc_torture/filter.das` from the repository
//! root, after a fetch): `skip.txt` is a line for every `execute/*.c` the first of
//! `filter_rules.das`'s `RULES` matches, less the ids `expected_pass.txt` lists.

let TESTS_DIR = "suites/gcc_torture/fetch/gcc/gcc/testsuite/gcc.c-torture/execute"
let SKIP_LEDGER = "suites/gcc_torture/skip.txt"
let EXPECTED_PASS = "suites/gcc_torture/expected_pass.txt"

[export]
def main : int {
    if (!fexist(TESTS_DIR)) {
        to_log(LOG_ERROR, "{TESTS_DIR} is missing: run suites/gcc_torture/fetch.sh\n")
        return 2
    }
    var compiled <- compile_rules()
    var passing : table<string>
    for (id in read_lines(EXPECTED_PASS)) {
        passing |> insert(id)
    }
    let ids <- c_file_ids(TESTS_DIR, "")
    var lines : array<string>
    for (id in ids) {
        let idx = key_exists(passing, id) ? -1 : first_rule(compiled, fread("{TESTS_DIR}/{id}.c"))
        if (idx >= 0) {
            lines |> push("{id}\t{RULES[idx].feature}\t{RULES[idx].reason}\t{RULES[idx].phase}")
        }
    }
    let text = build_string() $(writer) {
        writer |> write("# gcc-torture execute tests never run, one per line: id, feature, reason, the ledger row that\n# unblocks it (never for a construct no emulation reaches), tab-separated; written by\n# suites/gcc_torture/filter.das over the fetched tree, less the ids expected_pass.txt lists. A\n# test that merely does not pass yet is not listed; the ratchet reports it.\n")
        for (line in lines) {
            writer |> write("{line}\n")
        }
    }
    fwrite(SKIP_LEDGER, text)
    to_log(LOG_INFO, "filter: {length(lines)} of {length(ids)} tests skipped\n")
    return 0
}
