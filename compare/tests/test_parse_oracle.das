options gen2
options stack = 1048576
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../parse/parse_oracle.das

//! `compare/parse/parse_oracle.das`: the line form's pieces (the wildcard match, integer values,
//! the line-marker places, clang's type spellings), each fixture's verdict through the pinned
//! clang, and a mutated clang tree, a parser error and a broken dump each reported, never hidden.

[test(description = "a line matches clang's when equal; a ? stands for any run without a quote, so it never spans past a type")]
def test_lines_match(t : T?) {
    t |> success(lines_match("(decl x@1:5 \"int\")", "(decl x@1:5 \"int\")"))
    t |> success(!lines_match("(decl x@1:5 \"int\")", "(decl x@1:6 \"int\")"))
    t |> success(lines_match("(decl x@1:5 \"int[?]\")", "(decl x@1:5 \"int[3]\")"))
    t |> success(lines_match("(decl x@1:5 \"int[?]\")", "(decl x@1:5 \"int[n + 1]\")"))
    t |> success(lines_match("(decl x@1:5 \"?\")", "(decl x@1:5 \"typeof (1 + 1)\")"))
    t |> success(!lines_match("(decl x@1:5 \"?\")", "(decl x@1:5 \"int\" static)"))
    t |> success(!lines_match("(decl x@1:5 \"?\" = (int@1:9 1))", "(decl x@1:5 \"int\" = (int@1:9 2))"))
    t |> success(!lines_match("(decl x@1:5 \"int\")", "(decl x@1:5 \"int\" extern)"))
    t |> success(!lines_match("(f \"?\" (int 1))", "(f \"a\" (g) \"b\" (int 1))"))
}

[test(description = "an integer constant's value in decimal, every base and suffix, and ? past 64 bits or for no digits")]
def test_integer_value(t : T?) {
    t |> equal(integer_value("10"), "10")
    t |> equal(integer_value("0"), "0")
    t |> equal(integer_value("0x1F"), "31")
    t |> equal(integer_value("017"), "15")
    t |> equal(integer_value("0b101"), "5")
    t |> equal(integer_value("42uLL"), "42")
    t |> equal(integer_value("18446744073709551615ULL"), "18446744073709551615")
    t |> equal(integer_value("18446744073709551616"), "?")
    t |> equal(integer_value("0x"), "?")
    t |> equal(integer_value("09"), "?")
}

[test(description = "a byte offset is placed by the line markers before it: the line a marker names, its file, and the byte column")]
def test_presumed_places(t : T?) {
    let text = "# 1 \"a.c\"\nint x;\n# 7 \"b.h\" 1\n  int y;\n#line 20\nz;\n"
    let map <- presumed_map(text, "u.i")
    t |> equal(place_key(place_of(map, 0)), "u.i\t1\t1")
    t |> equal(place_key(place_of(map, 10 + 4)), "a.c\t1\t5")
    let y = find(text, "y;")
    t |> equal(place_key(place_of(map, y)), "b.h\t7\t7")
    t |> equal(place_key(place_of(map, find(text, "z;"))), "b.h\t20\t1")
    t |> equal(place_text(place_of(map, -1)), "@?")
}

[test(description = "clang's type spelling loses each __attribute__((...)) it writes, and the blank it leaves")]
def test_clang_type(t : T?) {
    t |> equal(clang_type("__attribute__((__vector_size__(4 * sizeof(int)))) int"), "int")
    t |> equal(clang_type("int *"), "int *")
    t |> equal(clang_type("int __attribute__((aligned(8))) *"), "int *")
}

// the flags of the test's clang runs, or a failure
def private flags_of(t : T?) : array<string> {
    var error : string
    var flags <- parse_flags(error)
    t |> equal(error, "")
    return <- flags
}

[test(description = "each fixture gives its verdict through the pinned clang: the same where both read the same, a skipped construct counted, clang's semantic difference reported, both refusals located", timeout = 1200)]
def test_fixture_verdicts(t : T?) {
    let flags <- flags_of(t)
    let work = test_temp_dir()
    let expected <- {"expressions.c" => "same", "types.c" => "same", "typedefs.c" => "same", "static_assert.c" => "same",
                     "skipped.c" => "same", "edges.c" => "same", "semantic.c" => "differs", "builtin.c" => "differs", "pragma.c" => "parser refused",
                     "clang_refuses.c" => "clang refused"}
    for (name, verdict in keys(expected), values(expected)) {
        let r <- compare_unit(path_join("compare/parse/fixtures", name), work, flags)
        t |> equal(r.verdict, verdict, "{name}: {describe_result(r)}")
        if (verdict == "same") {
            t |> success(r.lines >= 4, "{name}: {r.lines} lines")
        }
    }
}

[test(description = "the expression and type fixtures compare every form: no line of either side names an unknown node, and each compared family has its lines", timeout = 1200)]
def test_fixture_coverage(t : T?) {
    let flags <- flags_of(t)
    let work = test_temp_dir()
    let r <- compare_unit("compare/parse/fixtures/expressions.c", work, flags)
    let all = join(r.parser_lines, "\n")
    t |> success(find(all, "unknown") < 0, all)
    for (form in ["ident", "int", "float", "char", "string", "paren", "binary", "assign", "cond", "unary", "postfix", "cast",
                  "sizeof_expr", "sizeof_type", "alignof_expr", "alignof_type", "call", "index", "member", "compound_literal",
                  "extension", "va_arg", "offsetof", "types_compatible", "init_list"]) {
        t |> success(find(all, "({form}@") >= 0, form)
    }
    let types <- compare_unit("compare/parse/fixtures/types.c", work, flags)
    t |> equal(types.verdict, "same", describe_result(types))
    let spelled = join(types.clang_lines, "\n")
    for (piece in ["\"int (*[2])(void)\"", "\"int (*(int))(char)\"", "\"int *volatile *restrict\"", "\"const _Atomic(int)\"",
                   "\"int[16]\"", "\"int *const[2]\"", "static inline", "thread_local", "[x@21:77 y@21:84]"]) {
        t |> success(find(spelled, piece) >= 0, piece)
    }
}

[test(description = "the skipped constructs are counted by name and the declarations after them compared, a typedef name bound in a skipped declaration included", timeout = 1200)]
def test_skipped_constructs(t : T?) {
    let flags <- flags_of(t)
    let r <- compare_unit("compare/parse/fixtures/skipped.c", test_temp_dir(), flags)
    t |> equal(r.verdict, "same", describe_result(r))
    t |> equal(join(r.skipped, ", "), "a struct body, a struct body, an enum body, a function definition, an identifier list outside a function definition, a struct body")
    let all = join(r.parser_lines, "\n")
    for (piece in ["(decl an@5:6 \"Anon\")", "(decl e@7:5 \"int\" = (binary@7:9 + (ident@7:9 E1) (ident@7:14 E2)))", "(decl tt@12:4 \"TT\")", "(decl last@14:4 \"TT\")"]) {
        t |> success(find(all, piece) >= 0, piece)
    }
}

[test(description = "clang's semantic adjustment shows as the first differing line of both sides, never as the same", timeout = 1200)]
def test_semantic_difference(t : T?) {
    let flags <- flags_of(t)
    let r <- compare_unit("compare/parse/fixtures/semantic.c", test_temp_dir(), flags)
    t |> equal(r.verdict, "differs")
    t |> equal(r.differences[0].ours, "(decl g@4:6 \"void (F)\" [f@4:10])")
    t |> equal(r.differences[0].theirs, "(decl g@4:6 \"void (F *)\" [f@4:10])")
}

[test(description = "a library builtin's redeclaration differs by clang's own type, the difference named and the walk going on past it", timeout = 1200)]
def test_library_builtin_named(t : T?) {
    let flags <- flags_of(t)
    let r <- compare_unit("compare/parse/fixtures/builtin.c", test_temp_dir(), flags)
    t |> equal(r.verdict, "differs", describe_result(r))
    t |> equal(length(r.differences), 1, describe_result(r))
    t |> equal(unnamed_differences(r), 0)
    for (d in r.differences) {
        t |> equal(d.cause, LIBRARY_BUILTIN)
    }
    t |> equal(r.lines, 5)
}

[test(description = "the walk goes on past a line pair naming one entity, and stops at a pair naming two, which no longer align")]
def test_line_differences(t : T?) {
    let ours <- [FormLine(text = "(decl a@1:5 \"int\")"), FormLine(text = "(decl b@2:5 \"int\")"), FormLine(text = "(decl c@3:5 \"int\")"), FormLine(text = "(decl d@4:5 \"int\")")]
    let theirs <- [FormLine(text = "(decl a@1:5 \"long\")", cause = "x"), FormLine(text = "(decl b@2:5 \"int\")"), FormLine(text = "(decl d@4:5 \"int\")"), FormLine(text = "(decl e@5:5 \"int\")")]
    var compared = 0
    let found <- line_differences(ours, theirs, compared)
    t |> equal(length(found), 2)
    t |> equal(found[0].line, 1)
    t |> equal(found[0].cause, "x")
    t |> equal(found[1].line, 3)
    t |> equal(found[1].cause, "")
    t |> equal(compared, 2)
}

[test(description = "a refusal names its place: the directive the tokens refuse, and clang's own error", timeout = 1200)]
def test_refusals_located(t : T?) {
    let flags <- flags_of(t)
    let pragma <- compare_unit("compare/parse/fixtures/pragma.c", test_temp_dir(), flags)
    t |> success(ends_with(pragma.message, "pragma.c:3:2: the directive '#pragma' is not parsed"), pragma.message)
    let clang <- compare_unit("compare/parse/fixtures/clang_refuses.c", test_temp_dir(), flags)
    t |> success(find(clang.message, "clang_refuses.c:2:9: error: use of undeclared identifier") >= 0, clang.message)
}

// the preprocessed text and clang's dump of fixture `name`
def private dumped(t : T?; name : string) : tuple<error : string; text : string; json : string> {
    let flags <- flags_of(t)
    let unit = clang_dump(path_join("compare/parse/fixtures", name), test_temp_dir(), flags)
    t |> equal(unit.error, "")
    return unit
}

[test(description = "a clang tree mutated in an operator, a name, a type, a place or a value is caught as a difference at its line", timeout = 1200)]
def test_mutated_tree_differs(t : T?) {
    let unit = dumped(t, "expressions.c")
    let clean <- compare_texts("expressions.c", unit.text, unit.json)
    t |> equal(clean.verdict, "same", describe_result(clean))
    let mutations <- [("\"opcode\": \"*\"", "\"opcode\": \"/\""), ("\"name\": \"e_cond\"", "\"name\": \"e_kond\""),
                      ("\"qualType\": \"unsigned char\"", "\"qualType\": \"signed char\""), ("\"value\": \"31\"", "\"value\": \"32\""),
                      ("\"isPostfix\": true", "\"isPostfix\": false"), ("\"isArrow\": true", "\"isArrow\": false")]
    for (m in mutations) {
        t |> success(find(unit.json, m._0) >= 0, m._0)
        let r <- compare_texts("expressions.c", unit.text, replace(unit.json, m._0, m._1))
        t |> equal(r.verdict, "differs", m._1)
        t |> success(!empty(r.differences) && r.differences[0].ours != r.differences[0].theirs, describe_result(r))
    }
    // a place: the name `a` of the first declaration one byte later
    let a = find(unit.text, "int a, b") + 4
    let moved = replace(unit.json, "\"offset\": {a},", "\"offset\": {a + 1},")
    t |> success(moved != unit.json)
    let shifted <- compare_texts("expressions.c", unit.text, moved)
    t |> equal(shifted.verdict, "differs", describe_result(shifted))
    t |> equal(shifted.differences[0].ours, "(decl a@3:5 \"int\")")
    t |> equal(shifted.differences[0].theirs, "(decl a@3:6 \"int\")")
}

[test(description = "a line one side has and the other lacks is a difference, the missing side shown as (none)")]
def test_extra_line_differs(t : T?) {
    let text = "# 1 \"u.c\"\nint x;\nint y;\n"
    let json = "\{\"kind\": \"TranslationUnitDecl\", \"inner\": [\{\"kind\": \"VarDecl\", \"loc\": \{\"offset\": 14\}, \"range\": \{\"begin\": \{\"offset\": 10\}\}, \"name\": \"x\", \"type\": \{\"qualType\": \"int\"\}\}]\}"
    let r <- compare_texts("u.i", text, json)
    t |> equal(r.verdict, "differs", describe_result(r))
    t |> equal(r.differences[0].ours, "(decl y@2:5 \"int\")")
    t |> equal(r.differences[0].theirs, "(none)")
    t |> equal(r.lines, 2)
}

[test(description = "a parser error that is no construct refusal stops the unit as the parser's refusal, located")]
def test_parser_error(t : T?) {
    let r <- compare_texts("u.i", "# 1 \"u.c\"\nint x = ;\n", "\{\"kind\": \"TranslationUnitDecl\", \"inner\": []\}")
    t |> equal(r.verdict, "parser refused")
    t |> equal(r.message, "u.c:1:9: expected an expression, got ';'")
}

[test(description = "a dump that is no JSON is clang's refusal, nothing compared")]
def test_broken_dump(t : T?) {
    let r <- compare_texts("u.i", "int x;\n", "\{ not json")
    t |> equal(r.verdict, "clang refused")
    t |> success(starts_with(r.message, "clang's JSON: "), r.message)
}

[test(description = "an unknown corpus and a missing corpus folder are errors, never an empty set")]
def test_corpus_errors(t : T?) {
    var error : string
    let none <- corpus_units(getcwd(), "nope", error)
    t |> success(starts_with(error, "unknown corpus 'nope'"), error)
    error = ""
    let missing <- corpus_units(test_temp_dir(), "fixtures", error)
    t |> success(find(error, "is missing") >= 0, error)
    error = ""
    let fixtures <- corpus_units(getcwd(), "fixtures", error)
    t |> equal(error, "")
    t |> equal(length(fixtures), 10)
    t |> equal(length(none) + length(missing), 0)
}
