#!/usr/bin/env python3 -I
# Moves the hot, break-terminated opcode cases of luaV_execute's `_flag` chain to its front in a
# copy of lvm.das.inc: the time delta against the converted order is the chain's cost for them.
import re, sys
src, dst = sys.argv[1], sys.argv[2]
hot = sys.argv[3].split(',')
lines = open(src).read().split('\n')
start = re.compile(r'^                _flag \|\|= _goto == 0 && _cond == OpCode\.(OP_\w+)$')
other = re.compile(r'^                _flag \|\|= _goto == \d+')
idx = [i for i, l in enumerate(lines) if start.match(l) or other.match(l)]
# blocks: [begin, end) between consecutive chain heads, within luaV_execute's chain
first = idx[0]
blocks = []
for a, b in zip(idx, idx[1:] + [None]):
    if b is None:
        # the last block ends at the chain's closing `break` line of the while(true)
        b = a
        while not lines[b].startswith('            }'):
            b += 1
    name = start.match(lines[a]).group(1) if start.match(lines[a]) else lines[a].strip()
    blocks.append((name, a, b))
def ends_with_break(blk):
    _, a, b = blk
    tail = [l.strip() for l in lines[a:b] if l.strip()]
    return tail[-3:] == ['break', '}', '}']
moved, kept = [], []
for i, blk in enumerate(blocks):
    if blk[0] in hot:
        assert ends_with_break(blk), blk[0] + ' does not end with break'
        assert i == 0 or ends_with_break(blocks[i - 1]), blk[0] + ' is a fall-through target'
        moved.append(blk)
    else:
        kept.append(blk)
assert len(moved) == len(hot), 'not every hot opcode found'
end = blocks[-1][2]
out = lines[:first]
for _, a, b in moved + kept:
    out += lines[a:b]
out += lines[end:]
open(dst, 'w').write('\n'.join(out))
print('moved', [m[0] for m in moved], 'chain lines', first, end)
