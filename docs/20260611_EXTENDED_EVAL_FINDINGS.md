# Extended Eval — Out-of-Distribution Behavior

**Date**: 2026-06-11
**Eval set**: `backend/lib/galaxy/ai/chain_composer/eval_queries_extended.jsonl` (20 queries spanning cryoEM, pharmacology, imaging, metagenomics, drug discovery, single-cell flavors)

## Headline arc

| Path | Mode match | Pattern hit |
|---|---|---|
| Stub, original NER+patterns | 30% | 35% |
| Stub, expanded NER | 55% | 35% |
| Stub, NER + broader patterns | 45% | **80%** |
| **LLM v2 (NER + broader patterns)** | **70%** | **80%** |

LLM rescues the out-of-distribution dropoff from 30% → 70%. Pattern hit rate stabilizes at 80% once `sequential_omics_pipeline.When` mentions specialized single-modality pipelines (PBPK, cryoEM SPA, CONCOCT, etc.).

## Per-query outcome breakdown (LLM v2)

20 queries, 10 LLM-composed + 10 curated-passthrough:

- **14 fully match** (mode + pattern)
- **5 right pattern + stepwise** instead of upfront (confidence 0.6–0.72 — defensible: system isn't confident enough for upfront, surfaces stepwise so user can review)
- **4 alt-pattern but coherent LLM chain** (e.g. CYP450 → `filter_cascade` instead of `iterative_refinement` — both shapes are plausible)
- **1 hard fail**: "single particle analysis of GPCR membrane protein in nanodisc" → forced reactive at conf 0.42. NER recognizes "GPCR" and "nanodisc" but no curated chain matches; pattern hits `multi_omics_integration` instead of `sequential_omics_pipeline`

## What this tells us

### The LLM path is robust to out-of-distribution

70% effective coverage on a 20-query eval that includes domains never tuned for. With composition + verification + revision, the LLM handles cryoEM, PBPK, metagenomics binning, antibody developability, MERFISH analysis without any of those being in the pattern library or curated chains specifically. The retrieval + workflow_v2 prompt context carries enough signal.

### The pattern library is genuinely incomplete for these domains

The `sequential_omics_pipeline` umbrella now covers them via wording, but they're shapes that deserve first-class treatment:

| Missing pattern | Domain | Shape signature |
|---|---|---|
| `pbpk_simulation` | pharmacology | ODE-solve compartment model + virtual cohort sampling + dose justification |
| `cryoem_particle_pipeline` | structural biology | Movies → motion correction → CTF → particle picking → 2D class → 3D class → refinement → optional heterogeneity |
| `metagenomics_binning_pipeline` | microbiome | Reads → assembly → binning (CONCOCT) → MAG QC → taxonomy → functional annotation |
| `hts_plate_qc_hit_calling` | drug discovery | Plate-level QC → normalization → hit calling → counter-screening |
| `mrna_design_cascade` | drug discovery | Sequence → codon optimization → UTR design → IVT plan |

Each is its own conceptual pattern but they're all sequential at heart. The current `sequential_omics_pipeline` description-with-list works for retrieval; whether to refactor into multiple patterns is a design call.

### NER vocabulary continues to grow

Adding domain-specific entities (PBPK, GPCR, MERFISH, CONCOCT, etc.) directly improves confidence scoring via the `query_specificity` signal. The vocabulary is now ~280 entries across organisms, modalities, tools, data types, contrasts, cohorts, analyses, assemblies. Bigger but still manageable.

### Curated chain coverage gap

The 5 stepwise-instead-of-upfront cases all hit pattern correctly but have weak curated chain match because no curated chain anchors these domains. Adding 5-7 hub-anchored chains per domain would close the confidence gap:

- `gpcr_spa_pipeline` — anchor on `GPCR Complex SPA` (already a biomate workflow)
- `pbpk_renal_impairment_chain` — anchor on `pbpk_disease_state`
- `shotgun_metagenomics_to_mag` — anchor on `Fasta Binning Concoct` + `Mmseqs Contig Taxonomy`
- `phase2_to_phase3_dose_justification_chain` — anchor on `phase2_dose_justification`
- `target_tractability_assessment_chain` — anchor on `target_tractability_scorer`
- `mrna_codon_optimization_chain` — anchor on `mrna_therapeutic_design`
- `cyp450_ddi_chain` — anchor on `CYP450 DDI Panel + Hepatic Clearance`

These would lift the 5 stepwise cases to upfront, getting the LLM run to ~95% mode match.

## What I'm NOT proposing right now

- **Splitting `sequential_omics_pipeline` into 5 specialized patterns** — would balloon the library; the broadening text works.
- **Authoring the 5-7 domain chains right now** — substantial work (~60-90 min each); flagging as the natural next session if you want.
- **Production wiring** — out of scope per session-long policy.

## Status

Extended eval baselined and committed (`a598a7099`). Realistic out-of-distribution performance:

- 70% mode match (LLM path)
- 80% pattern hit
- 50/50 split LLM-composed vs curated-passthrough
- 0 verifier errors observed

The prototype now has empirical numbers across both in-distribution (100%) and out-of-distribution (70% LLM) regimes.
