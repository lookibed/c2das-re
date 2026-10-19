#!/usr/bin/env bash
# Minimize a csmith seed that does not pass: `suites/csmith/reduce.sh <seed> [reducer]`.
# The seed is judged afresh (`run.das --one`), and its program is reduced while every candidate
# keeps the seed's verdict: the native build is free of the undefined behaviour gcc's warnings and
# sanitizers see, the pinned clang's build prints what gcc's does (so no candidate leans on an
# evaluation order), and `run.das --check` gives the same status and signature (the converter's
# first error line with names blanked, the exit code, or differing output). The result is
# suites/csmith/work/<seed>/min.c. `reducer` is a cvise or creduce command; the default is the
# cvise `fetch.sh --cvise` builds.
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$here/../.." && pwd)"
cd "$repo_root"
. scripts/env.sh
seed="${1:?usage: suites/csmith/reduce.sh <seed> [reducer]}"
dir="$repo_root/suites/csmith/work/$seed"
if [ -n "${2:-}" ]; then
    reducer=("$2")
else
    "$here/fetch.sh" --cvise
    reducer=("$here/fetch/cvise-venv/bin/python" "$here/fetch/cvise/build/cvise-cli.py")
fi
"$repo_root/scripts/run_suite.sh" csmith --one "$seed"
want=$(cut -f1,2 "$dir/$seed.verdict")
case "$want" in
    pass*|native*|timeout*) echo "reduce: seed $seed is $(cut -f1 "$dir/$seed.verdict"); nothing to minimize" >&2; exit 1 ;;
esac
echo "reduce: seed $seed keeps \`$want\`"
cp "$dir/$seed.c" "$dir/min.c"
printf '%s\n' "$want" > "$dir/min.want"
cat > "$dir/interesting.sh" <<EOF
#!/usr/bin/env bash
# The interestingness test of seed $seed (written by suites/csmith/reduce.sh): run by the reducer
# in a folder holding a candidate min.c.
set -u
gcc -O1 -Wall -Wextra -funsigned-char -c -o /dev/null min.c 2> warnings.txt || exit 1
grep -qE 'uninitiali[sz]ed|incompatible|without a cast|control reaches end|defaults to|no return statement|implicit declaration|array bounds|may be undefined' warnings.txt && exit 1
gcc -O0 -fwrapv -funsigned-char -w -fsanitize=address,undefined -fno-sanitize-recover=all -o sanitized min.c || exit 1
timeout 10 ./sanitized > sanitized.out 2>&1 || exit 1
gcc -O0 -fwrapv -funsigned-char -w -o by_gcc min.c || exit 1
"$PATH_TO_LIBCLANG/bin/clang" -O0 -fwrapv -funsigned-char -w -o by_clang min.c || exit 1
timeout 10 ./by_gcc > by_gcc.out 2>&1 || exit 1
timeout 10 ./by_clang > by_clang.out 2>&1 || exit 1
cmp -s by_gcc.out by_clang.out || exit 1
"$repo_root/scripts/run_suite.sh" csmith --check "\$PWD/min.c" > /dev/null 2>&1 || exit 1
[ "\$(cut -f1,2 min.verdict)" = "\$(cat "$dir/min.want")" ]
EOF
chmod +x "$dir/interesting.sh"
(cd "$dir" && ./interesting.sh) || { echo "reduce: the unreduced program fails its own interestingness test (see $dir)" >&2; exit 1; }
(cd "$dir" && "${reducer[@]}" --n "$(nproc)" ./interesting.sh min.c)
echo "reduce: $dir/min.c"
