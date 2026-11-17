options gen2

require daslib/fio
require daslib/json_boost
require daslib/strings_boost
require daslib/clargs
require strings
require ../../converter/pipeline.das
require ../../converter/tiers.das

//! The translator page's examples (web/ARCHITECTURE.md section 8), converted at build time by the
//! native pipeline: for each C example of `examples.json`, its source, the C-IR the page converts
//! live, the module under the default knobs, and the converted program's output under the
//! interpreter (the page's recorded run); the Lua snippets pass through. Written as one JSON file.
//! usage: daslang web/translator/precompute.das -- <examples.json> <doom sidecar> <out.json> <work dir>

// the length of a JSON array, 0 when `v` is no array (json_boost's `?[i]` past the end is not null)
def private json_length(v : JsonValue?) : int => v != null && v.value is _array ? length(v.value as _array) : 0

// a JSON string literal of `s`
def private quoted(s : string) : string => write_json(JV(s))

[export]
def main : int {
    let args <- get_user_args()
    if (length(args) != 4) {
        to_log(LOG_ERROR, "usage: precompute.das -- <examples.json> <doom sidecar> <out.json> <work dir>\n")
        return 2
    }
    var error : string
    var manifest = read_json(fread(args[0]), error)
    if (manifest == null) {
        to_log(LOG_ERROR, "precompute: {args[0]}: {error}\n")
        return 1
    }
    let examples_dir = dir_name(args[0])
    let examples = manifest?["examples"]
    var entries : array<string>
    entries |> reserve(json_length(examples))
    for (k in range(json_length(examples))) {
        let ex = examples?[k]
        let id = ex?["id"] ?? ""
        let file = ex?["file"] ?? ""
        // an example in the repository lies beside the manifest; a fetched one (Doom) is a repository path
        let c_path = starts_with(file, "doom/") ? file : path_join(examples_dir, file)
        let sidecar = (ex?["sidecar"] ?? "") == "doom_defines" ? args[1] : ""
        let out_dir = path_join(args[3], id)
        let res <- convert(c_path, out_dir, "linux", "", sidecar)
        if (!res.ok) {
            to_log(LOG_ERROR, "precompute: {c_path}: {res.error}\n")
            return 1
        }
        var output : string
        let rc = run_tier(res.das_path, "interp", out_dir, output, ["c_runtime", "dasCRuntime"], 120.0)
        let sidecar_text = empty(sidecar) ? "\{\}" : fread(sidecar)
        entries |> push("\{\"id\": {quoted(id)}, \"title\": {quoted(ex?["title"] ?? id)}, \"about\": {quoted(ex?["about"] ?? "")}, \"file\": {quoted(file)}, \"c\": {quoted(fread(c_path))}, \"cir\": {quoted(res.cir_text)}, \"das\": {quoted(res.das_text)}, \"sidecar\": {sidecar_text}, \"output\": {quoted(output)}, \"exit\": {rc}\}")
        to_log(LOG_INFO, "precompute: {id}: {length(res.cir_text)} bytes of C-IR, exit {rc}\n")
    }
    let snippets = manifest?["lua"]
    var lua : array<string>
    lua |> reserve(json_length(snippets))
    for (k in range(json_length(snippets))) {
        let ex = snippets?[k]
        lua |> push("\{\"id\": {quoted(ex?["id"] ?? "")}, \"title\": {quoted(ex?["title"] ?? "")}, \"code\": {quoted(ex?["code"] ?? "")}\}")
    }
    if (!fwrite(args[2], "\{\"examples\": [\n{join(entries, ",\n")}\n], \"lua\": [\n{join(lua, ",\n")}\n]\}\n")) {
        to_log(LOG_ERROR, "precompute: cannot write {args[2]}\n")
        return 1
    }
    return 0
}
