#!/usr/bin/env bash
# Names the PCs a sampler.c file holds: self samples per function, the most first.
#   symbolize.sh <samples file> [--top N] [--dso <path substring>] [--addr <symbol substring>]
#                [--callers <symbol substring>] [--lines <symbol substring>]
# --dso keeps the samples of one mapped file; --addr prints one function's samples per
# instruction address (the ELF virtual address objdump -d shows); --callers names the stack-top
# word of the samples in a function, its caller when it is a frameless leaf; --lines one
# function's samples per source line (addr2line, the innermost inlined line; the file needs
# debug info: the JIT's --jit-debug). Needs nm, readelf, awk, addr2line.
set -euo pipefail
file="$1"; shift
top=40; addr=""; dso=""; callers=""; lines=""
while [ $# -gt 0 ]; do
    case "$1" in
        --top) top="$2"; shift 2 ;;
        --addr) addr="$2"; shift 2 ;;
        --dso) dso="$2"; shift 2 ;;
        --callers) callers="$2"; shift 2 ;;
        --lines) lines="$2"; shift 2 ;;
        *) echo "symbolize: unknown flag $1" >&2; exit 2 ;;
    esac
done
work="$(mktemp -d)"
trap 'rm -rf "${work:?}"' EXIT
# the executable mappings of every snapshot, once each: start end offset path
awk '/^# maps/{m=1; next} m && $2 ~ /x/ && NF >= 6 {print $1, $3, $6}' "$file" | sort -u |
    awk '{split($1, r, "-"); print r[1], r[2], $2, $3}' > "$work/maps"
awk '/^# maps/{exit} !/^#/' "$file" > "$work/raw"

# name_list <in: "count hexpc" lines> <out: "hexpc TAB name TAB path TAB vaddr TAB count" lines>
name_list() {
    awk -v maps="$work/maps" '
        function hex(s,   i, c, v) { v = 0; s = tolower(s); for (i = 1; i <= length(s); i++) { c = index("0123456789abcdef", substr(s, i, 1)) - 1; v = v * 16 + c }; return v }
        BEGIN { n = 0; while ((getline line < maps) > 0) { split(line, f, " "); lo[n] = hex(f[1]); hi[n] = hex(f[2]); off[n] = hex(f[3]); path[n] = f[4]; n++ } }
        { pc = hex($2); hit = 0
          for (i = 0; i < n; i++) if (pc >= lo[i] && pc < hi[i]) { printf "%s %d %s %s\n", path[i], pc - lo[i] + off[i], $1, $2; hit = 1; break }
          if (!hit) printf "[anon] %d %s %s\n", pc, $1, $2 }' "$1" > "$work/located"
    : > "$2"
    for path in $(awk '{print $1}' "$work/located" | sort -u); do
        if [ "$path" = "[anon]" ] || [ ! -r "$path" ]; then
            awk -v p="$path" '$1 == p {printf "%s\t?\t%s\t?\t%s\n", $4, p, $3}' "$work/located" >> "$2"
            continue
        fi
        # file offset to virtual address through the LOAD segments
        readelf -lW "$path" | awk '$1 == "LOAD" {print $2, $3, $5}' > "$work/loads"
        # nm pads the address: text order is address order
        { nm -n --defined-only "$path" 2>/dev/null; nm -n -D --defined-only "$path" 2>/dev/null; } |
            awk '$2 ~ /^[tTwWiI]$/ {a = $1; $1 = ""; $2 = ""; sub(/^  /, ""); print a "\t" $0}' | sort -u > "$work/syms"
        awk -v p="$path" -v loads="$work/loads" -v syms="$work/syms" '
            function hex(s,   i, c, v) { s = tolower(s); sub(/^0x/, "", s); v = 0; for (i = 1; i <= length(s); i++) { c = index("0123456789abcdef", substr(s, i, 1)) - 1; v = v * 16 + c }; return v }
            BEGIN { nl = 0; while ((getline line < loads) > 0) { split(line, f, " "); lo_off[nl] = hex(f[1]); va[nl] = hex(f[2]); sz[nl] = hex(f[3]); nl++ }
                    ns = 0; while ((getline line < syms) > 0) { t = index(line, "\t"); sa[ns] = hex(substr(line, 1, t - 1)); sn[ns] = substr(line, t + 1); ns++ } }
            $1 == p { o = $2 + 0; v = o
                      for (i = 0; i < nl; i++) if (o >= lo_off[i] && o < lo_off[i] + sz[i]) { v = o - lo_off[i] + va[i]; break }
                      l = 0; h = ns - 1; best = -1
                      while (l <= h) { m = int((l + h) / 2); if (sa[m] <= v) { best = m; l = m + 1 } else h = m - 1 }
                      printf "%s\t%s\t%s\t%x\t%s\n", $4, best >= 0 ? sn[best] : "?", p, v, $3 }' "$work/located" >> "$2"
    done
}

awk '{print $1}' "$work/raw" | sort | uniq -c > "$work/pcs"
total=$(awk '{s += $1} END {print s + 0}' "$work/pcs")
name_list "$work/pcs" "$work/named"
if [ -n "$dso" ]; then
    awk -F'\t' -v d="$dso" 'index($3, d)' "$work/named" > "$work/kept"
    mv "$work/kept" "$work/named"
fi
echo "# $(head -1 "$file" | sed 's/^# //'), $total located"
if [ -n "$addr" ]; then
    awk -F'\t' -v s="$addr" -v t="$total" 'index($2, s) {c[$4] += $5; f += $5} END {for (a in c) printf "%6d %5.1f%% %s\n", c[a], 100 * c[a] / f, a; printf "%6d %5.1f%% of all\n", f, 100 * f / t}' "$work/named" | sort -k3
    exit 0
fi
if [ -n "$lines" ]; then
    awk -F'\t' -v s="$lines" 'index($2, s) {print $3 "\t" $4 "\t" $5}' "$work/named" > "$work/in_fn"
    for path in $(cut -f1 "$work/in_fn" | sort -u); do
        awk -F'\t' -v p="$path" '$1 == p {print "0x" $2}' "$work/in_fn" | addr2line -e "$path" > "$work/where"
        awk -F'\t' -v p="$path" '$1 == p {print $3}' "$work/in_fn" | paste - "$work/where"
    done | awk -F'\t' '{n = split($2, q, "/"); c[q[n]] += $1; t += $1} END {for (k in c) printf "%7d %5.1f%%  %s\n", c[k], 100 * c[k] / t, k}' | sort -rn | head -n "$top"
    exit 0
fi
if [ -n "$callers" ]; then
    awk -F'\t' -v s="$callers" 'index($2, s) {print $1}' "$work/named" | sort -u > "$work/in_fn"
    awk 'NR == FNR {want[$1] = 1; next} ($1 in want) {print $2}' "$work/in_fn" "$work/raw" | sort | uniq -c > "$work/tops"
    name_list "$work/tops" "$work/top_named"
    awk -F'\t' '{k = $2 "\t" $3; c[k] += $5; t += $5} END {for (k in c) {split(k, f, "\t"); n = split(f[2], q, "/"); printf "%7d %5.1f%%  %-14s %s\n", c[k], 100 * c[k] / t, q[n], f[1]}}' "$work/top_named" | sort -rn | head -n "$top"
    exit 0
fi
awk -F'\t' -v t="$total" '{k = $2 "\t" $3; c[k] += $5} END {for (k in c) {split(k, f, "\t"); n = split(f[2], q, "/"); printf "%7d %5.1f%%  %-14s %s\n", c[k], 100 * c[k] / t, q[n], f[1]}}' "$work/named" | sort -rn | head -n "$top"
