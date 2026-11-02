#!/bin/sh
# 02-temporaries: native / converted / folded, interp and JIT, five samples each.
set -u
cd /root/wt-research/research/02-temporaries/composed
. /root/wt-research/scripts/env.sh
DAS="$DASLANG -load_module /root/wt-research/dasCRuntime -load_module /root/wt-research/c_runtime"
clang -O3 -w -funsigned-char -o out/pinned_copy_native pinned_copy.c || exit 1
for i in 1 2 3 4 5; do echo "native $(./out/pinned_copy_native)"; done
for v in pinned_copy pinned_copy_folded; do
  for lane in interp jit; do
    flag=""; [ $lane = jit ] && flag="-jit"
    for i in 1 2 3 4 5; do echo "$v $lane $($DAS $flag out/$v.das 2>&1 | grep -v '^\[I\]' | tail -1)"; done
  done
done
