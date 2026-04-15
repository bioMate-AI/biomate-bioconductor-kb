# Candidate Pickup Plan & Evaluation Plan
# Routing — Disambiguation — Workflow Generation

**Date:** 2026-04-15  
**Author:** BioMate Engineering

---

## Part 1 — Candidate Pickup Plan

### 1.1 What is "candidate pickup"?

Candidate pickup is the process by which BioMate assembles the set of workflows shown to the user when the routing system cannot commit to a single answer with high confidence. It spans three stages: search, scoring, and the disambiguation gate.

---

### 1.2 Stage 1: Multi-Signal Search

Every user query goes through `UnifiedWorkflowSearch.search()`, which scores each workflow in the database against the query using six independent signals:

| Signal | Weight | What it captures |
|---|---|---|
| BM25 FTS (full-text search) | 30% | Token overlap against indexed name + description + tags |
| Keyword matching | 25% | Exact matches of biologically meaningful terms |
| Key-phrase matching | 25% | Longer phrases (e.g. "variant calling", "differential abundance") |
| Name overlap | 15% | Similarity between query tokens and workflow name tokens |
| Source priority | 7% | nf-core (100) > biomni_nextflow (85) > bioconductor (75) |
| Domain bias | 5% | Bonus if workflow domain matches the detected query domain |
| Input type | 3% | Small bonus if query input format matches workflow expected input |

These signals are summed into a raw score. The score thresholds are:

```
score ≥ 12.0  →  high_confidence   (system can commit without user input)
score ≥  6.0  →  medium_confidence (plausible match; may need disambiguation)
score <  6.0  →  low_confidence    (weak match; fallback to generation)
```

The search returns up to 5 ranked results per query. The Step 0 chain search runs first (cosine similarity ≥ 0.42, then LLM scope check) and bypasses single-workflow search when a chain matches.

---

### 1.3 Stage 2: Disambiguation Gate

After iterative search trials complete, before committing to any single workflow:

```python
_DISAMBIG_MIN_SCORE     = 6.0   # minimum score to be a "plausible" candidate
_DISAMBIG_GAP_THRESHOLD = 3.0   # max acceptable gap between #1 and #2

plausible = [r for r in search_results if r.score >= _DISAMBIG_MIN_SCORE]

trigger = (
    match_type != 'high_confidence'         # top score < 12.0
    and len(plausible) >= 2                 # at least 2 plausible candidates
    and (plausible[0].score - plausible[1].score) < _DISAMBIG_GAP_THRESHOLD
)
```

**When the gate fires:**
- Returns `workflow_type = 'disambiguation'` with candidate list
- Does NOT launch any workflow
- Does NOT call the LLM for generation

**When the gate does NOT fire (normal path continues):**
- `high_confidence` single match → immediate workflow panel
- Only 1 result above 6.0 → immediate workflow panel (clear winner by absence of competition)
- Gap ≥ 3.0 → immediate workflow panel (score gap is large enough to trust #1)
- Chain match found (Step 0) → chain plan shown directly (chains have their own LLM clarification path)

---

### 1.4 Stage 3: Candidate List Assembly

When the gate fires, up to **4 candidates** are assembled from the `plausible` list in rank order:

```python
{
    'name':         m.name,                        # canonical DB name (e.g. "nf-core/atacseq")
    'display_name': m.display_name or m.name,      # human-readable label
    'description':  (m.description or '')[:220],   # truncated to 220 chars
    'source':       m.source,                      # "nfcore", "biomni_nextflow", "bioconductor", etc.
    'format':       m.format,                      # "nextflow", "bioconductor_nf", etc.
    'score':        round(m.score, 2),             # raw score for transparency / debug
}
```

**Why max 4?**  
Cognitive load. More than 4 options in a quick-pick UI stops being a disambiguation and becomes a search UI — which defeats the purpose. If we have > 4 plausible candidates within the gap threshold, the query is genuinely underspecified and the user should narrow it in a follow-up question (handled via the LLM clarification path, not disambiguation).

**Candidate ordering:**  
Strictly by score descending. Source priority is already baked into the score, so nf-core workflows naturally appear before Bioconductor equivalents for the same query.

---

### 1.5 Stage 4: Selection and Second-Turn Routing

The frontend card (`WorkflowDisambiguationCard`) renders each candidate. When the user clicks:

```typescript
onAdjustViaChat?.(`I want to use ${c.display_name}`)
```

This re-enters the chat pipeline with an explicit workflow name. The name uniquely identifies the workflow in the DB, so the second turn:
1. Returns `match_type = 'high_confidence'` (the name appears in the query → near-perfect name-overlap score)
2. Bypasses the disambiguation gate (gap condition not evaluated when score ≥ 12.0)
3. Returns the full workflow panel immediately

**Edge case:** If the user types a free-form response instead of clicking a card (e.g. "the second one"), the LLM clarification path handles it via the regular conversation flow.

---

### 1.6 Threshold Calibration Rationale

The thresholds were calibrated empirically from the 120-query routing benchmark:

| Scenario | Typical score range | Decision |
|---|---|---|
| Clear nf-core match (rnaseq, sarek) | 14–22 | high_confidence; no gate |
| Strong match, minor overlap uncertainty | 8–13 | medium_confidence; gate evaluates gap |
| Two similarly-named workflows for same protocol | 7–10 each, gap 0.5–2.5 | gate fires → disambiguation |
| Weak match, Bioconductor package | 4–7 | below plausible threshold; no disambiguation |
| No match | < 4 | generation path |

The `_DISAMBIG_GAP_THRESHOLD = 3.0` was chosen because:
- Gaps < 3.0 correspond to cases where either workflow would be a valid answer (atacseq vs chipseq for "peak calling")
- Gaps > 3.0 correspond to a clear #1 with a secondary option that's materially weaker

**Monitoring:** If disambiguation fires on > 30% of real user queries in production, the threshold is too permissive. If it fires on < 5%, it is likely too strict and ambiguous queries are silently misfiring.

---

## Part 2 — Evaluation Plan

The evaluation strategy has three tiers, matching the three system paths:

```
Query
  ├── Chain match        →  Tier A: Chain routing accuracy
  ├── Direct match       →  Tier B: Search IR metrics + chat E2E
  │     └── Ambiguous    →  Tier C: Disambiguation quality
  └── No match           →  Tier D: Generation quality
```

---

### Tier A: Chain Routing Accuracy

**What:** Curated multi-step pipelines in the `workflow_chains` table.

**Metric:** Precision (false positive rate). A chain is a false positive when it surfaces for a query asking for a single-workflow step.

**Current guardrails:**
- `min_score = 0.35` (Jaccard fallback raised from 0.15)
- `_CHAIN_REQUIRED_CONTEXT` gate for `rare_disease_multimodal_workup`
- `_chain_input_compatible()` pre-filter (rejects chains requiring processed inputs when user has FASTQ)

**Test dataset:** 20 adversarial chain queries in `evaluation/datasets/cross_domain_routing/queries.yaml` (items with `confusable_with` field pointing to a chain).

**Target:** False positive rate < 5% on adversarial set.

**Runner:** `python3 runners/run_routing.py --adversarial-only`

---

### Tier B: Direct Match — Search Layer (IR) + Chat E2E

**Purpose:** Measure the two independent quality axes of the direct-match path.

#### B1 — IR Metrics (search layer only)

**What:** Does the correct workflow appear in the ranked list, and at what position?

**Endpoint:** `POST /api/ai_assistant/search_ranked` → ranked list of up to 10 results

**Metrics:**

| Metric | Formula | Target |
|---|---|---|
| MRR | avg(1/rank of first correct result) | ≥ 0.85 |
| P@1 | fraction where correct is rank-1 | ≥ 0.75 |
| NDCG@3 | Σ(rel_i / log2(i+2)) / ideal_DCG, relevance binary | ≥ 0.90 |
| Hit@5 | fraction where correct is in top-5 | ≥ 0.95 |

**Baseline (2026-04-15, 120 queries):** MRR=0.847, P@1=0.742, NDCG@3=0.920, Hit@5=0.967

**Runner:** `python3 runners/run_routing.py --ir-mode --output results/routing_ir/`

**What IR metrics tell us:**
- Low MRR + high Hit@5 → correct answer is being buried at rank 3–5 (likely a description quality issue or scoring weight imbalance)
- Low Hit@5 → correct answer is genuinely missing from the search index (DB coverage gap or misclassification)
- Low P@1 + high MRR → correct answer at rank 2 often (disambiguation can surface it)

#### B2 — Chat E2E Accuracy

**What:** End-to-end — does the LLM pick the right workflow from the candidate list it receives?

**Metric:** Weighted accuracy: 1.0 = exact match, 0.5 = acceptable alternative, 0.0 = wrong/missing

**Baseline (pre-patch, v1):** 74% exact, mean=0.792  
**v3 (post-patch + principled fixes, 2026-04-15):** 78% exact, mean=0.825  
**Note:** Some v3 failures are disambiguation responses scored as 0.0 by the adapter (C1 fix recovers these)

**Target:** ≥ 80% exact, mean ≥ 0.850

**Runner:** `python3 runners/run_routing.py --output results/routing_chat/`

**Relationship between IR and Chat:**
- IR P@1 measures search; Chat P@1 measures search + LLM together
- If IR P@1 = 0.74 and Chat P@1 = 0.74, the LLM adds nothing (or hurts)
- If Chat P@1 > IR P@1, the LLM is recovering errors the search made (good)
- If Chat P@1 < IR P@1, the LLM is degrading correct results from search (bad — investigate prompting)

---

### Tier C: Disambiguation Quality

**Purpose:** Measure whether the disambiguation guardrail helps, hurts, or is neutral.

Three sub-questions:

#### C1 — Coverage: Is the correct answer in the candidate list?

When disambiguation fires, the user sees ≤ 4 candidates. If the correct answer is not in those 4, the guardrail has failed.

**Metric:** Candidate coverage = fraction of disambiguation events where correct_workflow ∈ candidates

**Target:** ≥ 95% (allowing ~5% for genuinely ambiguous cases where the correct answer was below plausible threshold)

**How to measure:** Run chat benchmark, extract all responses with `workflow_type = 'disambiguation'`, check whether `correct_workflow` appears in `candidates[*].name`.

**Runner:** Extend `routing_adapter.score()` to check candidates when `workflow_type = 'disambiguation'` — this is currently an open TODO.

#### C2 — Precision: Does disambiguation fire on the right queries?

**False positive:** Disambiguation fires but the correct answer was clearly #1 (should have been high_confidence).
**False negative:** Disambiguation should have fired but the system picked wrong silently.

**Metric:**
- False positive rate = fraction of disambiguation events where correct_workflow was already #1 by a large margin
- False negative rate = fraction of "wrong" chat results where the correct answer was in the top-3 search results (disambiguation would have surfaced it)

**How to measure:**
1. Run full chat benchmark
2. For each wrong answer (score=0.0), run `search_ranked` and check if correct_workflow was in the top-4
3. These are false negatives — the gate should have fired

**Target:** False negative rate < 20% (i.e., at most 1 in 5 routing errors is a case where disambiguation could have saved it)

#### C3 — Conversion: Does the second turn succeed?

After the user picks a candidate, the second-turn routing should return high-confidence.

**Metric:** Second-turn match success rate = fraction of disambiguation→selection→workflow-panel flows that complete successfully

**How to measure:** E2E Playwright test (see T5 in implementation doc). Send ambiguous query → click candidate card → verify workflow panel loads.

**Target:** 100% (the name is explicit; no reason for second-turn to fail unless the DB entry has a broken filename)

---

### Tier D: Workflow Generation Quality

**Applies when:** `match_type = 'no_match'` or score < 6.0 — the system generates a Nextflow workflow from scratch using the LLM.

This is the hardest path to evaluate because there is no single ground-truth workflow — the LLM produces novel compositions of tools.

#### D1 — Structural validity

**Metric:** Fraction of generated workflows that parse without Nextflow syntax errors

**How to measure:** `nextflow config <generated.nf>` exit code = 0

**Target:** ≥ 90%

#### D2 — Tool composition accuracy

**Metric:** Tool recall = fraction of expected tools present in generated workflow  
**Metric:** Tool precision = fraction of generated tools that are expected/relevant

These require a ground-truth tool set per query, which means hand-annotating a "generation benchmark" dataset.

**Proposed dataset:** 30 generation-only queries (queries where no nf-core or BioMate workflow directly matches), each with:
- The query text
- A list of expected tools (expert-annotated)
- A list of disqualified tools (tools that would indicate wrong domain)

**Labeling:** Each query is labeled by a bioinformatician reviewing the current nf-core catalog.

**Status:** Not yet built — this is the next milestone after disambiguation guardrail is stable.

#### D3 — LLM-as-Judge quality score

For each generated workflow + query pair, ask Claude (claude-haiku-4-5) to score 1–5 on:

| Criterion | Question |
|---|---|
| Goal alignment | "Does this workflow address the stated biological goal?" |
| Tool correctness | "Are the tools and their ordering correct for this analysis?" |
| Parameter validity | "Are the parameters biologically and technically valid?" |
| Output coverage | "Does the workflow produce the outputs the user needs?" |

**Score computation:** Mean of 4 criteria scores. Threshold: ≥ 3.5/5 = pass.

**Runner:** Add to `evaluation/runners/run_workflow_generation.py` (not yet implemented).

---

## Part 3 — Evaluation Roadmap

### Current state (2026-04-15, updated)

| Tier | Status | Score |
|---|---|---|
| A: Chain routing | Implemented, running in full benchmark | No dedicated metric yet |
| B1: IR metrics | Implemented + baseline collected | MRR=0.847, NDCG@3=0.920 (v1) |
| B2: Chat E2E | Implemented — **v5 benchmark complete** | **84% exact, mean=0.875** (target ≥80% ✓) |
| C1: Candidate coverage | **Implemented** — scorer checks `candidates[*].name` | Fires correctly for genuine ambiguity |
| C2: Disambiguation precision | Logic spec written; not yet implemented | Not measured |
| C3: Conversion rate | Not yet implemented (needs E2E test) | Not measured |
| D1: Structural validity | Not yet implemented | Not measured |
| D2: Tool composition | Dataset not yet built | Not measured |
| D3: LLM-as-judge | Not yet implemented | Not measured |

**Progress vs targets (v5):**
- B2 Chat E2E exact: **84%** ≥ 80% ✓ (was 74% at baseline, 78% v3)
- B2 Chat E2E mean: **0.875** — approaching 0.850 target (was 0.792 baseline)
- Variant calling domain: 0.567 — persistent weak point (routing to BioMate "Wgs Germline Gatk" instead of nf-core/sarek)

### Priority order for next sessions

1. **C1 first** — Update `routing_adapter.score()` to extract from `candidates[*].name` for disambiguation responses. This unlocks accurate chat-mode benchmark scores when the guardrail fires. (1–2 hours)

2. **C3 second** — Playwright E2E test for the full disambiguation→selection→workflow-panel flow. This validates the frontend card works end-to-end. (2–3 hours)

3. **D1 third** — Add Nextflow syntax validation to the generation runner. This is cheap and catches broken .nf files early. (1 hour)

4. **D2/D3 fourth** — Build the generation benchmark dataset + LLM-as-judge runner. This is the most expensive work (expert annotation + prompt engineering) but closes the biggest evaluation gap. (1–2 days)

5. **C2 last** — Implement false-negative detection. This requires correlating chat benchmark wrong answers with search_ranked results; straightforward but less critical than C1/C3. (2–3 hours)

---

## Part 4 — Metrics Dashboard Definition

The following metrics should be tracked on every benchmark run and trended over time:

```
┌─────────────────────────────────────────────────────────────────┐
│  BioMate Routing Quality Dashboard                               │
├─────────────────────────────────────────────────────────────────┤
│  Search Layer (IR mode)                                          │
│    MRR          target ≥ 0.85    baseline 0.847                  │
│    P@1          target ≥ 0.75    baseline 0.742                  │
│    NDCG@3       target ≥ 0.90    baseline 0.920  ✓               │
│    Hit@5        target ≥ 0.95    baseline 0.967  ✓               │
├─────────────────────────────────────────────────────────────────┤
│  End-to-End (Chat mode)                                          │
│    Exact (P@1)  target ≥ 0.80    v3=0.783  (baseline 0.740)      │
│    Mean score   target ≥ 0.85    v3=0.825  (baseline 0.792)      │
│    Weak domains: variant_calling (0.618), epigenomics (0.676)    │
├─────────────────────────────────────────────────────────────────┤
│  Disambiguation (C1–C3) — not yet measured                       │
│    Candidate coverage  target ≥ 0.95                             │
│    False negative rate target < 0.20                             │
│    Conversion rate     target = 1.00                             │
├─────────────────────────────────────────────────────────────────┤
│  Generation (D1–D3) — not yet measured                           │
│    Structural validity target ≥ 0.90                             │
│    Tool recall         target ≥ 0.80                             │
│    LLM judge score     target ≥ 3.5/5                            │
└─────────────────────────────────────────────────────────────────┘
```

All metrics should be stored in `evaluation/results/` and versioned by date so regressions are detectable across sessions.
