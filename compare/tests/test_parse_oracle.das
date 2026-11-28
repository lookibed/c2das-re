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
                     "bodies.c" => "same", "edges.c" => "same", "semantic.c" => "differs", "builtin.c" => "differs", "pragma.c" => "same", "imaginary.c" => "parser refused",
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

[test(description = "a refusal names its place: the constant the tokens refuse, and clang's own error", timeout = 1200)]
def test_refusals_located(t : T?) {
    let flags <- flags_of(t)
    let imaginary <- compare_unit("compare/parse/fixtures/imaginary.c", test_temp_dir(), flags)
    t |> success(ends_with(imaginary.message, "imaginary.c:3:21: invalid numeric constant '2.0i'"), imaginary.message)
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
    t |> equal(length(fixtures), 17)
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

// the result of unit `text` written to `name` in a fresh folder, through both sides
def private unit_result(t : T?; name, text : string) : ParseResult {
    let flags <- flags_of(t)
    let dir = path_join(test_temp_dir(), "units")
    mkdir_rec(dir)
    let path = path_join(dir, name)
    t |> success(fwrite(path, text), path)
    return <- compare_unit(path, dir, flags)
}

[test(description = "a tag body in an old-style definition's declaration list is compared where clang lists it, at file scope before the function's line", timeout = 600)]
def test_old_style_list_body(t : T?) {
    let r <- unit_result(t, "kr_body.c", "int kb(s) struct KS \{ int a; \} s; \{ return s.a; \}\n")
    t |> equal(r.verdict, "same", describe_result(r))
    let lines = join(r.parser_lines, "\n")
    t |> success(find(lines, "(record struct KS@1:18)\n(field a@1:27 \"int\")\n(end)\n(decl kb@1:5") >= 0, lines)
    t |> equal(length(r.not_compared), 0)
}

[test(description = "a stray `;` at file scope is no line on either side, as the parser keeps none", timeout = 600)]
def test_stray_semicolon(t : T?) {
    let r <- unit_result(t, "stray.c", "int a;;\nint b;\n")
    t |> equal(r.verdict, "same", describe_result(r))
    t |> equal(join(r.clang_lines, " "), join(r.parser_lines, " "))
    t |> success(find(join(r.clang_lines, " "), "unknown") < 0, join(r.clang_lines, " "))
}


// whether line `piece` is one of `lines`
def private has_line(lines : array<string>; piece : string) : bool => has_value(lines, piece)

[test(description = "a line marker's file name reads an escaped quote as the quote, and a unit whose name holds a quote compares the same", timeout = 600)]
def test_escaped_file_name(t : T?) {
    let text = "# 1 \"a\\\"b.c\"\nint x;\n"
    let map <- presumed_map(text, "u.i")
    t |> equal(place_of(map, find(text, "x;")).file, "a\"b.c")
    let two <- presumed_map("# 1 \"c\\\\d.c\"\nint y;\n# 1 \"e\\\nz", "u.i")
    t |> equal(place_of(two, 13).file, "c\\d.c")
    t |> equal(place_of(two, 28).file, "e\\")
    let r <- unit_result(t, "esc\"q.c", "int x;\n")
    t |> equal(r.verdict, "same", describe_result(r))
}

[test(description = "expression forms each unit reaches: __func__, clang's inserted anonymous-member access standing for its child, a bare return, and a clang kind the form does not name written as unknown", timeout = 600)]
def test_expression_forms_units(t : T?) {
    let fn <- unit_result(t, "func_name.c", "void f(void) \{ const char *s = __func__; (void)s; \}\n")
    t |> equal(fn.verdict, "same", describe_result(fn))
    t |> success(has_line(fn.parser_lines, "(decl s@1:28 \"const char *\" = (func_name@1:32))"), join(fn.parser_lines, "\n"))
    let anon <- unit_result(t, "anon_member.c", "struct O \{ union \{ int u; float f; \}; \} o;\nint z = sizeof(o.u);\n")
    t |> equal(anon.verdict, "same", describe_result(anon))
    t |> success(find(join(anon.clang_lines, "\n"), "(member@2:16 . (ident@2:16 o) u)") >= 0, join(anon.clang_lines, "\n"))
    let ret <- unit_result(t, "return_void.c", "void r(void) \{ return; \}\n")
    t |> equal(ret.verdict, "same", describe_result(ret))
    t |> success(has_line(ret.clang_lines, "(return@1:16 -)"), join(ret.clang_lines, "\n"))
    let unknown <- unit_result(t, "unknown_expr.c", "int z = sizeof(__builtin_FILE());\n")
    t |> equal(unknown.verdict, "differs", describe_result(unknown))
    t |> success(find(join(unknown.clang_lines, "\n"), "(unknown SourceLocExpr@1:16)") >= 0, join(unknown.clang_lines, "\n"))
}

[test(description = "declaration forms each unit reaches: an unnamed parameter, a _Static_assert among members and among block items, [*] below a parameter's outermost array, a tag placed past its attributes, a label at a block's end", timeout = 600)]
def test_declaration_forms_units(t : T?) {
    let up <- unit_result(t, "unnamed_param.c", "int up(int, int b) \{ return b; \}\n")
    t |> equal(up.verdict, "same", describe_result(up))
    t |> success(has_line(up.parser_lines, "(param - \"int\")"), join(up.parser_lines, "\n"))
    let sa <- unit_result(t, "record_assert.c", "struct SA \{ int a; _Static_assert(1, \"x\"); int b; \};\nvoid f(void) \{ _Static_assert(1, \"x\"); \}\n")
    t |> equal(sa.verdict, "same", describe_result(sa))
    t |> success(has_line(sa.parser_lines, "(static_assert@1:20 (int@1:35 1) (string@1:38))"), join(sa.parser_lines, "\n"))
    t |> success(has_line(sa.parser_lines, "(static_assert@2:16 (int@2:31 1) (string@2:34))"), join(sa.parser_lines, "\n"))
    let star <- unit_result(t, "array_star.c", "void star(int n, int (*e)[*]);\n")
    t |> equal(star.verdict, "same", describe_result(star))
    t |> success(find(join(star.parser_lines, "\n"), "\"void (int, int (*)[*])\"") >= 0, join(star.parser_lines, "\n"))
    let attr <- unit_result(t, "attr_tag.c", "struct __attribute__((packed)) P \{ char c; int i; \};\n")
    t |> equal(attr.verdict, "same", describe_result(attr))
    t |> success(has_line(attr.parser_lines, "(record struct P@1:32)"), join(attr.parser_lines, "\n"))
    let marker <- unit_result(t, "label_end.c", "void f(void) \{ goto l; l: \}\n")
    t |> equal(marker.verdict, "same", describe_result(marker))
    t |> success(find(join(marker.parser_lines, "\n"), "(label@1:24 l)\n(null)") >= 0, join(marker.parser_lines, "\n"))
}

[test(description = "an old-style parameter keeps a pointer type unpromoted, promotes a typedef or enum to ?, and drops its own qualifier before promotion", timeout = 600)]
def test_old_style_units(t : T?) {
    let kp <- unit_result(t, "kr_pointer.c", "int kp(p) const char *p; \{ return 0; \}\n")
    t |> equal(kp.verdict, "same", describe_result(kp))
    t |> success(has_line(kp.parser_lines, "(decl kp@1:5 \"int (const char *)\" [p@1:23])"), join(kp.parser_lines, "\n"))
    let kt <- unit_result(t, "kr_typedef.c", "typedef short S;\nint kt(s) S s; \{ return s; \}\nenum EE \{ X \};\nint ke(e) enum EE e; \{ return 0; \}\n")
    t |> equal(kt.verdict, "same", describe_result(kt))
    t |> success(find(join(kt.parser_lines, "\n"), "(decl kt@2:5 \"int (?)\"") >= 0, join(kt.parser_lines, "\n"))
    let kq <- unit_result(t, "kr_qualifier.c", "int kq(a) const char a; \{ return a; \}\n")
    t |> equal(kq.verdict, "same", describe_result(kq))
    t |> success(has_line(kq.parser_lines, "(decl kq@1:5 \"int (int)\" [a@1:22])"), join(kq.parser_lines, "\n"))
    t |> success(has_line(kq.parser_lines, "(param a@1:22 \"const char\")"), join(kq.parser_lines, "\n"))
}

[test(description = "tag bodies by place: none counted in a statement expression, one in a function's own parameter's declarator printed, one under an expression statement and one in a block declarator counted", timeout = 600)]
def test_tag_body_places_units(t : T?) {
    let se <- unit_result(t, "stmt_expr_body.c", "void v(void) \{ int y = (\{ struct T \{ int a; \} t = \{1\}; t.a; \}); (void)y; \}\n")
    t |> equal(se.verdict, "same", describe_result(se))
    t |> equal(length(se.not_compared), 0)
    let own <- unit_result(t, "own_param_body.c", "int f(int (*cb)(struct X \{ int x; \} x));\n")
    t |> equal(own.verdict, "same", describe_result(own))
    t |> success(find(join(own.parser_lines, "\n"), "(record struct X@1:24)") >= 0, join(own.parser_lines, "\n"))
    let ex <- unit_result(t, "expr_body.c", "void v(void) \{ (void)sizeof(struct Q4 \{ int c; \}); \}\n")
    t |> equal(ex.verdict, "same", describe_result(ex))
    t |> equal(length([for (n in ex.not_compared); n; where n == NOT_IN_BLOCK]), 1)
    let bd <- unit_result(t, "block_decl_body.c", "void v(void) \{ int (*fp)(struct X \{ int x; \} a); (void)fp; \}\n")
    t |> equal(bd.verdict, "same", describe_result(bd))
    t |> equal(length([for (n in bd.not_compared); n; where n == NOT_IN_BLOCK]), 1)
}

[test(description = "a unit's runs through clang: a (file) line opens each file's run, `clang -E`'s own refusal, and the first line of clang's message that holds `error:`", timeout = 600)]
def test_clang_runs_units(t : T?) {
    let dir = path_join(test_temp_dir(), "units")
    mkdir_rec(dir)
    t |> success(fwrite(path_join(dir, "inc.h"), "int inc;\n"))
    let two <- unit_result(t, "two_files.c", "#include \"inc.h\"\nint after;\n")
    t |> equal(two.verdict, "same", describe_result(two))
    t |> equal(length(two.parser_lines), 4)
    t |> success(starts_with(two.parser_lines[0], "(file ") && ends_with(two.parser_lines[0], "inc.h)"), two.parser_lines[0])
    t |> success(starts_with(two.parser_lines[2], "(file ") && ends_with(two.parser_lines[2], "two_files.c)"), two.parser_lines[2])
    let pre <- unit_result(t, "pp_error.c", "int before;\n#error stop\n")
    t |> equal(pre.verdict, "clang refused")
    t |> success(starts_with(pre.message, "clang -E: ") && find(pre.message, "error: stop") >= 0, pre.message)
    t |> success(fwrite(path_join(dir, "bad.h"), "int bad = undeclared2;\n"))
    let first <- unit_result(t, "first.c", "#include \"bad.h\"\nint after;\n")
    t |> equal(first.verdict, "clang refused")
    t |> success(find(first.message, "bad.h:1:11: error: use of undeclared identifier") >= 0, first.message)
}

[test(description = "a refused construct is read after the place's `:<line>:<col>: `, a folder holding `<digits>: ` aside")]
def test_refused_construct_split(t : T?) {
    t |> equal(refused_construct("v2: d/r.c:2:1: the __int128 type is not parsed"), "the __int128 type")
}

[test(description = "the line form's pieces on their edges: no digits, a size wildcard stopping at its ], a wildcard ending only at depth 0, a match taking all of clang's line, a builtin's restrict both ways, a cause held to its own shape, and a walk stopping at two typeless lines")]
def test_form_edges(t : T?) {
    t |> equal(integer_value(""), "?")
    t |> equal(integer_value("ul"), "?")
    t |> success(!lines_match("(decl a \"int[?]\")", "(decl a \"int[3][2]\")"))
    t |> success(!lines_match("(d \"int (?))\")", "(d \"int (f(a))\")"))
    t |> success(!lines_match("(decl a \"int\")", "(decl a \"int\") static"))
    t |> equal(explained_by("(decl f@1:5 \"int (char **)\")", FormLine(text = "(decl f@1:5 \"int (char *restrict *)\")", cause = LIBRARY_BUILTIN)), LIBRARY_BUILTIN)
    t |> equal(explained_by("(decl f@1:5 \"int (int *const)\")", FormLine(text = "(decl f@1:5 \"int (int *const restrict)\")", cause = LIBRARY_BUILTIN)), LIBRARY_BUILTIN)
    t |> equal(explained_by("(decl f@1:5 \"int (char *)\")", FormLine(text = "(decl f@1:5 \"int (char *restrict)\")", cause = MERGED_REDECLARATION, prior = "int (char *)")), "")
    var compared = 0
    let found <- line_differences([FormLine(text = "(break@2:5)"), FormLine(text = "(null)")], [FormLine(text = "(continue@2:5)"), FormLine(text = "(end)")], compared)
    t |> equal(length(found), 1)
    t |> equal(compared, 0)
}

[test(description = "a set's totals: verdicts, lines, differences by cause, units differing by named causes alone, refused constructs; their sum; and the lines that describe a result and the totals", timeout = 1200)]
def test_totals(t : T?) {
    let flags <- flags_of(t)
    let work = test_temp_dir()
    var totals : ParseTotals
    let causes <- compare_unit("compare/parse/fixtures/causes.c", work, flags)
    let semantic <- compare_unit("compare/parse/fixtures/semantic.c", work, flags)
    let refused <- compare_unit("compare/parse/fixtures/refused.c", work, flags)
    add_result(totals, causes)
    add_result(totals, semantic)
    add_result(totals, refused)
    t |> equal(totals.verdicts?["differs"] ?? 0, 2)
    t |> equal(totals.verdicts?["construct refused"] ?? 0, 1)
    t |> equal(totals.lines, causes.lines + semantic.lines)
    t |> equal(totals.differences?[LIBRARY_BUILTIN] ?? 0, 1)
    t |> equal(totals.differences?[MERGED_REDECLARATION] ?? 0, 2)
    t |> equal(totals.differences?["unnamed"] ?? 0, 1)
    t |> equal(totals.named_only, 1)
    t |> equal(totals.skipped?["the __int128 type"] ?? 0, 1)
    var twice : ParseTotals
    twice += totals
    twice += totals
    t |> equal(twice.verdicts?["differs"] ?? 0, 4)
    t |> equal(twice.lines, 2 * totals.lines)
    t |> equal(twice.differences?[MERGED_REDECLARATION] ?? 0, 4)
    t |> equal(twice.named_only, 2)
    t |> equal(twice.skipped?["the __int128 type"] ?? 0, 2)
    t |> success(find(describe_result(semantic), "(2 lines, 1 with no named cause; {semantic.lines} lines compared)") >= 0, describe_result(semantic))
    t |> success(find(describe_result(refused), ": ") >= 0 && ends_with(describe_result(refused), "refused.c:3:1: the __int128 type is not parsed"), describe_result(refused))
    t |> equal(length(split(describe_result(semantic, 1), "\n  line ")), 2)
    t |> success(find(describe_totals("set", totals), "differing lines by cause: ") >= 0 && find(describe_totals("set", totals), "unnamed 1") >= 0, describe_totals("set", totals))
}

// the command of `compare/parse/run.das` with `args`, through this checkout's daslang and modules
def private run_das(args : array<string>) : array<string> {
    var argv <- [get_das_root() + "/bin/daslang", "-load_module", "dasCRuntime", "-load_module", "c_runtime", "-load_module", "fetch/dasFlex", "compare/parse/run.das", "--"]
    argv |> push_from(args)
    return <- argv
}

[test(description = "run.das: --quiet prints no unit that is the same, --dump prints both sides' lines, and a clang that fails with no `error:` line is reported by its first line", timeout = 1200)]
def test_run_das(t : T?) {
    var out : string
    let work = path_join(test_temp_dir(), "work")
    t |> equal(run_and_capture(run_das(["--work", work, "--quiet", "compare/parse/fixtures/expressions.c"]), out, 600.0), 0)
    t |> success(find(out, "expressions.c: same") < 0 && find(out, "units (1 units): 1 same") >= 0, out)
    t |> equal(run_and_capture(run_das(["--work", work, "--dump", "compare/parse/fixtures/expressions.c"]), out, 600.0), 0)
    t |> success(find(out, "  parser (file") >= 0 && find(out, "  clang  (file") >= 0, out)
    let fake = path_join(test_temp_dir(), "fake")
    mkdir_rec(path_join(fake, "bin"))
    t |> success(fwrite(path_join(fake, "bin/clang"), "#!/bin/sh\nprintf 'a\\nb\\n'\nexit 1\n"))
    t |> equal(run_and_capture(["chmod", "+x", path_join(fake, "bin/clang")], out, 30.0), 0)
    var argv <- ["env", "PATH_TO_LIBCLANG={fake}"]
    argv |> push_from(run_das(["--work", work, "compare/parse/fixtures/expressions.c"]))
    run_and_capture(argv, out, 600.0)
    t |> success(find(out, "clang refused: clang -E: a") >= 0, out)
}

[test(description = "run_parse_oracle: a unit the parser refuses fails the run and a same one passes it, an unknown corpus fails it, a --define reaches the preprocessing; the frontend corpus is the own headers", timeout = 1200)]
def test_run_parse_oracle(t : T?) {
    let work = path_join(test_temp_dir(), "work")
    t |> equal(run_parse_oracle(ParseOracleArgs(work = work, show = 3, units <- ["compare/parse/fixtures/imaginary.c"])), 1)
    t |> equal(run_parse_oracle(ParseOracleArgs(work = work, show = 3, units <- ["compare/parse/fixtures/expressions.c"])), 0)
    t |> equal(run_parse_oracle(ParseOracleArgs(work = work, show = 3, corpus <- ["nope"])), 1)
    let unit = path_join(test_temp_dir(), "defined.c")
    t |> success(fwrite(unit, "#ifndef X\ndouble _Complex z = 2.0i;\n#endif\nint a;\n"))
    t |> equal(run_parse_oracle(ParseOracleArgs(work = work, show = 3, units <- [unit])), 1)
    t |> equal(run_parse_oracle(ParseOracleArgs(work = work, show = 3, define <- ["X"], units <- [unit])), 0)
    var error : string
    let headers <- corpus_units(getcwd(), "frontend", error)
    t |> equal(error, "")
    t |> success(!empty(headers) && empty([for (h in headers); h; where !ends_with(h, ".h")]), "{length(headers)} headers")
}

[test(description = "the defensive arms over shapes the pinned clang does not write, through hand-written dumps: a missing offset unplaced, a transparent node of two children, a statement and a file-scope node of no form, each written as unknown")]
def test_hand_written_dumps(t : T?) {
    let text = "# 1 \"u.c\"\nint x = 1;\n"
    let lit = "\{\"kind\": \"TranslationUnitDecl\", \"inner\": [\{\"kind\": \"VarDecl\", \"loc\": \{\"offset\": 14\}, \"range\": \{\"begin\": \{\"offset\": 10\}\}, \"name\": \"x\", \"type\": \{\"qualType\": \"int\"\}, \"inner\": [EXPR]\}]\}"
    let unplaced <- compare_texts("u.i", text, replace(lit, "EXPR", "\{\"kind\": \"IntegerLiteral\", \"range\": \{\"begin\": \{\}\}, \"value\": \"1\", \"type\": \{\"qualType\": \"int\"\}\}"))
    t |> success(has_line(unplaced.clang_lines, "(decl x@1:5 \"int\" = (int@? 1))"), join(unplaced.clang_lines, "\n"))
    let one = "\{\"kind\": \"IntegerLiteral\", \"range\": \{\"begin\": \{\"offset\": 18\}\}, \"value\": \"1\", \"type\": \{\"qualType\": \"int\"\}\}"
    let two <- compare_texts("u.i", text, replace(lit, "EXPR", "\{\"kind\": \"ImplicitCastExpr\", \"inner\": [{one}, {one}]\}"))
    t |> success(has_line(two.clang_lines, "(decl x@1:5 \"int\" = (unknown ImplicitCastExpr))"), join(two.clang_lines, "\n"))
    let ftext = "# 1 \"u.c\"\nvoid f(void) \{ \}\n"
    let fjson = "\{\"kind\": \"TranslationUnitDecl\", \"inner\": [\{\"kind\": \"FunctionDecl\", \"loc\": \{\"offset\": 15\}, \"range\": \{\"begin\": \{\"offset\": 10\}\}, \"name\": \"f\", \"type\": \{\"qualType\": \"void (void)\"\}, \"inner\": [\{\"kind\": \"CompoundStmt\", \"range\": \{\"begin\": \{\"offset\": 23\}\}, \"inner\": [\{\"kind\": \"IndirectGotoStmt\", \"range\": \{\"begin\": \{\"offset\": 25\}\}\}]\}]\}]\}"
    let stmt <- compare_texts("u.i", ftext, fjson)
    t |> success(find(join(stmt.clang_lines, "\n"), "(unknown IndirectGotoStmt@1:16)") >= 0, join(stmt.clang_lines, "\n"))
    let top <- compare_texts("u.i", text, "\{\"kind\": \"TranslationUnitDecl\", \"inner\": [\{\"kind\": \"FileScopeAsmDecl\", \"loc\": \{\"offset\": 10\}, \"range\": \{\"begin\": \{\"offset\": 10\}\}\}]\}")
    t |> success(has_line(top.clang_lines, "(unknown FileScopeAsmDecl@1:1)"), join(top.clang_lines, "\n"))
    t |> equal(top.verdict, "differs")
}
