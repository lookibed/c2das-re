# Babysit (PR review iteration)

The post-open loop: watch CI, triage review comments, fix, reply, resolve, re-request, merge.
PR creation is `skills/internal/make_pr.md`; comment verdicts are `skills/internal/review_triage.md`.

The driver is daScript's:
`$DASLANG_ROOT/bin/daslang $DASLANG_ROOT/utils/internal/pr-babysit/main.das -- --repo <owner>/c2das-re --pr <N> --watch`.
Exit codes: `0` ready to merge, `1` request or API failure, `2` CI red (failing checks
named), `3` a review targets the tip with unresolved threads, `5` nothing actionable within
the timeout. Run it BARE in a background Bash, never piped - the exit code is the verdict.
`--request-review`, `--list-unresolved` and `--resolve <id>` are the other verbs. The hook in
`.claude/settings.json` denies any hand-rolled watcher over the PR's checks.

## 0. Stop rule

The last round is a round that changed nothing: the latest review targets the current tip,
handling it required no code change, and every thread has an accept/reject reply and is
resolved. A round that changed code can never be the last one. "Good enough" is the gate:
known bugs merge with a ledger row, known prose defects merge or ledger. Merge = the stop
rule + CI green on the same tip + no pending human review. Any push invalidates the review:
re-request after every push.

## 1. The loop

1. Tip unreviewed and no unresolved threads -> re-request.
2. Triage every comment per `skills/internal/review_triage.md`.
3. Fixes changed the branch -> run the focused gates (`scripts/preflight.sh --only <gate>`;
   `--only lint --only review-md` on any `.das` or rule-document change), amend,
   `git push --force-with-lease`.
4. Reply to and resolve every thread of the round - rejections included.
5. Pushed a new tip -> re-request now.
6. Repeat until the stop rule holds; only then wait for CI green and merge.

## 2. CI red

Infra or real: a runner shutdown with no `error:` line is a reclaimed runner - a fresh push
supersedes it. Otherwise the driver names the failing check; `gh run view <id> --log-failed`
gives the log. Reproduce with the matching preflight gate, fix, push, back into the loop.
