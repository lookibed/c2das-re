options gen2

module _own_header_names public

require strings
require daslib/fio
require ../c_defines.das

//! The headers of the own set by the names a program includes them under (`sys/stat.h`), sorted:
//! what the header tests under `include/tests/` and `converter/tests/` both walk. It lives here
//! because a `require` path cannot spell the folder `include`, a daslang keyword.
def header_names : array<string> {
    var names : array<string>
    dir_rec(own_include_dir()) $(name, is_dir) {
        if (!is_dir && name |> ends_with(".h")) {
            names |> push(clone_string(name))
        }
    }
    sort(names)
    return <- names
}
