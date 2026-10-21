# Skills

Two kinds live here:

- **Vendored from daScript** - every file `scripts/sync_daslang_skills.sh` lists plus the
  whole `daslang/` language skill, copied from `$DASLANG_ROOT/skills` at the commit in
  `DASLANG_SKILLS_PIN`. Never edited here: a wrong claim is fixed in daScript, then re-synced.
  Some vendored files mention daScript-only paths (`bin/Release/...`, `tests/`, CI lanes);
  read those as descriptions of the upstream repository.
- **Written here** - every `internal/*.md` the sync script does not list: this repository's
  own pipeline.

The entry table is `CLAUDE.md`; a skill with no row there is a skill nobody opens.
