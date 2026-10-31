# Delivery Project Context

These instructions apply to this repository, including `gps_delivery_app/`.

## Recover Context

Before repository work, read `PROJECT_CONTEXT.md` and the latest entry in
`WORKLOG.md`, then inspect `git status --short`. Use the installed
`delivery-codebase-memory` skill when available. These files are sufficient to
resume even on a machine where that skill is not installed.

Treat the latest user request and current source as authoritative. The worklog
records evidence and unfinished work; it is not authorization to publish, push,
or modify a cloud database. For a brief continuation request, follow the current
handoff and existing commercialization plan without restarting the audit.

Read `gps_delivery_app/P0_SYNC_MATRIX.md` when changing authentication, ownership,
or cloud synchronization. Read `gps_delivery_app/COMMERCIALIZATION_PLAN.md` when
choosing the next implementation batch. A planned item is not a completed feature.

## Maintain Context

After meaningful code/configuration changes or a change of direction, update the
current handoff in `WORKLOG.md` with the outcome, relevant files, checks actually
run, remaining limits, and next concrete step. Keep it concise. Update
`PROJECT_CONTEXT.md` only when architecture or durable user decisions change.
Record narrow checks as narrow checks; do not carry old test results forward as
new production verification.

Never put passwords, tokens, private keys, full database connection strings,
customer data, or credential-bearing command output in these documents or skills.
Record configuration locations and variable names instead.

## Project Boundaries

- Preserve the existing staged, unstaged, and untracked work. Much of the cloud
  implementation is still untracked; the latest commit alone is not the app.
- Keep Admin login separate from the consumer interface. Keep provider secrets
  and database credentials in the backend/Admin configuration.
- Do not seed demo users, orders, balances, reviews, or sales into real data.
- Cloud and legacy local workflows still coexist. Never claim all screens use
  cloud or infer cloud ownership/roles from SQLite accounts.
- Keep user-visible labels free of route names and backend configuration details.
- Explain results to the user in concise Vietnamese.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

When the user types `$graphify` (or `/graphify`), use the installed graphify skill.

Repository instructions above remain authoritative. The graph is a navigation aid,
not evidence of correct behavior, authorization, deployment or completed roadmap work.
The initial index is code-only and local; do not enable semantic/API extraction or
live database introspection unless requested. Honor `.graphifyignore` on rebuilds.
Dart extraction in Graphify 0.9.99 is regex-based; verify relevant source and tests.
If `graphify` is unavailable in an already-open Windows session, invoke
`& "$env:USERPROFILE/.local/bin/graphify.exe"` in PowerShell.

Rules:
- When graphify-out/graph.json exists, start codebase exploration with `graphify query "<question>"` (CLI) or `query_graph` (MCP, passing `project_path` set to this repository root). Follow with source reads/search when the graph is incomplete, stale or ambiguous. Use `graphify path "<A>" "<B>"` / `shortest_path` for relationships and `graphify explain "<concept>"` / `get_node` for focused concepts.
- Dirty graphify-out/ files are expected after hooks or incremental updates; dirty graph files are not a reason to skip graphify. Only skip graphify if the task is about stale or incorrect graph output, or the user explicitly says not to use it.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
- Keep generated graphify-out/ files local and ignored; commit integration/configuration only when the user requests a commit.
