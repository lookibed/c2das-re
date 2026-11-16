options gen2

module suite_files public

require strings
require math
require daslib/strings_boost
require daslib/fio
require dastest/review_gate
require ../converter/cir.das

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

//! The suffix of a kernel's input key converted under `--loops while` (`perf/primes@while`).
let WHILE_KEY_SUFFIX = "@while"

//! The suffix of a kernel's input key converted under `--first-member reinterpret`
//! (`perf/blit@reinterpret`).
let REINTERPRET_KEY_SUFFIX = "@reinterpret"

//! The suffix of a kernel's or a Lua program's input key converted under `--inline-helpers`
//! (`perf/fixed_mandel@inline`, `lua/lua@inline`, the source layout).
let INLINE_KEY_SUFFIX = "@inline"

//! The suffix of a kernel's or a Lua program's input key converted under `--switch-dispatch goto`
//! (`perf/switch_goto@goto`, `lua/lua@goto`, the source layout).
let GOTO_KEY_SUFFIX = "@goto"

//! The suffix of a kernel's or a Lua program's input key converted under `--switch-dispatch table`
//! (`perf/switch_goto@table`, `lua/lua@table`, the source layout).
let TABLE_KEY_SUFFIX = "@table"

//! The suffix of a kernel's or a Lua program's input key converted under `--checks off`
//! (`perf/sieve@checks-off`, `lua/lua@checks-off`, the source layout).
let CHECKS_OFF_KEY_SUFFIX = "@checks-off"

//! The suffix of a kernel's or a Lua program's input key converted under `--past-end inline`
//! (`perf/blit@past-end-inline`, `lua/lua@past-end-inline`, the source layout).
let PAST_END_KEY_SUFFIX = "@past-end-inline"

//! The suffix of a kernel's or a Lua program's input key converted under `--fn-macros expand`
//! (`perf/blit@fn-macros-expand`, `lua/lua@fn-macros-expand`, the source layout).
let FN_MACROS_EXPAND_KEY_SUFFIX = "@fn-macros-expand"

//! The suffixes of a kernel's or a Lua program's input key converted under `--forms-off` of one
//! form (`perf/blit@pointer-steps-off`, `lua/lua@c-switch-off`, the source layout), in `FORMS`'
//! order, and the form each names.
let FORMS_OFF_KEY_SUFFIXES <- ["@pointer-steps-off", "@ranged-loops-off", "@c-switch-off"]
let FORMS_OFF_KEY_FORMS <- ["pointer_steps", "ranged_loops", "c_switch"]

//! The suffixes of a kernel's input key converted under a non-default option, each kernel's key
//! once per suffix.
let KERNEL_MODE_SUFFIXES <- [COPY_KEY_SUFFIX, WHILE_KEY_SUFFIX, REINTERPRET_KEY_SUFFIX, INLINE_KEY_SUFFIX, GOTO_KEY_SUFFIX, TABLE_KEY_SUFFIX, CHECKS_OFF_KEY_SUFFIX, PAST_END_KEY_SUFFIX, FN_MACROS_EXPAND_KEY_SUFFIX, "@pointer-steps-off", "@ranged-loops-off", "@c-switch-off"]

//! The suffixes of a Lua program's input key converted in the source layout under an opt-in.
let LUA_OPT_IN_SUFFIXES <- [INLINE_KEY_SUFFIX, GOTO_KEY_SUFFIX, TABLE_KEY_SUFFIX, CHECKS_OFF_KEY_SUFFIX, PAST_END_KEY_SUFFIX, FN_MACROS_EXPAND_KEY_SUFFIX, "@pointer-steps-off", "@ranged-loops-off", "@c-switch-off"]

//! The suffix of a Lua input key converted in the single layout (`lua/lua@single`), and of one in
//! the source-cut layout (`lua/lua@source-cut`); the bare key (`lua/lua`) is the source layout, the
//! converter's default.
let SINGLE_KEY_SUFFIX = "@single"
let CUT_KEY_SUFFIX = "@source-cut"

//! The Lua programs (`lua/sources.das`) the readability metric measures, each in the three layouts (source, source-cut, single).
let LUA_PROGRAMS <- ["lua", "luac"]

//! The kernel id a perf input key names: the key's id less its mode suffix.
def kernel_of_key(id : string) : string {
    for (suffix in KERNEL_MODE_SUFFIXES) {
        if (id |> ends_with(suffix)) {
            return slice(id, 0, length(id) - length(suffix))
        }
    }
    return id
}

//! Every input key (`<group>/<id>`) the readability metric converts, sorted: each ratchet
//! suite's listed ids less its ledgered ones, and every kernel converted by default, under
//! `--param-writes copy`, under `--loops while`, under `--first-member reinterpret`, under
//! `--inline-helpers`, under `--switch-dispatch goto` and `table`, under `--checks off`, under `--past-end
//! inline`, under `--fn-macros expand` and under `--forms-off` of each form, and each Lua program
//! in the three layouts and, in the source layout, under each of the last nine.
def expected_input_keys : array<string> {
    let kernels <- c_file_ids(KERNELS, "")
    var keys <- [for (name in kernels); "perf/{name}"]
    for (suffix in KERNEL_MODE_SUFFIXES) {
        keys |> push_from([for (name in kernels); "perf/{name}{suffix}"])
    }
    for (suffix in ["", SINGLE_KEY_SUFFIX, CUT_KEY_SUFFIX]) {
        keys |> push_from([for (name in LUA_PROGRAMS); "lua/{name}{suffix}"])
    }
    for (suffix in LUA_OPT_IN_SUFFIXES) {
        keys |> push_from([for (name in LUA_PROGRAMS); "lua/{name}{suffix}"])
    }
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

//! The highest phase a repository closes when it carries no `v0.<N>.0` tag (a shallow clone):
//! phases 1 to 4 closed with v0.4.0, and the owner's ruling (2026-10-22, item B) bars a skip line
//! from naming a closed phase.
let CLOSED_PHASE_FLOOR = 4

//! The phase a skip line's phase column names: `P7.5` and `P7` are 7, `P3.3` is 3; `never` and
//! any other text -1.
def phase_number(phase : string) : int {
    if (!(phase |> starts_with("P")) || length(phase) < 2) {
        return -1
    }
    let digits = text_before(slice(phase, 1), ".")
    return is_digit_run(digits, 0) ? to_int(digits) : -1
}

//! Whether a skip line's phase column is `never` or a ledger row id: `P7`, `P7.5`, `P5.1c` (a
//! row's minor number may end in one lowercase letter); `P4a`, `Px` and `P7.` are not.
def phase_well_formed(phase : string) : bool {
    if (phase == "never") {
        return true
    }
    if (!(phase |> starts_with("P"))) {
        return false
    }
    var inscope parts <- split(slice(phase, 1), ".")
    if (length(parts) > 2 || !is_digit_run(parts[0], 0)) {
        return false
    }
    if (length(parts) == 1) {
        return true
    }
    let minor = parts[1]
    let last = slice(minor, length(minor) - 1)
    let lettered = length(minor) > 1 && last >= "a" && last <= "z"
    return is_digit_run(lettered ? slice(minor, 0, length(minor) - 1) : minor, 0)
}

//! The highest closed phase: the largest N among `tags` spelled `v0.<N>.0`, never below
//! `CLOSED_PHASE_FLOOR`.
def highest_closed_phase(tags : array<string>) : int {
    var highest = CLOSED_PHASE_FLOOR
    for (tag in tags) {
        var inscope parts <- split(strip(tag), ".")
        if (length(parts) == 3 && parts[0] == "v0" && parts[2] == "0" && is_digit_run(parts[1], 0)) {
            highest = max(highest, to_int(parts[1]))
        }
    }
    return highest
}

//! Whether a skip line's phase column names a phase at or below `highest`, a closed one.
def names_closed_phase(phase : string; highest : int) : bool {
    let n = phase_number(phase)
    return n >= 0 && n <= highest
}
