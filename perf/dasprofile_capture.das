options gen2

require daslib/fio
require daslib/json_boost
require daslib/clargs
require ../converter/sidecar.das

//! dasProfile's capture copied under perf/ as this tree's record of it: the JSON its runner wrote
//! (`profile_results_linux.json`), with the dasProfile commit it ran and the toolchain line
//! (its C++ compiler, daslang and LLVM) stamped on top. `perf/dasprofile.sh` runs it.

[CommandLineArgs]
struct Args {
    @clarg_doc = "dasProfile's profile_results_linux.json"
    input : string = ""
    @clarg_doc = "the dasProfile commit the capture ran"
    commit : string = ""
    @clarg_doc = "the file to write"
    out : string = "perf/dasprofile_linux.json"
    @clarg_short = "?"
    @clarg_name = "show-help"
    @clarg_doc = "show this help and exit"
    show_help : bool
}

[export]
def main : int {
    var args = Args()
    let parsed = parse_args_with_help(args, "dasprofile_capture")
    if (parsed >= 0) {
        return parsed
    }
    if (args.show_help || empty(args.input) || empty(args.commit)) {
        print_help(get_command_info(type<Args>), "dasprofile_capture")
        return args.show_help ? 0 : 2
    }
    var error : string
    var js = read_json_file(args.input, error)
    if (js == null || !(js.value is _object)) {
        to_log(LOG_ERROR, "{args.input}: {empty(error) ? "not a JSON object" : error}\n")
        return 1
    }
    let versions = js?["versions"]
    let toolchain = "{versions?["cpp_compiler"] ?? ""}, daslang {versions?["daslang"] ?? ""}, LLVM {versions?["llvm"] ?? ""}"
    (js.value as _object)["dasprofile_commit"] = JV(args.commit)
    (js.value as _object)["toolchain"] = JV(toolchain)
    fwrite(args.out, write_json(js) + "\n")
    return 0
}
