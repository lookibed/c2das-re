options gen2
require dastest/testing_boost public
require strings
require daslib/strings_boost
require daslib/fio
require ../web/quake/frame_digest.das

//! The quakegeneric page's two pure pieces (web/ARCHITECTURE.md section 7): the frame-hash fold the
//! host runs against the page's `frameDigest` (under node, skipped where none is found), and
//! `web/quake/expected_frames.das`, which writes the reference out of the Rust repository's cases.

// 100 hashes with both signs, as the native entry prints them
def private sample_hashes : array<int> => <- [for (i in range(100)); (i * 1103515245 + 12345) * (i % 2 == 0 ? 1 : -1)]

def private find_node : string {
    if (executable_on_path("node")) {
        return "node"
    }
    let runner = "/opt/actions-runner/externals/node24/bin/node"
    return fexist(runner) ? runner : ""
}

[test(description = "the host's fold of 100 frame hashes equals the page's frameDigest over their native lines")]
def test_frame_digest_pair(t : T?) {
    let hashes <- sample_hashes()
    let digest = frame_digest(hashes, 100)
    t |> success(digest != frame_digest(hashes, 99), "the count matters")
    let node = find_node()
    if (empty(node)) {
        t |> skip("no node: the page's fold is checked where node runs")
        return
    }
    let page = fread("web/quake/shell.html")
    let start = find(page, "  function frameDigest(text) \{")
    t |> success(start >= 0, "shell.html defines frameDigest")
    if (start < 0) {
        return
    }
    let end = find(page, "\n  }\n", start)
    let fn_text = slice(page, start, end + 5)
    var dir_error : string
    let work = create_temp_directory("c2das_quake_digest", dir_error)
    t |> equal(dir_error, "")
    let lines = join([for (i in range(100)); "frame[{i}]={hashes[i]}"], "\n") + "\nframes=100\n"
    fwrite(path_join(work, "ref.txt"), lines)
    fwrite(path_join(work, "fold.js"), "{fn_text}\nconst r = frameDigest(require('fs').readFileSync(process.argv[2], 'latin1'));\nconsole.log(r.frames + ' ' + r.digest);\n")
    var out : string
    let rc = run_and_capture([node, path_join(work, "fold.js"), path_join(work, "ref.txt")], out)
    t |> equal(rc, 0, out)
    t |> equal(strip(out), "100 {fmt(":08x", digest)}")
    rmdir_rec(work)
}

// expected_frames.das run by the daslang running the test, with `args`; its output in `out`
def private extract(args : array<string>; var out : string&) : int {
    var argv <- ["{get_das_root()}/bin/daslang", "web/quake/expected_frames.das", "--"]
    argv |> push_from(args)
    return run_and_capture(argv, out, 120.0)
}

[test(description = "expected_frames.das writes the case's 100 frame lines and refuses a bad call, bad JSON and a case without 100 frames")]
def test_expected_frames(t : T?) {
    var dir_error : string
    let work = create_temp_directory("c2das_quake_frames", dir_error)
    t |> equal(dir_error, "")
    let hashes <- sample_hashes()
    let stdout = join([for (i in range(100)); "frame[{i}]={hashes[i]}"], "\\n") + "\\nframes=100\\n"
    let good = path_join(work, "good.json")
    fwrite(good, "\{\"cases\": [\{\"id\": \"other\"\}, \{\"id\": \"quakegeneric-demo1-std\", \"expected\": \{\"stdout\": \"{stdout}\"\}\}]\}")
    let out_file = path_join(work, "frames.txt")
    var out : string
    let rc_3288 = extract([good, out_file], out)
    t |> equal(rc_3288, 0, out)
    let written = fread(out_file)
    t |> equal(length(split(strip(written), "\n")), 100)
    t |> success(starts_with(written, "frame[0]={hashes[0]}\n"), written)
    let rc_3508 = extract([good], out)
    t |> equal(rc_3508, 2, out)
    let broken = path_join(work, "broken.json")
    fwrite(broken, "\{\"cases\": [")
    let rc_3638 = extract([broken, out_file], out)
    t |> equal(rc_3638, 1, out)
    let short = path_join(work, "short.json")
    fwrite(short, "\{\"cases\": [\{\"id\": \"quakegeneric-demo1-std\", \"expected\": \{\"stdout\": \"frame[0]=1\\nframes=1\\n\"\}\}]\}")
    let rc_3878 = extract([short, out_file], out)
    t |> equal(rc_3878, 1, out)
    t |> success(find(out, "not 100") >= 0, out)
    rmdir_rec(work)
}
