options gen2

module _stand_in public

require strings
require daslib/fio
require daslib/strings_boost
require ../demo_run.das

//! The converted program's demo run of `run.das --run` over a stand-in program: a das module
//! that checks its C `argv` and `$DOOMWADDIR/doom2.wad`, then prints the tic lines
//! `$DOOM_STAND_IN` (`<tics>,<desynced tic>,<exit code>,<sleep ms>,<missing tic>,<doubled tic>`)
//! asks for, held to a four-tic stand-in reference log; exit code 255 ends in the timedemo line,
//! with the host's timing line after it, any other in a decoy line, an `Error:` line and a later
//! lowercase error line, then the sleep. The native stand-in is a shell script that checks the
//! same, counts its runs in `runs` beside itself and prints the four tic lines (tic 2's `cs` off
//! under `$DOOM_NATIVE_DESYNC`), the timedemo line and the host's. Named `*-speed` it is the
//! speed build: no tic line but the `final` line of tic 3 before the timedemo line, and under
//! `$DOOM_NATIVE_SPEED_FAIL` an exit 0 without either. The das stand-in is the speed build too as a
//! file named `*_speed.das`, its `final` line of the last tic (`cs` off on the desynced tic) before
//! the timedemo line. Every run of either
//! appends its lane (`native`, `interp` or `jit`) and 1 for the speed build, else 0, as a line of
//! `$DOOMWADDIR/order`.
//! Like the host, it stops with exit code 0 after `-tics N` tics when N is fewer.

//! the das stand-in of the converted program
let STAND_IN = "options gen2\nrequire daslib/fio\nrequire strings\nrequire daslib/strings_boost\n[export]\ndef main : int \{\n    let args <- get_command_line_arguments()\n    if (length(args) < 2 || args[length(args) - 2] != \"-timedemo\" || args[length(args) - 1] != \"demo1\" || !stat(get_env_variable(\"DOOMWADDIR\") + \"/doom2.wad\").is_reg) \{\n        print(\"error: no -timedemo demo1 or no doom2.wad\\n\")\n        return 2\n    \}\n    let mode <- [for (field in split(get_env_variable(\"DOOM_STAND_IN\"), \",\")); to_int(field)]\n    let speed = length([for (arg in args); arg; where arg |> ends_with(\"_speed.das\")]) > 0\n    fopen(get_env_variable(\"DOOMWADDIR\") + \"/order\", \"ab\") $(f) \{\n        if (f != null) \{\n            fwrite(f, \"\{has_value(args, \"-jit\") ? \"jit\" : \"interp\"\} \{speed ? 1 : 0\}\\n\")\n        \}\n    \}\n    let at = find_index(args, \"-tics\")\n    let cap = at >= 0 ? to_int(args[at + 1]) : mode[0]\n    for (tic in range(cap < mode[0] ? cap : mode[0])) \{\n        if (tic != mode[4] && !speed) \{\n            print(\"tic=\{tic\} cs=0000000\{tic == mode[1] ? 9 : tic\}\\n\")\n        \}\n        if (tic == mode[5] && !speed) \{\n            print(\"tic=\{tic\} cs=0000000\{tic\}\\n\")\n        \}\n    \}\n    if (cap < mode[0]) \{\n        print(\"host: stopped after \{cap\} tics\\n\")\n        return 0\n    \}\n    if (mode[2] == 255 && speed) \{\n        let last = mode[0] - 1\n        print(\"final tic=\{last\} cs=0000000\{last == mode[1] ? 9 : last\}\\n\")\n    \}\n    print(mode[2] == 255 ? \"Error: timed \{mode[0]\} gametics in \{mode[0]\} realtics\\nhost: timed \{mode[0]\} gametics in 0.250000 s\\n\" : \"Z_Init: decoy\\nError: boom\\nerror: later\\n\")\n    if (mode[3] > 0) \{\n        sleep(uint(mode[3]))\n    \}\n    return mode[2]\n\}\n"

//! the native stand-in, a shell script
let NATIVE_STAND_IN = "#!/bin/sh\n[ \"$1 $2\" = \"-timedemo demo1\" ] && [ -f \"$DOOMWADDIR/doom2.wad\" ] || exit 2\necho run >> \"$(dirname \"$0\")/runs\"\ncase \"$0\" in *-speed) [ -n \"$DOOM_NATIVE_SPEED_FAIL\" ] && exit 0; speed=1;; esac\necho \"native $\{speed:-0\}\" >> \"$DOOMWADDIR/order\"\nfor tic in 0 1 2 3; do cs=$tic; [ \"$tic\" = 2 ] && [ -n \"$DOOM_NATIVE_DESYNC\" ] && cs=9; [ -z \"$speed\" ] && echo \"tic=$tic cs=0000000$cs\"; done\n[ -n \"$speed\" ] && echo \"final tic=3 cs=00000003\"\necho \"Error: timed 4 gametics in 4 realtics\"\necho \"host: timed 4 gametics in 0.125000 s\"\nexit 255\n"

//! A fresh scratch folder, "" when none can be made
def scratch(name : string) : string {
    var error : string
    let dir = create_temp_directory(name, error)
    return empty(error) ? dir : ""
}

//! The spec of a run of the stand-in under a fresh folder: the program, a wad, the four-tic
//! reference log in the second of two reference folders, `tics` tic lines compared.
def stand_in_spec(tics : int) : DemoSpec {
    let root = scratch("doom_demo_run")
    fwrite(path_join(root, "doom_main.das"), STAND_IN)
    fwrite(path_join(root, "stand.wad"), "IWAD")
    mkdir_rec(path_join(root, "ref"))
    fwrite(path_join(root, "ref/stand_demo1.log"), "# stand-in\n" + join([for (tic in range(4)); "tic={tic} cs=0000000{tic}"], "\n") + "\n")
    return <- DemoSpec(entry = path_join(root, "doom_main.das"), tier = "interp", wad = path_join(root, "stand.wad"), demo = 1, tics = tics, timeout = 60.0, work = path_join(root, "work"), ref_dirs <- [path_join(root, "none"), path_join(root, "ref")])
}


//! `NATIVE_STAND_IN` written to `path`, executable; false when it cannot be.
def write_native_stand_in(path : string) : bool {
    var out : string
    return fwrite(path, NATIVE_STAND_IN) && run_and_capture(["chmod", "+x", path], out, 30.0) == 0
}
