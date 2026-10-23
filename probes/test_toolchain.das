options gen2
require dastest/testing_boost public
require cbind
require strings
require daslib/strings_boost
require daslib/fio
require daslib/safe_addr
require _daslang_child

[test]
def test_toolchain(t : T?) {
    t |> run("cbind loads and libclang answers") @(t : T?) {
        let idx = clang_createIndex(0, 0)
        t |> success(idx != null, "clang_createIndex")
        clang_disposeIndex(idx)
    }
}

// the arguments of `__builtin_constant_p` the probe asks about, one per line of the program
let CONSTANT_P_CASES <- ["42", "-5", "1.5", "E1", "sizeof(int)", "sizeof x", "_Alignof(double)", "__builtin_offsetof(struct S, b)", "1 ? 2 : 3", "!0", "(1234 + 45) & ~7", "\"hi\"", "1 ? 2 : x", "0 && x", "1 || x", "1 / 0", "kc", "lc", "&glob", "\"hi\" + 1", "(void *)0", "(int)d", "1.0 / 3", "1.0 / 0.0", "x * 0", "(1, 2)", "-2147483647 - 1 - 1 > 0", "1 << 40", "\"hi\"[0]", "main", "(long)&glob", "&glob == 0", "x", "f()", "i++", "__builtin_constant_p(i++)", "x ? 1 : 1", "__builtin_choose_expr(1, 5, x)", "(x, x)", "(x, 5)", "(x, 5) + 1", "((void)x, 5)", "(x ? 1 : 2, 3)", "(double)(x, 2.5)", "__builtin_constant_p(x)", "__builtin_constant_p(x) + 1"]

// the last cases, which the evaluator cannot fold but the -O0 build answers 1: a comma operator,
// whose right operand the code generator emits on its own, and a nested call
let UNFOLDED_ONES = 7

// the program: one `printf` of a `__builtin_constant_p` per case, the case on line `CASE_LINE + n`
def constant_p_program : string {
    return build_string() $(writer) {
        writer |> write("int printf(const char *, ...);\nint glob = 3;\nstatic const int kc = 5;\nenum \{ E1 = 3 \};\nstruct S \{ int a; int b; \};\nstatic int calls;\nstatic int f(void) \{ calls++; return 4; \}\nint main(int argc, char **argv) \{\n    (void)argv;\n    int x = argc, i = 0;\n    const int lc = 9;\n    double d = 1.5;\n")
        for (arg in CONSTANT_P_CASES) {
            writer |> write("    printf(\"%d\", __builtin_constant_p({arg}));\n")
        }
        writer |> write("    printf(\" %d %d\", i, calls);\n    return 0;\n\}\n")
    }
}

let CASE_LINE = 13

// libclang's answer per case, from the outermost call on each case's line: `1` or `0` from
// `clang_Cursor_Evaluate`, `n` when it gives no result
def libclang_answers(path : string) : array<string> {
    var answers : array<string>
    answers |> resize(length(CONSTANT_P_CASES))
    var idx = clang_createIndex(0, 0)
    var args <- ["-w"]
    var unit = clang_parseTranslationUnit(idx, path, unsafe(addr(args[0])), length(args), null, 0u, 0u)
    visit_calls(clang_getTranslationUnitCursor(unit), answers)
    clang_disposeTranslationUnit(unit)
    clang_disposeIndex(idx)
    return <- answers
}

def visit_calls(var c : CXCursor; var answers : array<string>) {
    clang_visitChildren(c) $(var kid, _parent) {
        if (clang_getCursorKind(kid) == CXCursorKind.CallExpr && string(clang_getCursorSpelling(kid)) == "__builtin_constant_p") {
            var file : CXFile
            var line, column, offset : uint
            clang_getExpansionLocation(clang_getCursorLocation(kid), safe_addr(file), safe_addr(line), safe_addr(column), safe_addr(offset))
            let at = int(line) - CASE_LINE
            if (at >= 0 && at < length(answers) && empty(answers[at])) {
                var res = clang_Cursor_Evaluate(kid)
                if (res == null) {
                    answers[at] = "n"
                } else {
                    answers[at] = clang_EvalResult_getKind(res) == CXEvalResultKind.Int ? "{clang_EvalResult_getAsLongLong(res)}" : "?"
                    clang_EvalResult_dispose(res)
                }
            }
        }
        visit_calls(kid, answers)
        return CXChildVisitResult.Continue
    }
}

[test]
def test_constant_p_evaluation(t : T?) {
    t |> run("clang_Cursor_Evaluate on a __builtin_constant_p call gives the pinned clang's -O0 answer, no result where that answer is 0, except across a comma or over a nested unfolded call") @(t : T?) {
        let source = constant_p_program()
        let native = native_battery("c2das_probe_constant_p", ["-O0"], source)
        let path = "{temp_directory_result() as value}/c2das_probe_constant_p_lib.c"
        fwrite(path, source)
        let answers <- libclang_answers(path)
        remove(path)
        let cases = length(CONSTANT_P_CASES)
        t |> equal(length(native), cases + 4, native)
        t |> equal(slice(native, cases), " 0 0", "the argument is never evaluated: {native}")
        let wanted <- [for (ch in native); to_char(ch)]
        if (length(wanted) != cases + 4) {
            return
        }
        for (n in range(cases)) {
            let lib = answers[n]
            let want = wanted[n]
            if (n < cases - UNFOLDED_ONES) {
                // no result is clang's 0: the evaluator defers a call it cannot fold, and -O0 codegen answers 0
                t |> equal(lib == "n" ? "0" : lib, want, "`{CONSTANT_P_CASES[n]}`: libclang {lib}, native {want}")
            } else {
                // a comma or a nested call the evaluator cannot fold: libclang gives nothing, the -O0 build 1
                t |> equal(lib, "n", "`{CONSTANT_P_CASES[n]}`")
                t |> equal(want, "1", "`{CONSTANT_P_CASES[n]}`")
            }
        }
    }
}
