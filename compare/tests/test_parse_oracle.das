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

[test(description = "each fixture gives its verdict through the pinned clang: the same where both read the same, a refused construct ending its unit, clang's semantic difference reported, both refusals located", timeout = 1200)]
def test_fixture_verdicts(t : T?) {
    let flags <- flags_of(t)
    let work = test_temp_dir()
    let expected <- {"expressions.c" => "same", "types.c" => "same", "typedefs.c" => "same", "static_assert.c" => "same",
                     "bodies.c" => "same", "edges.c" => "same", "semantic.c" => "differs", "builtin.c" => "differs", "pragma.c" => "parser refused",
                     "clang_refuses.c" => "clang refused", "refused.c" => "construct refused", "causes.c" => "differs",
                     "wildcards.c" => "same", "oldstyle.c" => "same", "param_bodies.c" => "same", "forward.c" => "same"}
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

[test(description = "record, enum and function bodies are compared line by line: members, bit-fields, nested and anonymous records, enumerators, and every statement kind", timeout = 1200)]
def test_bodies_compared(t : T?) {
    let flags <- flags_of(t)
    let r <- compare_unit("compare/parse/fixtures/bodies.c", test_temp_dir(), flags)
    t |> equal(r.verdict, "same", describe_result(r))
    let all = join(r.parser_lines, "\n")
    t |> success(find(all, "unknown") < 0, all)
    for (piece in ["(record struct O@8:8)", "(record union -@8:35)", "(field b@8:71 \"unsigned int\" : (int@8:75 3))", "(field -@8:62 \"unsigned int\" : (int@8:80 0))",
                   "(enumerator E2@6:14 = (int@6:19 4))", "(case@18:23 (int@18:28 1) (int@18:34 2))", "(for@19:5 decl", "(if@19:35", "(do@22:5", "(goto@23:16 lab)",
                   "(label@18:5 lab)", "(default@18:80)", "(asm@25:5)", "(stmt_expr@26:12)", "(null)", "(while@21:5", "(switch@18:10", "(continue@19:46)",
                   "(break@20:21)", "(return@9:19 (ident@9:26 x))", "(decl calls@17:16 \"int\" static)", "(typedef L@24:20 \"long\")", "(end)"]) {
        t |> success(find(all, piece) >= 0, piece)
    }
}

[test(description = "a refused construct ends the unit: the verdict names it, it is counted by construct, nothing is compared", timeout = 1200)]
def test_refused_construct(t : T?) {
    let flags <- flags_of(t)
    let r <- compare_unit("compare/parse/fixtures/refused.c", test_temp_dir(), flags)
    t |> equal(r.verdict, "construct refused")
    t |> equal(join(r.skipped, ", "), "the __int128 type")
    t |> success(ends_with(r.message, "refused.c:3:1: the __int128 type is not parsed"), r.message)
    t |> equal(r.lines, 0)
}

[test(description = "clang's semantic adjustment shows as the first differing line of both sides, never as the same, and a merged redeclaration's type differs by its named cause", timeout = 1200)]
def test_semantic_difference(t : T?) {
    let flags <- flags_of(t)
    let r <- compare_unit("compare/parse/fixtures/semantic.c", test_temp_dir(), flags)
    t |> equal(r.verdict, "differs")
    t |> equal(r.differences[0].ours, "(decl g@4:6 \"void (F)\" [f@4:10])")
    t |> equal(r.differences[0].theirs, "(decl g@4:6 \"void (F *)\" [f@4:10])")
    t |> equal(length(r.differences), 2, describe_result(r))
    t |> equal(r.differences[1].ours, "(decl m@6:5 \"int ()\")")
    t |> equal(r.differences[1].theirs, "(decl m@6:5 \"int (void)\")")
    t |> equal(r.differences[1].cause, MERGED_REDECLARATION)
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
    let ours <- [FormLine(text = "(decl a@1:5 \"int ()\")"), FormLine(text = "(decl b@2:5 \"int\")"), FormLine(text = "(decl c@3:5 \"int\")"), FormLine(text = "(decl d@4:5 \"int\")")]
    let theirs <- [FormLine(text = "(decl a@1:5 \"int (void)\")", cause = MERGED_REDECLARATION, prior = "int (void)"), FormLine(text = "(decl b@2:5 \"int\")"),
                   FormLine(text = "(decl d@4:5 \"int\")"), FormLine(text = "(decl e@5:5 \"int\")")]
    var compared = 0
    let found <- line_differences(ours, theirs, compared)
    t |> equal(length(found), 2)
    t |> equal(found[0].line, 1)
    t |> equal(found[0].cause, MERGED_REDECLARATION)
    t |> equal(found[1].line, 3)
    t |> equal(found[1].cause, "")
    t |> equal(compared, 2)
}

[test(description = "a named cause explains only a difference of the type it names, of the shape it names: every other part equal, a builtin's type as written once clang's own spellings are undone, a redeclaration's type the earlier declaration's")]
def test_explained_by(t : T?) {
    let builtin = FormLine(text = "(decl memcpy@5:7 \"void *(void *restrict, const void *restrict, __size_t)\" [- - -])", cause = LIBRARY_BUILTIN)
    t |> equal(explained_by("(decl memcpy@5:7 \"void *(void *, const void *, size_t)\" [- - -])", builtin), LIBRARY_BUILTIN)
    t |> equal(explained_by("(decl memcpy@5:7 \"void *(void *, const void *, int)\" [- - -])", builtin), "")
    t |> equal(explained_by("(decl memcpy@5:8 \"void *(void *, const void *, size_t)\" [- - -])", builtin), "")
    t |> equal(explained_by("(decl memcpy@5:7 \"void *(void *, const void *, size_t)\" [- -])", builtin), "")
    t |> equal(explained_by("(decl memcpy@5:7 \"void *(void *, const void *, size_t)\" static [- - -])", builtin), "")
    let va = FormLine(text = "(decl v@1:5 \"int (struct __va_list_tag *, struct __jmp_buf_tag *)\")", cause = LIBRARY_BUILTIN)
    t |> equal(explained_by("(decl v@1:5 \"int (va_list, jmp_buf)\")", va), LIBRARY_BUILTIN)
    t |> equal(explained_by("(decl v@1:5 \"int (__gnuc_va_list, jmp_buf)\")", va), LIBRARY_BUILTIN)
    t |> equal(explained_by("(decl v@1:5 \"int (__builtin_va_list, jmp_buf)\")", va), LIBRARY_BUILTIN)
    t |> equal(explained_by("(decl v@1:5 \"int (char *, jmp_buf)\")", va), "")
    let merged = FormLine(text = "(decl m@7:5 \"int (void)\")", cause = MERGED_REDECLARATION, prior = "int (void)")
    t |> equal(explained_by("(decl m@7:5 \"int ()\")", merged), MERGED_REDECLARATION)
    t |> equal(explained_by("(decl n@7:5 \"int ()\")", merged), "")
    let unmerged = FormLine(text = "(decl m@7:5 \"int (int)\")", cause = MERGED_REDECLARATION, prior = "int (void)")
    t |> equal(explained_by("(decl m@7:5 \"int ()\")", unmerged), "")
    t |> equal(explained_by("(decl m@7:5 \"int ()\")", FormLine(text = "(decl m@7:5 \"int (void)\")", cause = "elsewhere")), "")
    t |> equal(explained_by("(static_assert@1:1 (int@1:16 1) -)", FormLine(text = "(static_assert@1:1 (int@1:16 0) -)", cause = LIBRARY_BUILTIN)), "")
}

// the `nth` occurrence (from 0) of `what` in `text` replaced by `with`
def private replace_nth(text, what, by : string; nth : int) : string {
    var at = -1
    for (_ in range(nth + 1)) {
        at = find(text, what, at + 1)
        return text if (at < 0)
    }
    return slice(text, 0, at) + by + slice(text, at + length(what))
}

[test(description = "a named cause never accepts a name, a place or a type of another shape: each mutation of a builtin's or a redeclaration's line is a difference no cause names", timeout = 1200)]
def test_named_causes_mutated(t : T?) {
    let unit = dumped(t, "causes.c")
    let clean <- compare_texts("causes.c", unit.text, unit.json)
    t |> equal(clean.verdict, "differs", describe_result(clean))
    t |> equal(length(clean.differences), 2, describe_result(clean))
    t |> equal(unnamed_differences(clean), 0, describe_result(clean))
    t |> equal(clean.lines, 11)
    // the second `f`'s parameter renamed, the second `f` renamed, the builtin's type and the merged type changed
    let renamed_param = replace_nth(unit.json, "\"name\": \"a\"", "\"name\": \"WRONG\"", 1)
    let renamed_f = replace_nth(unit.json, "\"name\": \"f\"", "\"name\": \"g\"", 1)
    let retyped = replace(unit.json, "__size_t)", "int)")
    let remerged = replace_nth(unit.json, "\"qualType\": \"int (void)\"", "\"qualType\": \"int (int)\"", 1)
    for (json in fixed_array(renamed_param, renamed_f, retyped, remerged)) {
        t |> success(json != unit.json)
        let r <- compare_texts("causes.c", unit.text, json)
        t |> success(unnamed_differences(r) > 0, describe_result(r))
    }
}

[test(description = "a ? stands for one part of a type: never for the type around it, a pointer, an array or a parameter beside it")]
def test_wildcard_one_part(t : T?) {
    t |> success(lines_match("(decl f \"int (?, int)\")", "(decl f \"int (typeof (1), int)\")"))
    t |> success(!lines_match("(decl f \"int (?, int)\")", "(decl f \"void (typeof (1), float)\")"))
    t |> success(!lines_match("(decl f \"int (?, int)\")", "(decl f \"int (int, int, int)\")"))
    t |> success(lines_match("(decl ta \"? *[3]\")", "(decl ta \"typeof (1) *[3]\")"))
    t |> success(!lines_match("(decl ta \"? *[3]\")", "(decl ta \"double\")"))
    t |> success(!lines_match("(decl ta \"? *[3]\")", "(decl ta \"int * *[3]\")"))
    t |> success(lines_match("(decl u \"? *\")", "(decl u \"struct (unnamed at u.c:1:1) *\")"))
    t |> success(!lines_match("(decl u \"?\")", "(decl u \"int *\")"))
    t |> success(!lines_match("(decl u \"?\")", "(decl u \"int[2]\")"))
    t |> success(lines_match("(decl a \"int[?]\")", "(decl a \"int[n * 2]\")"))
    t |> success(!lines_match("(decl a \"int[?]\")", "(decl a \"int[]\")"))
    t |> success(!lines_match("(decl a \"?\")", "(decl a \"\")"))
}

[test(description = "the parts of a type around a ? are compared: a mutated return type, parameter, pointer or array, and an _Atomic pointer's type, are differences", timeout = 1200)]
def test_wildcards_mutated(t : T?) {
    let unit = dumped(t, "wildcards.c")
    let clean <- compare_texts("wildcards.c", unit.text, unit.json)
    t |> equal(clean.verdict, "same", describe_result(clean))
    let mutations <- [("\"int (typeof (1), int)\"", "\"void (typeof (1), float)\""), ("\"typeof (1) *[3]\"", "\"double\""),
                      ("\"_Atomic(int *) *\"", "\"_Atomic(int *)\""), ("\"_Atomic(int (*)(void))\"", "\"_Atomic(int (*)(int))\"")]
    for (m in mutations) {
        t |> success(find(unit.json, m._0) >= 0, m._0)
        let r <- compare_texts("wildcards.c", unit.text, replace(unit.json, m._0, m._1))
        t |> equal(r.verdict, "differs", m._1)
    }
}

[test(description = "an old-style definition compares each parameter's declared type and the function's promoted type: a changed declaration-list type, on either side, is a difference", timeout = 1200)]
def test_old_style_mutated(t : T?) {
    let unit = dumped(t, "oldstyle.c")
    let clean <- compare_texts("oldstyle.c", unit.text, unit.json)
    t |> equal(clean.verdict, "same", describe_result(clean))
    let lines = join(clean.parser_lines, "\n")
    t |> success(find(lines, "(decl f@3:5 \"int (int, double, long)\"") >= 0, lines)
    t |> success(find(lines, "(param a@3:21 \"char\")") >= 0, lines)
    // the parser's text mutated in place, every offset kept: `long c` read as `char c`, `char a` as `int  a`
    for (m in fixed_array(("long c;", "char c;"), ("char a;", "int  a;"), ("char *p;", "long *p;"))) {
        t |> success(find(unit.text, m._0) >= 0, m._0)
        let r <- compare_texts("oldstyle.c", replace(unit.text, m._0, m._1), unit.json)
        t |> equal(r.verdict, "differs", m._1)
    }
}

[test(description = "a tag body clang's JSON leaves out is counted as not compared, each occurrence; one it lists beside the declaration is compared", timeout = 1200)]
def test_param_bodies(t : T?) {
    let unit = dumped(t, "param_bodies.c")
    let clean <- compare_texts("param_bodies.c", unit.text, unit.json)
    t |> equal(clean.verdict, "same", describe_result(clean))
    t |> equal(length([for (n in clean.not_compared); n; where n == NOT_IN_PARAMETER]), 2)
    t |> equal(length([for (n in clean.not_compared); n; where n == NOT_IN_BLOCK]), 1)
    var totals : ParseTotals
    add_result(totals, clean)
    t |> success(find(describe_totals("set", totals), "not compared, by reason: {NOT_IN_PARAMETER} 2, {NOT_IN_BLOCK} 1") >= 0, describe_totals("set", totals))
    t |> success(find(describe_result(clean), "3 not compared") >= 0, describe_result(clean))
    // the bodies clang lists are compared: a field renamed in the parser's text differs
    for (m in fixed_array(("int e;", "int z;"), ("int w;", "int z;"), ("int mp;", "int mq;"), ("Q \{ int a; \}", "Q \{ int z; \}"))) {
        t |> success(find(unit.text, m._0) >= 0, m._0)
        let r <- compare_texts("param_bodies.c", replace(unit.text, m._0, m._1), unit.json)
        t |> equal(r.verdict, "differs", m._1)
    }
}

[test(description = "a tag declared with no body is a line on both sides, at file scope, in a block and in a record; a changed keyword or a dropped declaration is a difference", timeout = 1200)]
def test_forward_tags(t : T?) {
    let unit = dumped(t, "forward.c")
    let clean <- compare_texts("forward.c", unit.text, unit.json)
    t |> equal(clean.verdict, "same", describe_result(clean))
    let lines = join(clean.clang_lines, "\n")
    for (piece in ["(tag struct S@2:8)", "(tag union U@3:7)", "(tag enum E@4:6)", "(tag struct L@6:23)", "(tag union N@6:45)", "(tag struct In@7:24)"]) {
        t |> success(find(lines, piece) >= 0, piece)
    }
    t |> equal(length([for (l in clean.clang_lines); l; where starts_with(l, "(tag ")]), 6)
    for (m in fixed_array(("struct S;", "union  S;"), ("struct L;", "         "), ("union N;", "        "), ("struct In;", "          "))) {
        t |> success(find(unit.text, m._0) >= 0, m._0)
        let r <- compare_texts("forward.c", replace(unit.text, m._0, m._1), unit.json)
        t |> equal(r.verdict, "differs", m._1)
    }
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
    t |> equal(length(fixtures), 16)
    t |> equal(length(none) + length(missing), 0)
}

[test(description = "a clang body mutated in a statement's kind, a range, a field, a tag's keyword, a label or a bit-field width is caught as a difference", timeout = 1200)]
def test_mutated_body_differs(t : T?) {
    let unit = dumped(t, "bodies.c")
    let clean <- compare_texts("bodies.c", unit.text, unit.json)
    t |> equal(clean.verdict, "same", describe_result(clean))
    let mutations <- [("\"isGNURange\": true", "\"isGNURange\": false"), ("\"kind\": \"ContinueStmt\"", "\"kind\": \"BreakStmt\""),
                      ("\"name\": \"fa\"", "\"name\": \"fb\""), ("\"tagUsed\": \"union\"", "\"tagUsed\": \"struct\""),
                      ("\"name\": \"lab\"", "\"name\": \"lap\""), ("\"value\": \"3\"", "\"value\": \"4\""), ("\"name\": \"E2\"", "\"name\": \"E3\"")]
    for (m in mutations) {
        t |> success(find(unit.json, m._0) >= 0, m._0)
        let r <- compare_texts("bodies.c", unit.text, replace(unit.json, m._0, m._1))
        t |> equal(r.verdict, "differs", m._1)
    }
}
