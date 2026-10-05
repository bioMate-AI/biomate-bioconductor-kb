# Speed findings — search, DB query, workflows (2026-10-05)

Evidence-based investigation of where speed can actually be improved. Honest headline: **search and
DB are already reasonably optimized** (diminishing returns — a few modest wins); the **biggest real
latency lever is Batch cold-start** for workflow execution, which is a direct cost/latency tradeoff.

## Search — already well-engineered; modest wins only
How it works (verified in `backend/lib/galaxy/ai/unified_workflow_search.py`):
- Primary: SQLite **FTS5 `workflows_fts` + bm25** ranking (`WHERE workflows_fts MATCH ? ORDER BY bm25`).
- Dense rerank: BGE (`bge-small-en-v1.5`) embeddings held in an **in-memory matrix** (`_WF_EMBED_MATRIX`),
  per query it encodes only the query (via a shared embed server or in-process) + a vectorized dot —
  it does NOT re-encode the catalog per query.
- The matrix is cached in an **`.npz`** (`docs/20260613_DENSE_EMBEDDINGS_PATHS.md`), built ≤once per
  process, with a SHA-256 content signature so it rebuilds only on DB drift (~5-10 ms check vs ~67 s
  rebuild), a **warmup thread** so the first request doesn't pay cold init, and a 5 s lock timeout so
  concurrent requests fall back to FTS-only instead of blocking during a rebuild.
- (The `workflow_embeddings` DB table being 0 rows is a red herring — vectors live in the `.npz`.)

Wins (modest):
1. **Drop `w.workflow_json` from the FTS candidate SELECT** (med/low effort). The main search query
   (`unified_workflow_search.py` ~line 880) pulls `w.workflow_json` (avg 6.5 KB, 27 MB total) for
   EVERY FTS candidate, then ranks/filters. A broad query matching 100–200 rows pulls/parses
   100 KB–1.3 MB of .nf JSON that's mostly discarded. Select the light columns for ranking; fetch
   `workflow_json` lazily only for the final returned set. Cuts per-query bytes + any downstream JSON
   parse. No behavior change.
2. **One-time `.npz` rebuild will fire once** after the WSI-row DB change I just made (signature drift)
   on the next worker's first search (~67 s, once). Expected, not a regression — flagging so it isn't
   misread as one.

## DB query — add indexes + connection PRAGMAs (low effort, low risk, modest win)
Verified on the live DB (322 MB, 4,210 workflows): the `workflows` table has only the implicit
UNIQUE autoindex on `filename`. Name/domain/`lower(name)` lookups are **table SCANs**. Benchmarked on a
copy (warm cache):

| query | before | after index |
|---|---|---|
| `lower(name)=? AND executable=1` (executor's per-run resolve) | 0.4 ms | 0.0 ms (SEARCH idx) |
| `lower(name) LIKE ?` | 2.1 ms | 0.3 ms |
| `domain=? AND executable=1` | 3.4 ms | 1.7 ms |

Absolute gains are small on a warm cache but real (SCAN→SEARCH, confirmed via EXPLAIN), and larger on
cold cache + under concurrency. Recommended:
```sql
CREATE INDEX idx_wf_name_lower   ON workflows(lower(name));
CREATE INDEX idx_wf_domain_exec  ON workflows(domain, executable);
ANALYZE;   -- ~70 ms build, adds a few MB
```
Plus connection PRAGMAs for the read-heavy Galaxy workers (set on connect, not a file change):
`PRAGMA journal_mode=WAL; PRAGMA cache_size=-65536; PRAGMA mmap_size=268435456;` (bigger page cache +
mmap for the 308 MB file improves cold reads + read concurrency).
> Caveat: adding indexes to the canonical DB must go through the safe DB-update path (fetch the full
> dev DB → add index → `sync_to_dev.sh`), same as the WSI-row registration — NOT a local-stub edit.

## Workflows (execution) — the BIGGEST lever: Batch cold-start
Observed on every real run this session (merfish/chipseq/ATAC/WSI): jobs sit **RUNNABLE→STARTING for
~2–4 min** (instance spin-up) + image pull before `RUNNING`. The WSI run was dispatched 16:12:50 and
didn't produce outputs until ~16:20 — most of that was cold-start + a 650 MB image pull, not compute.

Root cause: I set `biomate-nextflow-ce-v2 minvCpus=0` for the cost win (~$12/day saved). The tradeoff
is a cold start on the first job after idle. Levers, by impact:
1. **Warm pool** (biggest latency win; direct cost tradeoff): set `minvCpus` to keep 1 small node warm
   → near-instant starts, at ~$12/day. Pure cost-vs-latency decision — your call. (A middle ground:
   warm only during active hours via a scheduled min-vCPU bump.)
2. **Image pull time** (med effort): the cold node pulls the task image fresh (650 MB pathology,
   biocontainers). Options: pre-bake the common images into the Batch AMI (the launch template already
   pre-pulls the ECS agent — extend it), an **ECR pull-through cache / VPC endpoint** (faster in-region
   pulls), or slim the images.
3. **Spot** (built, dormant): a cost lever, NOT latency; and it adds reclaim risk. Leave as-is unless
   cost is the priority.

## Recommendation (ranked)
1. **Workflow latency:** decide the cold-start tradeoff — warm pool (`minvCpus≥1`, ~$12/day) for
   interactive speed, or keep min=0 for cost. This is the single biggest speed change and it's a
   business decision, not a code one.
2. **DB:** add the two indexes + connection PRAGMAs (free, low-risk; via the safe DB-update path).
3. **Search:** stop pulling `workflow_json` for every FTS candidate (lazy-load the chosen set).
4. Search dense/FTS internals are already optimized — leave them.

None of these are implemented yet — they're consequential (canonical DB / shared Batch CE / hot search
path), so flagging for a go-ahead before changing anything.

---

## VALIDATION (2026-10-05, deployed to dev + verified)

Validated each change on dev for correctness, no-new-errors, and actual benefit (the user asked —
rightly). Result: **2 of 3 kept, 1 reverted as ineffective.**

### ✅ DB indexes — VALIDATED, KEPT
Deployed to dev (DB synced, dev auto-backed-up). Verified on dev: `idx_wf_name_lower` +
`idx_wf_domain_exec` present, `integrity_check=ok`, 4210 rows, WSI row intact, and
`EXPLAIN QUERY PLAN` for `lower(name)=?` now shows **`SEARCH … USING INDEX idx_wf_name_lower`**
(was a full SCAN). Additive, result-identical, free. Kept.

### ✅ Search (workflow_json deferral + read PRAGMAs) — VALIDATED, KEPT
Exercised the **deployed** `UnifiedWorkflowSearch` in-container: `search("rnaseq differential
expression")` → top result **nf-core/rnaseq** (correct ranking), `workflow_json=None` on the hot path
(deferral works), and the `include_workflow_json=True` path **still returns the blob** (not broken).
Raw deployed FTS query with `NULL AS workflow_json` returns correct results for rnaseq/admet/nuclei
(0.2–1.2 ms), no SQL error. Dev Galaxy logs: **no new tracebacks/errors** since deploy. Result-identical
by construction (the blob was discarded to None on that path anyway). Kept.

### ❌ Batch warm pool (minvCpus=4) — VALIDATED AS INEFFECTIVE, REVERTED
The warm node that `minvCpus=4` keeps is an **m5.xlarge (4 vCPU / 16 GB)**, but a typical nextflow job
(merfish, `process_medium`) requests **6 vCPU / 36 GB** — it does NOT fit the warm node, so Batch
provisions a bigger instance anyway (observed: the test job sat RUNNABLE ~2 min while a new node spun
up; the warm node sat idle). So min=4 would waste ~$5/day without speeding typical jobs. **Reverted to
minvCpus=0.** Warm-start is memory-bound here (jobs need ~36 GB), so a *useful* warm node would be an
r5.2xlarge-class (8 vCPU / 64 GB), ~$12/day, and Batch's vCPU-only `minvCpus` doesn't cleanly guarantee
that RAM — making warm-pool an awkward, costly lever, not the clean win it looked like. Left OFF;
offered to the owner as a deliberate cost decision if interactive latency matters more than ~$12/day.

### Net
- **Kept (free, validated):** DB indexes + search deferral/PRAGMAs — correctness confirmed, no new
  errors, faster lookups/less I/O.
- **Reverted:** the warm pool (ineffective at min=4; the clean fix is costly + awkward).
- **Workflow cold-start** remains the real latency, but the better lever is image pre-caching
  (shrink STARTING→RUNNING pull time) rather than a memory-mismatched warm pool. Not pursued yet.

---

## QUANTIFIED SPEEDUP (measured 2026-10-05)

Honest numbers. The search/DB engine was already well-optimized, so those are modest free efficiency
wins; the large latency win is the (now correctly-sized) warm pool for workflow cold-start.

| Improvement | Before | After | Measured |
|---|---|---|---|
| **Workflow start — first job after idle** | ~200–320 s (cold: EC2 boot ~120–240 s + Batch scheduler ~30–60 s + image pull ~30–60 s) | **83 s** (warm r5.2xlarge, job fit → RUNNING) | **~2–4 min faster (~2.5–4×)**, measured end-to-end |
| Workflow start — warm node, image already cached | — | ~30–60 s (scheduler only) | floor = Batch scheduler latency |
| DB name-resolve (`lower(name)=?`, every run) | full SCAN (0.4 ms warm; **165 ms** cold multi-column text scan) | index SEARCH (~0 ms warm; **~1 ms** cold) — EXPLAIN-confirmed on dev | SCAN→SEARCH |
| DB domain filter | 3.4 ms | 1.7 ms | ~2× |
| Search per query (hot path) | reads + allocates ~6.5 KB × up to ~200 candidates (~up to 1.3 MB) | blob skipped (NULL) | reduced I/O/alloc (no isolated latency %) |

**Warm-pool config (the big win):** `biomate-nextflow-ce-v2` → instanceTypes **r5 family**
(r5.xlarge/2xlarge/4xlarge — memory-dense, fits the 12–36 GB jobs), **minvCpus=8** → one r5.2xlarge
(8 vCPU/64 GB) kept warm. Cost ≈ **$0.504/hr × 24 ≈ $12/day**. Only the first job after an idle period
benefits (~2–4 min saved); back-to-back jobs already reuse the node. The ~83 s floor (scheduler +
first image pull on a fresh node) is further reducible by **image pre-caching** (bake common images
into the AMI) — not done yet.

**Why min=4 failed earlier:** it kept a 4 vCPU/16 GB node; process_medium needs 6 vCPU/36 GB → didn't
fit → jobs cold-started anyway. Fixed by switching the CE to the r5 family (so minvCpus reliably keeps
a 64 GB node).

### Bottom line
- Biggest, measured win: **workflow cold-start ~2–4 min → 83 s** (first-after-idle), at ~$12/day.
- Free, verified wins: DB indexes (SCAN→SEARCH) + search blob-deferral/PRAGMAs — modest but safe.
- Next lever (not done): container image pre-caching to cut the ~83 s floor further.
