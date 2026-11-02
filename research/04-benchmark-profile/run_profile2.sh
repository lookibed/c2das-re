#!/usr/bin/env bash
# the instrumenting profiler on binary_trees 6 and 9 (tree summary to stderr), then the chain
# reorder delta: binary_trees 12 on the converted tree and on the copy with the hot cases first
set -u
cd /root/wt-research || exit 1
. scripts/env.sh
O=/root/wt-research/research/04-benchmark-profile
BENCH=ports/lua/bench/binary_trees.lua
LM="-load_module /root/wt-research/dasCRuntime -load_module /root/wt-research/c_runtime"
t() { local s e; s=$(date +%s.%N); "$@" > /dev/null 2>&1; e=$(date +%s.%N); echo "$e - $s" | bc; }
for n in 6 9; do
  s=$(date +%s.%N)
  /usr/bin/time -v "$DASLANG" $LM --das-profiler --das-profiler-time-unit us lua/work/lua/lua.das -- $BENCH $n > $O/profile_bt$n.txt 2>&1
  e=$(date +%s.%N)
  echo "profiled binary_trees $n: $(echo "$e - $s" | bc) s, load $(cut -d' ' -f1 /proc/loadavg)" >> $O/baseline.txt
done
{
  echo "reorder delta $(date -u +%TZ), load $(cut -d' ' -f1-3 /proc/loadavg)"
  echo "reordered startup warm: $(t "$DASLANG" $LM $O/lua_reorder/lua.das -- -e 'print(1)')"
  for s in 1 2; do
    echo "reordered startup: $(t "$DASLANG" $LM $O/lua_reorder/lua.das -- -e 'print(1)')"
    echo "reordered binary_trees 12: $(t "$DASLANG" $LM $O/lua_reorder/lua.das -- $BENCH 12)"
    echo "converted startup: $(t "$DASLANG" $LM lua/work/lua/lua.das -- -e 'print(1)')"
    echo "converted binary_trees 12: $(t "$DASLANG" $LM lua/work/lua/lua.das -- $BENCH 12)"
  done
  "$DASLANG" $LM $O/lua_reorder/lua.das -- $BENCH 12 | md5sum
  "$DASLANG" $LM lua/work/lua/lua.das -- $BENCH 12 | md5sum
} > $O/reorder_delta.txt 2>&1
echo done2 >> $O/baseline.txt
