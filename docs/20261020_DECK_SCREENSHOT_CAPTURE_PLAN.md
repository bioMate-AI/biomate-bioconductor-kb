# Deck screenshot capture plan — per use-case (2026-10-20)

Goal: each use-case deck gets a **full platform-flow** screenshot series showing
what BioMate looks like end-to-end for that use case. Captured against dev
(`https://dev-public.biomate.ai`) with a **clean-history user** so the sidebar has
no stale/foreign chats in frame.

## Clean-history requirement
The shared fixture (`lifeifei163361@163.com`) has a cluttered sidebar (many
"Screen these SMILES…" + Chinese chats). For clean screenshots, EITHER:
- register a fresh user (`/api/auth/register` + `terms_accepted:true` + e2e token) and capture as that user, OR
- delete the old chats first (`DELETE /api/sessions/:id` per session) so the sidebar is empty.
Prefer the fresh user. (Blocked right now by a dev Postgres-DNS drop — see
`docs/20261020_UI_REFINEMENT_TRACKER.md`.)

## Common full-flow sequence (every workflow-running deck)
01 cold-start · 02 goal typed in composer · 03 AI response + analysis plan ·
04 workflow card + panel (prerun, params, QC settings) · 05 Confirm & Run ·
06 running (phase cards, live SSE) · 07 (gate scenario, where relevant) ·
08 completed · 09 Results/Findings · 10 Outputs + one file preview ·
11 Reproducibility record · 12 Download menu. Then the cross-surfaces once:
Data hub (dataset object), Workflows, Models.

Non-run decks (search, routing/boin/param/protocol-QC capability demos) capture
the answer/evidence/routing surfaces instead of a run.

---

## Per-deck: query + data + grounding workflow

| Deck | Use-case query (type or seed) | Data / inputs | Grounding workflow |
|---|---|---|---|
| **t0-getting-started** | "Screen these compounds for safety and rank them" (doorway tour) | inline SMILES | cold-start → ADMET (cross-cutting) |
| **t1-design-and-generate** | "Design new analogs of this seed and rank by developability" | seed SMILES | REINVENT4 lead design |
| **t2-models-closed-loop** | "Train a hERG classifier on my data, then use it to gate a design loop" | small labeled CSV | run_code / QSAR + design loop |
| **t3-run-and-report** | "Run differential expression on my counts and give me a report" | counts.tsv + design.csv | nf-core/deseq2 |
| **t4-bringing-your-own-data** | upload a file → open it as a dataset object | counts.tsv (upload) | Data hub / dataset object |
| **d1-qsar-classical-ml** | "Predict hERG cardiac safety for these SMILES with a QSAR model" | inline SMILES | `pharmacology/qsar_rf_model` + `herg_cardiac_safety_qsar` |
| **d2-admet-deep-learning** | "Screen these SMILES for ADMET liabilities and rank by developability" | **safe panel** aspirin `CC(=O)Oc1ccccc1C(=O)O`, caffeine `CN1C=NC2=C1C(=O)N(C(=O)N2C)C`, ibuprofen `CC(C)Cc1ccc(cc1)C(C)C(=O)O` → clean Completed; **gate scenario** add terfenadine (hERG) for the halt beat | ADMET-AI (Chemprop) `pharmacology/predict_admet_properties` |
| **d3-generative-lead-design** | "Generate optimized analogs of this scaffold against hERG/QED and rank them" | seed scaffold SMILES | `drug_discovery/reinvent4_lead_design` |
| **d4-binding-free-energy** | "Rank this congeneric series against the reference by relative binding free energy" | reference + series (ligand set) | `drug_discovery/openfe_rbfe` (OpenFE RBFE) |

### Drug-development demo set (expanded — >10, full pipeline)

Grounded in BioMate's real catalog (49 pharmacology + 61 drug_discovery subworkflows +
structural biology). Routing **verified live on dev** `/api/ai_assistant/generate_workflow`
on 2026-10-20 (✓ = routed to the named workflow; ~ = routed to a related chain/variant,
query to be tuned). Pipeline-ordered: target → hit → lead → structure/dynamics → DMPK →
safety → clinical/regulatory.

| Deck | Use-case query | Data / inputs | Grounding workflow | Routing |
|---|---|---|---|---|
| **dd1-target-id** | "Rank candidate targets for an autoimmune indication by tractability and genetic evidence" | indication / gene set (OpenTargets live) | `drug_discovery/gwas_scrna_eqtl_target_chain`, `target_scorecard_ranker` | ✓ |
| **dd2-virtual-screening** | "Virtual screen a compound library against this target with DrugCLIP" | target + library | `drug_discovery/drugclip_virtual_screening` | ✓ |
| **dd3-docking** | "Dock these ligands into the binding site with AutoDock Vina" | receptor PDB + ligand set | `drug_discovery/docking_autodock_vina` | ✓ |
| **dd4-qsar** (=d1) | "Predict hERG cardiac safety for these SMILES with a QSAR model" | inline SMILES | `pharmacology/herg_cardiac_safety_qsar` | ✓ |
| **dd5-admet** (=d2) | ADMET liability screen + developability rank | SMILES panel | `pharmacology/predict_admet_properties` | ✓ |
| **dd6-generative** (=d3) | "Use REINVENT to generate novel analogs of this scaffold optimized for QED and potency" | seed SMILES | `drug_discovery/reinvent4_lead_design` | ~ (emphasize "REINVENT/generate") |
| **dd7-rbfe** (=d4) | congeneric series → relative binding free energy | ref + series | `drug_discovery/openfe_rbfe` | ✓ |
| **dd8-md** | "Run a molecular dynamics simulation of this protein–ligand complex" | complex PDB | `drug_discovery/amber_pmemd_md` / `gromacs_protein_md` | ✓ |
| **dd9-structure** | "Predict the 3D structure of this protein sequence" | sequence | `structural_biology/boltz_structure_prediction` | ~ (routes to structure chain) |
| **dd10-retrosynthesis** | "Plan a retrosynthetic route for this molecule" | SMILES | `drug_discovery/syncraft_synthesizability` / `aizynthfinder_retrosynthesis` | ✓ |
| **dd11-pbpk** (=s2) | "Predict plasma concentration over time with a PBPK model" | PK params | `drug_discovery/pbpk_simulation` | ✓ |
| **dd12-nca** (=s1) | "Run non-compartmental PK on this concentration–time data" | conc–time CSV | `drug_discovery/nca_pknca` | ✓ |
| **dd13-ames** | "Predict AMES genotoxicity for these compounds" | SMILES | `pharmacology/genotoxicity_ames_prediction` | ✓ |
| **dd14-cyclic-peptide** | "Design a cyclic peptide binder against this target epitope" | target / epitope | `structural_biology/cyclic_peptide_cofold` / `cyclic_peptide_design` | ✓ |
| **dd15-clinical-trial** | "Simulate a phase 2 clinical trial for this dose range" | trial params | `drug_discovery/clinical_trial_simulation` | ✓ |
| **dd16-novelty-fto** | "Score chemical novelty and freedom-to-operate for these compounds" | SMILES | `drug_discovery/compound_novelty_scorer` | ✓ (generated) |
| **dd17-cro-ind-export** | "Export a CRO submission / IND package for this program" | program results | `drug_discovery/cro_submission_export`, `run_audit_export` | capability |

Further real drug-dev workflows available if more are wanted: `antibody_developability`,
`bispecific_antibody_design`, `fcrn_antibody_pk`, `metabolite_prediction_biotransformer`,
`cyp_ddi_panel`, `pocket_detection_druggability`, `ich_s7a_safety_pharmacology`,
`ich_s5_reproductive_tox`, `analyze_fda_safety_signals`, `scaffold_hopping`,
`pharmacophore_filtering`, `nonmem_poppk`, `allometric_scaling`, `pbpk_pediatric_pregnancy`.

**Capture economics:** dd5/d2 runs full (Batch) as the flagship. The rest are captured at
**prerun/routing + card** depth by default (cheap, no Batch) — each shows cold-start → goal
→ AI plan → workflow card + prerun panel (name, steps, params). Promote individual ones to a
full completed run only when a specific deck needs the completed/findings/outputs beats.
| **m1-search-and-evidence** | "Is JAK1 linked to rheumatoid arthritis? give cited evidence" | none (literature) | search & evidence (instant lane) |
| **m2-rnaseq-differential-expression** | "Which genes change between treated and control?" | **GSE52778** counts (airway smooth-muscle, dex vs ctrl) | nf-core/rnaseq → DESeq2 |
| **m3-accession-to-workflow** | "Analyze GSE52778" (accession → inferred method → workflow) | accession **GSE52778** / SRR1039508 | resolve_accession + context routing |
| **s1-noncompartmental-pk** | "Run non-compartmental PK on this concentration–time data" | `concentration_time` test CSV | `drug_discovery/nca_pknca` (PKNCA) |
| **s2-pbpk-simulation** | "Predict plasma concentration over time for this compound" | PK params | PBPK workflow |
| **s4-survival-analysis** | "Fit Kaplan–Meier + Cox on this survival table" | time/event/group CSV | Bioconductor `survival` (survfit + coxph + cox.zph) |
| **qpcr-ddcq** | "Compute ΔΔCq fold-change from this qPCR Cq table" | Cq CSV (wells, targets, housekeeping) | qPCR ddCq (base-R 2^-ΔΔCt) |
| **b1-train-custom-model** | "Train a model on my data and report its accuracy" | labeled CSV | `run_code` (sklearn in sandbox) |
| **rb-routing** | several diverse requests → each routes to the correct workflow | none | cross-domain routing (capability demo) |
| **rb-param-prefill** | a free-text request → correct workflow parameters pre-filled | none | param prefill (capability demo) |
| **rb-protocol-qc** | a protocol → PASS/FAIL QC verdict | protocol text | protocol-QC (capability demo) |
| **rb-boin** | a dose-escalation scenario → BOIN MTD decision | trial params | BOIN (clinical dose escalation) |

## Data staging notes
- SMILES-based decks (d1/d2/d3, t0/t1) run from **inline SMILES** in the query — no upload.
- Accession deck (m3) runs from the **accession string** inline.
- File-based decks (m2/t3/t4, s1/s4, qpcr, b1) need a **staged demo dataset**. The
  cold-start example cards attach a prepared public demo dataset (onSeed) for several
  of these — prefer clicking the matching example card so the data is attached and
  runnable without an upload. Where no seed exists, upload a small test file from
  `biomate-test-data` (S3) / the team test_data (Drive `1iqi_JD0`).
- Capability demos (rb-*) are answer/score surfaces, not full runs — capture the
  routing/param/QC/decision screens.

## Priority order (per user)
1. **Drug-dev first:** d2 (ADMET) ✅ 5 shots captured, d1, d3, d4, drug-dev overview.
2. Modules: m1, m2, m3.
3. Statistical: s1, s2, s4; qpcr.
4. Tutorials t0–t4; b1; rb-*.
