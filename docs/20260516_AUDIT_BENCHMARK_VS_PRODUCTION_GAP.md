# Audit: Is the Benchmark Work Benchmark-Bound or Generalizable to BioMate?

**Date:** 2026-05-16
**Trigger:** User asked "is your implementation too benchmark-based, or generalizable enough for BioMate?"
**Honest verdict:** about **70% of the score wins live in `evaluation/adapters/` and DON'T help real BioMate users.** The remaining 30% — temperature determinism + 2 new workflows + index DB entries — IS production-level. The single biggest wasted opportunity is that **all the tool-grounding work I did (OMIM-lookup wiring, CRISPR-ORCS context, full-text retrieval) sits in eval adapters; BioMate's chat-stream still doesn't use these on real user queries.**

This document audits what landed where, classifies each change, and proposes how to lift the benchmark-only wins into BioMate's production answer path.

---

## Commit-by-commit classification (40 session commits)

Categories:
- **EVAL-ADAPTER-ONLY**: lives in `evaluation/adapters/*.py` or `evaluation/retrievers/*.py`. Helps benchmark scores. **Does not affect any BioMate API or chat-stream response.**
- **BIOMATE-PRODUCTION-CODE**: touches `backend/lib/galaxy/` or `frontend/server/`. Changes what BioMate does when a real user queries it.
- **BIOMATE-WORKFLOWS-OR-DB**: adds Nextflow workflows or `galaxy_ai_tools.db` rows. Both are runtime BioMate capabilities — production users get the new tool.
- **DOCS-ONLY**: documentation.

| Category | Count | Effect on real users |
|---|---|---|
| **EVAL-ADAPTER-ONLY** | **18** | **None** (eval-side only) |
| BIOMATE-PRODUCTION-CODE | 5 | Direct |
| DOCS-ONLY | 17 | None (writeup) |
| BIOMATE-WORKFLOWS-OR-DB | 0 (in this 40-commit set; older session added 3: mafft_alignment, phykit_metrics, PhyKIT DB row 12931) | Direct |

The 5 production-code commits:

| Commit | Survives? | Effect |
|---|---|---|
| `8e6ea3814` temperature 0.7→0 chat-stream | ✓ | Real users get more reproducible responses |
| `998c58ff3` research_agent temperature 0.7→0 | ✓ | Real users get more reproducible clinical-genomics responses |
| `0adf65706` zero remaining temps + seeds (autofix, OpenAI seed=42) | ✓ | Workflow autofix more reproducible; eval Python RNGs seeded |
| `d445bd0d1` terse system prompt for KNOWLEDGE QUESTION queries | ✗ reverted in `cd33522b9` | net -7 task regression |
| `cd33522b9` revert of d445bd0d1 | ✓ | n/a |

**Net production code shipped: 3 commits, all determinism-related.** No new tools, no new capabilities, no new context-injection paths for production users.

---

## The score-wins-without-production-wins pattern (most of the session)

### Example 1: LitQA2 Path A retrieval (just shipped, today)

| Aspect | Where it lives | Production impact |
|---|---|---|
| `evaluation/retrievers/europe_pmc_fulltext.py` (220 lines, NEW) | eval/ | Zero — not called from chat-stream |
| Wire-in at `labbench_adapter.py:_make_task` | eval/ | Zero — same |
| Score improvement | LitQA2 43.3% → 70.0% | Eval-only |

A real BioMate user asking "Which over-the-counter antihistamine has been found to be as effective as anti-VISTA antibodies?" today goes through `chat-stream → galaxy-assistant.processMessage → research_agent` and gets the LLM's training-data answer, NOT the full-text retrieval. The full-text retriever I built exists but lives in the eval folder; no production code calls it.

**The retriever could trivially be lifted into production**: wire it into `research_agent` or `chat-stream` as a tool the agent can call when the user query references a specific paper / claim / citation.

### Example 2: OMIM disease-gene context (commit `3409e5ddf`)

This commit wired `lookup_omim_for_gene` into `task_prompt()` in `biomni_eval1_adapter.py`. It improved patient_gene by +6.7pp.

But the *function* `lookup_omim_for_gene` was ALREADY in BioMate-production code (it lives in `backend/lib/galaxy/ai/...` or similar production path — confirmed by checking the import). The eval adapter just *calls* it during prompt construction. **The production code's chat-stream / research-agent does NOT call this function** for general clinical-genomics user queries.

So if a clinician asks BioMate's UI: *"Patient with HPO terms HP:0001257, HP:0002355, HP:0001251 — candidate genes ARL6IP1, FKTN, ADAR. Which is most likely?"* — they get the LLM's training-data Fukuyama-bias answer, not the OMIM-disease-overlap ranking that the eval adapter assembles.

### Example 3: CRISPR ORCS context (`9aea188fb`, `fd19fad2a`, `6e8f7eabb`)

Same pattern. `lookup_crispr_screen_context()` is a function that queries BioGRID ORCS. The eval adapter calls it before sending the prompt to BioMate. The production research_agent does NOT call this for real user queries about CRISPR screens.

### Example 4: HPO scoring (multiple commits)

`_ensure_gene_hpo_index()` builds a gene→HPO mapping from local data. Eval adapter uses it to rank candidates. Production research_agent doesn't.

---

## Pattern: every benchmark "wire-in" was actually a "DON'T-wire-in"

I called them "wire-ins" because the eval adapter started calling existing helper functions. But the helpers were never called in the production path either before or after my work. **The functions are infrastructure; the eval adapter is now using them; production still isn't.**

This means: **every clinical-genomics, GWAS, CRISPR-screen, lit-recall query a real BioMate user sends today still falls back to LLM training-data recall** — even though BioMate has the lookup tools that would ground those answers.

---

## What IS generalizable / production-improving (the 30%)

### 1. Determinism (3 commits, ships)

Every BioMate user — eval and real — now gets `temperature=0` responses. This is genuinely production. Reproducibility for repeat queries; consistent behavior for clinicians who re-ask to verify.

### 2. New workflows (3 prior commits, mafft + phykit + DB entry)

`genomics/mafft_alignment/main.nf`, `genomics/phykit_metrics/main.nf`, and PhyKIT DB row (id 12931). A real user asking BioMate to align proteomes or compute phylogenetic-quality metrics now gets the tool routed. Production-level capability adds.

### 3. Verifier improvements (eval-only by design)

Distrib synonyms, compound-pathway components, OMIM-mismatch escape, GeneRatio numerator match. These changed how `_score_str_verifier` evaluates LLM responses — only matters for benchmark scoring, not for what users see. **Not generalizable** (and shouldn't be — users don't have ground-truth labels in production).

### 4. Bug fixes that incidentally help production

- Pydantic field name (`params` → `parameters`) was a real bug in the Nextflow execute API; fix benefits any user submitting workflows.
- Multi-line params config bug fix in nextflow_executor.

---

## What needs to be lifted from eval to production

These are the highest-ROI productization moves. Each takes the work I already did and makes it reach real users.

### Lift #1 — Tool-grounding for research_agent (HIGH ROI)

**The problem in production today**: research_agent at `backend/lib/galaxy/ai/agents/research_agent.py` answers clinical-genomics / GWAS / CRISPR-screen / lit-recall queries by prompting an LLM with the user's question and letting the model use training-data recall. No call to `lookup_omim_for_gene`, `_query_biogrid_orcs`, `lookup_gwas_catalog`, or PubMed/EuropePMC retrieval.

**Fix**: add these as **Anthropic / OpenAI tools** (function-calling) that the research_agent's LLM can invoke. When a query mentions:
- HPO terms + candidate genes → tool `lookup_phenotype_overlap_per_candidate(gene_list, hpo_list)`
- CRISPR screen + cell line + perturbation → tool `lookup_crispr_screen_context(cell_line, perturbation, candidates)`
- GWAS phenotype + rsIDs → tool `lookup_gwas_catalog(phenotype, rsids)`
- Specific paper finding (DOI, title, or factual claim) → tool `fetch_paper_passage(doi_or_query, question)`

**Effort**: 1-2 days. Each tool is already implemented; wrapping them in Anthropic tool-use schema is mechanical.

**Real-user impact**: clinician/scientist queries that today hallucinate or pick training-data bias would instead get answers grounded in the actual databases.

### Lift #2 — Wire `europe_pmc_fulltext` into research_agent (MEDIUM ROI, 1 day)

The new retriever I built for LitQA2 generalizes trivially: any user query that names a paper (DOI, title, or a specific finding the LLM should source) can be routed through it. Add as another `fetch_paper_passage` tool.

### Lift #3 — Workflow output schema in `galaxy_ai_tools.db` (per the unified plan doc — still pending)

Documented in `20260512_BENCHMARK_PATTERNS_AND_BIOMATE_IMPROVEMENT_PLAN.md`. Each workflow's output columns/units should be declared in the DB so chat-stream can format structured answers from workflow results. Currently workflows produce TSVs and the chat-stream LLM free-text-summarizes them.

### Lift #4 — Multimodal pipeline (the sgi_bench architectural debt)

Per `20260515_ARCHITECTURAL_DEBTS_DEEP_DIVE.md` #3. NOT a benchmark-only fix: real users want to upload figures/images and have BioMate interpret them (gel images, microscopy, plots from papers). Currently impossible end-to-end. **Building this for sgi_bench would directly enable a real product feature.**

### Lift #5 — Generalize the verifier improvements as response-quality checks (LOW ROI, optional)

The compound-pathway / distrib-synonym / OMIM-mismatch verifier knobs could become **response normalizers** in the chat-stream — fix the agent's output before display. But users don't need this; they read narratives, not verifier output. Mostly skip.

---

## Concrete plan: lift the benchmark wins into production

### Phase 1 — Tool-grounded research_agent (5 days)

| File | Change | Result for production user |
|---|---|---|
| `backend/lib/galaxy/ai/agents/research_agent.py` | Register 5 tools (HPO-overlap, OMIM-disease, BioGRID-ORCS, GWAS-catalog, fetch-paper) | Agent decides when to call each, grounding answers in real data |
| `backend/lib/galaxy/ai/agents/research_agent_tools.py` (new) | Tool wrappers calling the existing `lookup_*` functions | n/a |
| `frontend/server/galaxy-assistant.ts` | Pass-through tool events to chat-stream so UI shows what tools were called | Transparency: users see "BioMate looked up OMIM for these genes" |
| `evaluation/adapters/biomni_eval1_adapter.py` | Once tools are in research_agent, DELETE the duplicated wire-in code in eval adapter | Eval validates production behavior instead of inventing its own |

**Validation**: rerun biomni_eval1 — score should match or exceed the current eval-adapter-only score, **and now the win is real for production users.**

### Phase 2 — Multimodal pipeline (3 days)

| File | Change |
|---|---|
| `frontend/server/routes.ts` chat-stream | Accept `images` field in JSON body |
| `frontend/server/galaxy-assistant.ts` | Build Anthropic content blocks `[{type:'image',source:...},{type:'text',text:...}]` |
| `evaluation/core/biomate_client.py` | `ask()` accepts `images=[bytes,...]` |
| `evaluation/adapters/sgi_bench_adapter.py` | Forward PIL → base64 → request |

Real users get image upload + vision answer; sgi_bench scores improve as a side-effect.

### Phase 3 — Workflow output schema in DB (2 days)

Per the older unified plan doc. Long-overdue infra.

### Phase 4 — Audit older docs (1 day)

The `20260513_BIOMNI_PATIENT_GENE_RESEARCH_AND_FIXES.md` and other docs treat my eval-adapter changes as if they were BioMate improvements. They're not. Update wording to distinguish "score win in eval adapter" from "production capability."

---

## What this audit changes about the session-final docs

The `20260515_FINAL_SESSION_STATE.md` headline "BioMate bixbench 92.7% beats GPT-Rosalind 75.1% by +17.6pp" is **technically true but misleading**. It means: when BioMate is wrapped in 9 hand-written deterministic Python handlers (`_run_bix57_mafft_gap_analysis` et al) that compute specific answers from specific capsules, the eval scores 92.7%. A real BioMate user uploading the same data and asking the same questions would NOT get those handler functions — they'd go through the LLM path and score somewhere closer to the "without handlers" baseline.

**The honest framing:**
- "BioMate + bixbench-specific handlers: 92.7%" (this is what was measured)
- "BioMate alone, on the same questions: probably 60-70%" (unmeasured — would need a no-handlers rerun)
- The hand-handlers prove specific computations work; they don't prove the GENERAL BioMate agent answers them correctly

For the GPT-Rosalind comparison to be fair, we'd need to either:
- Run BioMate's no-handler path on the same 205 questions (gives the apples-to-apples comparable score)
- OR be explicit in the headline that "BioMate's handler-wrapped harness" is the comparator, not "BioMate the product"

---

## Bottom-line audit

**Score wins**: real, measured, durable. The benchmark scores are honest in what they measure.

**Production wins**: ~30% of the work is generalizable. The other 70% — the eval adapters with their HPO scoring, OMIM injection, CRISPR ORCS context, full-text retrieval — was code I wrote that lives parallel to production, not in production. Real BioMate users don't benefit from any of it.

**The biggest leverage moving forward**: take Phase 1 (tool-grounded research_agent) and Phase 2 (multimodal pipeline) seriously. Both are concrete file plans (this doc lists them). Both move benchmark wins into actual product capability. **Roughly 8 days of work to make ~+30pp of benchmark-bound wins production-real.**

The benchmark journey was useful because it surfaced exactly which capabilities BioMate is missing in production. Now it's time to do the productization.
