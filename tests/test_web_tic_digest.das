options gen2
require dastest/testing_boost public
require strings
require daslib/strings_boost
require daslib/fio
require ../web/puredoom/tic_digest.das

//! The checksum fold of the PureDOOM browser host (web/ARCHITECTURE.md section 3) over the native
//! demo1 log, `doom/ref/freedoom2_demo1.log`: the das fold the host runs and the JS fold the page runs
//! give the same count and digest, pinned here. The JS arm runs the page's own `ticDigest` under node,
//! skipped where no node is found.

let private LOG = "doom/ref/freedoom2_demo1.log"
let private TICS = 2664
let private DIGEST = "ef184ab5"

// the hash as the host prints it, %08x
def private hex8(h : uint) : string {
    let s = fmt(":x", h)
    return repeat("0", 8 - length(s)) + s
}

[test(description = "the das fold of the native demo1 log: 2664 lines, digest ef184ab5, and pieces that are not checksum lines pass through")]
def test_das_fold(t : T?) {
    var digest = TicDigest()
    var folded = 0
    for (line in split(fread(LOG), "\n")) {
        if (!starts_with(line, "tic=")) {
            continue
        }
        // Doom prints `tic=` as a piece of its own, then the rest of the line
        let first = "tic="
        let rest = slice(line, 4) + "\n"
        if (tic_digest_piece(digest, unsafe(reinterpret<uint8?>(first)))) {
            folded++
        }
        tic_digest_piece(digest, unsafe(reinterpret<uint8?>(rest)))
    }
    t |> equal(digest.lines, TICS)
    t |> equal(folded, TICS)
    t |> equal(hex8(digest.hash), DIGEST)
    let other = "M_Init: Init miscellaneous info.\n"
    t |> success(!tic_digest_piece(digest, unsafe(reinterpret<uint8?>(other))), "a line that is not a checksum line is not folded")
    let longer = "tic=x"
    t |> success(!tic_digest_piece(digest, unsafe(reinterpret<uint8?>(longer))), "only the piece `tic=` itself starts a line")
}

// node on PATH, else the self-hosted runner's
def private find_node : string {
    if (executable_on_path("node")) {
        return "node"
    }
    let runner = "/opt/actions-runner/externals/node24/bin/node"
    return fexist(runner) ? runner : ""
}

[test(description = "the page's ticDigest over the same log gives the same count and digest")]
def test_js_fold(t : T?) {
    let node = find_node()
    if (empty(node)) {
        t |> skip("no node: the page's fold is checked where node runs")
        return
    }
    let page = fread("web/puredoom/shell.html")
    let start = find(page, "  function ticDigest(text) \{")
    t |> success(start >= 0, "shell.html defines ticDigest")
    if (start < 0) {
        return
    }
    let end = find(page, "\n  }\n", start)
    t |> success(end > start, "ticDigest ends")
    let fn_text = slice(page, start, end + 5)
    var dir_error : string
    let work = create_temp_directory("c2das_tic_digest", dir_error)
    t |> equal(dir_error, "")
    let script = path_join(work, "fold.js")
    fwrite(script, "{fn_text}\nconst r = ticDigest(require('fs').readFileSync(process.argv[2], 'latin1'));\nconsole.log(r.tics + ' ' + r.digest);\n")
    var out : string
    let rc = run_and_capture([node, script, LOG], out)
    t |> equal(rc, 0, out)
    t |> equal(strip(out), "{TICS} {DIGEST}")
    rmdir_rec(work)
}
