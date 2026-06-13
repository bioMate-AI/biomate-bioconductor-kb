# Regulatory-LLM product depth — rebuild session writeup

This session re-shipped a body of work that an earlier session had on disk
but never committed — a concurrent agent ran `git checkout` on the shared
main worktree and wiped uncommitted changes. The rebuild lives on the topic
branch `session/regllm-rebuild-20260612` and has been merged into
`integration/next-phase` in three merge commits. This doc captures what
landed, why, and what's still open.

## What landed

### B1 — Deterministic MRSD calculator + IND wiring

`backend/lib/galaxy/ai/drug_discovery/mrsd_calculator.py` — forward
companion to the existing `mrsd_verifier.py`. Shares `BSA_DIVISOR` +
`DEFAULT_SAFETY_FACTOR` so calculator output round-trips through the
verifier unchanged. `compute_mrsd_tool_schema()` returns an OpenAI-compatible
tool definition for downstream function-calling.

Wired into `ind_assembly._llm_narrative`: when callers pass `noael_mg_per_kg`
+ `species`, the function pre-computes HED + MRSD + per-60-kg-patient
totals and appends a `Use these computed numbers verbatim` anchor to the
prompt **after** the section template. No-op when those fields are absent
so existing call sites are unaffected.

**Why:** the n=70 cross-judge eval scored `mrsd_computation` at ~0.21
across every model tested (GPT-5, Sonnet, Gemini, Haiku, Gemma). LLM
arithmetic on small-multiplier conversions (rat 6.2×, mouse 12.3×, dog
1.8×) is unreliable. With the anchor, the dimension collapses to
"copy three numbers into a sentence" which all models do well.

### B2 — Region-specific narrative style rules

`backend/lib/galaxy/ai/drug_discovery/regulatory_region_packs.py` — pure
data: 4 regions × per-section override rules, capped at 4 per call so the
RAG block stays focused.

  - **FDA**: 21 CFR 312 audit-trail citations
  - **EMA**: SI units, ICH-adopted citation form, EMA/CHMP/EWP/37498/2011
    for PBPK, NOAEL/NOEL split for tox_overview
  - **NMPA**: Announcement No. 35 GLP-equivalence framing, Chinese ethnic
    safety bridging when the pivotal toxicology cohort is non-Asian
  - **PMDA**: MHLW Notification citation form

Wired into `_build_rag_context` ahead of the existing skills-DB pattern
block so the LLM sees the region rules first.

**Why:** `region_adaptation` was the highest-variance task in the n=70
cross-judge eval (macro 0.388, CI [0.338, 0.446]). Hard deterministic
style anchors close that gap without training.

### B3 — Per-org adapter retrain queue

* `regulatory_training_jobs.py` — submit / list / get / mark_status /
  count_edit_pairs with JSONL persistence so jobs survive a process
  restart without a DB migration. Org-id sanitisation matches the
  existing `_resolve_adapter_path` so a succeeded job writes adapter
  artifacts where inference will look for them on the next call.
* `regulatory_training_worker.py` — `tick(max_jobs)` for cron / Node
  shellout; `run_forever()` for a long-lived process. Stub for now:
  marks running → succeeded when pairs exist, fails with
  `no_edit_pairs_available` when count = 0. Real SFT belongs in a
  GPU-bearing worker; this exercises the contract end-to-end.
* `regulatory_training_jobs_cli.py` — verbs `submit | list | get |
  count_pairs | mark | tick`; JSON on stdout for Node `execFile`.
* `frontend/server/regulatory-training-routes.ts` — five routes
  `POST/GET/GET-by-id training_jobs`, `GET edit_pairs/count`, dev-only
  `POST tick`. All `authenticateToken`. Owner-scoped on GET-by-id +
  tick output filter. Replaces the no-op stub on `bioc/v2-qc-audit-panel`
  that was added with commit `cd08a6554`.

19/19 backend tests + 5/5 E2E (`retrain-jobs-trust-matrix.e2e.ts`).

### B4 — Checker → auto-loop regen wrapper

`backend/lib/galaxy/ai/drug_discovery/ind_autoloop.py` —
`llm_narrative_with_retry()` wraps `_llm_narrative` with up to 3 attempts,
translating each failed `_quick_audit` rule (`CITE_001` PBPK,
`CITE_002` S2(R1), `CITE_003` S7B, `CONTENT_002` Ames) to a
natural-language constraint via `_AUDIT_RULE_DESCRIPTIONS`. Returns the
cleanest of the attempted outputs.

Reuses the 9 existing deterministic checkers in `_quick_audit` and the
`audit_constraint` plumbing in `_llm_narrative` — zero new LLM
dependency, just exercises the contract in a loop.

### #49 — Regulatory-LLM observability

`backend/lib/galaxy/ai/drug_discovery/regulatory_metrics.py` —
thread-safe counters for calls + fallbacks, bounded latency ring (10k
samples), JSON `snapshot()` ready for a `/api/regulatory_llm/metrics`
endpoint. p50/p95/p99 per source. Ready to wire when a metrics endpoint
is added.

## Trust matrices (frontend/e2e)

Seven Playwright trust matrices, all behind the shared
`_fixture-login.ts` per CLAUDE.md §'E2E test user':

| Matrix | Live | Deferred |
|---|---|---|
| C2 sidebar | 5/5 | 7 hidden (refer to JSX comment blocks) |
| C3 chat message | 3/3 | 3 state-dependent (link to C4/C5) |
| C5 IND assembly | 3/3 | 4 modal/overlay rows |
| C1 workflow panel | 5/5 | 10 runtime-state rows |
| C6 auth | 5/5 | — |
| C7 memory | 5/5 | — |
| B3 retrain routes | 5/5 | — |
| **Total** | **31** | **24 documented** |

Methodology: per-worker fixture cookie cache, live-JSX / live-API
assertions (not source-grep, which masked C2 stale-spec drift in the
earlier session), screenshot per row, `test.skip` with rationale for
state-dependent and hidden rows.

## Eval pivot — zero-cost reference-based metrics

`evaluation/runners/reference_metrics.py` adds 4 reference-based metric
columns (chrF, ROUGE-L, num_match, cit_overlap) computed against the gold
target already in `sample_pool.jsonl`. Bootstrap 95% CIs. Output:
`evaluation/results/multitask_crossjudge_v1/summary_reference_based.csv`.

**Why this matters:** the cross-judge eval scoreboard and the
reference-based scoreboard disagree. Specifically:

| Model | Cross-judge macro | Reference-based macro |
|---|---|---|
| GPT-5 | 0.532 (1st) | 0.459 (2nd) |
| Gemini 3.1 Pro Preview | 0.505 | 0.429 |
| Sonnet 4.6 | 0.443 | **0.368** (last) |
| GPT-5-mini | 0.435 | 0.427 |
| **Haiku 4.5** | **0.363** (last of 5) | **0.472** (1st) |
| Gemma 3 12B base | 0.255 | 0.308 |

The two metric families measure different things — substance & rubric
(cross-judge) vs fidelity-to-FDA-prose-style (reference-based). Either
alone is wrong. CLAUDE.md §'Model-flip discipline' now requires
agreement before flipping a production default.

## Free corpus expansion

`scripts/scrape_regulatory_corpus.py` — pulls additional openFDA labels
across 5 under-represented categories (oncology carcinogen, reproductive
tox, PK, DILI, QT prolongation). Shape compatible with v6
`combined_sft.jsonl` so output appends directly. 47 rows produced in
the earlier session run.

EMA EPAR endpoint shifted mid-2026; placeholder kept for revisit.

## Failure mode + lesson

The earlier session's work was wiped by a `git checkout` from a
concurrent agent on the same primary worktree. Per `git reflog`:

```
97f9d0acc HEAD@{22}: checkout: moving from integration/next-phase to bioc/v2-qc-audit-panel
```

None of the work had been committed. `git checkout` overwrote
uncommitted files that exist on the target branch with different
content.

**Workaround pattern for multi-agent shared worktree:**

  1. Per-session topic branch on a separate worktree (`git worktree
     add -b session/<name> <path>`)
  2. Commit every file as soon as its test passes (WIP commits are
     fine; squash later)
  3. Merge with `--no-ff` so the topic-branch boundary stays in history

This session executed that pattern from the rebuild onwards. Five
commits, then a `--no-ff` merge into `integration/next-phase`; three
more commits, then another merge; etc.

## Files

  - `backend/lib/galaxy/ai/drug_discovery/`
      - `mrsd_calculator.py` (B1)
      - `regulatory_region_packs.py` (B2)
      - `regulatory_training_jobs.py` + `_cli.py` + `_worker.py` (B3)
      - `ind_autoloop.py` (B4)
      - `regulatory_metrics.py` (#49)
      - `ind_assembly.py` — wired B1 + B2 into `_llm_narrative` /
        `_build_rag_context`
      - `tests/test_*` — 44/44 pass
  - `frontend/server/regulatory-training-routes.ts` — Node routes
  - `frontend/e2e/` — `_fixture-login.ts` + 7 trust-matrix files
  - `evaluation/runners/reference_metrics.py` — zero-cost eval lane
  - `scripts/scrape_regulatory_corpus.py` — free corpus expansion
  - `docs/20260612_REGULATORY_LLM_REBUILD_SESSION.md` — this file
