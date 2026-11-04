-- timed: runs the script arg[1] with the rest of the arguments as its own `arg`, reading the clock
-- (os.clock, the process's CPU time) before and after it, and reports the seconds between as the
-- line `c2das_work_s=<seconds>` on stderr, so the load of the interpreter stays out of the work
-- the library functions are held from the start: the test suite's all.lua ends by clearing globals
local clock, stderr, format = os.clock, io.stderr, string.format
local script = assert(arg and arg[1], "usage: timed.lua <script> [arguments]")
local shifted = {}
for i, v in pairs(arg) do
  shifted[i - 1] = v
end
arg = shifted
local started = clock()
dofile(script)
stderr:write(format("c2das_work_s=%.6f\n", clock() - started))
