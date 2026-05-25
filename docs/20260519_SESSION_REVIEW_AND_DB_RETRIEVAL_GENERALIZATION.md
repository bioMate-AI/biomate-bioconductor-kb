# Session Review & DB-Based Retrieval — Generalization Opportunities

**Date:** 2026-05-19
**Status:** Strategic analysis. No code changes.
**Context:** Two layers of benchmark-driven retrieval improvements shipped this session (sandbox). User asked: *what experiences from this work can transfer to BioMate's broader DB-based information retrieval?*

---

## Part 1 — Review of session work

### What was built

| Layer | Sandbox | Data | Library | Lift | Tests |
|---|---|---|---|---|---|
| Wrapper-level | `sandbox/retrieval_v2/` | `tool_family_aliases.yaml` (155) + `tool_family_canonical.yaml` (60) | `family_dedup.py` | 25% → 90% top-1 canonical (n=40) | 29 |
| Workflow-level (reorder) | `sandbox/workflow_search_v2/` | `intent_anchors.yaml` (40) | `workflow_intent.py` | 64.5% → 70.3% top-1 (n=155) | 15 |
| Workflow-level (inject) | same | same | same lib, `inject_canonical=True` | 64.5% → **76.8%** top-1 (n=155) | 18 |

8 commits on `origin/integration/next-phase`. 47 tests passing. **Zero production consumers wired.**

### Lessons distilled (the transferable ones)

**1. Data beats schema for messy catalogs.**
The session started with a proposal to build a 3-level canonical-tools SQLite schema. After Phase 0 measurement, the data showed only 1.43× compression — schema work wasn't justified. A 155-line YAML did most of what schema migration would have done. *Generalization:* for any messy DB, before designing a new schema, measure what a curated mapping over the existing one achieves.

**2. Investigation gates building.**
The original wrapper-level proposal had "5 DESeq2 wrappers" as the headline duplication; the measurement showed DESeq2 wasn't even in the top-25 actual duplicates. The original workflow-level proposal led with "adjacency confusion (rnaseq vs scrnaseq)"; the categorization showed adjacency was 1.3% of failures. *Generalization:* spend 30 min running the existing benchmark and categorizing failures before building. The categorization is cheap insurance against building the wrong thing.

**3. Honest estimate-vs-actual calibration matters.**
| Stage | Estimate | Actual |
|---|---|---|
| Wrapper proposal | 10-25× compression | 1.43× |
| Workflow proposal | +10pp | — |
| Workflow categorization | +15.5pp | — |
| Workflow reorder only | — | +6.5pp |
| Workflow + injection | — | +12.3pp |
Each estimate was overconfident relative to the next measurement. *Generalization:* track estimate-vs-actual deliberately; each gap teaches what bias was in the prior model.

**4. Reorder has a hard ceiling. Injection breaks it.**
Reorder-only mode caps at "items in candidate list" — couldn't go past +6.5pp because 15% of workflows weren't in the FTS top-10 at all. Injection (synthesize a candidate when intent fires confidently) lifted to +12.3pp. *Generalization:* whenever a retrieval system has both a candidate-generation step and a re-ranking step, plan to augment BOTH layers. The candidate-generation gap is often invisible until you measure it.

**5. Confidence gates prevent false positives.**
The 4 wrong flips in pass 1 (workflow intent) all came from overly-eager trigger matches. Three guards closed them: trigger density ≥ 2, disqualifier lists, single-intent-must-fire. After tightening, 0 false positives across all passes including inject mode. *Generalization:* any "auto-promote" or "auto-inject" rule needs **explicit disqualifiers** more than it needs additional triggers. Negative knowledge is more valuable than positive knowledge.

**6. Sandbox-first respects production.**
The session deliberately kept everything in `sandbox/retrieval_v2/` and `sandbox/workflow_search_v2/`. When user reverted the early `tool_parameter_recommender.py` patch and `llm_client.py` env-flag, those were honored. When the library proved valuable, it was promoted only as opt-in (env flag). *Generalization:* for retrieval improvements, ship the library first (testable in isolation), then wire production consumers as a separate PR. Lower deploy risk, easier to revert, telemetry-friendly.

---

## Part 2 — Where these patterns apply to BioMate's broader DB-based tasks

### BioMate's DB API surface (what I've observed this session)

Multiple SQLite databases plus retrievers, all with the same broad shape: **natural-language user query → structured lookup → ranked results**. Concrete examples encountered:

| Resource | Used by | Current state |
|---|---|---|
| `galaxy_ai_tools.db` workflows table | `UnifiedWorkflowSearch.search` | FTS + BGE + LLM-rank — the layer we improved this session |
| `galaxy_ai_tools.db` tools table | `ToolParameterRecommender.search_tools` | FTS5 only (no BM25 column weights, no BGE) — the wrapper layer |
| `tool_compatibility`, `tool_usage_patterns` | tool recommender | direct SQL, no intent layer |
| `dataset_tool_mapping` | tool recommender's `_get_database_recommendations` | direct SQL keyed on `tool_id` |
| `chat_sessions`, `chat_messages` | chat history endpoints | direct SQL, time-ordered |
| Memory dir (`~/.claude/projects/.../memory/`) | auto-memory subsystem | file-based; MEMORY.md index loaded into prompt |
| Europe PMC live API | `europe_pmc_fulltext.py` (built this session) | keyword-overlap passage extraction |
| OMIM/MyGene/UniProt | `omim.py` (built this session) | direct REST + dedup |
| `tool_knowledge`, `cryo_em_chunks_vec` | cryo-EM RAG | sqlite-vec embeddings |
| `campaigns_registry.db`, `esig_global.db` | CRO compliance, regulatory | direct SQL keyed on user/campaign |
| `regulatory_skills.db` | regulatory LLM eval | direct SQL |
| `benchmark_knowledge.db` | benchmark scoring | direct SQL |

**Common pain points across these resources** (mirroring what we just fixed at the workflow layer):

1. **Natural-language queries don't map cleanly to structured fields.** "Show me the last RNA-seq run" requires intent classification before the DB lookup knows which `chat_sessions.id` to look at.
2. **FTS / keyword search returns the wrong granularity.** This session's wrapper work: user types "samtools", FTS returns `clc_assembly_cell`. The same failure mode exists in any DB whose `description` column is long enough to drown out short-name matches.
3. **Canonical entities aren't surfaced.** The user wants "the BRCA1 OMIM entry" but the search returns 5 secondary references that mention BRCA1.
4. **No confidence gating on automatic actions.** If memory recall, auto-resume, etc. fire when the user query is ambiguous, it produces silent errors.
5. **Each retriever reinvents the wheel.** Europe PMC, OMIM, tool recommender, chat history search — each has its own scoring, no shared confidence/disqualifier logic.

---

## Part 3 — Concrete opportunities to transfer the pattern

Five high-leverage DB-retrieval tasks where the same architecture (curated intent YAML + pure-function reranker/injector + confidence gates) would deliver real value. Listed in order of estimated impact-per-effort.

### Opportunity 1 — Memory recall ranking (~1 day)

**Today:** Auto-memory dumps `MEMORY.md` index (1084 lines, 113.8KB, truncated past line 200) into every conversation. The LLM has to scan it linearly to find relevant entries. When the user asks "what did we discuss about cryo-EM benchmarks last week," memory recall is "all memory files matching loose keywords."

**Pattern transfer:**
- `memory_intent.yaml` — curated intent map: `{intent: "benchmark_status", trigger_terms: ["benchmark results", "current scores", "where are we on"], canonical_files: ["20260518_PHASE1_AB_RESULTS.md", "20260518_SESSION_FINAL.md"]}`.
- `prioritize_memory_by_intent(query, candidate_files)` reorders/injects from this map before the LLM sees the candidate list.
- Confidence-gated: only fires when ≥ 2 trigger terms match. Otherwise falls through to existing fuzzy match.

**Why this works:** memory is messy in exactly the way `tools_fts` was messy. The MEMORY.md index is 113KB of unstructured pointers; a 5KB YAML of intent → top-3-files mapping would let the right memory surface for the right query without spamming the whole index.

**Effort:** ~1 day curation + library + tests. Already have `family_dedup`-style scaffold to adapt.

### Opportunity 2 — Chat session resume (~half day)

**Today:** `currentChatSession` resolution via localStorage + remount logic in `chat-with-artifacts.tsx`. When the session lookup misses, the user lands on the welcome screen instead of their in-progress run.

**Pattern transfer:**
- Not really a YAML problem — but the same **confidence gate** pattern applies. Instead of always restoring the last session, fire restore only when (a) `invocationId` is terminal-state AND (b) session age < N minutes AND (c) query intent matches "resume" (not "new conversation").
- Disqualifier list: queries like "start fresh", "new project", "clear" should block restore.

**Effort:** ~half day, mostly UX testing.

### Opportunity 3 — Tool parameter recommendation by intent (~1.5 days)

**Today:** `ToolParameterRecommender.recommend_parameters` returns whatever the `dataset_tool_mapping` table has for a given `tool_id`. No query-level customization — "give me high-throughput ADMET screening params" returns the same as "give me regulatory-grade ADMET params" because both resolve to the same `tool_id`.

**Pattern transfer:**
- `param_intent.yaml` — `{intent: "admet_regulatory_grade", trigger_terms: ["ind-ready", "regulatory submission", "fda-grade"], canonical_preset: {temperature: 0, ensemble_size: 100, ...}}`.
- Library applies param-preset injection when intent fires confidently.

**Effort:** ~1.5 days including the preset curation per intent.

### Opportunity 4 — Biological-entity canonical resolution (~1 day)

**Today:** Gene/disease/compound lookups in chat use whatever the LLM hallucinates as the entity. "ARL6IP1" might be confused with similar-spelled genes; "BRCA1" might be looked up under "BRCA-1" or "BRCA 1".

**Pattern transfer:**
- `entity_canonical.yaml` — maps fuzzy variants to canonical IDs: `{HGNC: "BRCA1", aliases: ["brca1", "brca-1", "brca 1", "RNF53"]}`.
- Library normalizes user query entities before invoking OMIM/MyGene retrievers — preventing wasted API calls and surfacing the right entry.

**Effort:** ~1 day if curated from existing HGNC/OMIM crosswalk; ~3 days if generated from scratch.

### Opportunity 5 — Regulatory / compliance question router (~2 days)

**Today:** Regulatory questions ("is this CMC requirement applicable to my IND?") go through general LLM chat. No structured retrieval against `regulatory_skills.db` or `esig_global.db`.

**Pattern transfer:**
- `regulatory_intent.yaml` — maps natural-language regulatory questions to specific table/row lookups: `{intent: "ind_cmc_module_3", trigger_terms: ["module 3", "drug substance", "manufacturing"], db: "regulatory_skills.db", query_template: "SELECT ... WHERE module=3"}`.
- Library executes the parametrized lookup, injects the canonical regulatory snippet into the LLM context.

**Effort:** ~2 days due to careful query-template curation (regulatory answers must be auditable).

---

## Part 4 — Proposed shared library: `backend/lib/galaxy/ai/intent_retrieval/`

Instead of growing 5 parallel sandboxes, the natural consolidation is a single intent-retrieval framework with per-domain YAMLs:

```
backend/lib/galaxy/ai/intent_retrieval/
├── __init__.py
├── core.py                    # generic infer_target_intent, prioritize, inject helpers
├── adapters/                  # per-domain wrappers
│   ├── workflow.py            # wraps prioritize_workflow_by_intent
│   ├── memory.py              # memory recall ranking
│   ├── parameters.py          # param preset injection
│   ├── entity.py              # canonical entity resolution
│   └── regulatory.py          # regulatory question routing
└── data/
    ├── workflow_intents.yaml  # promoted from sandbox/workflow_search_v2/data/
    ├── memory_intents.yaml
    ├── param_intents.yaml
    ├── entity_canonicals.yaml
    └── regulatory_intents.yaml
```

**Common contract for every adapter:**

```python
def prioritize(query: str, candidates: list, *, inject: bool = False) -> list:
    """Reorder/inject candidates per the domain's intent map.
    Returns a new list; never mutates input. Honors per-domain env flags."""
```

Shared `core.py` provides:
- `load_intents(yaml_path)` — cached YAML loader with chain/cycle resolution (reused from `family_dedup`)
- `infer_target_intent(query, intents)` — confidence-gated match
- `_intent_matches`, `_has_pipeline_intent` — reusable
- `prioritize_candidates(query, candidates, intents, *, inject_synthesizer=None)` — the core algorithm

Each adapter is ~30 lines wrapping `core.prioritize_candidates` with domain-specific candidate types.

**Estimated effort to lift the framework:** ~2 days (mostly factoring; the algorithms exist in `family_dedup.py` + `workflow_intent.py`).

---

## Part 5 — What's NOT proposed

- ❌ A unified-DB ORM or schema migration. Each DB stays as-is. The intent layer is additive.
- ❌ Replacing existing retrievers (Europe PMC, OMIM, etc.). They become consumers of the framework, not replacements.
- ❌ A "smart" intent inference using ML. Curated YAMLs over LLM-classified intents — for the same reasons curated alias YAMLs beat schema migrations.
- ❌ Wiring everything in one PR. Each adapter ships separately, behind its own env flag, with its own A/B against an existing benchmark or curated eval set.

---

## Part 6 — Recommended next-step menu

Pick one (or none — review first):

**A. Lift the shared framework first (2 days, foundation).** Refactor `family_dedup.py` + `workflow_intent.py` into `backend/lib/galaxy/ai/intent_retrieval/{core,adapters/workflow}.py`. No production consumers wired. Provides scaffolding for opportunities 1-5 to plug into. Highest leverage if we plan to do ≥ 2 of the opportunities.

**B. Pick the highest-impact opportunity directly (varies, 0.5-2 days each).** Build Opportunity 1 (memory recall) or 3 (param recommendation) in its own sandbox, mirroring the workflow_search_v2 structure. Faster to ship; less code reuse.

**C. Wire one library to production behind feature flag (~half day).** Take the existing `family_dedup` or `workflow_intent`, ship a 5-line patch in `ai_assistant.py` behind `BIOMATE_FAMILY_DEDUP=1` / `BIOMATE_WORKFLOW_INTENT_PRIORITIZE=1`. Gather real-user telemetry before further library work.

**D. Investigation step on one of the opportunities (30 min each).** Run a sample query against memory recall today vs simulated YAML-injected; categorize where memory currently fails. Same investigation-first discipline that's worked twice this session.

**E. Stop — let the user review the session's commits + this proposal.**

My recommendation: **A then B**. The framework lift (~2 days) makes every subsequent opportunity ~half-day instead of ~1-2 days; pays for itself by the 3rd opportunity. If only one opportunity will be done, go straight to **B** with Opportunity 1 (memory recall) — biggest user-facing improvement of the five.
