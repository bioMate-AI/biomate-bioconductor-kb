# Unified Speedup Backlog — Single Source of Truth

**Date:** 2026-07-12
**Purpose:** One authoritative, status-tagged, biggest-win-first backlog for ALL engineering speedups, consolidating three previously-scattered sources so nothing is double-tracked or lost:
- `20260704_SPEEDUP_LLM_PILOT_AND_UNIQUENESS_STRATEGY.md` §1 — internal engineering items (1-A…1-E)
- `20260703_LLM_LATENCY_ROOT_CAUSE_AND_FIXES.md` — LLM latency fixes
- `20260712_SPEEDUP_SURVEY_AND_ADOPTION_PLAN.md` — external community-method adoption + auto-update

**Status legend:** ✅ SHIPPED · 🟡 PARTIAL (built, not wired) · ⬜ NOT-STARTED
**Discipline:** every speedup ships with its QC gate (exact re-rank / domain guard). "Aggressively fast, because QC-verified." Status claims below are code-verified (file:line).

---

## A. Already shipped — do NOT re-track

| Item | Win | Evidence |
|---|---|---|
| ✅ **Nextflow `-resume` for QC-loop reruns** (1-D) | 60–80% on partial reruns | `nextflow_executor.py:4683` passes `-resume`; `:5383` resume endpoint; `:4506` copies `.nextflow/` cache; work dir retained |
| ✅ **LLM retry_attempts = 1** (no 2×120s stacking) | removes ~120s worst-case | `config/llm_providers.yml:16,28,38,48,60` |
| ✅ **`_generate_gemini` respects injected timeout** | removes hardcoded 120s | `llm_client.py:410` `kwargs.get('timeout',30)`; same for Anthropic/OpenAI |
| ✅ **Timeout injected into kwargs + Flash thinking_budget=0** | caps per-provider latency | `llm_client_fallback_implementation.py:318,323` |
| ✅ **Intent model pinned to Flash (no Pro for long msgs)** | removes 110s+ Pro hangs | `galaxy-assistant.ts:275` returns `gemini-3.5-flash` |
| ✅ **Workflow generator uses `use_fast_model`** | Flash-first on 2 critical calls | `galaxy_workflow_generator.py:450,644` |

---

## B. Actionable backlog — ranked by win ÷ effort

| # | Item | Lever | Expected win | Status | Effort | Source | Next action / QC gate |
|---|---|---|---|---|---|---|---|
| 1 | **Activate tiered model routing (1-A)** | internal | **3–5×** latency on ~80% of calls | 🟡 PARTIAL | **Low** (code exists, inert) | 04 §1-A | Wire `HybridLLMRouter.classify_task()` into `ai_assistant.py` + `galaxy-assistant.ts` model selection. **Highest ROI — the hard part is already built.** |
| 2 | **Redis + MCP descriptor caching across 14 connectors** | external | biggest multi-DB latency cut, near-zero risk | ⬜ | Low | 12 | Wrap each connector fetch in cache get/set + per-source TTL; cache schemas once. Uses existing Redis. |
| 3 | **AWS Batch array jobs for compound libraries (1-E)** | internal | **20–50×** ADMET screening throughput | 🟡 IMPLEMENTED (local-tested; dev Batch pending) | Med | 04 §1-E | **Done via Nextflow channel fan-out**, not literal `arrayProperties` (Nextflow-on-Batch submits one job per task). `predict_admet_properties/main.nf` now shards `smiles_list` (`params.admet_shard_size`, default 25) → parallel `ADMET_INFER_SHARD` map jobs → single `PREDICT_ADMET_PROPERTIES` reduce that keeps the QC worst-case aggregation unchanged over the full set. Local tests 8/8 (`tests/run_local_test.sh`); **no executor change**. Remaining: dev Batch run (~50–100 compounds) to confirm N parallel jobs + worst-case parity + hERG gate. Plan: `.claude/plans/cozy-beaming-scott.md`. |
| 4 | **Foldseek + prebuilt AFDB index** | external | **~10³–10⁵×** structure/protein match | ⬜ | Low–Med | 12 | Prebuild AFDB/PDB Foldseek index once → S3, mount read-only on Batch; wrap `foldseek easy-search`. QC = TM-align exact re-rank on top hits. |
| 5 | **Reference data pre-indexing (1-C)** | internal | eliminates 3–8s live-API round-trips/run | ⬜ | Med | 04 §1-C | Create `reference_cache.py`: parquet/SQLite cache for OpenTargets/GWAS/DICE instead of live calls. |
| 6 | **Nextflow process-level parallelism (1-B)** | internal | DE ensemble 18→7 min; chain overlap ~12 min/run | ⬜ | Med | 04 §1-B | Apply `parallel` channel operators to DE (DESeq2+edgeR+limma), ADMET 3-tool, GWAS→scRNA→eQTL. |
| 7 | **MMseqs2-GPU persistent search service** | external | ~6× BLAST, higher sensitivity | ⬜ | Med | 12 | Primitive B: target DB hot in GPU mem; CPU MMseqs2/DIAMOND fallback. QC = E-value threshold + confirm. |
| 8 | **FPSim2 chemical-similarity workflow** | external | ChEMBL/PubChem scale, ms/query | ⬜ | Low–Med | 12 | Primitive A: prebuilt ChEMBL FPS file → `chem_similarity` tool. QC = Tanimoto ≥0.7 + exact re-score. |
| 9 | **MD fast-modes: NNPOps + ANI-2x ML/MM; GB-Neck2 toggle** | external | 2.7× vs classical; several-× (implicit solvent) | ⬜ | Med | 12 | `nnpops` conda; ligand=ANI/env=MM; `GBn2` for ADMET pre-screen. QC = gate to validated chemistry (neutral/±1); off for binding-site water. |
| 10 | **MedCPT + Qdrant/LanceDB retrieval; BioEmu ensembles** | external | fast biomedical retrieval; 1000 conf/40 min | ⬜ | Med | 12 | Phase 2. |

**Licensing landmines (do NOT adopt):** MACE-OFF (non-commercial ASL), chemfp commercial (no hosting → use FPSim2), SmallWorld/Enamine-REAL billions (API-only).

---

## C. Second dimension — Auto-update (latest tools/data, fast)

- **Created:** `.github/workflows/auto-update-tools.yml` — Tue/Fri 02:00 UTC, blog gen OFF, artifact-for-review, deploy stays sanctioned-manual (`sync_to_dev.sh`). Details in `20260712_SPEEDUP_SURVEY_AND_ADOPTION_PLAN.md`.
- **To activate:** set secret `WORKFLOW_DB_SOURCE_URL` (fetchable copy of current DB) + merge the workflow to the default branch.

---

## D. Recommended next 3 actions (biggest-win-first, lowest-risk)
1. **Activate tiered routing (#1)** — the router is already written; wiring it is the cheapest 3–5× we have.
2. **Redis/MCP connector cache (#2)** — near-zero risk, uses existing infra, cuts multi-DB latency now.
3. **AWS Batch array jobs (#3)** — unlocks 20–50× on the ADMET/compound-library path that matters most to the drug-discovery wedge.

Then Foldseek (#4) for the structure-match step-change. Each lands with its QC gate.
