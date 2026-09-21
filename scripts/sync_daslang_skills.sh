#!/usr/bin/env bash
# Re-copy the vendored daScript skills from DASLANG_ROOT and record the commit they came
# from in skills/DASLANG_SKILLS_PIN. The list below is the whole vendored set; a skill
# not listed here is either this repository's own (skills/internal/*.md written here) or
# read in place at $DASLANG_ROOT/skills. Vendored files are never edited here: fix them
# upstream and re-run this script.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
src="$DASLANG_ROOT/skills"
dst="$repo_root/skills"
vendored=(
    comment_style_hygiene.md
    dupe_audit.md
    tdd_audit.md
    review_md.md
    writing_tests.md
    das_formatting.md
    das_macros.md
    daslib_modules.md
    dynamic_modules.md
    daspkg.md
    cpp_integration.md
    external_module_debugging.md
    mcp_tools.md
    writing_benchmarks.md
    memory_leak_detection.md
    jobque_debugging.md
    profiler.md
    perf_lint.md
    style_lint.md
    tune.md
    design_philosophy.md
    internal/review_triage.md
    internal/woodpecker.md
    internal/writing_skills.md
    internal/detect_dupe.md
    internal/detect_dupe_reference.md
    internal/find_dupe.md
    internal/clang_bind_build.md
)
for f in "${vendored[@]}"; do
    mkdir -p "$dst/$(dirname "$f")"
    cp "$src/$f" "$dst/$f"
done
rm -rf "$dst/daslang"
cp -r "$src/daslang" "$dst/daslang"
rm -f "$dst/daslang/README.md"
git -C "$DASLANG_ROOT" rev-parse HEAD > "$dst/DASLANG_SKILLS_PIN"
echo "synced ${#vendored[@]} skills + daslang/ from $(cat "$dst/DASLANG_SKILLS_PIN")"
