---
trigger: always_on
description: Consult the graphify knowledge graph at graphify-out/ for codebase and architecture questions while honoring repository boundaries in AGENTS.md.
---

## graphify (Antigravity)

This project has a local code-only knowledge graph at `graphify-out/` (built from `Graphify-Labs/graphify`).

Rules:
- Root `AGENTS.md`, `PROJECT_CONTEXT.md`, and `WORKLOG.md` remain authoritative. Treat the graph as a navigation aid, not proof of runtime/cloud behavior; Dart extraction is regex-based, so verify relevant source files and tests.
- When `graphify-out/graph.json` exists, start codebase or architecture exploration with `query_graph` (MCP, passing `project_path` set to the workspace root) or `graphify query "<question>"` (CLI). Use `shortest_path` / `graphify path "<A>" "<B>"` for relationships and `get_node` / `graphify explain "<concept>"` for focused symbols.
- If `graphify-out/wiki/index.md` exists, use it for broad navigation before raw directory browsing.
- Read `graphify-out/GRAPH_REPORT.md` only for broad architecture review or when `query` / `path` / `explain` do not surface enough context.
- Honor `.graphifyignore`; keep rebuilds local and code-only unless the user explicitly asks for semantic/API extraction or live database introspection.
- After modifying code files, run `graphify update .` to keep the graph current (AST-only, no API cost).
