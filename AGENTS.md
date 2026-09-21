# Agents

`CLAUDE.md` is the entrypoint for every agent: it routes to the documents, the skills, the
gates and the review machinery. Codex sessions take their MCP wiring from
`.codex/config.toml` (copy `.codex/config.toml.example`); Claude Code sessions from
`.mcp.json` and the LSP plugin under `.claude/skills/daslang-lsp`.

# Workspace hygiene

- Never use `docs/`, `probes/`, `suites/` or a deployment directory as scratch space. Diagnostic
  logs go under `logs/` (gitignored), converted output under `out/` (gitignored), suite fetches
  under `suites/*/fetch/`.
- Clean up files created for probes, benchmarks and abandoned launches when the work is done.
  Keep active process logs, user data and one useful rollback artifact unless asked otherwise.
- `git status` is clean of untracked files when a session ends: commit, ignore with a reason,
  or delete.
