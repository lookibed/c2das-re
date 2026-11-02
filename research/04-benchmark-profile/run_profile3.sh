#!/usr/bin/env bash
# nbody: baseline 20000 and 1000, the profiler on 1000; binary_trees 6 under the memory profiler
# (is the das heap idle); the load split with -log-compile-time
set -u
cd /root/wt-research || exit 1
. scripts/env.sh
O=/root/wt-research/research/04-benchmark-profile
LM="-load_module /root/wt-research/dasCRuntime -load_module /root/wt-research/c_runtime"
t() { local s e; s=$(date +%s.%N); "$@" > /dev/null 2>&1; e=$(date +%s.%N); echo "$e - $s" | bc; }
{
  echo "nbody $(date -u +%TZ), load $(cut -d' ' -f1-3 /proc/loadavg)"
  echo "startup: $(t "$DASLANG" $LM lua/work/lua/lua.das -- -e 'print(1)')"
  echo "nbody 20000: $(t "$DASLANG" $LM lua/work/lua/lua.das -- ports/lua/bench/nbody.lua 20000)"
  echo "nbody 1000: $(t "$DASLANG" $LM lua/work/lua/lua.das -- ports/lua/bench/nbody.lua 1000)"
  echo "native nbody 20000: $(t lua/work/lua_native ports/lua/bench/nbody.lua 20000)"
} > $O/nbody_baseline.txt 2>&1
/usr/bin/time -v "$DASLANG" $LM --das-profiler --das-profiler-time-unit us lua/work/lua/lua.das -- ports/lua/bench/nbody.lua 1000 > $O/profile_nbody1000.txt 2>&1
/usr/bin/time -v "$DASLANG" $LM --das-profiler --das-profiler-memory --das-profiler-time-unit us lua/work/lua/lua.das -- ports/lua/bench/binary_trees.lua 6 > $O/memprofile_bt6.txt 2>&1
"$DASLANG" $LM -log-compile-time lua/work/lua/lua.das -- -e 'print(1)' > $O/load_split.txt 2>&1
echo done3 >> $O/baseline.txt
