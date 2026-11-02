#!/usr/bin/env python3
"""Classify every `_tN` declaration of a converted das file by the reason it exists.
Usage: classify_temps.py file.das [...]"""
import re, sys
DECL = re.compile(r'^\s*(let|var)\s+(_t\d+)(\s*:\s*[^=]+)?(\s*=\s*(.*))?$')
def functions(lines):
    start = 0
    for i, l in enumerate(lines):
        if re.match(r'^(def|\[c_function\]|\[init\])', l) and i > start:
            yield lines[start:i]; start = i
    yield lines[start:]
def classify(body, i):
    m = DECL.match(body[i]); kw, name, typ, _, rhs = m.groups()
    rhs = (rhs or '').strip()
    nxt = body[i+1].strip() if i+1 < len(body) else ''
    later = [l for l in body[i+1:] if re.search(r'\b%s\b' % name, l)]
    uses = sum(len(re.findall(r'\b%s\b' % name, l)) for l in later)
    if typ and not rhs and nxt.startswith('if ('): return 'ternary'
    if kw == 'var' and (nxt == f'if ({name}) {{' or nxt == f'if (!{name}) {{'): return 'and_or_flag'
    if rhs and (nxt in (rhs+'++', rhs+'--') or nxt.startswith(rhs+' = '+rhs+' + 1') or nxt.startswith(rhs+' = '+rhs+' - 1')
                or re.match(re.escape(rhs)+r' = (int|uint)\d*\((int|uint)\('+re.escape(rhs)+r'\) [+-] 1\)', nxt)):
        return 'postfix_old_value' if uses else 'postfix_old_value_unused'
    if uses == 0: return 'discarded'
    if re.match(r'[A-Za-z_][\w:]*\(', rhs) and not rhs.startswith(('deref(','addr(','int(','uint(','int64(','uint64(','reinterpret<')): 
        return 'call_result_'+('once' if uses==1 else 'multi')
    if rhs == '1 != 0' or rhs == '0 != 0': return 'constant_bool'
    return 'pin_'+('once' if uses==1 else 'multi')
for path in sys.argv[1:]:
    lines = open(path).read().split('\n')
    counts = {}; samples = {}
    for body in functions(lines):
        for i, l in enumerate(body):
            if DECL.match(l):
                c = classify(body, i); counts[c] = counts.get(c, 0) + 1
                samples.setdefault(c, []).append(l.strip())
    print(f'== {path}: {sum(counts.values())} declarations')
    for c in sorted(counts, key=lambda k: -counts[k]):
        print(f'  {counts[c]:4d} {c}   e.g. {samples[c][0][:90]}')
