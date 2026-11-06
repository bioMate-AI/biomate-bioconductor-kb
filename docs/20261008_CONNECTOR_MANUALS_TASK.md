# Task Description — BioMate Connector User Manuals

**Date:** 2026-10-08
**Owner doc (living).**

> **2026-10-09 verification update:** The historical results below used the deprecated Python path and do not certify the published npm/client journey. The actual published npm package was tested today: a real workflow completed, but output discovery and report export failed. See [workflow test gate](20261009_CONNECTOR_WORKFLOW_TEST_GATE.md). Recording remains on hold; the prior env-var-mismatch diagnosis does not apply to the npm server.

**Ask:** write buyer-facing user manuals for BioMate's connectors (the integrations that let external AI surfaces drive BioMate), which don't exist yet at the manual level — only dev-facing READMEs in `connectors/<surface>/` and the general `T9-connecting-data-and-tools` / `I12-connectors-and-skills` chapters.

## 1. Goal

One user manual **per connector surface** — "install BioMate into <surface>, authorize it, and run real bioinformatics from it" — matching the existing instrument-tutorial template (workflow/usage-focused, honest status, bilingual EN + natural Chinese), so a non-developer can self-serve. These complement (don't duplicate) `T9`/`I12`, which stay as the conceptual overview.

## 2. Scope — the 8 surfaces (from `connectors/README.md`, ground truth)

| Surface | Install path | Auth | Status | Manual |
|---|---|---|---|---|
| Claude Code | `npx @biomate/connect claude-code` (MCP stdio) | refresh token | ✓ | NEW |
| Claude Desktop | `npx @biomate/connect claude-desktop` (MCP stdio) | refresh token | ✓ | NEW |
| **Claude Science** (user's term — confirm surface) | TBD — likely Claude Desktop/claude.ai MCP | OAuth/token | ? | NEW |
| Cursor | `npx @biomate/connect cursor` (MCP stdio) | refresh token | ✓ | NEW |
| Codex CLI | `npx @biomate/connect codex` → `~/.codex/config.toml` | refresh token | ✓ | NEW |
| ChatGPT | Custom GPT + OpenAPI Action (no local install) | OAuth 2.1 + PKCE | ✓ | NEW |
| Open Claw / WeChat | `npx @biomate/connect open-claw` | OAuth/token | ✓ | NEW |
| Slack | Add-to-Slack | OAuth | **Pilot** (public ~2 wks post-launch) | NEW (mark pilot) |

Shared across all: the 19-tool MCP (`backend/lib/mcp/tools_manifest.py`), the OAuth service, and the revoke page `biomate.ai/account/connectors`.

## 3. Per-connector manual template

1. **Who this is for / time.** (e.g. "you already use Codex CLI and want to run real pipelines from it.")
2. **§1 What this connector gives you** — BioMate runs real bioinformatics (not code-about-it); the 19 tools; example prompts.
3. **§2 Install** — the exact real steps from `connectors/<surface>/README.md` (verified, not invented): the `npx` command / Custom-GPT setup, where config is written, restart step.
4. **§3 Authorize** — the OAuth/refresh-token flow; where to get the token (`biomate.ai/account/connectors/<surface>`); scopes; how to revoke.
5. **§4 Use it — worked examples** — 3-4 real prompts (ADMET screen, RNA-seq DE, UniProt lookup, CryoSPARC) and what comes back on that surface (progress events / deep links — surface-specific rendering).
6. **§5 Reading results** — the deep link back to the BioMate run panel; where outputs/reports live.
7. **§6 Honest limits** — surface quirks (Codex: no rich progress UI → polls `get_run`; Slack: pilot; ChatGPT: Action rate limits), and anything not yet live.
8. **§7 Troubleshooting** — token expired, server not picked up (restart), tool-not-found.
- **Bilingual:** EN in `docs/user-manual/tutorials/connectors/` + zh mirror in `tutorials/zh/connectors/`. → docx → Drive `tutorial_docs/{en,zh}/connectors/`.

## 4. What I can write now (no input needed)

Draft every manual's **§1–§3, §5–§7** from the connector packages (`connectors/<surface>/README.md`, `INSTALL.md`, `gpt_config.md`, `config-snippet.toml`, `openapi.json`) + the shared MCP/OAuth docs. These contain the real install/auth steps.

## 5. WHAT I NEED FROM YOU

### A. Your real configs (redact secrets — replace the token with `<your-refresh-token>`)
1. **Codex** — your `~/.codex/config.toml` `[mcp_servers.biomate]` block, so I verify the manual's steps match reality.
2. **Claude Science** — your config/screenshots for however you connected BioMate (this tells me which surface "Claude Science" is and its exact setup). **Please confirm: is it Claude Desktop, claude.ai, or another surface?**
3. (Optional) any surface where the documented step differs from what you actually did.

### B. Screenshots (you offered — here's the exact list; redact tokens/emails)
**Shared (once):**
- `biomate.ai/account/connectors` page (connected surfaces + revoke).
- The OAuth consent screen during a connect.

**Per surface you have set up** (you mentioned Codex + Claude Science; others welcome):
- **Codex:** terminal after `npx @biomate/connect codex` (success); a `codex "... Use BioMate"` run showing BioMate's progress summary + deep link.
- **Claude Science / Desktop:** the MCP/tools indicator showing `biomate` connected; a conversation where a prompt triggers a BioMate run (card/progress/link).
- **ChatGPT** (if you have it): the BioMate Custom GPT; a chat with a prompt → BioMate response.
- **Cursor / Claude Code** (if set up): the MCP list showing `biomate`; a prompt → run.
- **Slack / WeChat** (if set up): the app in the client; a mention/prompt → response.

Format: PNG, full-window, redact any token/email/private data. Name them `<surface>-<what>.png` (e.g. `codex-install.png`, `codex-run.png`, `claude-science-tools.png`). Drop them anywhere and tell me the path.

## 6. Division of labor & sequence
1. I draft all 8 manuals' install/auth/usage from the connector packages now (EN + zh).
2. You send configs (A) + screenshots (B) → I correct any step that differs from your real setup, embed the screenshots, and mark true status.
3. Convert → docx → publish to Drive `tutorial_docs/{en,zh}/connectors/`.

## Connection test results (2026-10-08, against dev — prod api/app.biomate.ai are DOWN)

Verified end-to-end with real data (token = fixture-login JWT used directly as the Bearer `BIOMATE_API_KEY`; no OAuth needed for reads):

| Transport / surfaces | Result |
|---|---|
| **Offline** (manifest + sandbox + chatgpt tests) | ✅ 130 tests pass |
| **stdio + Bearer** — Claude Code, Claude Desktop, Cursor, Codex | ✅ FULL: initialize → **19 tools** → real `search_workflow` result |
| **HTTP + OAuth (/mcp)** — Claude Science | ⚠️ handshake + real data work, but exposes only **3 tools**; reads not auth-gated; **OAuth consent flow not round-tripped** (needs a registered client + user consent → blocked on user) |
| **REST Actions** — ChatGPT, Slack, Feishu | ✅ openapi 19 ops; real `search_workflow`/`resolve_accession` results |

**Launch-blocking discrepancies found (these would break a real user's setup):**
1. **Env-var name mismatch** — published snippets set `BIOMATE_API_BASE`; the Python stdio server reads `BIOMATE_API_URL` and **ignores** `BIOMATE_API_BASE`. A copy-pasted config silently fails.
2. **Default hosts are DOWN** — READMEs/snippets point at `api.biomate.ai`/`app.biomate.ai` (both unreachable). Only `dev-public.biomate.ai` works today. Prod must be stood up before public launch.
3. **Tool-count drift** — 19 (this repo + REST openapi) vs 24 (connector repo, adds quota/usage/instrument tools) vs 3 (dev `/mcp` HTTP). Three counts live at once.
4. **Deprecated server still canonical on dev** — `backend/lib/mcp/biomate_mcp_server.py` self-declares DEPRECATED v1.0.0 (points to the connector-repo v2 / `npx @biomate/connect`), yet it's what answers on dev.
5. **Config path/format** — Codex `.toml`, others `.json`; website says Codex `.yaml` (wrong). Auth not enforced on dev read surfaces (public-catalog reads open).

Token mint (reproducible): `POST /api/auth/login` (fixture + `x-e2e-test-token`) → JWT → use as Bearer. No OAuth/galaxyApiKey needed for reads.

## Open questions for you
- **"Claude Science"** — which surface exactly? (determines one manual's setup)
- Which surfaces do you actually want shipped first? (default: Codex + Claude Science, since you have them live, then ChatGPT + Claude Code/Desktop/Cursor, then Slack/WeChat as pilot.)
