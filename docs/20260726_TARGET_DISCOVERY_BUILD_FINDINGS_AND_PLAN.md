# Target Discovery Build — Findings, Dedup Audit & Corrected Plan

**Date:** 2026-07-26
**Context:** Building the UCB "modern target discovery" capability (see `20260723_TARGET_IDENTIFICATION_UCB_GAP_EVALUATION.md`). This doc records what already exists in BioMate, what was mistakenly started and removed, and the corrected plan grounded in the real catalog.

---

## 1. Design decisions captured

### Established vs. cutting-edge (resolved)
- **Ranking/decision layer = established + transparent.** The target scorecard uses OpenTargets-style weighted evidence aggregation (Ochoa 2021), genetic-support-of-success weighting (Nelson 2015), TDL (Oprea 2018). Rationale: UCB's explicit requirement is a closed, auditable, no-black-box, human-in-the-loop system. A learned ranker at the decision layer violates that.
- **Cutting-edge belongs in evidence generation** (GEARS GNN, scVI, MOFA+), and as an **advisory second opinion** on the ranking — user chose this. Implemented: Random Walk with Restart (network propagation, GNN-family, unsupervised) + harmonic-sum (OpenTargets production aggregation). Transparent score stays decision-of-record; disagreements are flagged for human review. A supervised GNN/LTR can slot behind the same interface once target-outcome training labels exist.

### Open-source leverage (all runnable INSIDE the closed system — data in, no data out)
Open Targets, STRING, CELLxGENE Census, Human Protein Atlas, GWAS Catalog, Reactome, MOFA2/mixOmics(DIABLO), TwoSampleMR/OpenGWAS, LINCS/CMap, OmniPath, scPerturb, Geneformer/scGPT/UCE.

---

## 2. Dedup audit against the real catalog (4,000+ workflows + tools index)

The local `galaxy_ai_tools.db` has only 386 workflows — NOT the production catalog. Audited via the live dev search API (`/api/workflows/search`, `/api/galaxy/tools/search` on dev-public.biomate.ai).

### Already exists — DO NOT rebuild
| Capability | Exists as | Verdict |
|---|---|---|
| Mendelian Randomization | **GMRP** (`bioconductor_nf`) — "MR of multiple SNPs to determine risk factors causing disease" | ✅ exists |
| Multi-omics integration | **`mofa_plus_integration`** + chain "Multi-Omics Integration — MOFA+" (rnaseq_deseq2_de → bioc_proteomics_de_v2 → lcms_metabolomics_consensus → mofa_plus_integration) | ✅ exists |
| Tractability | **Target Tractability Scorer** (real, 357-line Nextflow) | ✅ exists |
| Data-source tools (indexed) | `query_opentarget`, `query_stringdb`, `query_gwas_catalog`, `query_chembl`, `query_gtex`, `query_reactome`, `query_cbioportal`, cellxgenedp, STRINGdb, GWAS_CATALOG, REACTOME | ⚠️ indexed but see §3 |

### Mistakenly started, then REMOVED (were duplicates)
Three subagents were launched to build OT-loader / MOFA-integration / MR workflows. On discovering GMRP + mofa_plus_integration + query_opentarget already exist, all three were stopped and their partial dirs deleted:
- `drug_discovery/opentargets_evidence_loader/` (removed)
- `multi_omics/multiomics_factor_integration/` (removed)
- `genetics/mr_causal_support/` (removed)

---

## 3. CRITICAL FINDING — the data-acquisition layer is stubbed, not functional

The Biomni tools were converted into Nextflow subworkflows **structurally**, but the **database/data-source query workflows are non-functional stubs**:

- `backend/biomni_workflows/nextflow/subworkflows/database/` — **42** query workflows, **0** contain real API calls, **37** are `touch <name>_output.txt` stubs (create an empty file and exit).
- `Biomni/biomni_nextflow/subworkflows/database/` — 42/42 are touch-stubs.
- `query_opentarget.nf` specifically: just `touch query_opentarget_output.txt`. No GraphQL call.
- **No real implementation exists in Python either** — `Biomni/biomni/tool/database.py` (301 lines) has only `get_hpo_names`, `blast_sequence`, `region_to_ccre_screen`, `get_genes_near_ccre`. No `query_opentarget`. Grep for the OT API URL / GraphQL query body across all of Biomni: **zero hits**. Only a GraphQL **schema** pkl exists (`schema_db/opentarget.pkl`) — the schema, not a query.

**So "Open Targets Platform GraphQL" is registered in the tools index but has no working code behind it.** Same pattern for the other data-source query tools.

By contrast, the **analysis** workflows are real (Target Tractability Scorer, GMRP, mofa_plus_integration, and the new scorecard are full implementations, 0 touch-stubs).

### Additional infra note (from user)
The `biomate_data_management` biomni **data-lake files** (DepMap, miRTarBase, BindingDB, etc.) are **not deployed local or on dev — backed up in S3**. So the local-file data-lake tools also can't function until that data is restored. The live-API tools (OT, STRING via API) don't need the data lake — but they need their query logic implemented (per above).

---

## 4. What is genuinely NEW (the real gap) — and its status

| Piece | Status |
|---|---|
| **`target_scorecard_ranker`** — multi-omic evidence → ranked, provenance-backed targets; coverage-aware; human-in-the-loop; advisory RWR/harmonic second opinion | ✅ **built + locally tested** (pure-stdlib Python, runs under `nextflow -profile standard`; validated on custom CSV + JSON, weight reconfiguration changes rankings correctly). NOTE: currently ships a bundled illustrative cohort fallback — to be **removed** per "real system, no demo." |
| **Evidence acquisition for OT/STRING/GWAS** | ❌ stubbed (see §3) — must be **implemented** (fill existing stubs), NOT duplicated |
| **`target_discovery_full` chain** — wires acquisition → GMRP/MOFA/tractability → scorecard → ranked targets | ❌ not built |
| **DB registration** of scorecard + chain | ❌ not done |

---

## 5. Corrected plan (leverage-first, no duplication)

1. **Remove the demo cohort fallback** from `target_scorecard_ranker`; make it require a real evidence file (error clearly if absent). Add ingestion of the real Open Targets output schema.
2. **Implement the `query_opentarget` stub for real** (fill the existing `query_opentarget.nf` with a real GraphQL call: disease→EFO, associatedTargets, per-target genetic/tractability/safety). This completes an existing registered tool — not a duplicate. Same approach available for `query_stringdb`, `query_gwas_catalog` as needed.
3. **Build `target_discovery_full` chain**: `query_opentarget` (evidence) [+ optional GMRP causal, mofa_plus_integration for cohort omics, Target Tractability Scorer] → **`target_scorecard_ranker`** → ranked targets → hand-off to existing `target_to_lead_full`.
4. **Register** scorecard workflow + chain in the DB (idempotent script, mirroring `add_gwas_methods_chain.py`).
5. **Restore the S3 data-lake** to dev if the local-file data-source tools are in scope (separate infra task).

**Open decision (for the user):** confirm step 2 — implement the real query logic by filling the existing stubs (recommended), vs. calling Biomni tools another way. This determines how the scorecard gets fed real data.
