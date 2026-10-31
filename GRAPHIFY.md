# Graphify For Antigravity & Codex

Installed from `https://github.com/Graphify-Labs/graphify` (`0.9.99`, branch `v8`) with SQL and MCP extras:

```powershell
python -m uv tool install --force "graphifyy[sql,mcp] @ git+https://github.com/Graphify-Labs/graphify.git"
python -m uv tool update-shell
```

## Installed Components

- **Executables**: `%USERPROFILE%\.local\bin\graphify.exe` and `%USERPROFILE%\.local\bin\graphify-mcp.exe` (isolated tool venv under `%APPDATA%\uv\tools\graphifyy`).
- **Antigravity (Global)**:
  - Skill: `%USERPROFILE%\.gemini\config\skills\graphify\SKILL.md` and `references/` (Windows PowerShell bundle).
  - MCP Server: `%USERPROFILE%\.gemini\config\mcp_config.json` (`graphify` stdio server exposing `query_graph`, `get_node`, `get_neighbors`, `get_community`, `god_nodes`, `graph_stats`, `shortest_path`, `list_prs`, `get_pr_impact`, `triage_prs`). Reload/restart the Antigravity MCP connection if a session was already open before installation.
- **Antigravity (Project Workspace)**:
  - Skill: `.agents/skills/graphify/SKILL.md` and `references/` (enables `/graphify` in chat without deprecated `.agents/workflows/`).
  - Always-on rule: `.agents/rules/graphify.md` (aligned with root `AGENTS.md`).
- **Codex (Project Workspace)**:
  - Skill: `.codex/skills/graphify/SKILL.md` and `references/`, plus `AGENTS.md` (`$graphify`).

If an already-open terminal session has not refreshed `PATH`, invoke `& "$env:USERPROFILE\.local\bin\graphify.exe"` directly.

## Local Workflow

From the repository root:

```powershell
graphify extract . --code-only --max-workers 2
graphify cluster-only . --no-label
graphify explain "CloudAccountSession"
graphify query "CloudOrdersRepository" --budget 1500
graphify update .
```

Use `--force` on `graphify extract` only intentionally when replacing an existing graph. In Antigravity MCP calls, pass `project_path` set to this repository root (`c:\baiTap_LTDiDongDaNenTang\DoAn_PhatTrienUngDungDiDongDaNenTang`).

`graphify-out/graph.html` is the interactive map; `GRAPH_REPORT.md` and `graph.json` are generated beside it. Outputs/caches are ignored by Git, and `.graphifyignore` excludes credentials, runtime databases, dependencies, build artifacts, `.agents/`, and `.codex/`.

## Limits

The graph is local and code-only by default: no semantic LLM API calls, document analysis, live database introspection, uploads, or deployment. SQL is parsed from repository files via `tree-sitter-sql`. Dart extraction in `0.9.99` remains regex-based (not a Dart analyzer or tree-sitter grammar), and 16 scanned files currently yield no symbols. Verify findings against current source and focused tests, and run `graphify update .` after code changes.
