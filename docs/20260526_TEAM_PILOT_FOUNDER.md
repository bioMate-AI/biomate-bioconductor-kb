# Team brief — Pilot Tester + Founder

**For pilot users:** how to install, what to test, how to file bugs.
**For the founder:** what blocks public push, launch-week schedule, decision points.

---

## Pilot tester — install + test (10 min)

### Pick your surface and install

| Surface | One command |
|---|---|
| Claude Code | `npx @biomate/connect claude-code` |
| Claude Desktop | `npx @biomate/connect claude-desktop` |
| Cursor | `npx @biomate/connect cursor` |
| Codex CLI | `npx @biomate/connect codex` |
| ChatGPT | Open the [BioMate (internal) GPT](#) — share link from launch coordinator |
| WeChat | `npx @biomate/connect open-claw` then follow `/connect <code>` in the BioMate AI 公众号 |

**Where to install against (staging vs prod):**

```bash
# Point at the internal staging deploy (don't use prod for testing)
export BIOMATE_AUTH_BASE=https://staging.biomate.ai
export BIOMATE_API_BASE=https://staging.biomate.ai
npx @biomate/connect claude-code
```

Restart your client after install (Claude Desktop, Cursor, Codex need a full quit/reopen).

### Try these prompts (paste verbatim)

```
Screen aspirin and caffeine for hERG inhibition and CYP3A4 metabolism.
```

```
Run nf-core/rnaseq differential expression on these FASTQs:
  s3://biomate-demo/treated_R1.fq.gz, s3://biomate-demo/treated_R2.fq.gz
  s3://biomate-demo/control_R1.fq.gz, s3://biomate-demo/control_R2.fq.gz
Compare treated vs control, GRCh38.
```

```
Look up UniProt P04637 and summarize the top 3 cancer-associated mutations.
```

```
What workflows do you have for CryoSPARC?
```

### What "passing" looks like

- The model picks the right tool (you'll see it call `biomate_session`, `search_workflow`, or `query_database`).
- For workflow runs: phase events stream inline (or appear as a polled status if your surface doesn't render progress).
- A clickable `https://biomate.ai/runs/<id>` deep link appears in the response.
- The final result is structured (table, code block, or attached PDF) — not free prose only.

### Known gaps you may hit (not your bug)

| Surface | What may be missing | Why |
|---|---|---|
| Slack | PDF attachment doesn't arrive | `files.upload_v2` bridge not yet built |
| Codex | No plots in the terminal | ASCII renderer not yet built |
| WeChat | Thumbnails missing from QC cards | Bridge drops them; fix pending |
| ChatGPT | No live progress events, only final status | Actions don't support `notifications/progress` |

**Don't file these as bugs** — they're tracked in `docs/20260526_TEAM_BACKEND_DEVOPS.md`.

### Bugs to file (please do)

- Anything that crashes
- Wrong tool selected for an unambiguous prompt
- Wrong workflow chosen for a clear domain (e.g., RNA-seq prompt → ADMET)
- Auth flow that fails or hangs
- Methods report content errors (wrong run ID, missing sections)
- UI/UX problems: confusing error messages, broken links, scary stack traces

### How to file

GitHub issue at the (forthcoming) `bioMate-AI/biomate-connectors` repo. Until that's public, paste in the internal Slack `#connectors-pilot` channel with:
- Surface (Claude Code / Cursor / etc.)
- Exact prompt you typed
- What you expected vs. what happened
- Screenshot if visual

---

## Founder — what blocks public push

### Pre-GA blockers (must clear)

1. **Backend P0s** — 4 items, ~1 week of work, owned by backend team. See `docs/20260526_TEAM_BACKEND_DEVOPS.md` tasks #1–4.
2. **Security gaps (xfail)** — 2 items: OAuth rate limiting + refresh-token-family revocation. Same doc, task #5.
3. **Internal test plan completion** — Phases 1–6 of `docs/20260525_INTERNAL_TEST_PLAN.md`. Phase 0 done; Phases 1–6 require team execution this week.
4. **Staging deploy** — connector branch not wired into Galaxy ASGI app yet. Backend team is the dependency.
5. **DNS** — `api.biomate.ai` and `staging.biomate.ai` need to resolve from team dev machines.

### What you decide this week

| Decision | When | Who advises | Default |
|---|---|---|---|
| Public repo name + license | Before push | designer + legal | `bioMate-AI/biomate-connectors`, MIT |
| Should Slack be on the launch list or deferred? | Before launch announcement | QA based on pilot results | **Defer** (already in internal docs) |
| Free tier: 3 runs or different? | Before launch landing locks | billing + product | "3 runs" claim conflicts; pick one |
| WeChat-first vs Western-first launch | Day of launch | marketer | West Mon-Thu, China Wed-Thu |
| Do we ship demo videos before or with the launch? | This week | designer | Ideal: with launch; acceptable: 48h after |

### Launch-week schedule (per `connectors/submissions/README.md`)

| Day | What | Owner |
|---|---|---|
| Mon | Anthropic MCP servers PR + Cursor MCP directory | engineer + designer |
| Tue | Anthropic Skills gallery + OpenAI GPT store | designer |
| Wed | WeChat 公众号 + 知乎 | marketer (zh) |
| Thu | HN Show HN + X thread + LinkedIn | marketer |
| Fri | Slack App Directory (deferred until pilot wraps) | — |

### Talking points (for press / pitches)

The strongest one-liners from `connectors/marketing/blog/launch-post.md`:

- "Generic AI can write code about hERG screening. With BioMate, Claude Code **runs it** — on AWS Batch, with QC gates, and gives you the IND-ready methods PDF."
- "One OAuth flow. One MCP surface. Six places to call it from. 2,455 indexed workflows."
- "We resisted the temptation to ship 50 tools. We landed on 14 — across 3 tiers: one streaming agentic tool, six workflow primitives, seven outputs/analysis/reporting."
- "Same execution engine biomate.ai uses; same QC gates; same reports. Not a demo."

### Numbers you can cite

- 14 MCP tools across 3 tiers
- 2,455 indexed workflows across 34 biological domains
- 6 surfaces live + Slack in pilot
- 97 passing automated tests + 2 xfail (known issues, tracked)
- OAuth 2.1 + PKCE; per-surface scopes; refresh tokens HMAC-SHA256 hashed at rest
- 30-min HS256 JWT access tokens, rotated on use per OAuth 2.1 §6.1
- 35 SDK-validation cases (Anthropic, OpenAI, MCP Python SDK, OpenAPI 3.1, JSON Schema)
- 4/4 Anthropic live tool-routing tests pass (test_connector_live.py)
- Phase 0 smoke: 10/10 PASS against live OAuth server (2026-05-25)

### Go/no-go gate (you call it Friday)

Per `docs/20260525_INTERNAL_TEST_PLAN.md` Phase 8. QA brief at `docs/20260526_TEAM_QA.md` has the full checklist. If 4+ items are red on Friday, slip launch by one week — better to ship clean than ship broken.

### Press strategy notes

- **HN Show HN** — likely strongest distribution; budget time to engage in comments for 4+ hours
- **Anthropic + OpenAI directories** — these reach the right audience but are slow (days–weeks for approval)
- **WeChat / 知乎** — Chinese researcher audience; the Mandarin demo (#6) is the key asset
- **Twitter / X** — supporting; not the primary channel for a B2B science tool

## Reference

- `docs/20260525_SESSION_SUMMARY.md` — full work index
- `docs/20260525_INTERNAL_TEST_PLAN.md` — Phase 0–8 sandbox playbook
- `connectors/marketing/blog/launch-post.md` — your edit pass before publish
- `connectors/TEST_PLAN.md` §13 — open issues
