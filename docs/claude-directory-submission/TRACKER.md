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
| 4 | Remote HTTPS MCP endpoint (`https://app.biomate.ai/mcp`) | ⏳ Pending | Infra | Deploy `mcp/biomate_http_server.py` behind SSL on app.biomate.ai |
| 5 | Team/Enterprise org + Owner role | ⏳ Pending | User | Upgrade org or confirm existing Team/Enterprise plan |
| 6 | Reviewer test account + credentials | ⏳ Pending | User | Prepare a scoped API key + test user for Anthropic reviewer |

## Notes on blocker 4 — MCP endpoint

The remote HTTP MCP server code exists at `biomate-connector/mcp/biomate_http_server.py`.  
What's needed:
- A public hostname (`app.biomate.ai`) with valid SSL
- The server running and reachable at `https://app.biomate.ai/mcp`
- OAuth 2.1 authorization server running (code in `oauth_server/`)

Current state: `app.biomate.ai` returns connection refused. Either point the domain at an EC2 instance running the HTTP MCP server, or host on the existing BioMate EC2 behind a new nginx vhost.

## Submission checklist (from claude-directory.md)

- [ ] Privacy policy page live
- [x] Tool annotations complete (17 tools, all with title + readOnly/destructive hints)
- [ ] Team/Enterprise org + Owner role confirmed
- [ ] Remote HTTPS MCP endpoint published & reachable
- [ ] Documentation URL live (`biomate.ai/connectors`)
- [ ] Logo asset attached (≥512×512)
- [ ] Reviewer test account + credentials prepared
- [ ] Policy attestations (7) checked at submission time
