# c2das-re Code Review Checklist

**Read `REVIEW_COMMON.md` (repo root) first - its contract binds this checklist.** Architecture
doc: `ARCHITECTURE.md` (repo root). Planned work: `docs/implementation_order.md`.

**A diff whose code disagrees with a document under `docs/` resolves the disagreement in the
same change: a probe that settles it, then either the code changes or the finding is reported
to the documents' authoring repository - never a silent divergence.**

**A das-fact a diff relies on - a layout, a promotion rule, a `goto` shape, a copy semantics -
has a probe under `probes/` that fails when the fact stops holding, added in the same
change.**

**A diff that lowers a suite's pass count, or skips a suite test, adds the ledger line for it
under `suites/` - the feature, the reason, the phase that unblocks it - in the same change.**

**Never commit or hand-edit converted output - regenerate it, and put per-project judgment in
the sidecar.** Converted `.das` lives under `out/` or a suite work folder; the tree records
golden output as hashes.

**A diff that adds C code under GPL-2 keeps it under `doom/`; C code anywhere else ships
under a permissive license.**

**A diff that changes what the toolchain must provide - a daScript module, a configure flag,
the libclang or ast-grep version - updates `VERSIONS.md` and `scripts/verify_daslang.sh` in the
same change.**

**Never edit a vendored skill under `skills/` - fix it in daScript and run
`scripts/sync_daslang_skills.sh`.** A skill written here lives under `skills/internal/`.
