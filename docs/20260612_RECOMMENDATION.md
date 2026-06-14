# Recommendation — What to Do Next with the Chain Composer Prototype

**Date**: 2026-06-12
**Companion**: `docs/20260612_VALIDATION_DOCUMENT.md` (evidence)

## Bottom line

**Stop building. Start shadow-validating against real user traffic.**

The prototype is empirically validated on synthetic + 12 representative use cases (`docs/20260612_VALIDATION_DOCUMENT.md`). Every subsequent improvement on synthetic evals carries Goodhart's risk — fitting the test rather than improving the system. The next dollar of investment should buy real-user data, not more synthetic improvements.

## What we don't yet know

Synthetic evals cannot answer:
- How does the composer handle queries from real users we haven't anticipated?
- Where does the LLM's 95% break down on actual traffic?
- Are the 47 curated chains the right ones, or do users want shapes we don't have?
- Is the `query_specificity → reactive floor` triggering too often or too rarely on real queries?
- Which queries does the existing router handle better than the composer, and vice versa?

None of these are answerable with synthetic data. They're empirical questions about real research behavior in our user base.

## Why not "just wire it to production now"

Naive production wiring (the composer answering users directly) is risky:

1. The composer would route real user queries; wrong answers waste user time and erode trust.
2. The Galaxy + Node routing pipeline is mature; a quiet shadow rollout is the right shape, not a switchover.
3. Production code paths have not been touched in this session deliberately; integration needs care.

## The recommended 3-step plan

### Step 1 — Telemetry-only shadow wiring (~half day)

Add a single hook in `frontend/server/galaxy-assistant.ts` (or the Galaxy `ai_assistant.py` routing path, depending on where chat queries land first) that:

- Calls `compose_chain(query)` on every routing turn behind a default-off feature flag
- Does **not** surface results to the user
- Logs `{ts, user_id, session_id, query, signals, source, mode, confidence, steps, verifier_report, latency_ms, cost_est}` to a JSONL
- Wraps every line in try/except so the composer never breaks routing
- Gates on a percentage flag so initial rollout can be 1% or 0.1%
- Cost cap per session

Cost: nothing in user experience. Gathers the real data calibration needs.

### Step 2 — Audit the logs (~1 week of passive collection)

Once logs accumulate:

- Look at queries where composer disagrees with the existing router
- Manually classify: who's right? Where does composer say upfront but the existing system says no? Where does composer fall to reactive on a query that's clearly answerable?
- Surface real coverage gaps — these are what real users want, not what I imagined.

### Step 3 — Decide whether to graduate (data-driven)

Two outcomes possible from step 2:

- **Composer is consistently better or equal** → graduate to A/B test where composer's output is shown to a small percentage of users with the right consent + fallback to existing routing on errors.
- **Composer has a specific systematic failure** → fix that one thing in a targeted way, repeat step 1.

Either way, decisions are made on real data.

## Why this is the right shape — 6 observations

1. **The prototype is defensible right now.** Stopping doesn't lose anything; every artifact is committed, every DB change is reversible, the catalog improvements survive on their own.
2. **Synthetic eval improvements past 95% have diminishing returns and high overfitting risk.** I added NER terms to fix specific eval queries; that's a smell.
3. **The honest answer to "what do users want" is "I don't know yet."** Real telemetry tells you. Synthetic evals tell you what I imagined.
4. **The biggest catalog improvements have landed** — 18 new chains, 545 domain reassignments, 2,123 Bioc workflows with real outputs, 73,072-edge type-flow graph. Future catalog work has lower ROI per unit effort.
5. **The infrastructure for shadow validation already exists** — `compose_chain` returns structured data including the verifier report and confidence breakdown. Adding telemetry is small.
6. **Production wiring WITHOUT telemetry first is the genuinely risky move.** Shadow logging is cheap and informative; switching surfaces is expensive and risky.

## What I'd NOT do (and why)

| Move | Why not |
|---|---|
| Author more curated chains | Diminishing returns; real users will tell us which chains they want |
| Add more NER vocabulary | 290 entities already; further tuning fits the eval, not the user |
| Promote 5 specialized patterns to first-class | Not needed unless real users hit them at volume |
| Refresh BGE embeddings for the 545 relabeled workflows | Production retrieval already picks them up via BM25 + new domain labels; BGE refresh is incremental |
| Build more prototype-internal docs | There are 35 already; further docs are documentation rot |
| Wire composer to answer users directly without shadow | Risky; no real-data baseline for failure modes |

## The single thing I would invest in

**Step 1 — telemetry-only wiring.** Smallest production-touching change with the highest information value. ~2-4 hours of careful focused work, no user-visible impact, real data starts collecting immediately.

If the user chooses to stop entirely, that's also defensible. The artifact-of-record is at `docs/20260612_VALIDATION_DOCUMENT.md` and the worktree branch `worktree-agent-aaf4e393b5ea5b614`. Nothing requires immediate action.

## Decision matrix

| Path | Effort | Risk | Information gained | Recommendation |
|---|---|---|---|---|
| Stop here | 0 | 0 | 0 | Defensible if no current product priority |
| Telemetry wiring | half day | low (default off, log-only) | high (real query distribution) | **Recommended** |
| Promote to user-facing | days | medium-high (real users see composer output) | very high but slow | Only after telemetry |
| Keep building synthetic improvements | session by session | none to product | low (Goodhart risk) | Not recommended |
| Production wiring without telemetry | days | high (no failure-mode baseline) | medium | Not recommended |

The recommendation is the second row.
