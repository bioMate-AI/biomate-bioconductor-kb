# Internal test plan — pre-launch (2026-05-25)

**Branch:** `connectors-v2-launch`
**Worktree:** `/home/yzhang/biomate_worktrees/connectors_v2`
**Goal:** validate every surface end-to-end before public launch using sandboxes that don't require directory/store submission.

## Test environments

| Surface | Sandbox | Submission required? | Notes |
|---|---|---|---|
| Claude Code | local install | no | `npx @biomate/connect claude-code` against a staging URL |
| Claude Desktop | local install | no | same installer, different config path |
| Cursor | local install | no | same |
| Codex CLI | local install | no | same |
| ChatGPT | Custom GPT, "Only me" | no — public submission only when ready | chatgpt.com/gpts/editor |
| Anthropic Workbench | API account | no | console.anthropic.com/workbench |
| Slack | dev workspace + private app | no — public store submission deferred | api.slack.com/apps |
| WeChat / Open Claw | 测试号 sandbox | no | mp.weixin.qq.com/debug/cgi-bin/sandbox |

## Pre-flight checklist (one-time)

1. ✅ Branch `connectors-v2-launch` deployed to a staging BioMate environment that exposes `/oauth/*` endpoints (see `backend/lib/galaxy/connectors/oauth/router.py`)
2. ✅ Seed OAuth clients: `python backend/scripts/seed_oauth_clients.py`
3. ✅ Environment variables on staging backend:
   - `BIOMATE_OAUTH_SIGNING_KEY` (64 random bytes, base64)
   - `BIOMATE_OAUTH_DB=/var/lib/biomate/oauth.db`
4. ✅ Test user account on staging (`testers@biomate.ai`) with paid-tier quota
5. ✅ Demo S3 fixtures public-read at `s3://biomate-demo/`:
   - `compounds/admet_3.smi` — 3 SMILES for ADMET
   - `rnaseq/{T1,T2,T3,C1,C2,C3}_R{1,2}.fq.gz` — 6 RNA-seq FASTQs
   - `wgs/sample{1..4}_R{1,2}.fq.gz` — 4 WGS FASTQs
   - `cryo/particles_25k.cs` + `cryo/ref_3A.mrc`

## Phase 0 — local smoke (today, ~30 min)

**Verify the connector machinery works in total isolation, no real BioMate backend behind.**

1. Start the OAuth server standalone from the worktree
2. Run the installer pointing at `http://127.0.0.1:8090`
3. Verify `~/.claude.json` is written with a valid refresh token
4. Run a test refresh-token round-trip

**Pass criteria:** installer completes; `~/.claude.json` has correct shape; refresh token rotates on demand.

## Phase 1 — Anthropic Workbench (Mon morning, ~1 hr, ~$0.30)

**Probe the LLM's tool-selection accuracy across all 14 tools.**

For each of 14 tools, prepare 2–3 representative prompts. Paste the tool manifest into Workbench. Run each prompt; verify the model picks the intended tool.

| Tool | Test prompts |
|---|---|
| `biomate_session` | "Screen aspirin for hERG"; "Run RNA-seq DE on these FASTQs..." |
| `search_workflow` | "What workflows do you have for cryo-EM?"; "List proteomics pipelines" |
| `get_workflow_spec` | "What params does nf-core/sarek need?"; "Show the schema for ADMET" |
| `run_workflow` | "Start workflow 12849 with these params: ..."; "Run workflow 12722 with stream=true" |
| `cancel_run` | "Cancel run-abc-123"; "Stop my running ADMET" |
| `list_runs` | "Show my runs from this week"; "List CRYOSPARC runs in last 7 days" |
| `get_run` | "What's the status of run-xyz?"; "Show progress for the WGS run" |
| `preview_file` | "Show me the volcano plot from run-xyz"; "Preview the VCF output" |
| `export_report` | "Generate a methods PDF for run-xyz"; "Make an IND §2.6.1 narrative" |
| `analyze_results` | "What do these DE results mean biologically?"; "Interpret these QC metrics" |
| `explain_error` | "Why did my run fail?"; "What does this STAR error mean?" |
| `recall_memory` | "What were my prior CRISPR screens about?"; "Show similar workflows I've run" |
| `upload_file` | "I have a local FASTQ I need to upload"; "How do I send my SMILES file?" |
| `query_database` | "Look up UniProt P04637"; "Get PDB 1AKE structure" |

**Pass criteria:** ≥39/42 prompts (93%) route to the correct tool with `temperature=0`. <93% means description tightening needed.

## Phase 2 — Local installs (Mon afternoon, ~2 hr)

Each team member runs the installer on their primary surface and verifies one workflow.

| Tester | Surface | Test prompt | Expected |
|---|---|---|---|
| <person> | Claude Code | "Screen aspirin and caffeine for hERG and CYP3A4" | ADMET runs, PASS gate, deep link |
| <person> | Claude Desktop | "Run nf-core/rnaseq DE on s3://biomate-demo/rnaseq/" | Phase progress inline, volcano plot thumb, methods PDF link |
| <person> | Cursor | "Refine s3://biomate-demo/cryo/particles_25k.cs with CryoSPARC homo refinement" | 3D viewer link, FSC at end |
| <person> | Codex | "Variant calling on s3://biomate-demo/wgs/ samples, sarek best-practices" | VCF link, top findings as table |

Each tester records: install time, first-token latency, total run time, anything weird in the chat surface.

## Phase 3 — ChatGPT private GPT (Tue, ~2 hr)

1. Create a GPT at chatgpt.com/gpts/editor named "BioMate (internal)"
2. Configure per `connectors/chatgpt/INSTALL.md`:
   - Import OpenAPI from `staging.biomate.ai/connectors/chatgpt/openapi.json`
   - OAuth: client_id=`biomate-chatgpt`, PKCE public client, no secret
   - Paste instructions from `connectors/chatgpt/INSTALL.md` §"Configure tab"
3. Set visibility to **"Only me"**
4. Test in the right pane: 4 conversation starters from the GPT metadata
5. Share link with 3 internal testers (switch visibility to "Anyone with the link")

**Pass criteria:** OAuth flow completes in <30s; first tool call returns valid response; methods PDF downloadable.

## Phase 4 — Slack dev workspace (Tue, ~3 hr)

### Setup

1. Sign in to api.slack.com/apps as the biomate-ai admin
2. **Create New App** → "From scratch" → name `BioMate Dev`
3. Workspace: **Create new** → `biomate-test-slack` (free)
4. **OAuth & Permissions** → bot scopes:
   - `commands`, `chat:write`, `chat:write.public`, `files:write`, `users:read`, `users:read.email`
5. **Slash Commands** → Create `/biomate` → Request URL = `https://<ngrok-url>/connectors/slack/webhook`
6. **Socket Mode** → Enable (avoids needing a public HTTPS for the bot itself)
7. **Event Subscriptions** → Subscribe to `app_mention`, `message.channels`
8. **Install to workspace**
9. On the dev machine: `ngrok http 5000` (or Cloudflare Tunnel) → paste public URL into slash command config

### Tests

| # | Test | Expected |
|---|---|---|
| 1 | `/biomate login` in a channel | OAuth link posts ephemerally; clicking → callback completes |
| 2 | `/biomate run Screen aspirin for hERG` | Thread starts, phase updates edit message in place |
| 3 | `/biomate search rnaseq` | Top 5 workflows in markdown table |
| 4 | `/biomate runs` | Last 10 runs filtered to current channel |
| 5 | `/biomate recall CRISPR` | Prior CRISPR-related runs / findings |
| 6 | 3 users in same channel run workflows simultaneously | No thread cross-talk |
| 7 | `@biomate Run RNA-seq` in a thread | Same as slash command, response in thread |
| 8 | `/biomate logout` | Subsequent commands prompt for login |

**Known limitation:** `files.upload_v2` integration not yet built (per audit P0). Methods PDF posts as a link, not an attachment, until that ships.

## Phase 5 — WeChat 测试号 (Wed, ~3 hr)

### Setup

1. Visit https://mp.weixin.qq.com/debug/cgi-bin/sandbox?t=sandbox/login
2. Log in with a personal WeChat (scan QR)
3. Note the **appID** + **appSecret** from the sandbox dashboard
4. Configure webhook:
   - URL: `https://<ngrok-url>/connectors/open-claw/webhook`
   - Token: any random string (must match `WECHAT_VERIFY_TOKEN` env on the bridge)
   - EncodingAESKey: generate random
5. Set bridge env vars on the dev backend:
   ```bash
   export WECHAT_APP_ID=<sandbox-appid>
   export WECHAT_APP_SECRET=<sandbox-secret>
   export WECHAT_VERIFY_TOKEN=<random>
   ```
6. Click **Verify URL** in the sandbox UI — should succeed
7. Scan the sandbox's "test 公众号 QR" to follow it as a test user

### Tests

| # | Test | Expected |
|---|---|---|
| 1 | `/connect <code>` after running `npx @biomate/connect open-claw` | Bot confirms account linked |
| 2 | "筛选 aspirin 的 hERG" | Markdown summary + biomate.ai link, Chinese response |
| 3 | "Screen aspirin for hERG" (English) | English response |
| 4 | Long RNA-seq run started; wait for push notification | Notification arrives ≤30s after completion |
| 5 | Tap deep link in WeChat | Opens biomate.ai/runs/<id> in WeChat's in-app browser; QC card renders |
| 6 | Replay a tampered webhook payload (using curl) | Server rejects with 403 (HMAC verification) |
| 7 | `/disconnect` | Bot confirms; subsequent prompts say "please /connect" |

**Known limitation:** Thumbnail forwarding currently dropped per the bridge code (audit P0 #3). Test will show text-only responses until the fix lands.

## Phase 6 — Cross-surface integration (Thu, ~2 hr)

The hardest scenarios: state continuity across surfaces.

| # | Scenario | Expected |
|---|---|---|
| 1 | Start RNA-seq run in Claude Code; check status in Cursor | `list_runs` in Cursor shows the run; `get_run` returns same state |
| 2 | Start ADMET in ChatGPT; recall from Claude Desktop | `recall_memory` finds the prior run with findings |
| 3 | Two surfaces same account same run | No race in webhook events; both see terminal status |
| 4 | Revoke Cursor at biomate.ai/account/connectors; Claude Code still works | Cursor calls fail with auth error; Claude Code unaffected |
| 5 | OAuth signing-key rotation mid-session | All surfaces force refresh; no run loss |

## Phase 7 — Compile bug list (Fri AM, ~1 hr)

Triage everything found in phases 1–6 against the existing P0/P1 lists in:
- `connectors/TEST_PLAN.md` §13 (open issues)
- The two audit reports (product design + viz/report) in the prior session

File any new issues as `[INTERNAL_TEST]` GitHub issues on the public repo once it's created.

## Phase 8 — Go/no-go (Fri PM, ~30 min)

Launch criteria — ALL must be ✅:

- [ ] Phase 1: ≥39/42 LLM routing
- [ ] Phase 2: each surface installs + first prompt succeeds for ≥3 testers
- [ ] Phase 3: ChatGPT GPT works for 3 external testers via shared link
- [ ] Phase 4: Slack 8/8 dev workspace tests pass
- [ ] Phase 5: WeChat 6/7 tests pass (test #6 requires the thumbnail-forwarding fix; deferred)
- [ ] Phase 6: cross-surface scenarios 1–4 pass; #5 (key rotation) deferred to GA
- [ ] No new P0 bugs found in phase 7 triage
- [ ] Backend audit P0s either fixed or downgraded with explicit rationale:
  - `report_ready` event branch in `_normalize_sse_event`
  - Slack `files.upload_v2` bridge (README updated to remove PDF-attach claim if deferred)
  - Open Claw `thumbnail_png_b64` forwarding
  - Codex CLI ASCII renderer (or README updated to set expectations)

If go: proceed with public repo push (Task #9), then directory submissions per `connectors/submissions/README.md` weekly schedule.

## Fixtures, costs, and risks

### Cost ceiling for the week

| Item | Estimate |
|---|---|
| Anthropic Workbench probes (42 prompts × $0.01) | $0.42 |
| ChatGPT tester GPT-4o tokens (3 testers × 10 prompts × $0.05) | $1.50 |
| Local installs × 4 surfaces × 3 testers × ~$2 of staging Batch | $24 |
| Slack dev workspace | $0 |
| WeChat 测试号 | $0 |
| ngrok / Cloudflare Tunnel | $0 |
| **Total** | **~$26** |

### Risks

1. **Staging vs prod env drift** — staging.biomate.ai must match prod's `oauth/*` endpoint shape exactly. Mitigate: deploy from `connectors-v2-launch` to staging before phase 0.
2. **WeChat sandbox cap of 100 followers** — only matters if we widen the test pool beyond the team.
3. **Slack workspace cap of 10 users** — fine for now; will need an org workspace for public Slack pilot.
4. **API keys leaking via shared GPTs** — only Plus/Team users in the share link can call Actions; tokens are server-side.
5. **Backend P0s not yet fixed** — phases 4 and 5 will show degraded UX. Document expected gaps in test reports.

## Owners (fill in before Monday)

| Phase | Owner | Backup |
|---|---|---|
| 0 — local smoke | | |
| 1 — Workbench | | |
| 2 — local installs | rotate per team member | |
| 3 — ChatGPT | | |
| 4 — Slack | | |
| 5 — WeChat | | |
| 6 — cross-surface | | |
| 7 — triage | (whole team) | |
| 8 — go/no-go | founder | |

## Start here

Phase 0 commands (run from `/home/yzhang/biomate_worktrees/connectors_v2`):

```bash
# 1. Standalone OAuth server on localhost:8090
export BIOMATE_OAUTH_SIGNING_KEY=$(python -c "import secrets,base64;print(base64.urlsafe_b64encode(secrets.token_bytes(64)).decode())")
export BIOMATE_OAUTH_DB=/tmp/biomate-phase0.db
PYTHONPATH=backend/lib python backend/scripts/seed_oauth_clients.py
PYTHONPATH=backend/lib python -c "
import uvicorn
from fastapi import FastAPI
from galaxy.connectors.oauth.router import router
app = FastAPI()
app.include_router(router)
uvicorn.run(app, host='127.0.0.1', port=8090)
" &
SERVER_PID=$!

# 2. Run installer against localhost:8090 (uses tmp HOME so it doesn't touch ~/.claude.json)
TMPHOME=$(mktemp -d)
cd connectors/installer
HOME=$TMPHOME BIOMATE_AUTH_BASE=http://127.0.0.1:8090 BIOMATE_API_BASE=http://127.0.0.1:8090 ./node_modules/.bin/tsx src/cli.ts claude-code
cat $TMPHOME/.claude.json
kill $SERVER_PID
```

If the installer completes and `.claude.json` is written, phase 0 passes and we proceed to phase 1.
