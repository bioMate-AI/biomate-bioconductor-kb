# BioMate platform generality audit — which "general" features are actually case-specific (2026-11-04)

Follows the deck-scenario audit (`20261104_DECK_SCENARIO_CAPABILITY_AUDIT_AND_FIXES.md`).
Four parallel code audits judged shipped code only. The worry — "good features that
are case-specific, not general" — is confirmed, and resolves into **four distinct
patterns**, each with a different fix.

## The four patterns
- **A — general core, single consumer.** The design is domain-neutral; it has only ever
  been wired to ONE case. Fix = add a second real consumer.
- **B — hardcoded per domain, no general mechanism.** Hand-written branches for a handful
  of domains; a new domain gets nothing. Fix = build the missing general mechanism.
- **C — general substrate, non-uniform quality.** The base (retrieval/LLM/schema) is general,
  but all the quality-boosting logic is hand-tuned for a few domains. Fix = fold special-cases
  into the general layer / data-drive them.
- **D — general engine BUILT but dormant behind a default-off flag.** Fix = activate + validate
  (the cheapest, highest-leverage wins).

## Consolidated map

| Subsystem | Verdict | Real coverage vs ~34–40 catalog domains | Pattern |
|---|---|---|---|
| Execution engine (Nextflow/Batch), literature search, methods-text | **GENERAL** | all | — |
| Accession resolve | general but **seq-only** (GEO/SRA/ENA; no PDB/ChEMBL/PRIDE) | — | C |
| **Model training** | **GENERALIZED this session** (generic tabular + k-fold CV + routing) | was 0 non-molecule; now general | D→fixed (activate `ML_TRAINING_ROUTING`) |
| **Multi-omics integration** | **general engine (arbitrary N layers, 7 methods, data-shape selection, generic normalizer) — but DORMANT** behind `MULTIOMICS_ROUTING`=off; default face is a hardcoded MOFA2 rna+protein workflow | engine: any; default-reachable: 1 | **D (quick win)** |
| Multi-channel **arbiter** | general fusion math; target-ID-named types/weights; **0 consumers outside `target_id/`** | 1 | A |
| **Grounded** evidence engine | pluggable tier model; assembly logic + both corpora regulatory-threshold-specific | 2 (both CMC/GMP) | A/B |
| **Reward / rule-gate** vocabulary | genuinely general declarative vocab (no domain terms); **only `ml_training` GRPO uses it** | 1 | A |
| **QC-evidence gates** | **CASE-SPECIFIC** — ~45 bespoke parsers + ~37 process-name threshold branches; config tunes *values* not *gate definitions*; new domain → "not_evaluated". BUT a general self-describing path exists (`qc_records.assess_qc_document` reads a workflow-emitted `_all_metrics`/`qc_metrics.json`) and a `BIOC_` catch-all | ~10 blocking (+ self-describe path under-used) | B (general path exists, not the default) |
| Auto-loop **parameter remediation** | **CASE-SPECIFIC** — 5 hardcoded pharma domains (ADMET/docking/CYP-DDI/NCA-PK/PBPK), per-gate `if gate=="herg_ic50"`. (The general `autofix/` LLM layer only fixes execution CRASHES, never gate/param breaches.) | 5 | B |
| **Routing rules** | **CASE-SPECIFIC** — hand-written blocks for 7 domains (drug_discovery = 26 of ~50 bullets), even a per-accession S3 hardcode; no-rule domains get an irrelevant full-dump + generic search | 7 | B/C |
| **Param-prefill** | general schema+description LLM base, overlaid with RNA-seq-contrast / genome / SMILES special-cases + 18 drug-workflow alias tables | base: all; boosted: ~RNA-seq + drug cluster | C |
| **Findings / results** | general grounded-LLM fallback for TEXT outputs; ~8–9 workflow families have bespoke rich parsers; data-driven descriptor system exists (5 rows); proactive next-step = **1 hardcoded demo storyline** (complement→Iptacopan); binary outputs degrade | ~8–9 rich; rest = LLM best-effort | C |

**The through-line:** BioMate's *substrate* is general (execution, retrieval, LLM bases, and
several genuinely general *cores*), but nearly every *intelligence layer that makes it good*
— routing, param boosts, QC gates, remediation, findings parsers — is hand-written for **~5–6
sequencing domains + a hand-tuned drug-discovery cluster**. The code's own
`pattern_router.py` self-rating agrees: transcriptomics/genomics/variant/epigenomics/single-cell
0.72–0.80; everything else < 0.75. Breadth is real in the *catalog*; the *smarts* are concentrated.

## Prioritized generalization plan (impact × tractability)

**Tier 1 — activate what's already general (days, low risk).**
1. **Model training** — DONE (code): generic tabular + k-fold CV + routing. Activate by setting
   `ML_TRAINING_ROUTING=1` on dev + a CPU Batch smoke.
2. **Multi-omics** — the general engine is already built and tested-looking; set `MULTIOMICS_ROUTING=1`,
   validate the planner on a 2–3 layer example, and replace the hardcoded MOFA2-rna+protein
   default face with the planner. Highest leverage per hour.

**Tier 2 — one general mechanism replaces many hardcodes (the synergy).**
3. **Make the declarative rule-gate engine the GENERAL QC-gate mechanism.** The reward/rule-gate
   interpreter (Pattern A, general vocab, already shipped) + the self-describing `qc_records`
   path are the same idea as the ~45 hardcoded QC branches. Have workflows *declare* their gates
   as data (they already can via `qc_metrics.json`), route them through the general interpreter,
   and the per-process if/elif chains stop being the only path. One engine covers training gates,
   QC gates, and inference guardrails → removes Pattern B for QC.
4. **Generalize the arbiter** — rename public types `TargetScore`→generic `EntityScore`, move the
   target-ID channel priors into config, and wire a second consumer (e.g. the multi-omics or
   literature evidence-fusion). Turns Pattern A into exercised generality.

**Tier 3 — fold case-specifics into the general layer (larger).**
5. **Routing** — convert the 7 hardcoded rule blocks into per-domain rule *data* (one schema any
   domain fills), so coverage scales without code; keep the retrieval substrate.
6. **Param-prefill** — move the RNA-seq-contrast / genome / SMILES special-cases behind the
   schema+description general extractor so any workflow's params benefit.
7. **Findings** — lean on the data-driven descriptor system + the grounded-LLM fallback; retire the
   single hardcoded "complement→Iptacopan" proactive storyline.

## This is a program, not a one-session fix
Generalizing 8 subsystems across ~30 under-served domains is multi-week. The right first moves
are Tier 1 (activate the two dormant general engines — model-training is done, multi-omics is a
flag + a day) and Tier 2 item 3 (one general gate engine). Which domains to generalize *first*
should follow the business, not catalog breadth — see below.

## Business-grounded priority (SYSUCC 中山肿瘤 + faculty research directions)
Two source materials, read 2026-11-04, converge on the same spearhead:
- **SYSUCC** (`docs/20261030_SYSUCC_BD_CAPABILITY_AND_USE_CASES_ZH.md`): China's #1 tumor
  clinical-trial center. Published strengths = **genomics, single-cell & spatial, pathology,
  immunology, biomarkers**. Data assets = a ~1,000-patient CRC genomic cohort, an NPC single-cell
  + spatial atlas, blood/ctDNA biomarkers. Drug modalities = PD-1/PD-L1, ADC, bispecific, cell
  therapy, EBV vaccines/antibodies — **NOT small-molecule原创**. BioMate's role = the "科研执行与
  学习层" turning hospital data into stratification/biomarker/IND-advancing evidence (IIT→IND).
- **Faculty survey** (`business/BioMate_Research_Direction_Survey_20260303.md`): Direction B =
  "RNA-seq for **Patient Subgrouping, Diagnosis & Prognosis**" (#2); thesis: *"the AI advantage
  stops at molecule design; patient stratification from RNA-seq and biomarker-driven design are
  the next frontiers."* FFPE RNA-seq (hospital biobank format) flagged as a differentiator.

**The spearhead = all basic omics layers made first-class, feeding stratification / prognosis /
biomarker discovery on hospital cohorts** — depth on one chain, not breadth across 30 domains.

Basic omics stack and its current generality (prioritize the weak ones, they are NOT niche):
- Transcriptomics 0.80, genomics/variant 0.78, single-cell 0.72 — **strong** (keep).
- **Spatial 0.55 — PARTIAL** (no composed pipeline): SYSUCC's *published* NPC spatial atlas → top demo.
- **Proteomics 0.62, metabolomics 0.58 — WEAK but FOUNDATIONAL.** Correction (2026-11-04): these
  are NOT low priority. They are basic omics layers; SYSUCC's blood/plasma **biomarker** research is
  largely mass-spec proteomics/metabolomics, and multi-omics stratification is incomplete without
  them as first-class layers. The analysis workflows exist (DEqMS, MSstats, xcms, clusterProfiler);
  what's thin is the *intelligence layer* (routing, param prefill, QC gates, stratification wiring).
  → prime generalization targets, alongside spatial.
- Clinical / multi-modal — the 院内数据 core; correspondence established by the hospital (honest).

Re-ranked program (business-weighted):
1. **Patient stratification / prognosis** — model-training generalization (DONE tonight: expression
   matrix → subtype/prognosis + k-fold CV); next, wire to the clinical-stratification workflow and
   demo on a CRC-subtype / NPC cohort.
2. **Multi-omics integration, with EVERY basic layer first-class** — activate the engine AND bring
   the routing/param/QC generalization to the weak layers (spatial, **proteomics, metabolomics**),
   so "integrate genomic+transcriptomic+proteomic+metabolomic+clinical → subtype" is really general.
3. **Spatial omics** composed pipeline (SYSUCC NPC atlas). **Deeper finding (2026-11-04):** the
   atomic spatial subworkflows cannot simply be chained — they are **vignette-bound stubs with
   incompatible contracts**, not a shared interface: `spatialexperiment` emits a SpatialExperiment
   `.rds`, but `spatialde` takes `[meta, [Rep11_MOB_0, MOB_sample_info]]` (a specific vignette
   dataset), `spotlight` takes `[sce, spe]`, `spatialdecon` takes `[nsclc]` (a GeoMx vignette set).
   So the real work is **(a) standardize each spatial subworkflow to a shared SpatialExperiment
   take/emit contract, (b) then compose** `visiumio/spatialexperiment → QC → spatialde → spotlight`
   into `workflows/bioconductor_spatial/`, and (c) validate on a dev Visium run. Authoring the
   composition blind would ship a broken DAG — do (a) first. (Also no slide-image segmentation:
   add cellpose/stardist or drop that step from the illustration.)
4. **Immunology / immune deconvolution** (their PD-1/immunotherapy trial strength; currently generic).
5. **Target-ID (arbiter) generalization** — EBV / immunotherapy own-drug direction.

Lower priority for THESE audiences:
- Generic **small-molecule** drug design (ADMET/docking/QSAR) — SYSUCC doesn't do small-molecule原创.
- Their drug side (antibody/ADC/bispecific/cell-therapy) is already hand-tuned (`adc_design`,
  `bispecific_format_triage`, `cart_construct_design`) → needs **polish, not generalization**.
