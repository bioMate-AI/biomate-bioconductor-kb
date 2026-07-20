# Connector tests + handoff documentation

**Date:** 2026-05-22
**Branch:** `connectors-v2-launch` (worktree: `/home/yzhang/biomate_worktrees/connectors_v2`)
**Author:** Claude (handoff session)

## Why this document exists

The connector launch work spans 4 commits, ~5,000 lines of code, 8 surfaces,
3 test layers, and 5 marketing artifacts. Anyone picking this up needs a
single page that says "what was built, where it is, what's tested, what's
left, how to run it" — that's this doc.

## What's on the branch

### Code (committed)

| Module | Path | LOC | Tests |
|---|---|---|---|
| OAuth 2.1 + PKCE server | `backend/lib/galaxy/connectors/oauth/` | ~600 | ✓ |
| Client seed script | `backend/scripts/seed_oauth_clients.py` | 60 | n/a |
| `@biomate/connect` installer | `connectors/installer/` | ~500 | ✓ |
| MCP tools manifest | `backend/lib/mcp/tools_manifest.py` | (prior) | ✓ |
| ChatGPT OpenAPI + GPT config | `connectors/chatgpt/` | (prior) | sandbox |
| Claude Skill bundle | `skills/biomate/` | (prior) | sandbox |
| Per-surface READMEs (8) | `connectors/{claude-code,claude-desktop,cursor,codex,chatgpt,open-claw,wechat,slack}/` | ~1,200 docs | n/a |

### Tests (committed in this session)

| File | Cases | Status |
|---|---|---|
| `backend/tests/connectors/test_oauth_server.py` | 7 | ✓ 7/7 |
| `backend/tests/connectors/test_oauth_router.py` | 15 | ✓ 15/15 |
| `backend/tests/connectors/test_oauth_security.py` | 10 | ✓ 8/8 + 2 xfail (known issues) |
| `connectors/installer/src/__tests__/pkce.test.ts` | 4 | ✓ 4/4 |
| `connectors/installer/src/__tests__/configWriters.test.ts` | 4 | ✓ 4/4 |
| `connectors/installer/src/__tests__/flow.test.ts` | 12 | ✓ 12/12 |
| `backend/tests/test_tools_manifest.py` | (prior) | ✓ |
| `backend/tests/test_connector_sandbox.py` | 35 | ✓ |
| `backend/tests/test_connector_live.py` | 4 (+ 10 specified) | ✓ 4/4 |

**Total automated: 50 new cases + 2 xfail + ~42 pre-existing = ~92 passing.**

### Documentation (committed)

| Doc | Path | Purpose |
|---|---|---|
| Architecture v2 | `docs/20260513_CONNECTOR_ARCHITECTURE_V2.md` | Why 14 tools, why 6 surfaces, why streaming |
| Sandbox results | `docs/20260513_CONNECTOR_SANDBOX_RESULTS.md` | 35-case offline validation report |
| Test plan | `connectors/TEST_PLAN.md` | Full 5-layer test strategy, 14 sections, 480 lines |
| Per-suite test docs | `connectors/test-docs/{README,oauth_unit,oauth_router,oauth_security,installer_unit,installer_flow,manifest_drift,live_api}.md` | One page per test suite |
| Per-surface READMEs | `connectors/*/README.md` | Install + demo prompts + tools |
| Marketing assets | `connectors/marketing/{videos,landing,blog,social}/` | Launch materials |
| Submission packages | `connectors/submissions/*.md` | Pre-filled directory submissions |
| This handoff doc | `docs/20260522_CONNECTOR_TESTS_AND_HANDOFF.md` | Single-page session summary |

## How to verify everything works

### One command for Python tests

```bash
cd /home/yzhang/biomate_worktrees/connectors_v2
BIOMATE_OAUTH_SIGNING_KEY=$(python -c "import secrets,base64;print(base64.urlsafe_b64encode(secrets.token_bytes(64)).decode())") \
  BIOMATE_OAUTH_DB=/tmp/biomate_oauth_test.db \
  PYTHONPATH=backend/lib \
  python -m pytest backend/tests/connectors/ -v
```

Expect: **30 passed, 2 xfailed** (the xfails are known issues, see `test-docs/oauth_security.md`).

### One command for TS tests

```bash
cd /home/yzhang/biomate_worktrees/connectors_v2/connectors/installer
./node_modules/.bin/vitest run
```

Expect: **20 passed** across 3 files (pkce, configWriters, flow).

### One command for live LLM routing

Requires API keys.

```bash
cd /home/yzhang/biomate_worktrees/connectors_v2
ANTHROPIC_API_KEY=sk-ant-... \
  PYTHONPATH=backend/lib \
  python -m pytest backend/tests/test_connector_live.py -v
```

Expect: **4 passed** (Anthropic side; OpenAI skipped without key). Cost: ~$0.04.

## What's left for the next person

In execution order:

### 1. Pre-GA test work (~1 day)

- [ ] Write the 10 additional live-API cases per `test-docs/live_api.md`
- [ ] Write the 3 manifest-↔-adapter drift cases per `test-docs/manifest_drift.md`
- [ ] Flip the 2 xfail security tests (after addressing the underlying gaps; see §3)

### 2. Manual L5 E2E walkthrough (~3 hours)

Per `TEST_PLAN.md §6`. Walk through at least 6.1 Claude Code (the gold path), recording any issues found. Defer 6.7 Slack — that's still in pilot.

### 3. Pre-GA security gaps (~3 days)

`test-docs/oauth_security.md` lists 2 SEV-2 known issues blocking GA:

- [ ] Rate limiting on `/oauth/token` — add `slowapi` middleware (~1 day)
- [ ] Refresh-token-family revocation — add `family_id` column + replay detection (~2 days)

Once each lands, flip the corresponding `xfail` to `xfail(strict=True)` then to a passing test.

### 4. Push public repo (Task #9 in tracker)

Pending user review. Per the user's prior choice: single repo at `github.com/bioMate-AI/biomate-connectors`. Use `git subtree split` to keep only the connector subdirs + their history, then push:

```bash
# Approximate flow (verify before running):
gh repo create bioMate-AI/biomate-connectors --public --description "..."

# Subtree split for each public-facing dir
cd /home/yzhang/biomate_worktrees/connectors_v2
git subtree split --prefix=connectors -b _public-connectors
git subtree split --prefix=skills/biomate -b _public-skill
git subtree split --prefix=backend/lib/mcp -b _public-mcp
git subtree split --prefix=backend/lib/galaxy/connectors -b _public-oauth

# Push as a single repo (combine the branches into a coherent root —
# probably easier: just `git push --mirror` after curating files manually)
```

Alternative (simpler): cherry-pick the 4 connector commits into a fresh repo
root, rewriting paths so `connectors/` lives at the top. Either way, **do not
push the entire bioMate codebase publicly.**

### 5. Launch week

Per `connectors/submissions/README.md`:

- Mon: Anthropic MCP servers PR + Cursor MCP directory
- Tue: Anthropic Skills gallery + OpenAI GPT store
- Wed: WeChat 公众号 + 知乎 announcements
- Thu: HN Show HN + X thread + LinkedIn
- Fri: Slack (deferred until pilot wraps)

## Where to look for what

| Question | Answer |
|---|---|
| "Why 14 tools, not 50?" | `docs/20260513_CONNECTOR_ARCHITECTURE_V2.md` §"Tool surface" |
| "How does PKCE work here?" | `test-docs/oauth_unit.md` + `backend/lib/galaxy/connectors/oauth/pkce.py` |
| "Why does the installer mock `os` module?" | `test-docs/installer_flow.md` §"Fixtures" |
| "Which surfaces support streaming?" | `connectors/README.md` table + `docs/20260513_CONNECTOR_ARCHITECTURE_V2.md` §"Streaming over MCP" |
| "What's the gold-path E2E test?" | `TEST_PLAN.md §6.1` (Claude Code, ADMET screening) |
| "When does the manifest CI fail?" | `test-docs/manifest_drift.md` §"When it fails" |
| "How do I revoke a user's connector access?" | `POST /oauth/grants/revoke` with `surface=...`; covered by `test-docs/oauth_router.md` |
| "Can I run tests without API keys?" | Yes — L4 skips cleanly; L1+L2+L3 run fully offline |
| "What if a security test fails?" | `test-docs/oauth_security.md` has a SEV-level table per assertion |

## Glossary

| Term | Meaning |
|---|---|
| Surface | A host application that connects to BioMate (Claude Code, Cursor, ChatGPT, etc.) |
| Tool surface | The 14-tool MCP API exposed to LLMs |
| L1 / L2 / L3 / L4 / L5 | Test layers: unit / integration / sandbox-SDK / live-LLM / E2E-real |
| Manifest | The single source of truth for tool schemas (`backend/lib/mcp/tools_manifest.py`) |
| Drift test | A test that fails if downstream adapters disagree with the manifest |
| PKCE | Proof Key for Code Exchange (RFC 7636) — OAuth without shared client secret |
| Token family | A refresh-token lineage; reuse detection revokes the whole family |
| xfail | pytest's "expected failure" marker — tracked known issue, doesn't break CI |
| Open Claw | BioMate's hosted WeChat bridge |

---

**End of handoff.** Questions: filed as GitHub issues on `bioMate-AI/biomate-connectors` once the public repo is up. Until then, ask in the team Slack.
