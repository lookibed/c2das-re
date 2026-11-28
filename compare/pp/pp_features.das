options gen2

module pp_features public

require strings
require daslib/strings_boost
require daslib/fio
require ../../frontend/c_defines.das
require ../../converter/cir.das
require ../../converter/dumper_a.das

//! The feature-query tables of `frontend/predefined/` (`frontend/ARCHITECTURE_EVAL.md#pp-eval-features`)
//! generated from the pinned clang: the names clang's own headers list for each query, each asked of
//! clang under the dumper's flags of the dialect, every answer that is not the query's default kept.

//! The queries a table answers, in the table's order.
let FEATURE_QUERIES <- ["__has_attribute", "__has_builtin", "__has_c_attribute", "__has_constexpr_builtin", "__has_declspec_attribute",
                        "__has_extension", "__has_feature", "__has_warning", "__is_identifier", "__is_target_arch", "__is_target_environment",
                        "__is_target_os", "__is_target_vendor"]

// the target names a query of the triple's parts is asked of
let private TARGET_NAMES <- {"__is_target_arch" => ["x86_64", "x86", "i386", "i686", "aarch64", "arm", "wasm32"],
                             "__is_target_vendor" => ["pc", "unknown", "apple", "w64"],
                             "__is_target_os" => ["linux", "windows", "win32", "darwin", "macos", "freebsd", "none"],
                             "__is_target_environment" => ["gnu", "msvc", "musl", "android", "itanium"]}

// every `<open>name<close>` of `text`, `name` of identifier characters only
def private names_between(text, open, close : string; var into : table<string; bool>) {
    peek_data(text) $(bytes) {
        var at = find(bytes, open)
        while (at >= 0) {
            let from = at + length(open)
            let end = find(bytes, close, from)
            if (end > from) {
                let name = slice(bytes, from, end)
                if (is_identifier(name)) {
                    into |> insert(name, true)
                }
            }
            at = find(bytes, open, from)
        }
    }
}

// the first word of every line starting `<macro>(`, the macros a `.def` file lists entries by
def private def_entries(text : string; macros : array<string>; var into : table<string; bool>) {
    for (line in split(text, "\n")) {
        for (m in macros) {
            if (starts_with(line, "{m}(")) {
                var name = strip(slice(line, length(m) + 1))
                let comma = find(name, ",")
                name = strip(comma >= 0 ? slice(name, 0, comma) : name)
                name = name |> replace("\"", "")
                if (is_identifier(name)) {
                    into |> insert(name, true)
                }
            }
        }
    }
}

def private sorted_keys(names : table<string; bool>) : array<string> {
    var out <- [for (k in keys(names)); k]
    sort(out)
    return <- out
}

//! The operands each query is asked of, read from clang's headers under `headers` (the pinned SDK's
//! `include/` folder): the builtin tables, the attribute spellings, the feature list, the warning
//! groups and the keywords; `error` names a header that is missing.
[arch(at="ARCHITECTURE.md#features")]
def feature_candidates(headers : string; var error : string&) : table<string; array<string>> {
    var out : table<string; array<string>>
    let basic = path_join(path_join(headers, "clang"), "Basic")
    var texts : table<string; string>
    for (name in ["Builtins.inc", "BuiltinsX86.inc", "BuiltinsX86_64.inc", "AttrHasAttributeImpl.inc", "Features.def", "DiagnosticGroups.inc",
                  "TokenKinds.def"]) {
        let path = path_join(basic, name)
        if (!fexist(path)) {
            error = "{path}: no such clang header"
            return <- out
        }
        texts |> insert(name, fread(path))
    }
    var builtins : table<string; bool>
    for (name in ["Builtins.inc", "BuiltinsX86.inc", "BuiltinsX86_64.inc"]) {
        names_between(texts?[name] ?? "", "\"", "\\0\"", builtins)
        names_between(texts?[name] ?? "", "    BI", ",\n", builtins)
    }
    var attrs : table<string; bool>
    names_between(texts?["AttrHasAttributeImpl.inc"] ?? "", ".Case(\"", "\"", attrs)
    var features : table<string; bool>
    def_entries(texts?["Features.def"] ?? "", ["FEATURE", "EXTENSION"], features)
    var keywords : table<string; bool>
    def_entries(texts?["TokenKinds.def"] ?? "", ["KEYWORD", "ALIAS", "CXX11_KEYWORD", "C99_KEYWORD", "C23_KEYWORD", "CXX_KEYWORD_OPERATOR",
                                                 "OBJC_AT_KEYWORD", "TYPE_TRAIT_1", "TYPE_TRAIT_2", "TYPE_TRAIT_N", "ARRAY_TYPE_TRAIT",
                                                 "EXPRESSION_TRAIT", "TRANSFORM_TYPE_TRAIT_DEF", "CXX20_KEYWORD", "CONCEPTS_KEYWORD",
                                                 "MODULES_KEYWORD", "PPKEYWORD", "NOTABLE_IDENTIFIER", "PUNCTUATOR", "TOK"], keywords)
    var warnings : array<string>
    for (line in split(texts?["DiagnosticGroups.inc"] ?? "", "\n")) {
        if (starts_with(line, "DIAG_ENTRY(")) {
            let open = find(line, "/* ")
            let close = find(line, " */")
            if (open >= 0 && close > open + 3) {
                warnings |> push("-W{slice(line, open + 3, close)}")
            }
        }
    }
    sort(warnings)
    let builtin_names <- sorted_keys(builtins)
    let attr_names <- sorted_keys(attrs)
    out["__has_builtin"] <- clone_to_move(builtin_names)
    out["__has_constexpr_builtin"] <- clone_to_move(builtin_names)
    out["__has_attribute"] <- clone_to_move(attr_names)
    out["__has_declspec_attribute"] <- clone_to_move(attr_names)
    var scoped : array<string>
    for (scope in ["", "gnu::", "clang::"]) {
        scoped |> push_from([for (a in attr_names); "{scope}{a}"])
    }
    out["__has_c_attribute"] <- scoped
    let feature_names <- sorted_keys(features)
    out["__has_feature"] <- clone_to_move(feature_names)
    out["__has_extension"] <- clone_to_move(feature_names)
    out["__has_warning"] <- warnings
    out["__is_identifier"] <- sorted_keys(keywords)
    for (q, names in keys(TARGET_NAMES), values(TARGET_NAMES)) {
        out[q] <- clone_to_move(names)
    }
    return <- out
}

// the query applied to `name` as source text: a string literal for `__has_warning`
def private query_text(q, name : string) : string => q == "__has_warning" ? "{q}(\"{name}\")" : "{q}({name})"

//! The feature table of `target` as file text: each query asked of each candidate (`feature_candidates`)
//! in one `clang -E -P` run a query, under `flags` (the dialect's dumper flags), into `work`; every
//! answer that differs from the query's default (0; 1 for `__is_identifier`) a line. `error` names
//! a clang run that fails or answers a line short.
[arch(at="ARCHITECTURE.md#features")]
def generate_features(dialect : string; flags : array<string>; candidates : table<string; array<string>>; work : string;
                      var error : string&) : string {
    var lines : array<string>
    for (q in FEATURE_QUERIES) {
        var inscope names : array<string>
        get(candidates, q) $(found) {
            names := found
        }
        let unit = path_join(work, "features_{dialect}{q}.c")
        fwrite(unit, join([for (n in names); query_text(q, n)], "\n") + "\n")
        var inscope argv <- [default_clang()]
        argv |> push_from(flags, ["-E", "-P", unit])
        var out = ""
        if (run_and_capture(argv, out, 300.0) != 0) {
            error = "clang -E on {q}: {slice(out, 0, 400)}"
            return ""
        }
        var inscope answers <- [for (l in split(out, "\n")); strip(l); where !empty(strip(l))]
        if (length(answers) != length(names)) {
            error = "clang -E on {q}: {length(answers)} answers for {length(names)} names"
            return ""
        }
        let fallback = q == "__is_identifier" ? "1" : "0"
        for (n, spelled in names, answers) {
            let a = spelled |> replace("L", "")
            if (a != fallback) {
                lines |> push("{q} {n} {a}")
            }
        }
    }
    let head = "# The feature-query answers of the `{dialect}` dialect as the pinned clang gives them under the dumper's\n# flags (frontend/ARCHITECTURE_EVAL.md#pp-eval-features): `<query> <operand> <value>`, a query not listed answering 0\n# (__is_identifier: 1). Generated by `das compare/pp/run.das -- --features`; never edited by hand.\n"
    return head + join(lines, "\n") + "\n"
}

//! The dumper's flags of `dialect` for a feature run: no `-w` matters, the answers are text.
def dialect_flags(dialect : string; var error : string&) : array<string> =>
    <- dumper_frontend_flags(target_by_name(dialect), error)
