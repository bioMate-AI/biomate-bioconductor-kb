# Grounded Standards Assistant (prototype)

Evidence-tiered, provenance-honest answering for regulated-domain questions
(GMP / standards / pharmacopoeia). Built in response to two real limits a pharma
engineer hit using AI for GMP work:

1. **Depth** — a generic AI can't answer *why a regulatory threshold is the
   number it is / what work produced it*; it goes generic or confabulates.
2. **Provenance & isolation** — in a shared Copilot, one user's unverified notes
   leak into others' answers, so "professional" answers can be unvalidated opinion.

This prototype grounds what the authoritative record supports, **names where the
record stops**, routes the rest to the real experts (standards committee / PDA /
ISPE), and **never** lets an unverified personal note stand in for fact or leak
across users.

Full write-up, reality-check of the worked example, and production-wiring steps:
**`docs/20261014_GROUNDED_STANDARDS_ASSISTANT.md`**.

## Quick start (no dependencies)

```bash
python3 tests/test_engine.py          # 11 tests (classification, boundary, isolation)
python3 demo.py                       # CLI: 3 scenarios incl. the EN 285 example
python3 mcp_server/http_api.py        # http://127.0.0.1:7788/  (visual demo page)
```

Add the MCP tool to a co-pilot (Claude Desktop / Cursor / company Copilot):

```json
{ "mcpServers": {
    "grounded": { "command": "python3",
                  "args": ["<abs-path>/grounded-prototype/mcp_server/server.py"] } } }
```

## Layout
- `engine/` — pure-Python engine (Py3.9-safe, zero deps): models, corpus,
  classifier, tenant-isolated retrieval, answer assembly.
- `mcp_server/` — stdio MCP server (`server.py`) and a stdlib HTTP API (`http_api.py`).
- `frontend/` — self-contained `demo.html`, plus the drop-in BioMate panel
  (`grounded-assistant-panel.tsx`) + typed client (`grounded-api.ts`).
- `tests/`, `demo.py`.
