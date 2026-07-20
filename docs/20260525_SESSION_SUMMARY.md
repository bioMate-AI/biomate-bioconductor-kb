# Connector launch — full session summary (through 2026-05-25)

**Branch:** `connectors-v2-launch`
**Worktree:** `/home/yzhang/biomate_worktrees/connectors_v2`
**8 commits on top of the prior connector-architecture work** (see git log below)
**Status:** ready for staging deploy; public repo push (Task #9) pending user OK

---

## Where everything lives

| Type | Location | What it is |
|---|---|---|
| OAuth server (Python) | `backend/lib/galaxy/connectors/oauth/` | 7 modules: scopes, pkce, tokens, store, server, router, __init__ |
| Installer CLI (TS/npm) | `connectors/installer/` | `@biomate/connect` — PKCE flow + atomic config writers |
| Per-surface adapters | `connectors/{claude-code,claude-desktop,cursor,codex,chatgpt,open-claw,wechat,slack}/` | READMEs + config snippets |
| Marketing assets | `connectors/marketing/{videos,landing,blog,social}/` | Drafts + storyboards |
| Directory submissions | `connectors/submissions/` | 5 pre-filled metadata files |
| Skill bundle | `skills/biomate/` | Catalog + render templates |
| MCP server + manifest | `backend/lib/mcp/` | Single source of truth for 14 tools |
| Unit/integration tests | `backend/tests/connectors/`, `connectors/installer/src/__tests__/` | 50 passing + 2 xfail |
| Architecture | `docs/20260513_CONNECTOR_ARCHITECTURE_V2.md` | Why 14 tools, why 6 surfaces |
| Sandbox results | `docs/20260513_CONNECTOR_SANDBOX_RESULTS.md` | 35-case offline SDK validation |
| Test plan | `connectors/TEST_PLAN.md` | 5-layer test strategy, 14 sections, 480 lines |
| Per-suite test docs | `connectors/test-docs/` | 8 docs, one per test suite |
| Handoff (older) | `docs/20260522_CONNECTOR_TESTS_AND_HANDOFF.md` | Pre-audit snapshot |
| Internal test plan | `docs/20260525_INTERNAL_TEST_PLAN.md` | 8-phase pre-launch sandbox playbook |
| Phase 0 results | `docs/20260525_PHASE0_RESULTS.md` | 10/10 PASS |
| **This doc** | `docs/20260525_SESSION_SUMMARY.md` | Single-page session index |

## Commits added in this session (newest first)

```
13706eb49 test+docs(connectors): Phase 0 local smoke PASS — 10/10
c72c7a1c9 docs(connectors): apply P0 audit fixes
36c9e457b fix(connectors): two audit findings — lazy OAuth store init + handled rejection
eab15a5eb test+docs(connectors): L2/L7 test suites + per-suite documentation
36ca85735 docs(connectors): comprehensive test plan for handoff
aba57ab05 feat(connectors): per-surface adapter packages, marketing, submissions
a4727b6fc feat(connectors): @biomate/connect one-line installer CLI
dd97ef4ce feat(connectors): OAuth 2.1 + PKCE authorization server
```

Plus 4 commits from the prior architecture session (`4f2002fd2..a22f6eeab`).

## Test pass rates (all green at last run)

| Suite | Layer | Cases | Status |
|---|---|---|---|
| OAuth core | L1 unit | 7 | ✓ 7/7 |
| OAuth router HTTP | L2 integration | 15 | ✓ 15/15 |
| OAuth security | L2/L7 | 10 | ✓ 8/8 + 2 xfail (known issues) |
| Installer PKCE | L1 unit | 4 | ✓ 4/4 |
| Installer config writers | L1 unit | 4 | ✓ 4/4 |
| Installer end-to-end flow | L2 integration | 12 | ✓ 12/12 |
| Tools manifest drift | L2/L3 | (prior) | ✓ green |
| Sandbox SDK validation | L3 | 35 | ✓ 35/35 |
| Live LLM tool routing | L4 | 4 (+10 specified) | ✓ 4/4 (Anthropic; OpenAI skipped) |
| **Phase 0 protocol smoke** | E2E vs live server | 6 | ✓ 6/6 |
| **Phase 0 installer smoke** | E2E vs live server | 4 | ✓ 4/4 |
| **TOTAL** | | **101** | **97 pass + 4 pre-existing pass + 2 xfail** |

## Audits run, findings applied

### Product design review (2026-05-21 → 2026-05-22)

P0 fixes shipped:
- ChatGPT README OAuth section corrected (PKCE public client, no Client Secret)
- Slack status → "Pilot" everywhere (was inconsistently "Live ✓")
- `poll_run` references → `get_run` in codex/README.md + demo script (manifest only has get_run)
- S3 demo paths normalized to `s3://biomate-demo/` across all assets (was mix of `s3://example/` + `s3://lab/`)
- Slack subcommand count fixed (three → four)
- Montage voiceover script: "npx @biomate/connect" (was "npx at-biomate-slash-connect")

P1/P2 deferred to launch-week polish pass.

### Viz/report convenience audit (2026-05-21 → 2026-05-22)

P0 findings — **all require backend code changes that did not happen this session**:
1. `_normalize_sse_event` in `biomate_mcp_server.py` has no `report_ready` branch
2. Slack `files.upload_v2` integration unwritten (README promises PDF attachment that doesn't exist)
3. Open Claw drops `thumbnail_png_b64` despite WeChat supporting inline images
4. Codex CLI gets zero image fidelity (no ASCII fallback rendered server-side)

These are tracked as launch-blockers in `connectors/TEST_PLAN.md §13` and `docs/20260525_INTERNAL_TEST_PLAN.md` Phase 8.

## Bugs fixed in this session

| # | Bug | Fix | Severity |
|---|---|---|---|
| 1 | `router.py` module-level `OAuthStore()` crashed on import without `BIOMATE_OAUTH_DB` writable | Lazy init via `get_server()` + `set_server()` hook | SEV-2 (broke import for anyone) |
| 2 | Vitest reported 2 unhandled rejections from installer's error-path tests | Attach noop `.catch(() => undefined)` to codePromise to mark handled | SEV-3 (cosmetic, no behavior impact) |
| 3 | Slack README claimed 3 slash subcommands but listed 4 | Doc fix | SEV-3 |
| 4 | ChatGPT install README contradicted INSTALL.md on PKCE vs Client Secret | Doc fix to match INSTALL.md | SEV-2 (would fail ChatGPT review) |
| 5 | `poll_run` referenced in 2 places but missing from manifest | Renamed refs to `get_run` | SEV-2 (drift CI would catch on next regen) |

## Open items (in execution order for the next person)

### Pre-GA backend (~1 week of work)

1. Add `report_ready` event branch to `_normalize_sse_event` in `biomate_mcp_server.py`. Emits `{kind:"report_ready", summary_md, view_url, delta:{pdf_url, docx_url}}`. **Unblocks Slack file upload, ChatGPT PDF link, WeChat deep link.**
2. Implement Slack `files.upload_v2` bridge — `connectors/slack/bridge.py` calling Slack's file-upload flow on `report_ready` events.
3. Enable `thumbnail_png_b64` forwarding in the Open Claw bridge for `qc_gate` and `finding` events.
4. Add server-side ASCII/Unicode-block rendering for volcano/FSC/ROC plots; include in `summary_md` when client advertises `images: false`.
5. Flip the 2 xfail security tests by implementing:
   - Rate limiting on `/oauth/token` (slowapi middleware)
   - Refresh-token-family revocation (add `family_id` column, revoke whole family on replay)

### Pre-GA test work (~1 day)

6. Write the 10 additional live-API cases per `connectors/test-docs/live_api.md`
7. Write the 3 manifest-drift cases per `connectors/test-docs/manifest_drift.md`
8. Execute Phases 1–6 from `docs/20260525_INTERNAL_TEST_PLAN.md`

### Public repo (Task #9 — pending user OK)

9. Create `bioMate-AI/biomate-connectors` (public). Subtree-split the public-facing directories so the rest of the BioMate codebase doesn't leak.

### Launch week (per `connectors/submissions/README.md`)

10. Mon: Anthropic MCP servers PR + Cursor MCP directory
11. Tue: Anthropic Skills gallery + OpenAI GPT store
12. Wed: WeChat 公众号 + 知乎
13. Thu: HN Show HN + X thread + LinkedIn
14. Fri: Slack (deferred until pilot wraps)

## How to verify on a fresh machine

```bash
# Clone the worktree (assumes branch is pushed)
git fetch origin connectors-v2-launch
git worktree add /tmp/biomate-connectors-test origin/connectors-v2-launch
cd /tmp/biomate-connectors-test

# Python suites (no API keys needed)
BIOMATE_OAUTH_SIGNING_KEY=$(python -c "import secrets,base64;print(base64.urlsafe_b64encode(secrets.token_bytes(64)).decode())") \
  BIOMATE_OAUTH_DB=/tmp/test.db \
  PYTHONPATH=backend/lib \
  python -m pytest backend/tests/connectors/ -v
# expect: 30 passed, 2 xfailed

# TypeScript suites
cd connectors/installer && npm install && ./node_modules/.bin/vitest run
# expect: 20 passed

# Phase 0 smoke (real network socket)
# See docs/20260525_PHASE0_RESULTS.md for the test scripts in /tmp/
```

## Known constraints

- **prod biomate.ai DNS not reachable** from this machine — staging deploy + DNS verification needed before Phase 1 can run against staging.biomate.ai
- **No API keys in current env** — Phases 1 + 3 + Live API tests need keys configured separately
- **No production OAuth signing key rotation** — `BIOMATE_OAUTH_SIGNING_KEY` rotation procedure is documented but not yet tested in prod
- **Slack pilot ongoing** — 3 lab beta in progress; public Slack store submission deferred to ~2 weeks post-launch

## Glossary

| Term | Meaning |
|---|---|
| Surface | A host application that connects to BioMate (Claude Code, Cursor, ChatGPT, etc.) |
| Tool surface | The 14-tool MCP API exposed to LLMs |
| L1–L5 | Test layers: unit / integration / sandbox-SDK / live-LLM / E2E-real |
| Manifest | Single source of truth for tool schemas (`backend/lib/mcp/tools_manifest.py`) |
| Drift test | Fails if downstream adapters disagree with the manifest |
| PKCE | Proof Key for Code Exchange (RFC 7636) — OAuth without shared client secret |
| Token family | Refresh-token lineage; reuse detection should revoke the whole family |
| xfail | pytest "expected failure" — tracked known issue, doesn't break CI |
| Open Claw | BioMate's hosted WeChat bridge |

---

**End of session summary.** Next person: read `docs/20260525_INTERNAL_TEST_PLAN.md` Phase 0 to verify the work compiles on your machine, then proceed to Phase 1.
