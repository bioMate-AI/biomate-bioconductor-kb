# Claude Directory Submission Prep — Session Notes
**Date:** 2026-07-11

## What was done

Three of the six Claude Directory submission blockers are now resolved and live on `biomate.ai`.

### Blocker 1 — Privacy policy
- **File:** `reference/claude_design/webpage_design_v2/legal/privacy.html`
- **Live at:** https://biomate.ai/legal/privacy.html
- Covers: who we are, 7 data categories, usage, sub-processors (AWS/LLM providers/Lago), security, retention, rights, contact
- Source: `biomate-connector/connectors/legal/privacy.md` (draft — legal review still needed before final submission)

### Blocker 2 — Connectors documentation
- **File:** `reference/claude_design/webpage_design_v2/connectors.html`
- **Live at:** https://biomate.ai/connectors.html
- Content: overview, 5 surfaces (Claude Code, Claude Desktop, ChatGPT, Slack, Feishu), 19 tools table, per-surface install guides, auth/scopes, manual config, FAQ
- Sidebar nav, sticky header, code blocks with syntax highlighting

### Blocker 3 — Logo ≥512×512
- **File:** `reference/claude_design/webpage_design_v2/images/biomate-logo-512.png`
- **Live at:** https://biomate.ai/images/biomate-logo-512.png
- 512×512 square PNG, source logo letterboxed with transparent background

### Blocker 4 — Remote HTTPS MCP endpoint (PENDING — infra)
- Code exists at `biomate-connector/mcp/biomate_http_server.py`
- `app.biomate.ai` currently returns connection refused
- Needs: SSL-terminated reverse proxy on `app.biomate.ai`, Python HTTP MCP server running behind it, OAuth 2.1 server from `oauth_server/`

### Blocker 5 — Team/Enterprise org (PENDING — user action)
- Submission requires submitter to be Owner of a Anthropic Team or Enterprise org
- Submission path: Team/Enterprise admin → Settings → Directory → Submit connector

### Blocker 6 — Reviewer test account (PENDING — user action)
- Anthropic reviewers need a scoped API key + test user to verify the connector works
- Generate at https://biomate.ai/account/api-keys and document in the submission form

## Connector blog post (also updated this session)
- `webpage_design_v2/blog-connectors.html`
- Hero figure replaced with inline SVG: 5 clients (Claude Code, Claude Desktop, ChatGPT, Slack, Feishu), BioMate hub with 19 tools, 4 capability pills
- Body architecture SVG: removed Codex CLI, fixed staging URL → `app.biomate.ai`
- Roadmap section removed
- Subtext legibility fixed (font-size and color improved)

## Files changed this session
- `reference/claude_design/webpage_design_v2/connectors.html` (NEW)
- `reference/claude_design/webpage_design_v2/legal/privacy.html` (NEW)
- `reference/claude_design/webpage_design_v2/images/biomate-logo-512.png` (NEW)
- `reference/claude_design/webpage_design_v2/blog-connectors.html` (modified)
- `docs/claude-directory-submission/TRACKER.md` (NEW)

## Commit
`2546de487` — feat: add connectors docs page, privacy policy, and 512px logo for Claude Directory submission

## Next steps (in priority order)
1. **Infra** — deploy `mcp/biomate_http_server.py` behind SSL on `app.biomate.ai` (blocker 4)
2. **User** — confirm Team/Enterprise org ownership (blocker 5)
3. **User** — prepare reviewer test account + scoped API key (blocker 6)
4. Once all 6 blockers resolved: open submission at Claude admin panel (Settings → Directory → Submit connector)
5. **Legal review** of `connectors/legal/privacy.md` before final submission — currently marked DRAFT
