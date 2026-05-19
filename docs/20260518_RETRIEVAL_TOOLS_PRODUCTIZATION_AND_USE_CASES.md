# Retrieval Tools — Productization & Validation Use Cases

**Date:** 2026-05-18
**Status:** Implementation in progress (Phase 1 of architectural-debt plan)
**Related docs:** `20260515_ARCHITECTURAL_DEBTS_DEEP_DIVE.md`, `20260516_AUDIT_BENCHMARK_VS_PRODUCTION_GAP.md`

## Why this exists

The benchmark work (BixBench → 92.7%, LitQA2 → 70%, biomni_eval1 patient_gene +6.7pp, rare_disease +30pp) leaned heavily on retrieval modules that live in `evaluation/` and are only invoked by the benchmark harness:

- `evaluation/retrievers/europe_pmc_fulltext.py` — DOI/PMID → full-text → keyword-scored passage
- OMIM lookup helpers inside `evaluation/adapters/biomni_eval1_adapter.py`
- CRISPR ORCS (BioGRID) lookup helpers inside the same adapter

These are clean, generic Python modules. They do not depend on benchmark machinery. Real BioMate users (chat, workflows, auto-loop, CRO) currently get zero benefit from them — that's the productization gap.

This doc captures the **use cases** the productized retrievers should serve, with **concrete validation criteria** for each. Future regression tests live or die by these criteria.

## Information-flow pattern

All five use cases below share the same shape:

```
user query / workflow state
  → entity extraction (gene, compound, DOI, etc.)
  → retriever tool call (external API / DB)
  → structured fact or passage
  → LLM synthesis with grounded context
  → cited answer or action
```

This is the same pattern used in eval adapters; the only difference is the entry point. Productization = adding tool definitions so the production LLM can call the retrievers, with the same caching, rate-limiting, and error handling.

## Use cases for validation

### UC-1: Chat literature QA with citation

**Scenario:** User asks in chat "What's known about ARL6IP1 in hereditary spastic paraplegia?"

**Information flow:** entity extraction (gene=ARL6IP1, phenotype=HSP) → OMIM lookup for gene → Europe PMC search for "ARL6IP1 spastic paraplegia" → LLM synthesizes 3-paragraph answer with PMIDs.

**Validation:**
- Answer mentions SPG61 / OMIM 615685 (the correct rare-disease association)
- Answer cites at least one real PMID, retrievable via Europe PMC
- Answer does NOT hallucinate a more famous gene (e.g. SPG7) when the query is specifically about ARL6IP1
- Latency: < 10 s end-to-end on cache miss, < 1 s on cache hit

**Test fixtures:** chat session JSON with this question; assert answer contains "OMIM" or "615685" and at least one valid PMID regex match.

---

### UC-2: CRO compliance — literature-grounded narrative

**Scenario:** CRO user asks "Pull recent (post-2020) literature on hERG liability for compound class N-aryl piperazines, draft §2.6.4 paragraph."

**Information flow:** entity extraction (compound class, safety endpoint) → Europe PMC search with date filter → fetch top 3 full-texts → passage extraction per paper → LLM synthesis as FDA §2.6.4 prose with inline `[PMID]` citations.

**Validation:**
- Draft paragraph contains ≥ 3 distinct PMIDs, all from Europe PMC search results (not LLM-invented)
- Each cited paper actually mentions hERG (verified by grep on retrieved passages)
- No "et al." citations without a corresponding PMID
- Length 200–400 words (CRO submission norm)

**Test fixtures:** synthetic CRO campaign; assert PMID extraction from output + cross-check against Europe PMC search response.

---

### UC-3: Auto-loop remediation with literature evidence

**Scenario:** ADMET workflow auto-loop detects hERG > 50% threshold breach. Remediation step should not just suggest "lower logP" generically — it should pull structural-alert literature for the specific compound and propose a substituent change with citation.

**Information flow:** compound SMILES + failing endpoint → Europe PMC search "<structural-class> hERG mitigation" → passage extraction → LLM proposes specific substituent change ("replace 4-methylpiperidine with 4-methylpiperazine, ref PMID …") → remediation card shows the citation.

**Validation:**
- Remediation card includes a citation badge with a real PMID
- Suggested change is structurally plausible (regex check: SMILES of new substituent is a valid SMILES)
- Re-running the workflow with the suggested change passes the gate in ≥ 50% of test compounds (existing auto-loop benchmark)

**Test fixtures:** existing ADMET auto-loop test set (`experiments/admet_autoloop/`); extend with citation-presence assertion.

---

### UC-4: IND §2.6.1 narrative — target-validation evidence

**Scenario:** IND §2.6.1 currently uses pure-LLM prose for the "pharmacology summary" section. Augment with target-validation evidence pulled from CRISPR ORCS and OMIM.

**Information flow:** target gene → CRISPR ORCS lookup (essentiality scores, screen conditions) + OMIM lookup (disease association) → LLM weaves evidence into §2.6.1.1 paragraph with proper grounding.

**Validation:**
- For target=BRD4, narrative must mention essentiality in ≥ 1 cancer screen (verified against ORCS payload)
- For target=BRCA1, narrative must mention OMIM 113705 / breast-ovarian cancer
- Narrative cites the screen source (e.g. "DepMap 24Q2") when ORCS lookup returns one
- No invented essentiality scores (LLM must use the numeric value from the tool payload)

**Test fixtures:** `evaluation/datasets/ind_narratives/` plus 5 target genes; assert numeric evidence matches tool payload.

---

### UC-5: Workflow param prefill — free-text reference resolution

**Scenario:** User pastes "run RNA-seq with the same params as PMID 36287100" or "use the genome build from doi:10.1038/s41586-022-04657-6".

**Information flow:** PMID/DOI extraction → Europe PMC fetch → passage extraction targeting Methods section → LLM extracts param values (genome build, aligner, etc.) → param-prefill panel populates.

**Validation:**
- Genome build extracted correctly for ≥ 3 test papers (manual gold standard)
- If the paper is paywalled / no full-text, system says "couldn't fetch full text" rather than hallucinating
- Cache hit on re-run (test by running same query twice; second call must be < 200 ms)

**Test fixtures:** YAML of (PMID, expected_param_name, expected_value) triples; pull from existing `param_prefill` benchmark cases.

---

## Architecture corrections (2026-05-18, after audit)

Two corrections to the original framing in this doc:

### Correction 1: Two-tier tool surface, not 3 hand-rolled retrievers

BioMate has **12,274 indexed tools** in `backend/database/galaxy_ai_tools.db` (Sequence Analysis 1,300; Metagenomics 948; Proteomics 400; RNA 389; nf-core 231; etc.) — each with parameters, inputs, outputs, EDAM ops, citations, container info. The right tool surface for an LLM is to expose this catalog, not 3 hand-coded helpers.

**Tier 1 — fixed discovery + execution tools (~8 schemas):**
- `search_workflows(query, domain?)` — hybrid FTS+BGE search against `galaxy_ai_tools.db` (endpoint `/api/ai_assistant/search_ranked` already exists)
- `get_tool_details(tool_id)` — params/inputs/outputs/examples for the LLM to fill in
- `run_workflow(tool_id, params, inputs)` — submit via Nextflow executor
- `get_run_status(invocation_id)`
- `search_literature(query)` ← already built (UC-2)
- `fetch_literature_passage(query, doi|pmid)` ← already built (UC-3, UC-5)
- `lookup_omim_gene(gene_symbol)` ← already built (UC-1, UC-4)
- Optional later: `lookup_compatible_tools(tool_id)` from `tool_compatibility` table

**Tier 2 — the 12,274 tools — surfaced dynamically.** Static-schemaing all 12k would obliterate context. LLM uses Tier-1 discovery → gets candidates → details → runs.

### Correction 2: Gemini is the primary, not Claude

Per `backend/config/llm_providers.yml` (committed in `a01e0c26a`), the fallback chain is:

1. **Primary:** Gemini 3.1 Pro Preview
2. Fallback 1: Gemini 3.0 Flash Preview
3. Fallback 2: Claude Sonnet 4.5
4. Fallback 3: GPT-4o
5. Fallback 4: Local Qwen3-32B

Tool-use must be implemented in priority order: Gemini first, then Anthropic, then the rest. Each provider has a different tool-call protocol; we author tool schemas once in Anthropic shape and translate per provider. The `FallbackChainManager` must propagate tool definitions through the chain so a mid-loop failover doesn't lose the tools.

Temperature defaults in `llm_providers.yml` updated to 0 (deterministic by default; callers can override for creative tasks).

## What we're building (this PR)

### Files created
1. `backend/lib/galaxy/ai/retrievers/__init__.py` — package marker, public API exports
2. `backend/lib/galaxy/ai/retrievers/europe_pmc.py` — DOI/PMID/keyword → full-text passage; lifted from `evaluation/retrievers/europe_pmc_fulltext.py`, generalized to also accept search queries
3. `backend/lib/galaxy/ai/retrievers/omim.py` — gene symbol → OMIM phenotype IDs + names + clinical synopsis; lifted from biomni_eval1 adapter
4. `backend/lib/galaxy/ai/retrievers/crispr_orcs.py` — gene + cell line/condition → essentiality scores + screen metadata; lifted from biomni_eval1 adapter
5. `backend/lib/galaxy/ai/retrievers/tools.py` — Anthropic tool-use JSON schemas + dispatch table
6. `backend/tests/test_retrievers.py` — live-API + cache tests

### Files explicitly NOT touched in this PR
- `backend/lib/galaxy/ai/agents/research_agent.py` — integration deferred until tests pass
- `frontend/server/galaxy-assistant.ts` — same
- `evaluation/retrievers/europe_pmc_fulltext.py` — kept as-is for backward compat; will switch to re-export from backend module once stable

This sequencing follows CLAUDE.md: review code before testing, no speculative deploys.

## Test plan before integration

1. **Unit per retriever:** offline cache hit, live API call (skip if no network), malformed input returns empty string (never raises)
2. **Tool dispatch:** each Anthropic tool schema validates; dispatch returns expected shape for one canonical input
3. **End-to-end smoke per use case:** UC-1 and UC-5 above, run against this module directly without research_agent
4. **Performance:** cache hit < 200 ms p99; live call < 10 s p99

Integration into `research_agent.py` and chat tool-use only happens after all of the above are green.

## Success criteria for this productization

- Retrievers are importable from `backend.lib.galaxy.ai.retrievers` with no eval-package imports
- ≥ 90% of `test_retrievers.py` passes on live-network runs
- UC-1 and UC-5 smoke tests pass on real biological inputs documented in this file
- No behavior change for existing eval adapters (`evaluation/retrievers/europe_pmc_fulltext.py` still works as before)

When all four are green, we move on to Phase 1 step 2: wire the dispatch table into `research_agent.py` and add tool-use to the chat path.
