# Claude Directory Submission — Blocker Tracker

Submission target: Team/Enterprise org admin → Settings → Directory → Submit connector  
Reference: https://claude.com/docs/connectors/building/submission#submit-your-connector  
Full package: `/Users/kky/biomate-connector/connectors/submissions/claude-directory.md`

## Blockers

| # | Blocker | Status | Owner | Output |
|---|---------|--------|-------|--------|
| 1 | Privacy policy live at `biomate.ai/legal/privacy` | ✅ Live | Claude | https://biomate.ai/legal/privacy.html |
| 2 | Connectors docs live at `biomate.ai/connectors` | ✅ Live | Claude | https://biomate.ai/connectors.html |
| 3 | Logo asset ≥512×512 square PNG | ✅ Live | Claude | https://biomate.ai/images/biomate-logo-512.png |
| 4 | Remote HTTPS MCP endpoint | ⚠️ Partial | Infra | stdio server works on dev; HTTP/REST (`POST /mcp`) not yet deployed — `GET /mcp` hits SPA fallback |
| 5 | Team/Enterprise org + Owner role | ⏳ Pending | User | Upgrade org or confirm existing Team/Enterprise plan |
| 6 | Reviewer test account + credentials | ✅ Done | Claude | `docs/claude-directory-submission/REVIEWER_CREDENTIALS.md` |

## Notes on blocker 4 — MCP endpoint (partial)

The **stdio** MCP server works on dev-public: Claude Code can connect using
`BIOMATE_API_KEY` + `BIOMATE_API_URL=https://dev-public.biomate.ai`.

The **HTTP/REST** transport needed for ChatGPT and REST-based surfaces is NOT
yet deployed. `GET /mcp` on dev-public returns the React SPA (index.html), not
a JSON-RPC endpoint. `POST /mcp` returns 404.

To complete this blocker:
- Run `biomate-connector/mcp/biomate_http_server.py` as a persistent process
- Expose it via nginx at a path that doesn't conflict with the SPA catch-all
  (e.g. proxy `POST /api/mcp/jsonrpc` → uvicorn:8001, or add a new vhost)
- Update the Claude Directory submission URL accordingly

For the initial Directory submission, the stdio path alone may be sufficient
if Anthropic accepts Claude Code as the primary surface.

## Notes on blocker 6 — Reviewer credentials

- Account: `reviewer@biomate.ai` / `BioMateReview2026!` on dev-public.biomate.ai
- API key: `bm_live_zTKrjJi6_wa5QNkt3LeUUhpPGx6zJ8px`
- Full details: `docs/claude-directory-submission/REVIEWER_CREDENTIALS.md`
- Trial expires **2026-07-26** — extend or recreate on prod before submitting

## Submission checklist (from claude-directory.md)

- [ ] Privacy policy page live
- [x] Tool annotations complete (17 tools, all with title + readOnly/destructive hints)
- [ ] Team/Enterprise org + Owner role confirmed
- [ ] Remote HTTPS MCP endpoint published & reachable
- [ ] Documentation URL live (`biomate.ai/connectors`)
- [ ] Logo asset attached (≥512×512)
- [ ] Reviewer test account + credentials prepared
- [ ] Policy attestations (7) checked at submission time
