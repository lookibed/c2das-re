options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../c_defines.das

//! `frontend/c_defines.das`: the one parser of a macro definition entry, and the reader of a
//! dialect's predefined-macro table, which fails closed naming the file and the line.

// `entry` as `parse_define` reads it, `name|params|value` with `fn` ahead of a function-like one;
// "refused" when it is no entry
def private parsed_as(entry : string) : string {
    var parsed : Define
    if (!parse_define(entry, parsed)) {
        return "refused"
    }
    return "{parsed.fn_like ? "fn " : ""}{parsed.name}|{join(parsed.params, ",")}|{parsed.value}"
}

[test(description = "a macro definition entry is NAME, NAME=value or NAME(params)=value, and nothing else")]
def test_parse_define(t : T?) {
    t |> run("a bare name has the value 1, an empty value stays empty, a value keeps its `=` and blanks") @(t : T?) {
        t |> equal(parsed_as("_N1"), "_N1||1")
        t |> equal(parsed_as("E="), "E||")
        t |> equal(parsed_as("M=a=b c"), "M||a=b c")
        t |> equal(parsed_as("__INT_MAX__=2147483647"), "__INT_MAX__||2147483647")
    }
    t |> run("a function-like macro keeps its parameters in order, `...` the last") @(t : T?) {
        t |> equal(parsed_as("__INT64_C(c)=c##L"), "fn __INT64_C|c|c##L")
        t |> equal(parsed_as("TRY(L, c, a)=\{ a \}"), "fn TRY|L,c,a|\{ a \}")
        t |> equal(parsed_as("NONE()=0"), "fn NONE||0")
        t |> equal(parsed_as("LOG(fmt, ...)=f(fmt)"), "fn LOG|fmt,...|f(fmt)")
    }
    t |> run("a head that is no identifier, and a function-like head that is malformed or has no value, are refused") @(t : T?) {
        for (bad in fixed_array("", "-UN", "=x", "1N", "A-B=1", " A=1", "F(x)", "F(1x)=0", "F(x,)=0", "F(..., x)=0", "F(x=0", "(x)=0", "F(x)y=0")) {
            t |> equal(parsed_as(bad), "refused", bad)
            t |> equal(is_define(bad), false, bad)
        }
        t |> equal(is_define("F(x)=0"), true)
    }
    t |> run("a second parse into the same value leaves nothing of the first") @(t : T?) {
        var parsed : Define
        t |> equal(parse_define("F(a, b)=a", parsed), true)
        t |> equal(parse_define("G", parsed), true)
        t |> equal("{parsed.name} {parsed.fn_like} {length(parsed.params)} {parsed.value}", "G false 0 1")
    }
}

[test(description = "a predefined-macro table is one entry a line, read in order, refused with the file and the line")]
def test_parse_predefined(t : T?) {
    t |> run("entries come in the file's order as written; an empty line and a `#` line are skipped") @(t : T?) {
        var error : string
        let entries <- parse_predefined("# head\n\nB=2\n#A=0\nA\nF(x)=x##L\nE=\n", "t.defs", error)
        t |> equal(error, "")
        t |> equal(join(entries, ";"), "B=2;A;F(x)=x##L;E=")
    }
    t |> run("a line that is no entry is refused with the file and its line, a blank at either end included") @(t : T?) {
        for (bad in fixed_array("1A=2", "A B", " A=1", "A=1 ", "\tA", "F(x)", "-DA")) {
            var error : string
            parse_predefined("A0=1\n\n{bad}\nZ=1\n", "dir/t.defs", error)
            t |> equal(error, "dir/t.defs:3: `{bad}` is no entry `NAME`, `NAME=value` or `NAME(params)=value`")
        }
    }
    t |> run("a name defined twice is refused at its second line, naming the first, whatever its form") @(t : T?) {
        for (again in fixed_array("A=1", "A", "A(x)=x", "A=")) {
            var error : string
            parse_predefined("# c\nA=1\nB=2\n{again}\n", "t.defs", error)
            t |> equal(error, "t.defs:4: `A` is defined at line 2 already")
        }
    }
}

[test(description = "the table files: a missing or empty one is refused by its path, and each dialect's own is well formed")]
def test_read_predefined(t : T?) {
    t |> run("a file that does not exist, and one with no entry, are refused naming the path") @(t : T?) {
        let missing = path_join(test_temp_dir(), "c_defines_missing.defs")
        var error : string
        t |> equal(length(read_predefined(missing, error)), 0)
        t |> equal(error, "{missing}: no such predefined-macro table")
        let hollow = path_join(test_temp_dir(), "c_defines_hollow.defs")
        fwrite(hollow, "# nothing\n\n")
        var hollow_error : string
        read_predefined(hollow, hollow_error)
        t |> equal(hollow_error, "{hollow}: the predefined-macro table holds no entry")
        var malformed_error : string
        fwrite(hollow, "A=1\nA=2\n")
        read_predefined(hollow, malformed_error)
        t |> equal(malformed_error, "{hollow}:2: `A` is defined at line 1 already")
    }
    t |> run("each dialect's table lies beside the module, reads clean, and states the language once") @(t : T?) {
        for (dialect in DIALECTS) {
            let path = predefined_path(dialect)
            t |> success(path |> ends_with("frontend/predefined/{dialect}.defs"), path)
            var error : string
            var inscope entries <- read_predefined(path, error)
            t |> equal(error, "")
            t |> success(has_value(entries, "__STDC_VERSION__=201710L"), "{path} states no gnu17 __STDC_VERSION__")
            t |> success(has_value(entries, "__STDC_NO_VLA__=1"), "{path} states no __STDC_NO_VLA__")
            for (entry in entries) {
                t |> success(find(entry, "=") > 0, "{path}: `{entry}` spells no value")
            }
        }
    }
}
