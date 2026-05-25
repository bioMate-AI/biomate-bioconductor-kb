# Production Test Plan — Sandbox Libraries → Real Telemetry

**Date:** 2026-05-20
**Status:** Plan only. No code changes. Awaiting user authorization.
**Prerequisites:** 16 commits of sandbox work + held-out validation per `20260520_ENTITY_HELDOUT_AND_COMPLETE_SCORECARD.md`.

## Why this doc exists

Five libraries have been built and held-out validated in sandbox. None are wired to production. To responsibly move ANY of them from "passes synthetic eval" to "proven beneficial on real users," there needs to be a structured rollout with explicit gates, measurable criteria, and trivial rollback.

This is the plan for that. Per your deploy discipline, the plan is reviewed before any wiring happens.

## Section 1 — Which library to wire first

### Recommendation: `family_dedup` (wrapper-level)

**Rationale:**

1. **Largest measured lift:** 25% → 90% top-1 canonical on n=40 (+65pp). The biggest user-facing improvement of any of the libraries.
2. **Held-out safety strongest:** 30/30 identical to baseline on 30 uncovered families (production-DB-realistic queries). Zero false positives in a held-out test designed specifically for safety.
3. **Smallest call-site surface:** Single integration point at `tool_parameter_recommender.py:search_tools()`. One method, one file, ~10 LOC patch.
4. **Library already in production path:** `backend/lib/galaxy/ai/retrievers/family_dedup.py` is importable from production. Tests pass against the real DB (`backend/database/galaxy_ai_tools.db`).
5. **Lowest blast radius:** the autofix tool recommender is an internal LLM-facing consumer, not a direct user-visible UX. Wrong outputs → autofix proposes a sub-optimal tool, not a broken pipeline.

### Second priority: `workflow_intent` (workflow level)

After family_dedup is wired, validated, and stable for ≥ 2 weeks. Workflow_intent has bigger user-facing impact (chat routing) but a bigger code surface and is rarer to be reverted cleanly mid-session.

### Lower priority (require more groundwork before wiring):

- `memory` adapter — needs an integration point that doesn't yet exist (no centralized memory-recall API; it would have to slot into the auto-memory injection path)
- `chat_session` — needs frontend coordination + a UX decision for the "uncertain" branch (prompt user vs default to last session vs default to new)
- `entity` — YAML coverage of only 17 entries is too sparse for production traffic; needs bulk HGNC import first

## Section 2 — The exact patch for family_dedup

### File: `backend/lib/galaxy/ai/workflow_ops/autofix/tool_parameter_recommender.py`

### Current state (lines 100-139, restored to pre-session form):

```python
def search_tools(self, query: str, limit: int = 10) -> List[ToolInfo]:
    if not self.conn:
        return []
    try:
        cursor = self.conn.execute("""
            SELECT t.tool_id, t.name, t.category, t.description, t.rawText, t.version
            FROM tools t
            JOIN tools_fts fts ON t.tool_id = fts.tool_id
            WHERE tools_fts MATCH ?
            LIMIT ?
        """, (query, limit))
        results = []
        for row in cursor:
            results.append(ToolInfo(...))
        return results
    except Exception as e:
        log.error(f"Failed to search tools: {e}")
        return []
```

### Proposed patch:

```python
def search_tools(self, query: str, limit: int = 10) -> List[ToolInfo]:
    if not self.conn:
        return []

    # When the family-prioritizer is enabled, fetch wider so the canonical
    # wrapper (often at FTS rank 50-100) is in the candidate pool. The
    # prioritizer trims back to `limit` after reordering.
    import os
    use_prioritize = os.environ.get("BIOMATE_FAMILY_PRIORITIZE") == "1"
    fetch_limit = limit * 10 if use_prioritize else limit

    try:
        cursor = self.conn.execute("""
            SELECT t.tool_id, t.name, t.category, t.description, t.rawText, t.version
            FROM tools t
            JOIN tools_fts fts ON t.tool_id = fts.tool_id
            WHERE tools_fts MATCH ?
            LIMIT ?
        """, (query, fetch_limit))
        results = []
        for row in cursor:
            results.append(ToolInfo(
                tool_id=row['tool_id'],
                name=row['name'],
                category=row['category'],
                description=row['description'] or '',
                raw_text=row['rawText'] or '',
                version=row['version'],
            ))

        if use_prioritize and results:
            try:
                from backend.lib.galaxy.ai.retrievers import prioritize_query_family
                # Convert ToolInfo dataclasses to dicts for the library
                as_dicts = [
                    {"tool_id": t.tool_id, "name": t.name, "_idx": i}
                    for i, t in enumerate(results)
                ]
                reordered = prioritize_query_family(query, as_dicts)
                # Reassemble ToolInfo list in new order, trim to limit
                results = [results[d["_idx"]] for d in reordered[:limit]]
                _LOG_PRIORITIZE_HIT(query, len(reordered))
            except Exception as exc:
                # Library NEVER breaks the recommender: on any error, fall
                # back to raw FTS results
                log.warning("family-prioritize failed: %s", exc)
                results = results[:limit]

        return results

    except Exception as e:
        log.error(f"Failed to search tools: {e}")
        return []


def _LOG_PRIORITIZE_HIT(query: str, n_candidates: int) -> None:
    """Telemetry hook — keep as a no-op function call so it's grepable
    when we add real telemetry. See Section 5 for instrumentation plan."""
    pass
```

**Patch size: ~25 net new lines.** Behind `BIOMATE_FAMILY_PRIORITIZE=1` env flag. When the flag is unset (production default), behavior is **bit-identical** to current code — verified by:
- The `if use_prioritize` branch is the only diff
- The original `cursor.execute` + result loop is unchanged
- The exception handling in the outer `try` catches anything including the new code

### Why FETCH_LIMIT = limit × 10

The earlier A/B measurement (`sandbox/retrieval_v2/scripts/measure_canonical_lift.py`) found that the canonical wrapper sits at FTS rank 50-100 for many queries (samtools at 81, picard at 55, bedtools at 27). Fetching only `limit` rows means the prioritizer can't promote what isn't in the pool. `limit * 10` (typically 100) is the smallest pool size where prioritize_query_family reliably finds the canonical.

**Cost of fetching 10×:** SQLite FTS5 with `LIMIT 100` adds <2ms vs `LIMIT 10` for a `tools_fts` query (measured locally: ~3ms vs ~1ms). Negligible at the autofix latency budget.

## Section 3 — Dev → Stage → Prod rollout plan

### Stage 0 — pre-deploy (no code change yet)

**Goal:** make sure the library imports cleanly in the actual production Python environment.

```bash
# On dev EC2 (without syncing any changes yet):
ssh dev-public
cd /path/to/biomate
python3 -c "from backend.lib.galaxy.ai.retrievers import prioritize_query_family; print('ok')"
python3 -m pytest backend/tests/test_family_dedup.py -q
```

**Pass criteria:** import succeeds; 29 tests pass.

**Rollback if this fails:** nothing to roll back; we haven't deployed.

### Stage 1 — apply patch to integration/next-phase, deploy to dev

**Goal:** verify the patch compiles, the recommender still works with flag OFF (bit-identical), and the autofix system smoke-tests pass.

Steps:

```bash
# Locally:
git checkout integration/next-phase
# Apply the patch (the diff from Section 2)
PYTHONPATH=. python -m pytest backend/tests/test_family_dedup.py -q  # 29 pass

# Sync to dev (per existing tooling):
scripts/sync_to_dev.sh
# AND verify BIOMATE_FAMILY_PRIORITIZE is NOT set in dev env

# On dev, smoke-test the autofix recommender:
ssh dev-public
curl -X POST http://localhost:8081/api/autofix/... -d '{"query": "samtools sort"}'  # exact endpoint TBD
# Expected: same output as before the patch
```

**Pass criteria:**
- All existing `test_family_dedup.py` tests still pass on dev
- Smoke-test response identical to pre-patch behavior (flag is OFF)
- No new errors in dev logs for 1 hour after deploy

**Rollback if this fails:**
- `git revert <patch commit>`
- `scripts/sync_to_dev.sh`
- 5-minute total recovery.

### Stage 2 — enable flag on dev only, run smoke A/B for 48 hours

**Goal:** observe the prioritizer firing on real dev traffic. Validate that:
- Latency overhead is < 10ms p99
- No exceptions in the new code path
- Recommender outputs visibly change shape (canonical_family_id stamped on results)

```bash
# Set env on dev only:
ssh dev-public
echo "BIOMATE_FAMILY_PRIORITIZE=1" >> /etc/biomate.env
sudo systemctl restart biomate-backend  # exact command TBD

# Monitor for 48h:
- ssh dev-public; tail -f /var/log/biomate/backend.log | grep "family-prioritize"
- check latency dashboard for tool_parameter_recommender.search_tools p50/p99
- check error rate for /api/autofix/*
```

**Pass criteria:**
- Zero exceptions logged from the prioritize path
- `tool_parameter_recommender.search_tools` p99 latency < pre-deploy p99 + 10ms
- /api/autofix/* error rate unchanged (within ± 5% of pre-deploy)
- At least 50 prioritize-fires logged (proves the flag is actually taking effect)

**Rollback if this fails:**
- `unset BIOMATE_FAMILY_PRIORITIZE` (or remove from env file) + restart
- 1-minute recovery; no code revert needed

### Stage 3 — collect dev telemetry, decide on prod

**Goal:** confirm prioritize actually helps real dev queries, not just synthetic eval.

After 48h on dev:
- Pull `family-prioritize` log lines
- Tabulate top-10 queries that triggered prioritize
- For each top query: was the prioritized top-1 better than what raw FTS returned?
- Spot-check 20 queries manually

**Pass criteria for prod rollout:**
- ≥ 60% of spot-checked queries: prioritized top-1 is more relevant than raw FTS top-1
- 0 cases where prioritized top-1 is plainly wrong (e.g. unrelated tool)
- (These match the held-out safety properties; we're confirming they hold on real traffic)

**If fewer than 60% of queries show improvement:**
- The eval set was unrepresentative of real traffic. **Do not promote.**
- Build a real-traffic-derived eval set and re-iterate.

### Stage 4 — prod rollout, flag OFF by default

**Goal:** ship the code to prod but keep it dormant. Allows ops to flip the flag without a deploy.

```bash
# Merge integration/next-phase → main (or whichever prod branch)
git checkout main && git merge integration/next-phase
# Deploy to prod
scripts/sync_to_prod.sh  # if exists; otherwise the existing prod deploy mechanism
# Verify flag is NOT set in prod env
ssh prod; env | grep BIOMATE_FAMILY_PRIORITIZE  # empty
```

**Pass criteria:** prod recommender behaves identically to before (flag OFF). Verified via the same smoke-tests as Stage 1.

### Stage 5 — enable flag on prod for 5% of traffic (canary)

If your infrastructure supports per-pod env vars or feature-flag service:

```bash
# Set BIOMATE_FAMILY_PRIORITIZE=1 on 5% of backend pods only
# Or: gate on user_id % 20 == 0 inside the recommender code
```

**Run for 1 week.** Monitor:
- Same metrics as Stage 2 (latency, error rate, exception count)
- Plus user-side: do users in the canary group accept more autofix suggestions? Reject fewer? (telemetry hook in Section 5)

**Pass criteria for full rollout:**
- Canary-group autofix-acceptance rate ≥ control-group acceptance rate
- No spike in support tickets / user complaints from canary group
- All Stage 2 latency/error gates still pass

### Stage 6 — full prod rollout

Set flag globally. Monitor for another week. If stable, the wiring is done.

### Total timeline

| Stage | Duration |
|---|---|
| 0 (pre-deploy check) | 30 min |
| 1 (dev deploy, flag OFF) | 1 hour + 1h observation |
| 2 (dev with flag ON) | 48 hours |
| 3 (dev review) | ~2 hours |
| 4 (prod deploy, flag OFF) | 1 hour |
| 5 (canary 5%) | 1 week |
| 6 (full prod) | 1 week monitoring |
| **Total** | **~2.5 weeks** from authorization to fully rolled out |

## Section 4 — Success criteria (what "proven beneficial" means)

In order of importance:

1. **Zero high-cost mistakes.** No spike in autofix proposing plainly wrong tools (defined as: tool from a different domain than the user's query, or tool not commonly used for the user's stated task). Measured by 1-week canary spot-check of ~50 prioritize-fires.

2. **Latency budget held.** `search_tools` p99 stays within +10ms of pre-deploy baseline. Anything worse means we need to optimize before fuller rollout.

3. **Autofix acceptance rate non-decreasing.** If users accept LLM-proposed tool fixes at the same rate or higher with the flag ON vs OFF, the change is beneficial. Specifically: `acceptance_rate_with_flag >= acceptance_rate_without_flag - 2pp` (allow tiny noise).

4. **Disambiguation card fire rate non-increasing.** If the upstream disambiguation card starts firing more often after the wiring, something is wrong downstream. This is a sanity-check metric.

5. **No support tickets attributable to the change.** Specifically zero user complaints in the canary period mentioning autofix returning unexpected tools.

## Section 5 — Telemetry hooks needed before wiring

The patch in Section 2 includes a `_LOG_PRIORITIZE_HIT(query, n_candidates)` placeholder. Before Stage 2, replace it with real instrumentation:

**Minimum required:**

```python
def _LOG_PRIORITIZE_HIT(query: str, n_candidates: int) -> None:
    log.info(
        "family-prioritize-fire",
        extra={
            "query": query[:200],            # truncate for log size
            "n_candidates_pre": n_candidates,
            "timestamp": time.time(),
        }
    )
```

**Nice-to-have (Stage 5 canary):**

Hook into the existing analytics/billing track-call pattern at `backend/lib/galaxy/ai/llm_client.py:46`:

```python
from galaxy.ai.analytics.tracking_decorator import manual_track_call
manual_track_call(
    session_id=..., step_name="family_prioritize",
    scenario_name="tool_recommender",
    input_tokens=len(query), output_tokens=0,
    duration_ms=elapsed_ms, model_name="prioritize_query_family",
    success=True,
)
```

This routes through existing observability infrastructure — no new pipelines needed.

**What to track per fire:**
- Input query (truncated to 200 chars)
- Whether `prioritize_query_family` reordered results (vs returned unchanged)
- Number of candidates pre-prioritize
- Number of candidates post-prioritize (should be same; library doesn't add/drop)
- Resolved canonical family_id (when known)
- Latency added by the prioritize call (ms)

## Section 6 — What could go wrong even though tests are green

1. **Real-world queries differ from the eval set.** The 40-case A/B was hand-curated by me; production users phrase things differently. Mitigation: Stage 2 + Stage 3 dev observation catches this.

2. **Caller-side caching interactions.** If `tool_parameter_recommender` results are cached upstream (Redis, in-process), enabling/disabling the flag mid-session could produce inconsistent results. Mitigation: identify caching layers in Stage 0; if any, document the cache-bust requirement when flipping the flag.

3. **DB load from `LIMIT 100`.** Across hundreds of concurrent autofix requests, 10× the FTS row scan could matter. Mitigation: monitor SQLite query latency in Stage 2; if regression > 10ms, consider lowering `fetch_limit` to `limit * 5`.

4. **YAML drift between local and prod.** The library reads from `backend/config/tool_family_aliases.yaml` and `tool_family_canonical.yaml`. If the prod sync doesn't include these files, the library degrades silently to no-op. Mitigation: Stage 1 verify both files exist on dev/prod via `ls -la`.

5. **The `lru_cache` on YAML load** never clears in a long-running process. If you edit the YAMLs in prod without restarting the backend, changes don't take effect. Mitigation: documented in `20260518_FAMILY_DEDUP_INTEGRATION_GUIDE.md` ("YAML reloads on next process start").

## Section 7 — Decision points needing user input before any wiring starts

1. **Authorization to apply the Section 2 patch** to `integration/next-phase`. (No sync yet.)
2. **Confirmation of dev EC2 access** for Stage 1-3. (Need ssh access, ability to set env vars, ability to restart backend.)
3. **Telemetry infrastructure choice** — use the existing `galaxy.ai.analytics.tracking_decorator` pattern, or build a separate metrics pipeline?
4. **Canary mechanism for Stage 5** — does prod infrastructure support per-pod env vars or feature flags? If not, code-side gating on `user_id % 20` is the fallback.
5. **Definition of "autofix acceptance rate"** — does this metric already exist in production telemetry? If not, instrumenting it is a separate ~1-day prerequisite.

## Section 8 — Order-of-operations summary (one screen)

```
[Today]      Plan written. Awaiting authorization.
[Day 1]      Stage 0: pre-deploy import check on dev (30min)
[Day 1]      Stage 1: patch applied, dev deploy with flag OFF (1h)
[Day 1-3]    Stage 2: enable flag on dev, 48h observation
[Day 3]      Stage 3: review dev telemetry, decide go/no-go on prod
[Day 4]      Stage 4: prod deploy with flag OFF
[Day 4]      Stage 5: enable flag on 5% prod traffic
[Day 11]     Stage 5 review, decide go/no-go on full
[Day 12]     Stage 6: full prod rollout
[Day 19]     Stage 6 review, declare wiring complete
```

**Total wall-clock: ~2.5 weeks** (mostly observation gaps). **Active engineering effort: ~1 day** spread across the timeline.

## What's NOT in this plan

- Wiring of any library other than `family_dedup` — those come AFTER family_dedup is stable in prod for ≥ 2 weeks.
- Bulk-import of HGNC for entity adapter — separate prerequisite work, not blocking family_dedup.
- Any UI changes — none of these libraries touch the UI directly.
- Performance optimization of the library itself — current measurements show negligible latency overhead; revisit only if Stage 2/5 metrics indicate a problem.

## Open questions for the user

1. Authorize the Section 2 patch on `integration/next-phase` (no dev sync yet)?
2. Approve the Section 3 6-stage rollout timeline, or modify gates?
3. Confirm Section 5 telemetry approach (route through existing analytics)?
4. Any prior-art telemetry that already tracks autofix-acceptance-rate, or do we need to instrument that fresh?

Your call on each — until you say "go on stage N", nothing changes.
