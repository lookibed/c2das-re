# The multi-agent review round

Read this before running a deep review of a branch or diff - the pre-PR review round of
`skills/internal/make_pr.md`, or a standalone "review this" request. The shape: **ground ->
derive dimensions -> surface -> prove -> report**. Two principles carry it: review dimensions
are derived from THIS change's risks, never from generic categories; and every finding is a
hypothesis until an adversarial prover fails to disprove it.

## Diff range

`git merge-base origin/main HEAD`..`HEAD`, plus the working tree when reviewing uncommitted
work. Always the whole arc.

## Phase 0 - grounding (one agent)

When the round is `make_pr`'s surfacing phase, the comment harvest has LANDED before Phase 0
starts. Spawn ONE `targeted-reviewer` over the full diff range. It produces a map, not
findings: **intent**, **integration surface** (every boundary the change touches: callers,
data formats - the C-IR above all - caches, module edges, ownership handoffs), **hotspots**
(with WHY and file:line), **blind spots** (what the diff does not show: generated output,
sidecars, suite expectations, the other dumper), and **the REVIEW.md binding set**
(`$DASLANG_ROOT/utils/internal/review-md/main.das -- --base origin/main --list-only`).
Grounding is context, not authority.

## Phase 1 - derive dimensions (orchestrator, no agent)

From the grounding, 3-6 surfacing dimensions, each naming a specific risk this change
introduces, in the change's own vocabulary. A name that would fit a different change is too
generic; a name that states the exact defect to find has already anchored the surfacer.

## Phase 2 - surfacing (parallel agents)

Launch the woodpecker first in a background Bash (`skills/internal/woodpecker.md`). Then, in
ONE message: one `targeted-reviewer` per dimension (prompt = the dimension plus its hotspot
notes), one general surfacer, one `review-md-auditor` per discovered checklist, one
`tdd-auditor` over the whole diff (`skills/tdd_audit.md`), one `dupe-auditor` over the whole
diff (`skills/dupe_audit.md`), and the `style-hygiene-auditor` (non-blocking, skips the
prover). Findings come back as `file:line`, the concern, the evidence, a severity (`bug` /
`concern` / `suggestion` / `nitpick`) and whether it should block.

## Phase 3 - proving (one agent)

Dedupe same-location same-concern findings, then spawn ONE prover (a `targeted-reviewer`
assigned the prove phase). Gates, in order: a falsification attempt named and run; every
factual assertion traced to the prover's own fresh read; the inference chain verified; a
regression claim needs the pre-change baseline verified. Post-gates: scope (unchanged code
counts only when this change made it wrong), style (no codebase convention behind it =
reject), severity recalibration. Auditor verdicts ride through as their own sections:
UNPROVEN as evidence requests, SELF-REVIEW as checklist defects, UNTESTED / RETUNED /
WEAKENED as coverage defects, DUPLICATE through the fresh-read gate.

## Phase 4 - report, then fix

The report, in the conversation: confirmed findings ranked most-severe first with the gate
trail, then the evidence requests, then rejected counts by gate. Zero confirmed findings is a
reportable result. Findings are discussed before fixing; accepted fixes land as one batch per
round; a lint-able pattern is named as a lint or `REVIEW.das` candidate. Checklist findings
go through the damper in `skills/review_md.md`: two dragon passes per document per round.

## Mechanics

Every agent is read-only and report-only. Grounding, surfacers and the prover are
`targeted-reviewer` instances; when the session's registry lacks the agent, fall back to
general-purpose with an explicit opus pin. Spawn independent agents in a single message.
