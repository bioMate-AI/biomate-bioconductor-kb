# BioMate × AI Drug Discovery — Internal Opportunity Analysis

**Audience:** BioMate product/engineering (internal only; not for the partner)
**Context:** Codebase audit against the introduction and study proposal documents, March 2026
**Purpose:** Honest fit assessment — what BioMate can actually deliver today, what requires engineering before the study, and what is a longer-term opportunity.

---

## 1. Where BioMate Adds Immediate Value

### A. Structure prediction and docking

AlphaFold3 structure prediction, AutoDock Vina, DiffDock, and Schrödinger Glide are all live in the codebase as first-class Nextflow workflows. The `structure_prediction_docking` subworkflow has been run end-to-end and has real execution results in the repo (EGFR kinase, DiffDock + Vina poses, timeline + report HTML). This is the strongest and most defensible part of the drug discovery stack.

### B. ADMET profiling

Two ADMET workflows exist (`predict_admet_properties` and `ADMET_pred`). Both use RDKit-based property calculation. The `predict_admet_properties` workflow covers Lipinski/Veber/Egan filters plus hERG, DILI, Ames, ClinTox predictions. This is complete enough for sequential gating in a virtual screening pipeline.

### C. REINVENT4 generative design

REINVENT4 (AstraZeneca open-source) is indexed and available as a workflow. SA score is embedded in the scaffold hopping pipeline. This gives BioMate a credible generative design story that no other non-commercial platform fully covers.

### D. Scaffold hopping and analogue design

The scaffold hopping workflow (RECAP fragmentation + matched molecular pair analysis) is live. SA score is computed alongside MMP results. This is directly useful for lead optimisation when a researcher needs analogue ideas without committing to a full generative run.

### E. Molecular dynamics and binding free energy

GROMACS protein-ligand MD + MM-GBSA and AMBER pmemd GPU MD are both indexed. GROMACS has real execution results in the repo. This covers the high-precision re-ranking step that separates fast virtual screening from defensible hit ranking.

### F. Drug repurposing

TxGNN repurposing workflow exists (1 workflow, 4 tools). Returns top-k approved drugs for a disease indication. Useful for both target validation (what drugs are known to hit this target family?) and repurposing campaigns.

### G. Research intelligence agent

The research agent (PubMed + preprint synthesis) is operational. For an AI drug discovery researcher, this is the layer that makes BioMate qualitatively different from a pipeline runner: it answers "why did this scaffold fail selectivity in the literature?" and "what published crystal structures exist for this binding site?" in the same session as the docking run.

### H. Chemoproteomics

`Chemoproteomics Pulldown` and `Doscheda` (differential chemoproteomics) exist as workflows. Relevant for off-target profiling and target engagement validation — exactly the data type that closes the loop between in silico and wet lab for covalent and probe compounds.

---

## 2. Engineering Gaps — Status (Updated March 2026)

All gaps from the initial audit have been resolved. The table below is the historical record; see Section 4 for the updated summary.

Original gap list confirmed by auditing the codebase against every claim in `BioMate_DrugDiscovery_Introduction.md` and `BioMate_DrugDiscovery_Study_Proposal.md`.

### Gap 1 — Custom model wrapper interface ✅ RESOLVED
**Impact:** Critical — blocks Study Proposal Arm C entirely
**Effort:** ~2–3 weeks

The study proposal commits to letting the partner integrate their own ML models (GNN-based affinity predictors, retrosynthesis models, selectivity scorers) as first-class pipeline steps. No such interface exists. BioMate needs a standardised adapter that accepts:
- A Python function (called with a SMILES list, returns a score dict)
- A Docker container (stdin/stdout SMILES → JSON scores)
- A REST endpoint (POST SMILES list, receive scores)

The adapter must: log custom model runs in the audit trail, incorporate custom scores into the integrated compound ranking, and toggle the model on/off for reproducibility comparison. Without this, Arm C is not executable.

### Gap 2 — Druggability assessment workflow ✅ RESOLVED
**Impact:** High — claimed in Phase 1 of the introduction; currently only a Galaxy tool
**Effort:** ~1 week

`fpocket` exists as a Galaxy tool but is not wrapped as a first-class BioMate Nextflow workflow with QC governance. The introduction claims "druggability assessment (fpocket + SiteMap-equivalent)" under Phase 1. A BioMate druggability workflow would: accept a PDB or AlphaFold structure, run fpocket to detect binding pockets, score each pocket (volume, druggability score, hydrophobicity), and return a ranked list of sites with a QC gate on minimum pocket volume and score. SiteMap requires a Schrödinger license; fpocket is the open-source path.

### Gap 3 — Pharmacophore-based filtering workflow ✅ RESOLVED
**Impact:** Medium — claimed in Phase 2 of the introduction; tools exist but no workflow
**Effort:** ~1 week

Pharmacophore alignment and Pharmacophore tools exist in the tools table (Galaxy-level), but there is no orchestrated BioMate workflow that: generates a pharmacophore query from a known active compound set, screens a library against the query, and returns filtered SMILES with match scores. This is a meaningful pre-screen step that reduces the docking workload for large libraries.

### Gap 4 — Drug-synthesis retrosynthesis ✅ RESOLVED
**Impact:** Medium-High — claimed in the introduction ("SA score + RetroStar lookup")
**Effort:** ~1.5 weeks
**Resolution:** AiZynthFinder (AstraZeneca open-source) wrapped as `aizynthfinder_retrosynthesis` Nextflow workflow. Introduction updated to reflect AiZynthFinder (not RetroStar).

`RetroPath2.0` exists in the tools table but is a metabolic pathway retrosynthesis tool (for synthetic biology), not a medicinal chemistry retrosynthesis tool. RetroStar (MIT) covers drug-like small molecule synthesis routes. No RetroStar or equivalent (ASKCOS, AiZynthFinder) workflow exists in BioMate. The SA score component is available via scaffold hopping, but a true synthesis route predictor is missing. This should be corrected in the introduction unless the claim is limited to SA score only.

**Correction for introduction document:** Change "SA score + RetroStar lookup" to "SA score (via scaffold hopping pipeline)" until RetroStar or ASKCOS is wrapped. Do not claim RetroStar.

### Gap 5 — Multi-objective Bayesian optimisation (BO) round orchestration ✅ RESOLVED
**Impact:** Critical — required for DMTA loop closure described in the feedback loop survey
**Effort:** ~3–4 weeks
**Resolution:** `bayesian_optimizer.py` built with GP surrogate per objective, Pareto front computation, hypervolume improvement acquisition, diversity-penalised batch selection, and SQLite-persisted proposals.

The "Bayesian optimisation" hits in the database are biology/genomics workflows (`GSgalgoR`, `MOGAMUN` — genetic algorithms for biological network optimisation). There is no drug discovery BO loop: no GP or GNN surrogate, no acquisition function, no round proposal, no Pareto front display. This is the central piece missing for BioMate to participate in a closed DMTA loop. Without it, BioMate is a one-shot screener, not an iterative campaign platform.

The build would include:
- Surrogate model fit on assay + docking + ADMET data (GP or GNN, configurable)
- Acquisition function: expected improvement (EI) for single objective; hypervolume improvement for multi-objective
- Round proposal: given a virtual library, score all candidates under the surrogate, return the top-N recommended for the next synthesis/assay batch
- Pareto front display for multi-objective campaigns (potency × selectivity × ADMET)

### Gap 6 — Structured assay data ingestion ✅ RESOLVED
**Impact:** High — required for any real DMTA loop; enables session memory to learn from experimental outcomes
**Effort:** ~1–2 weeks

BioMate session memory stores compound decisions and ADMET outcomes from in silico runs. It does not yet accept structured assay results from the wet lab or CRO. The gap is:
- A defined CSV template: `compound_id, smiles, assay_type, value, unit, assay_date`
- A BioMate ingest endpoint that parses the CSV, maps results to the compounds designed in that campaign, and updates the campaign memory
- Trigger: after ingestion, automatically propose the next BO round (depends on Gap 5)

Without this, BioMate cannot close the DMTA loop — it can only run isolated Design + Analyse sessions that the researcher must manually reconnect.

### Gap 7 — CRO-ready compound order output ✅ RESOLVED
**Impact:** Medium — enables practical workflow for groups using CRO partners
**Effort:** ~1 week
**Resolution:** `cro_order_export.py` with WuXi AppTec, Pharmaron, Enamine CSV formats, scientific summary Markdown, and QC JSON report.

After BioMate proposes a next-round compound set, there is currently no structured export in formats that CROs (WuXi AppTec, Pharmaron) accept directly. The gap is a template-based export that produces:
- SMILES + compound ID + priority rank + requested quantity + salt form + purity spec
- A covering scientific rationale per compound (generated by BioMate, citing the assay outcome that motivated the design)
- QC summary of the proposed set (ADMET pre-filter results, SA score distribution, diversity metrics)

### Gap 8 — Automated pocket detection workflow (standalone) ✅ RESOLVED
**Impact:** Medium — claimed in Phase 2 as a distinct step; currently only reachable inside the docking workflow
**Effort:** ~3 days

Pocket detection is currently embedded inside the docking workflow (the docking box is centered automatically). A standalone pocket detection step — run before compound selection, returning visualisable pocket coordinates and druggability scores — is more useful for target validation decisions earlier in the pipeline, before compounds are even selected.

### Gap 9 — Drug treatment MoA characterisation pipeline ✅ RESOLVED
**Impact:** Medium — mentioned in feedback loop survey as multi-modal data for DMTA loop
**Effort:** ~1 week
**Resolution:** `drug_moa_rnaseq` workflow built: DESeq2 → MSigDB Hallmark GSEA → LINCS CMap lookup → MoA hypothesis report.

For cellular target engagement validation, researchers run bulk RNA-seq on drug-treated vs. control cells and interpret the transcriptomic response as a mechanism-of-action readout. BioMate has nf-core/rnaseq and DESeq2 pipelines, but there is no packaged "drug MoA from RNA-seq" workflow that: accepts treated/control RNA-seq, runs DE, runs gene set enrichment against a drug response database (LINCS L1000, CMap, MSigDB Hallmarks), and returns a ranked MoA hypothesis. This is the "T → A" data type most relevant to drug discovery DMTA loops.

### Gap 10 — Commercial availability and vendor catalogue check ✅ RESOLVED
**Impact:** Low-Medium — useful final step before synthesis order submission
**Effort:** ~3 days
**Resolution:** `commercial_availability.py` built with mock and live (PubChem PUG REST) modes, batch checking, and availability report export.

One Galaxy tool references Enamine, but there is no BioMate workflow that checks commercial availability of proposed compounds against Enamine REAL Space, Chembridge, Sigma-Aldrich catalogue via API. This matters for academic groups where "synthesise in-house vs. order commercially" is a cost and timeline decision on every round.

---

## 3. Pre-Study Engineering Commitments (for Study Proposal)

The study proposal commits to the following being ready before Month 2 begins:

| Commitment | Gap # | Effort | Priority |
|---|---|---|---|
| Session memory module: structured compound outcome storage + retrieval | (existing) | Verify | Critical |
| Memory on/off toggle for Arm D control | (existing) | Verify | Critical |
| Custom model wrapper interface | Gap 1 | 2–3 weeks | Critical |
| Structured assay data ingestion (CSV template + ingest endpoint) | Gap 6 | 1–2 weeks | High |

**Total pre-study engineering: ~4–6 weeks.** Start Month 1 immediately after agreement.

---

## 4. Summary Table

| Introduction claim | BioMate today | Status |
|---|---|---|
| Literature mining and hypothesis generation | Research agent operational | ✅ Live |
| TxGNN target-disease association | Workflow confirmed | ✅ Live |
| AlphaFold3 structure prediction | Workflow confirmed (executed) | ✅ Live |
| Druggability assessment (fpocket) | `pocket_detection_druggability` Nextflow workflow | ✅ Built |
| AlphaFold Proteome DB search | Workflow confirmed | ✅ Live |
| Fingerprint similarity search | Galaxy tools confirmed | ✅ Live |
| AutoDock Vina docking | Workflow confirmed (executed) | ✅ Live |
| DiffDock docking | Workflow confirmed | ✅ Live |
| Schrödinger Glide | Workflow confirmed (requires license) | ✅ Live (license) |
| Pocket detection (standalone) | `pocket_detection_druggability` workflow | ✅ Built |
| Pharmacophore-based filtering | `pharmacophore_filtering` Nextflow workflow | ✅ Built |
| TxGNN drug repurposing | Workflow confirmed | ✅ Live |
| ADMET profiling (hERG, DILI, Ames, ClinTox) | Workflow confirmed | ✅ Live |
| Integrated ADMET scoring pipeline | Confirmed; sequential gating works | ✅ Live |
| REINVENT4 generative design | Workflow confirmed | ✅ Live |
| Scaffold hopping (RECAP + MMP) | Workflow confirmed + SA score | ✅ Live |
| SA score (synthetic accessibility) | Embedded in scaffold hopping | ✅ Live |
| AiZynthFinder retrosynthesis | `aizynthfinder_retrosynthesis` Nextflow workflow | ✅ Built |
| GROMACS MD + MM-GBSA | Workflow confirmed (executed) | ✅ Live |
| AMBER MD | Workflow confirmed | ✅ Live |
| Anti-target rescoring | Galaxy tool confirmed | ✅ Live |
| Custom model integration (study Arm C) | `custom_model_wrapper.py` + `custom_model_registry.py` | ✅ Built |
| Multi-objective BO round proposal (DMTA loop) | `bayesian_optimizer.py` — GP surrogate, Pareto front, HVI acquisition | ✅ Built |
| Assay data ingestion (DMTA loop) | `assay_ingestion.py` + `assay_schema.py` | ✅ Built |
| CRO compound order output | `cro_order_export.py` — WuXi, Pharmaron, Enamine formats | ✅ Built |
| Drug MoA characterisation pipeline | `drug_moa_rnaseq` Nextflow workflow | ✅ Built |
| Commercial availability check | `commercial_availability.py` — PubChem live + mock | ✅ Built |

---

## 5. Immediate Corrections to Client-Facing Documents

Before sharing the introduction or proposal externally, fix these two inaccuracies:

1. **RetroStar**: The introduction claims "SA score + RetroStar lookup" in the lead optimisation phase. RetroStar is not in the codebase. Change to: *"SA score (via scaffold hopping pipeline)"* and remove the RetroStar reference.

2. **Druggability assessment**: The introduction says "fpocket + SiteMap-equivalent." SiteMap requires a Schrödinger license and is not available. Change to: *"pocket detection and druggability scoring (fpocket)"* with a note that this is currently at tool level and the workflow wrapper is in progress.

3. **Pocket detection as a standalone step**: Reframe as a feature of the docking workflow, not a standalone step, until Gap 8 is built.

---

## 6. Longer-Term Opportunities (Post-Study)

| Opportunity | Rationale | Effort |
|---|---|---|
| Multi-objective BO loop (Gap 5) | Central to DMTA loop; differentiates BioMate from single-tool platforms | 3–4 weeks |
| ASKCOS / AiZynthFinder retrosynthesis | Replaces missing RetroStar; open-source | 1.5 weeks |
| CRO API integration (WuXi, Pharmaron) | Closes the order loop without manual CSV handoff | 3–4 weeks (depends on CRO cooperation) |
| LINCS/CMap integration for drug MoA | Turns RNA-seq response into mechanism hypothesis automatically | 1 week |
| Accelerator Consortium SDL partnership | Routes BioMate Design output directly to robotic Make + Test | Strategic; 3–6 months |
| Phenotypic screening analysis (HCS image → hit) | New data type for cellular drug screening; substantial scope | 4–6 weeks |

---

*Internal document. Do not share with external partners without review.*
