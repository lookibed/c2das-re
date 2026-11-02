#!/usr/bin/env bash
# baselines without the profiler, then the instrumenting profiler on binary_trees (tree summary to stderr)
set -u
cd /root/wt-research || exit 1
. scripts/env.sh
O=/root/wt-research/research/04-benchmark-profile
BENCH=ports/lua/bench/binary_trees.lua
run() { "$DASLANG" -load_module "$PWD/dasCRuntime" -load_module "$PWD/c_runtime" "$@"; }
t() { local s e; s=$(date +%s.%N); "$@" > /dev/null 2>&1; e=$(date +%s.%N); echo "$e - $s" | bc; }
{
  echo "box: $(nproc) cores, load $(cut -d' ' -f1-3 /proc/loadavg), $(date -u +%FT%TZ)"
  echo "startup warm: $(t run lua/work/lua/lua.das -- -e 'print(1)')"
  echo "startup: $(t run lua/work/lua/lua.das -- -e 'print(1)')"
  echo "startup: $(t run lua/work/lua/lua.das -- -e 'print(1)')"
  echo "binary_trees 12: $(t run lua/work/lua/lua.das -- $BENCH 12)"
  echo "binary_trees 9: $(t run lua/work/lua/lua.das -- $BENCH 9)"
  echo "binary_trees 6: $(t run lua/work/lua/lua.das -- $BENCH 6)"
  echo "native startup: $(t lua/work/lua_native -e 'print(1)')"
  echo "native binary_trees 12: $(t lua/work/lua_native $BENCH 12)"
} > $O/baseline.txt 2>&1
for n in 6 9; do
  s=$(date +%s.%N)
  /usr/bin/time -v run --das-profiler --das-profiler-time-unit us lua/work/lua/lua.das -- $BENCH $n > $O/profile_bt$n.txt 2>&1
  e=$(date +%s.%N)
  echo "profiled binary_trees $n: $(echo "$e - $s" | bc) s" >> $O/baseline.txt
done
echo done >> $O/baseline.txt
