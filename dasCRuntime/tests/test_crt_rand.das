options gen2
require dastest/testing_boost public
require strings
require daslib/fio

//! The wasm archive's glibc rand (dasCRuntime/src/glibc_rand.cpp, ARCHITECTURE.md section 8) against
//! the host's own glibc: the file compiled natively with its functions renamed, the sequences compared
//! for an unseeded program and several seeds. Skipped where no C++ compiler is on PATH, or the host
//! C library is not glibc.

def private find_cxx : string {
    for (cxx in ["c++", "clang++", "g++"]) {
        if (executable_on_path(cxx)) {
            return cxx
        }
    }
    return ""
}

[test(description = "glibc_rand.cpp draws glibc's sequence: unseeded, and seeded with 0, 1, 42 and 12345")]
def test_glibc_rand(t : T?) {
    let cxx = find_cxx()
    if (empty(cxx)) {
        t |> skip("no C++ compiler on PATH")
        return
    }
    var dir_error : string
    let work = create_temp_directory("c2das_crt_rand", dir_error)
    t |> equal(dir_error, "")
    let source = path_join(work, "rand_check.cpp")
    let binary = path_join(work, "rand_check")
    let file = get_full_file_name("dasCRuntime/src/glibc_rand.cpp")
    // the file's rand and srand renamed, so the program also reaches the C library's own
    fwrite(source, "#define rand glibc_rand_copy\n#define srand glibc_srand_copy\n#include \"{file}\"\n#undef rand\n#undef srand\n#include <stdio.h>\n#include <stdlib.h>\nint main() \{\n#ifndef __GLIBC__\n    printf(\"not glibc\\n\");\n    return 0;\n#else\n    int diffs = 0;\n    for (int i = 0; i < 1000; i++) diffs += glibc_rand_copy() != rand();\n    unsigned seeds[] = \{0, 1, 42, 12345\};\n    for (unsigned s : seeds) \{\n        glibc_srand_copy(s);\n        srand(s);\n        for (int i = 0; i < 1000; i++) diffs += glibc_rand_copy() != rand();\n    \}\n    printf(\"diffs %d\\n\", diffs);\n    return 0;\n#endif\n\}\n")
    var out : string
    let built = run_and_capture([cxx, "-std=c++17", "-o", binary, source], out, 120.0)
    t |> equal(built, 0, out)
    let ran = run_and_capture([binary], out, 60.0)
    t |> equal(ran, 0, out)
    if (strip(out) == "not glibc") {
        t |> skip("the host C library is not glibc")
    } else {
        t |> equal(strip(out), "diffs 0")
    }
    rmdir_rec(work)
}
