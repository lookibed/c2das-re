#!/usr/bin/env python3 -I
# Folds the daslang profiler's tree summary (two-space indented "<name> <count> <time><unit>" lines)
# into per-function inclusive and self time. Usage: python3 -I tree_top.py <profile.txt> [N]
import re, sys, collections
path = sys.argv[1]; top = int(sys.argv[2]) if len(sys.argv) > 2 else 30
line_re = re.compile(r'^\[I\] ((?:  )*)(\S.*?) (\d+) (-?\d+)(ns|us|ms|s)$')
unit = {'ns': 1e-3, 'us': 1.0, 'ms': 1e3, 's': 1e6}
rows = []   # (depth, name, count, inclusive_us)
for raw in open(path, errors='replace'):
    m = line_re.match(raw.rstrip('\n'))
    if m:
        rows.append((len(m.group(1)) // 2, m.group(2), int(m.group(3)), int(m.group(4)) * unit[m.group(5)]))
incl = collections.Counter(); self_t = collections.Counter(); calls = collections.Counter()
# self = inclusive - sum of direct children's inclusive
child_sum = [0.0] * len(rows)
stack = []
for i, (d, name, n, t) in enumerate(rows):
    while stack and rows[stack[-1]][0] >= d:
        stack.pop()
    if stack:
        child_sum[stack[-1]] += t
    stack.append(i)
root_total = 0.0
for i, (d, name, n, t) in enumerate(rows):
    if d == 0:
        root_total += t
    base = name.split('`')[0] + '`' + name.split('`')[1] if name.count('`') >= 2 else name
    # strip the hash suffix daslang appends to mangled names
    short = re.sub(r'`[0-9]+$', '', name.split(' ')[0])
    incl[short] += t; self_t[short] += t - child_sum[i]; calls[short] += n
print(f'rows {len(rows)}, roots total {root_total/1e6:.3f} s')
def show(title, counter):
    print(f'\n== top {top} by {title} (s, % of total, calls) ==')
    for name, t in counter.most_common(top):
        print(f'{t/1e6:10.3f} {100*t/root_total:6.2f}% {calls[name]:12d}  {name}')
show('self time', self_t); show('inclusive time', incl)
