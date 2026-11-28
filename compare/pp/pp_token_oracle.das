options gen2

module pp_token_oracle public

require strings
require daslib/strings_boost
require daslib/fio
require daslib/json_boost
require pp_oracle
require ../../converter/sidecar.das
require ../../doom/doom_sources.das
require ../../chibicc/sources.das
require ../projects.das
require ../rust_translator.das

//! The token oracle of the whole preprocessor (`ARCHITECTURE.md#pp6`): the expansion oracle of
//! section 5 over every corpus, with `gcc -E` as the second reference, the units where clang and
//! gcc disagree listed as implementation-defined.

//! A corpus of the token oracle: its units, and whether it is held to clang alone (`strict`: a
//! suite or a project, which must be clean) or may be implementation-defined where clang and gcc
//! disagree.
struct Pp6Corpus {
    name : string
    units : array<OracleUnit>
    strict : bool
}

//! The folder of the committed corpus lists of the preprocessor-loading inputs.
let PP6_LISTS = "compare/pp/corpus"

//! The list of implementation-defined units the runner reads, from the repository root.
let IMPLEMENTATION_DEFINED = "compare/pp/implementation_defined.txt"

//! The list of known differences: units of a corpus that is not strict where the preprocessor
//! differs from clang and gcc agrees with clang, each with its cause.
let KNOWN_DIFFERENCES = "compare/pp/known_differences.txt"

//! The named corpora of the fast set: the fixtures, the own headers and c-testsuite.
let PP6_FAST <- ["frontend", "pp2", "pp3", "pp4", "c-testsuite"]

//! The named corpora the full set adds before every list of `PP6_LISTS`: gcc-torture and every
//! project's units.
let PP6_FULL <- ["gcc-torture", "lua", "doom", "chibicc", "projects"]

//! The gcc the second reference runs, and the file its pinned version is read from.
let PP6_GCC = "gcc-14"
let PP6_VERSIONS = "VERSIONS.md"

//! The C standard gcc is given when the unit names none: clang's default for C, which gcc-14's
//! default is too, written out so a gcc of another default reads the same dialect.
let GCC_DEFAULT_STD = "-std=gnu17"

//! The gcc flags of the clang flags `clang`: each flag gcc spells the same kept (`-undef`, `-D`,
//! `-funsigned-char`, `-w`, `-nostdinc`, `-isystem`, `-I`, `-x`, `-std=`, `-include`), `-std=gnu17`
//! first unless one is named; `-target` and its triple have no gcc twin and are dropped into
//! `dropped`, the native gcc-14 being that target, and so is any other flag.
[arch(at="ARCHITECTURE.md#pp6")]
def gcc_flags(clang : array<string>; var dropped : array<string>) : array<string> {
    var flags : array<string>
    let named_std = !empty([for (f in clang); f; where starts_with(f, "-std=")])
    if (!named_std) {
        flags |> push(GCC_DEFAULT_STD)
    }
    var i = 0
    while (i < length(clang)) {
        let f = clang[i]
        let has_operand = i + 1 < length(clang)
        if (f == "-target" && has_operand) {
            dropped |> push_from([f, clang[i + 1]])
            i++
        } elif ((f == "-isystem" || f == "-x" || f == "-include") && has_operand) {
            flags |> push_from([f, clang[i + 1]])
            i++
        } elif (f == "-undef" || f == "-funsigned-char" || f == "-w" || f == "-nostdinc" || starts_with(f, "-D")
                || starts_with(f, "-I") || starts_with(f, "-std=")) {
            flags |> push(f)
        } else {
            dropped |> push(f)
        }
        i++
    }
    return <- flags
}

//! The gcc version `PP6_VERSIONS`'s text `versions` pins on its `gcc:` line, "" when none.
def pinned_gcc(versions : string) : string {
    for (line in split(versions, "\n")) {
        if (starts_with(line, "gcc: ")) {
            let rest = strip(slice(line, 5))
            let blank = find(rest, " ")
            return blank < 0 ? rest : slice(rest, 0, blank)
        }
    }
    return ""
}

//! Why gcc cannot be the second reference: "" when `PP6_GCC -dumpfullversion` answers the version
//! `PP6_VERSIONS` pins; asked once, at the first unit gcc reads, so a run whose units are all clean
//! needs no gcc.
var private gcc_refusal = "unasked"

def private checked_gcc : string {
    if (gcc_refusal == "unasked") {
        var version : string
        let rc = run_and_capture([PP6_GCC, "-dumpfullversion"], version, 30.0)
        let pin = pinned_gcc(fread(PP6_VERSIONS))
        let ok = rc == 0 && !empty(pin) && strip(version) == pin
        gcc_refusal = ok ? "" : "{PP6_GCC} -dumpfullversion gives '{strip(version)}', {PP6_VERSIONS} pins gcc '{pin}': the second reference runs the pinned gcc"
    }
    return gcc_refusal
}

//! What gcc gave on a unit clang and the preprocessor disagree on: `error` when gcc refused it,
//! else whether clang's and gcc's streams disagree and the first difference shown.
struct GccAnswer {
    error : string
    disagrees : bool
    shown : string
}

//! The unit `r` compared once more, under gcc: `gcc -E -P` with `gcc_flags` of clang's flags and
//! at `ORACLE_EPOCH`, its output token-dumped by clang as clang's own is, aligned with clang's
//! stream by kind, spelling and `at_bol`, and its `#pragma` lines counted against clang's. On a
//! unit clang refuses, gcc disagrees when it accepts the unit. A gcc that is not the pinned one
//! (`checked_gcc`) answers nothing: its error makes the unit differ.
[arch(at="ARCHITECTURE.md#pp6")]
def gcc_answer(r : Pp2Result; work : string) : GccAnswer {
    var answer = GccAnswer(error = checked_gcc())
    return answer if (!empty(answer.error))
    var dropped : array<string>
    let out_path = path_join(work, "{base_name(r.unit)}.gcc.i")
    var argv <- [PP6_GCC, "-E", "-P"]
    argv |> push_from(gcc_flags(r.clang_flags, dropped), [r.read, "-o", out_path])
    var out : string
    let env <- ["SOURCE_DATE_EPOCH={ORACLE_EPOCH}"]
    let refused = run_and_capture(argv, "", env, out, 300.0) != 0
    if (r.clang_refused) {
        answer.error = refused ? "gcc -E refuses the unit too" : ""
        answer.disagrees = !refused
        answer.shown = "clang refuses, gcc accepts"
        return answer
    } elif (refused) {
        answer.error = "gcc -E: {slice(out, 0, 400)}"
        return answer
    }
    var clang_dump_text, gcc_dump_text : string
    if (clang_dump(r.preprocessed, clang_dump_text) != 0 || clang_dump(out_path, gcc_dump_text) != 0) {
        answer.error = "clang -dump-tokens of the references' output failed"
        return answer
    }
    let clang <- clang_tokens(clang_dump_text)
    let gcc <- [for (t in clang_tokens(gcc_dump_text)); Pp2Token(tok = t)]
    var gave_up = false
    let differences <- pp2_differences(clang, gcc, PP2_ALIGN_LIMIT, gave_up)
    let gcc_pragmas = pragma_lines(fread(out_path))
    answer.disagrees = !empty(differences) || gcc_pragmas != r.clang_pragmas
    if (!empty(differences)) {
        let d = differences[0]
        let gcc_side <- [for (t in gcc); t.tok]
        answer.shown = "clang [{oracle_spellings(clang, d.clang_at, d.clang_count)}] | gcc [{oracle_spellings(gcc_side, d.pp_at, d.pp_count)}]"
    } elif (answer.disagrees) {
        answer.shown = "pragma lines: clang {r.clang_pragmas} | gcc {gcc_pragmas}"
    }
    return answer
}

//! The expansion-oracle class of a unit `clang -E` refuses, in a corpus that is not strict: clean
//! when the preprocessor raises an error too, else it differs - it accepts what clang refuses.
[arch(at="ARCHITECTURE.md#pp6")]
def refusal_class(r : Pp2Result) : Pp2Class => empty(r.errors) ? Pp2Class.differs : Pp2Class.clean

//! The class of a unit to the token oracle.
enum Pp6Class {
    clean                   //!< the preprocessor's stream is clang's
    refused                 //!< clang refuses the unit and so does the preprocessor: nothing to compare
    implementation_defined  //!< it is not, and clang and gcc disagree on the unit
    differs                 //!< it is not, and gcc agrees with clang, refused the unit, or the corpus is strict
}

//! The class of a unit whose expansion-oracle class is `cls`: clean when clean; else
//! implementation-defined when gcc read the unit (`gcc.error` empty) and disagrees with clang and
//! the corpus is not `strict`; else it differs.
[arch(at="ARCHITECTURE.md#pp6")]
def pp6_class(cls : Pp2Class; gcc : GccAnswer; strict : bool) : Pp6Class {
    return Pp6Class.clean if (cls == Pp2Class.clean)
    return Pp6Class.implementation_defined if (empty(gcc.error) && gcc.disagrees && !strict)
    return Pp6Class.differs
}

//! What a set gave the token oracle: the units of each verdict, and the tokens and reference
//! failures as `OracleTotals` counts them.
struct Pp6Totals {
    clean : int
    refused : int
    known : int             //!< differs, and the known differences name it in a corpus that is not strict
    listed : int            //!< implementation-defined, and the list names it
    unlisted : int          //!< implementation-defined, and the list does not name it: fails the run
    differs : int
    stale : int             //!< listed as implementation-defined, and clean: its line is dropped
    oracle : OracleTotals
}

def operator +=(var a : Pp6Totals; b : Pp6Totals) {
    a.clean += b.clean
    a.refused += b.refused
    a.known += b.known
    a.listed += b.listed
    a.unlisted += b.unlisted
    a.differs += b.differs
    a.stale += b.stale
    a.oracle += b.oracle
}

//! The totals line of `t` headed `name`.
def describe_pp6_totals(name : string; t : Pp6Totals) : string {
    let o = t.oracle
    return "{name} {t.clean} clean, {t.refused} refused by both, {t.listed} implementation-defined (listed), {t.unlisted} implementation-defined (unlisted), {t.known} known differences, {t.differs} differ, {o.listed} reference failures (listed), {o.unlisted} reference failures (unlisted), {t.stale + o.stale} listed units clean; {o.tokens} tokens"
}

//! The run's exit code: 0 when no unit differs, every implementation-defined unit is listed and
//! every reference failure is listed; else 1.
[arch(at="ARCHITECTURE.md#pp6")]
def pp6_exit_code(t : Pp6Totals) : int => t.differs == 0 && t.unlisted == 0 && t.oracle.unlisted == 0 ? 0 : 1

//! The preprocessor's answer on a unit that is not clean, beside gcc's in a list line: its first
//! difference from clang, or that it accepts what clang refuses.
def pp_answer(r : Pp2Result) : string {
    return "pp accepts it" if (r.clang_refused)
    for (s in r.shown) {
        let at = find(s, "| pp [")
        return slice(s, at + 2) if (at >= 0)
    }
    return "pp error: {r.errors[0]}" if (!empty(r.errors))
    return "pp: pragma lines {r.pp_pragmas}, clang {r.clang_pragmas}"
}

//! The lists a unit's verdict is read against: the implementation-defined units and the known
//! differences.
struct Pp6Lists {
    impl : array<ReferenceFailure>
    known : array<ReferenceFailure>
}

//! A unit of class `cls` counted into `totals` against `lists`, and the line printed for it: an
//! implementation-defined unit is listed or unlisted; a unit that differs is a known difference when
//! the known differences name it and the corpus is not `strict`; a clean or refused unit either list
//! names is stale.
[arch(at="ARCHITECTURE.md#pp6")]
def count_pp6(lists : Pp6Lists; unit : string; cls : Pp6Class; strict : bool; var totals : Pp6Totals) : string {
    let reason = listed_reason(lists.impl, unit)
    let cause = listed_reason(lists.known, unit)
    if (cls == Pp6Class.clean || cls == Pp6Class.refused) {
        if (cls == Pp6Class.clean) {
            totals.clean++
        } else {
            totals.refused++
        }
        if (!empty(reason) || !empty(cause)) {
            totals.stale++
            let what = !empty(reason) ? "implementation-defined ({reason})" : "a known difference ({cause})"
            return "{unit}: listed as {what}, {cls}: drop its line"
        }
        return ""
    } elif (cls == Pp6Class.differs) {
        if (!empty(cause) && !strict) {
            totals.known++
            return "{unit}: differs (known): {cause}"
        }
        totals.differs++
        return "{unit}: differs"
    } elif (empty(reason)) {
        totals.unlisted++
        return "{unit}: implementation-defined (unlisted)"
    }
    totals.listed++
    return "{unit}: implementation-defined (listed): {reason}"
}

//! The token oracle over `corpus`: each unit through the expansion oracle, each that is not clean
//! through gcc, classed and counted against `lists`, each not clean
//! printed with its differences and gcc's answer, an unlisted implementation-defined unit with the
//! line that lists it; then the corpus's totals line.
def run_set_pp6(corpus : Pp6Corpus; work : string; flags : array<string>; refs : array<ReferenceFailure>; lists : Pp6Lists;
                entries, search : array<string>; show : int) : Pp6Totals {
    var totals : Pp6Totals
    for (u in corpus.units) {
        let r <- compare_unit_pp2(u.path, work, flags, entries, search, show, true, u.flags)
        let both_read = !r.clang_refused || corpus.strict
        continue if (both_read && reference_failure(refs, u.path, r.error, totals.oracle))
        totals.oracle.tokens += r.clang_tokens
        let pp_cls = both_read ? r.cls : refusal_class(r)
        let gcc = pp_cls == Pp2Class.clean ? GccAnswer() : gcc_answer(r, work)
        let pp6 = pp6_class(pp_cls, gcc, corpus.strict)
        let cls = !both_read && pp6 == Pp6Class.clean ? Pp6Class.refused : pp6
        let line = count_pp6(lists, u.path, cls, corpus.strict, totals)
        continue if (empty(line))
        print("{line}\n")
        continue if (cls == Pp6Class.clean || cls == Pp6Class.refused)
        let pp_line = (r.clang_refused ? "accepts what clang refuses: {slice(r.error, 0, 300)}"
                                       : "{length(r.differences)} differences, pragmas {r.clang_pragmas} clang / {r.pp_pragmas} pp")
        print("    pp: {pp_line}\n")
        for (s in r.shown) {
            print("    {s}\n")
        }
        for (e in r.errors) {
            print("    pp error: {e}\n")
        }
        let gcc_line = (!empty(gcc.error) ? gcc.error : gcc.disagrees ? "clang and gcc disagree: {gcc.shown}" : "gcc agrees with clang")
        print("    gcc: {gcc_line}\n")
        if (cls == Pp6Class.implementation_defined && empty(listed_reason(lists.impl, u.path))) {
            print("    list it: {u.path}\t{gcc.shown}; {pp_answer(r)}\n")
        }
    }
    let head = "{corpus.name} (pp6{corpus.strict ? ", strict" : ""}): {length(corpus.units)} units,"
    print("{describe_pp6_totals(head, totals)}\n")
    return totals
}

// the units of the C files `paths` under the sidecar `sidecar`'s defines, include folders and
// forced includes, as the converter dumps them
def private sidecar_units(paths : array<string>; sidecar : string; var error : string&) : array<OracleUnit> {
    let side = read_sidecar(sidecar, error)
    var flags <- [for (d in side.defines); "-D{d}"]
    flags |> push_from([for (d in side.include_dirs); "-I{d}"])
    for (f in side.include_files) {
        flags |> push_from(["-include", f])
    }
    return <- [for (p in paths); OracleUnit(path = p, flags := flags)]
}

// every project of the Rust checkout's table, each translation unit (and its bench twin) under the
// flags the converter dumps it with: the standard, include folders, defines of both sides, extras
def private project_units(var error : string&) : array<OracleUnit> {
    var units : array<OracleUnit>
    let checkout = rust_checkout()
    if (!stat(checkout).is_dir) {
        error = "corpus projects: the Rust checkout {checkout} is missing (scripts/build_c2das_rust.sh, C2DAS_RUST)"
        return <- units
    }
    for (p in project_table(checkout)) {
        var inscope flags <- clang_args(p)
        flags |> push_from([for (d in p.ours_defines); "-D{d}"])
        for (tu in [p.tu, p.bench_tu]) {
            if (!empty(tu)) {
                units |> emplace(OracleUnit(path = project_path(p, tu), flags := flags))
            }
        }
    }
    return <- units
}

//! The corpus `name` of the token oracle under `root`: a folder corpus of `corpus_units`, `lua`
//! (the list `fixtures/pp5/lua.txt`), `doom`, `chibicc` (each program's units under its sidecar),
//! `projects` (the Rust checkout's projects), each strict; or a list file of `PP6_LISTS`, by its
//! path, not strict. `error` names an unknown or missing corpus.
[arch(at="ARCHITECTURE.md#pp6")]
def pp6_corpus(root, name : string; var error : string&) : Pp6Corpus {
    var corpus = Pp6Corpus(name = name, strict = true)
    if (ends_with(name, ".txt")) {
        corpus.name = base_name(name)
        corpus.strict = false
        if (!stat(name).is_reg) {
            error = "corpus list {name} is missing"
        } else {
            corpus.units <- list_units(name)
        }
        return <- corpus
    }
    if (name == "lua") {
        let list = "compare/pp/fixtures/pp5/lua.txt"
        corpus.units <- list_units(list)
        let first = empty(corpus.units) ? "" : corpus.units[0].path
        if (empty(first) || !stat(first).is_reg) {
            error = "corpus lua: {first} is missing (fetch it with lua/fetch.sh)"
        }
    } elif (name == "doom" || name == "chibicc") {
        let folder = name == "doom" ? doom_sources::SOURCES : sources::SOURCES
        if (!stat(folder).is_dir) {
            error = "corpus {name}: {folder} is missing (fetch it with {name}/fetch.sh)"
            return <- corpus
        }
        let paths <- (name == "doom" ? doom_sources::program_sources()
                                     : [for (u in sources::UNITS); path_join(sources::SOURCES, "{u}.c")])
        corpus.units <- sidecar_units(paths, name == "doom" ? doom_sources::SIDECAR : sources::SIDECAR, error)
    } elif (name == "projects") {
        corpus.units <- project_units(error)
    } else {
        corpus.units <- oracle_units(corpus_units(root, name, error))
    }
    return <- corpus
}

//! The corpora of a set: the fast set (`PP6_FAST`), or with `full` the fast set, `PP6_FULL` and
//! every list of `PP6_LISTS` in name order.
def pp6_set(full : bool) : array<string> {
    var names := PP6_FAST
    if (full) {
        names |> push_from(PP6_FULL)
        var lists : array<string>
        dir(PP6_LISTS) $(f) {
            if (ends_with(f, ".txt")) {
                lists |> push(path_join(PP6_LISTS, f))
            }
        }
        sort(lists)
        names |> push_from(lists)
    }
    return <- names
}

//! The token oracle over the set `args.fast` or `args.full` names and the corpora, lists and units `args` names, from
//! `root`: each corpus's line and the total printed; `pp6_exit_code` of the total, 1 also when a
//! corpus is unknown or missing.
def run_pp6(args : OracleArgs; root : string; flags : array<string>; refs : array<ReferenceFailure>) : int {
    var error : string
    let setup <- pp2_setup(error)
    let lists <- Pp6Lists(impl <- reference_failures(fread(IMPLEMENTATION_DEFINED)),
                          known <- reference_failures(fread(KNOWN_DIFFERENCES)))
    var names <- (args.fast || args.full) ? pp6_set(args.full) : array<string>()
    names |> push_from(args.corpus, args.list)
    var total : Pp6Totals
    for (name in names) {
        break if (!empty(error))
        let corpus <- pp6_corpus(root, name, error)
        if (empty(error)) {
            total += run_set_pp6(corpus, args.work, flags, refs, lists, setup.entries, setup.search, args.show)
        }
    }
    if (empty(error) && !empty(args.units)) {
        let corpus <- Pp6Corpus(name = "units", units <- oracle_units(args.units), strict = true)
        total += run_set_pp6(corpus, args.work, flags, refs, lists, setup.entries, setup.search, args.show)
    }
    if (!empty(error)) {
        to_log(LOG_ERROR, "{error}\n")
        return 1
    }
    print("{describe_pp6_totals("total (pp6):", total)}\n")
    return pp6_exit_code(total)
}

//! The token oracle's command line, from the repository root: the dumper's flags and the
//! reference-failure list read as `run_oracle` reads them, then `run_pp6`.
def run_pp6_main(args : OracleArgs) : int {
    var error : string
    let flags <- preprocess_flags(error)
    let refs <- reference_failures(fread(REFERENCE_FAILURES))
    if (empty(error) && empty(refs)) {
        error = "{REFERENCE_FAILURES}: no entry read"
    }
    if (!empty(error)) {
        to_log(LOG_ERROR, "{error}\n")
        return 1
    }
    mkdir_rec(args.work)
    return run_pp6(args, getcwd(), flags, refs)
}
