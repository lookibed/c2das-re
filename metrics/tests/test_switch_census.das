options gen2
options stack = 1048576
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../switch_census_count.das

let FIXTURE = "metrics/tests/fixtures/switch_census.c"

var private g_rows : array<SwitchFacts>

// the fixture's rows, read once
def private fixture_rows(t : T?) : array<SwitchFacts> {
    if (empty(g_rows)) {
        var error : string
        g_rows |> push_clone_from(census_c_file(FIXTURE, error))
        t |> equal(error, "")
    }
    return <- clone_to_move(g_rows)
}

// `count` programs of the fixture's rows, each row given twice, `falls` and `plain` hot
def private fixture_programs(t : T?; count : int) : array<ProgramCensus> {
    var twice <- fixture_rows(t)
    twice |> push_clone_from(fixture_rows(t))
    return <- [for (_ in range(count)); program_census("fixture", twice, ["falls", "plain"])]
}

// the `nth` switch of function `func` of the fixture
def private of(t : T?; func : string; nth : int = 0) : SwitchFacts {
    var left = nth
    for (f in fixture_rows(t)) {
        if (f.func == func && left-- == 0) {
            return <- clone_to_move(f)
        }
    }
    return <- SwitchFacts()
}

def private got(f : SwitchFacts; name : string) : int => f.n?[name] ?? 0

[test]
def test_census(t : T?) {
    t |> run("every switch of the file is a row, a nested one its own") @(t : T?) {
        let rows <- fixture_rows(t)
        t |> equal(length(rows), 19)
        t |> equal([for (f in rows); f.func; where f.line == 157 || f.line == 165], ["stops", "nested"])
    }
    t |> run("the condition's kind is read below the promotion, a character label makes an int a char") @(t : T?) {
        t |> equal(of(t, "plain").cond, "int")
        t |> equal(of(t, "by_enum").cond, "enum")
        t |> equal(of(t, "by_char").cond, "char")
        t |> equal(got(of(t, "by_char"), "char_labels"), 2)
        t |> equal(of(t, "by_bool").cond, "bool")
        t |> equal(of(t, "dense").cond, "int")
    }
    t |> run("labels, distinct values, their range and how full it is, and where default stands") @(t : T?) {
        let dense = of(t, "dense")
        t |> equal(got(dense, "labels"), 8)
        t |> equal(got(dense, "values"), 8)
        t |> equal(dense.lo, 0l)
        t |> equal(dense.hi, 9l)
        t |> equal(got(dense, "density"), 80)
        t |> equal(dense.default_at, "none")
        t |> equal(of(t, "plain").default_at, "last")
        t |> equal(of(t, "by_enum").default_at, "middle")
        t |> equal(got(of(t, "plain"), "labels"), 6)
        t |> equal(got(of(t, "plain"), "values"), 5)
    }
    t |> run("labels sharing a body and a case that does nothing are no real fall") @(t : T?) {
        let plain = of(t, "plain")
        t |> equal(got(plain, "groups"), 5)
        t |> equal(got(plain, "shared_labels"), 2)
        t |> equal(got(plain, "real_falls"), 0)
        t |> equal(plain.cls, "S1")
    }
    t |> run("statements that run into the next label are a real fall, the last group's are not") @(t : T?) {
        let falls = of(t, "falls")
        t |> equal(got(falls, "real_falls"), 1)
        t |> equal(got(falls, "fall_line"), 56)
        t |> equal(falls.cls, "S2")
    }
    t |> run("a fall into a group that only breaks, through a case that does nothing, is no real fall") @(t : T?) {
        let to_break = of(t, "to_break")
        t |> equal(got(to_break, "falls_to_break"), 1)
        t |> equal(got(to_break, "real_falls"), 0)
        t |> equal(got(to_break, "shared_labels"), 1)
        t |> equal(to_break.cls, "S1")
        t |> equal(got(of(t, "falls"), "falls_to_break"), 0)
    }
    t |> run("a group ending in a noreturn call, an endless loop, an if leaving on both arms or a switch that always leaves does not fall") @(t : T?) {
        t |> equal(got(of(t, "stops"), "real_falls"), 0)
        t |> equal(of(t, "stops").cls, "S1")
    }
}

[test]
def test_census_jumps(t : T?) {
    t |> run("a loop's break and a break that is not its group's last statement are counted apart") @(t : T?) {
        let breaks = of(t, "breaks")
        t |> equal(got(breaks, "loop_breaks"), 1)
        t |> equal(got(breaks, "early_breaks"), 1)
        t |> equal(breaks.cls, "S1")
        t |> equal(got(of(t, "falls"), "early_breaks"), 0)
    }
    t |> run("a goto into another group, a label entered from outside and a goto out of the switch") @(t : T?) {
        t |> equal(got(of(t, "cross"), "goto_cross"), 1)
        t |> equal(of(t, "cross").cls, "S3")
        t |> equal(got(of(t, "entered"), "labels_entered"), 1)
        t |> equal(got(of(t, "entered"), "goto_cross"), 0)
        t |> equal(of(t, "entered").cls, "S3")
        t |> equal(got(of(t, "leaves"), "goto_out"), 1)
        t |> equal(of(t, "leaves").cls, "S1")
    }
    t |> run("a declaration with a label after it is S3 only when a later case names it") @(t : T?) {
        t |> equal(got(of(t, "decl_used"), "decl_cross"), 1)
        t |> equal(got(of(t, "decl_used"), "decl_used_later"), 1)
        t |> equal(of(t, "decl_used").cls, "S3")
        t |> equal(got(of(t, "decl_unused"), "decl_cross"), 1)
        t |> equal(got(of(t, "decl_unused"), "decl_used_later"), 0)
        t |> equal(of(t, "decl_unused").cls, "S1")
    }
    t |> run("a continue that reaches the loop around the switch, and a case label inside a loop") @(t : T?) {
        t |> equal(got(of(t, "continues"), "continues_out"), 1)
        t |> equal(of(t, "continues").cls, "S1")
        t |> equal(got(of(t, "duff"), "nested_labels"), 1)
        t |> equal(of(t, "duff").cls, "S3")
    }
    t |> run("a nested switch keeps its fall and its breaks to itself") @(t : T?) {
        t |> equal(of(t, "nested").cls, "S1")
        t |> equal(got(of(t, "nested"), "early_breaks"), 0)
        t |> equal(of(t, "nested", 1).cls, "S2")
    }
}

[test]
def test_class(t : T?) {
    t |> run("a condition that is no integer is S4 before any other fact") @(t : T?) {
        var f = SwitchFacts(cond = "other")
        f.n["goto_cross"] = 1
        t |> equal(switch_class(f), "S4")
    }
    t |> run("each S3 fact alone makes S3, a real fall beside it too") @(t : T?) {
        for (name in ["goto_cross", "labels_entered", "decl_used_later", "nested_labels"]) {
            var f = SwitchFacts(cond = "int")
            f.n[name] = 1
            f.n["real_falls"] = 1
            t |> equal(switch_class(f), "S3")
        }
    }
}

[test]
def test_rows_text(t : T?) {
    t |> run("a row's line reads back as the row") @(t : T?) {
        var ok = false
        let falls = of(t, "falls")
        let back <- read_facts_line(facts_line(falls), ok)
        t |> success(ok)
        t |> equal(facts_line(back), facts_line(falls))
        t |> equal(back.func, "falls")
        t |> equal(back.cls, "S2")
        t |> equal(got(back, "fall_line"), 56)
    }
    t |> run("a line of another shape is no row") @(t : T?) {
        var ok = true
        read_facts_line("file\t00001", ok)
        t |> success(!ok)
    }
    t |> run("a file the dumper refuses gives its error and no row") @(t : T?) {
        var temp_error : string
        let folder = create_temp_directory("switch_census_", temp_error)
        let path = path_join(folder, "range.c")
        fwrite(path, "int f(int x) \{ switch (x) \{ case 1 ... 3: return 1; \} return 0; \}\n")
        var error : string
        let none <- census_c_file(path, error)
        rmdir_rec(folder)
        t |> success(find(error, "case range") >= 0)
        t |> equal(length(none), 0)
    }
}

[test]
def test_tables(t : T?) {
    t |> run("a switch met twice is one row, hot by its function's name") @(t : T?) {
        let ps <- fixture_programs(t, 1)
        t |> equal(length(ps[0].rows), 19)
        t |> equal([for (f in ps[0].rows); f.func; where f.hot], ["plain", "falls"])
    }
    t |> run("the class table: each class with its share, the hot switches, a pooled total") @(t : T?) {
        let lines <- split(render_classes(fixture_programs(t, 2), "all"), "\n")
        t |> equal(lines[0], "| program | switch | S1 | S2 | S3 | S4 | hot | hot S1 |")
        t |> equal(lines[2], "| fixture | 19 | 13 (68%) | 2 (11%) | 4 (21%) | 0 (0%) | 2 | 1 (50%) |")
        t |> equal(lines[4], "| all | 38 | 26 (68%) | 4 (11%) | 8 (21%) | 0 (0%) | 4 | 2 (50%) |")
        t |> equal(length(split(render_classes(fixture_programs(t, 1), ""), "\n")), 4)
    }
    t |> run("the feature table counts switches, over the hot ones alone when asked") @(t : T?) {
        let all <- split(split(render_features(fixture_programs(t, 1), "", false), "\n")[2], " | ")
        t |> equal([for (idx in range(1, 12)); all[idx]], ["19", "16", "1", "1", "1", "7", "1", "16", "2", "1", "1"])
        t |> equal([for (idx in range(12, 24)); trim_suffix(all[idx], " |")], ["2", "2", "1", "1", "1", "1", "1", "1", "1", "2", "1", "1"])
        let hot <- split(split(render_features(fixture_programs(t, 1), "", true), "\n")[2], " | ")
        t |> equal([for (idx in range(1, 4)); hot[idx]], ["2", "2", "0"])
    }
    t |> run("the site list holds the switches that are not S1 and the hot ones") @(t : T?) {
        let ps <- fixture_programs(t, 1)
        let sites = render_sites(ps[0])
        t |> equal(length(split(sites, "\n")), 8)
        t |> success(find(sites, ":55 `falls` S2 hot int: 3 values, 100% full, default none, real fall 1, first fall at line 56") >= 0)
        t |> success(find(sites, "`plain` S1 hot int") >= 0)
        t |> success(find(sites, "`by_enum`") < 0)
    }
}
