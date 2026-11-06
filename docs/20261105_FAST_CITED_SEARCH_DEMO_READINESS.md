# "Multi-agent fast search" demo — readiness audit + hardening (2026-11-05)

Audit of the second headline demo use case (`project_demo_use_cases_priority`): a **fast cited
answer** fanning out over literature + databases + the workflow catalog. User chose (this session)
to **harden the existing single-pass research path** rather than activate the dormant multi-agent
orchestrator — the right call: the NMI result (`project_agent_patterns_research`) is that multi-agent
*hurts* above a capability threshold, and the user-visible value is "fast cited answer," not
"multi-agent" under the hood.

## 1. Orchestrator reachability (confirmed still dormant)
The literal multi-agent orchestrator is **not on the live path**, unchanged from the 2026-10-08 finding:
- `generate_workflow_multi_agent` endpoint exists but the live chat path
  (`frontend/server/galaxy-assistant.ts`) hits `/api/ai_assistant/generate_workflow` (unified single-pass).
- The `handler == 'agent_orchestrator'` dispatch in `ai_assistant.py` itself falls back to
  `generate_workflow_unified` (inline comment: the multi-agent path it would reach is "dormant").
- `pattern_router.py` (the single-vs-multi chooser) has **zero live callers** (tests only).

## 2. Existing research path — fan-out IS wired (3 dimensions)
`research_agent.py` (`ResearchAgent`, endpoint `POST /api/ai_assistant/research_query`):
- **Literature** — retrieval + synthesis over real papers (live-verified below).
- **Databases** — `_build_synthesis_prompt` injects live DB facts from GWAS Catalog / Open Targets /
  Ensembl / Monarch / MyGene / ClinVar / HPO / OMIM (gene/variant queries) + CRISPR-screen literature.
- **Catalog / tools** — injects `tool_knowledge` (tool_name/use_cases/recommended_parameters) from
  `galaxy_ai_tools.db`.

## 3. Integrity — live-verified on dev (GLM-5.3), the user's stated concern
The `research_query` PMID-confabulation risk (`project_research_confabulation`, fixed Aug 2026) is
**still closed on the current dev build**. Two live calls against `localhost:8081`:

| Query | Result |
|---|---|
| **Real topic** ("best splice-aware aligner for long-read RNA-seq, cite the literature") | 3 citations, **all real, DOI-verifiable, topically correct** (Križanović 2017 `10.1101/126656`; GLASS `10.1101/2025.04.07.647681`; novoSplice). No PMIDs because these are **preprints** (DOI is the right id — not a gap). Answer hedges honestly where abstracts don't support a firm conclusion (correct integrity behavior, NOT to be "fixed" by forcing confidence). |
| **Fabricated entities** ("evidence table, verify every PMID, for ZZZX9 directly ubiquitinates QQR7B") | **0 citations**, honest *"Insufficient retrievable evidence… no reference could be grounded"*, **zero** PMIDs/DOIs/table/records-count. No confabulation. |

## 4. Hardening applied (`f22bd970c`) — model-independent anti-confabulation
The explicit empty-cites guard shipped in Aug 2026 had been **dropped in the DB-facts refactor**;
dev passed §3 only via the grounding guard + "never invent" instructions *on GLM-5.3*. Restored for
defense-in-depth (the default model just changed to GLM-5.3 — exactly when model-independence matters):
- When `cites == []`, `_build_synthesis_prompt` now injects `## Retrieved Literature: NONE` forbidding
  any `[N]` / evidence table / PMID / DOI / PDB / accession / "records retrieved" count, requiring an
  `EVIDENCE: insufficient` opener.
- The deep evidence-review "produce a markdown evidence table" instruction is **gated on `cites`**
  (with zero literature it is replaced by an explicit "do NOT produce a table"), removing the
  contradiction that previously invited confabulation on table-requesting prompts.
- +2 tests (`test_research_citation_grounding.py`: empty-cites NONE guard; cites-present numbered
  list + table allowed); also fixed a pre-existing stale stub (`_split_evidence_verdict`). 3/3 pass.
- **Re-verified live on dev** after deploy: the fabricated-entity trap again returns the honest
  no-evidence answer with zero fabricated identifiers.

## 5. Demo verdict
The fast-cited-answer demo is **trustworthy and demo-ready on the existing path**: it fans out over
literature + DBs + catalog, returns real verifiable citations, and refuses to fabricate when
retrieval is empty — now model-independently. Residuals are quality-not-integrity and intentionally
left: answers hedge when only abstracts (not full text) are retrieved — correct behavior; forcing
confidence would reintroduce fabrication. A future enhancement (not required for the demo) is wider
full-text retrieval for crisper answers. The literal multi-agent orchestrator remains a separate,
dormant capability (`project_agent_patterns_research` build order) — out of scope for this demo.

Commits: `f22bd970c` (hardening). Deployed to dev; PR #295.
