options gen2
// the pipeline parses clang's JSON dump below the test's own frames: a deep expression tree
// overflows the default 16 KB context stack
options stack = 1048576
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../pipeline.das

//! The edge census of `--edge-census` (`converter/layout.das`, `ARCHITECTURE_LAYOUT.md#census`): a
//! program of three cycles, one of calls alone, one of objects and a call, one of function addresses
//! and a record, reported by kind with the clusters left were functions, then objects too,
//! forward-declared; the partition and its report untouched; the refusals.

let CENSUS = "converter/tests/fixtures/p7_census"

// the census of the fixture, `program.edges.txt` line by line
let CENSUS_LINES <- [
    "today: clusters 3",
    "  2 nodes, 2 units: a b",
    "    2 edges; per kind the edges carrying it (its symbols or types): call 2 (2), address 0 (0), global 0 (0), type 0 (0); 2 edges of calls alone, 2 of calls and globals alone",
    "  2 nodes, 2 units: c d",
    "    2 edges; per kind the edges carrying it (its symbols or types): call 1 (1), address 0 (0), global 2 (2), type 0 (0); 0 edges of calls alone, 2 of calls and globals alone",
    "  2 nodes, 2 units: e f",
    "    2 edges; per kind the edges carrying it (its symbols or types): call 0 (0), address 2 (2), global 0 (0), type 1 (1); 0 edges of calls alone, 0 of calls and globals alone",
    "calls forward-declared: clusters 2",
    "  2 nodes, 2 units: c d",
    "  2 nodes, 2 units: e f",
    "calls and globals forward-declared: clusters 1",
    "  2 nodes, 2 units: e f"
]

// the C files of the fixture, in its manifest's link order
def private census_paths : array<string> {
    var error : string
    let input <- read_program_input("{CENSUS}/program.json", "linux", error)
    return <- clone_to_move(input.c_paths)
}

// the fixture's paths and its conversions in the source layout without and with the census, which
// the arms of `test_edge_census` read
var paths : array<string>
var plain : ConvertResult
var census : ConvertResult

[test]
def test_edge_census(t : T?) {
    var dir_error : string
    let root = create_temp_directory("c2das_census", dir_error)
    t |> equal(dir_error, "")
    delete paths
    paths <- census_paths()
    let plain_dir = path_join(root, "plain")
    let census_dir = path_join(root, "census")
    delete plain
    plain <- convert_program(paths, plain_dir, "linux", "", "", "", "", "main", "source")
    delete census
    census <- convert_program(paths, census_dir, "linux", "", "", "", "", "main", "source", true)
    t |> equal(plain.error, "")
    t |> equal(census.error, "")
    t |> run("the census reports each cluster's edges by kind, and the clusters left were functions, then objects too, forward-declared") @(t : T?) {
        t |> equal(join(census.census, "\n"), join(CENSUS_LINES, "\n"))
        t |> equal(fread(path_join(census_dir, "program.edges.txt")), join(CENSUS_LINES, "\n") + "\n")
    }
    t |> run("without the flag no census is written, and the flag leaves the partition and its report as they are") @(t : T?) {
        t |> success(!fexist(path_join(plain_dir, "program.edges.txt")))
        t |> equal(fread(path_join(census_dir, "program.layout.txt")), fread(path_join(plain_dir, "program.layout.txt")))
        t |> equal(join(census.files, " "), join(plain.files, " "))
    }
    t |> run("a conversion without the flag deletes an earlier conversion's census") @(t : T?) {
        let again <- convert_program(paths, census_dir, "linux", "", "", "", "", "main", "source")
        t |> equal(again.error, "")
        t |> success(!fexist(path_join(census_dir, "program.edges.txt")))
    }
    t |> run("in the source-cut layout the census reads the edges before the cut") @(t : T?) {
        let cut <- convert_program(paths, path_join(root, "cut"), "linux", "", "", "", "", "main", "source-cut", true)
        t |> equal(cut.error, "")
        t |> equal(join(cut.census, "\n"), join(CENSUS_LINES, "\n"))
    }
    t |> run("the census of one file or of the single layout is refused") @(t : T?) {
        let one <- convert_program([paths[0]], path_join(root, "one"), "linux", "", "", "", "", "main", "", true)
        t |> equal(one.error, "--edge-census reports the cycles among a program's files; one file has none")
        let single <- convert_program(paths, path_join(root, "single"), "linux", "", "", "", "", "main", "single", true)
        t |> equal(single.error, "--edge-census reports the cycles among a program's modules; the single layout has one module")
    }
    rmdir_rec(root)
}
