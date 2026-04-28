# Drug Development Gap Workflows — Build Session
**Date:** 2026-04-17  
**Branch:** integration/next-phase

---

## Summary

Built 16 new Nextflow workflows for drug development gaps, all registered in `galaxy_ai_tools.db` with FTS + BGE dense embeddings updated (2449 → 2465 workflows).

---

## Workflows Built (IDs 12861–12876)

All workflows follow the standard pattern:
- Location: `backend/biomni_workflows/nextflow_nfcore/subworkflows/{pharmacology,drug_discovery}/*/main.nf`
- Container: `biomate/biomni-tools:latest` (ECR: `biomni-tools:x86`)
- Python inline via `<< 'PYEOF'` heredoc; RDKit + SciPy + NumPy available
- `nextflow.config` copied from `predict_admet_properties/`

### 14 TRULY_NEW (built from scratch)

| ID | Name | Gap | Key algorithm |
|----|------|-----|---------------|
| 12861 | `allometric_scaling` | D4 | Power-law regression (log-log), Rule of Exponents, MABEL/MRSD FIH dose (FDA 2005) |
| 12862 | `cns_penetration_prediction` | B2 | CNS MPO score (Wager 2010, 6 descriptors), P-gp Seelig model, Kpuu brain (Friden 2011) |
| 12863 | `dart_toxicity_prediction` | A5 | 16 DART SMARTS alerts (ICH S5/OECD/EPA DSSTox), placental transfer model (MW/LogP/TPSA/HBD) |
| 12864 | `oral_absorption_bcs_model` | B3 | ESOL solubility (Delaney 2004), Caco-2 QSAR (Hou 2004), BCS I–IV, dissolution ODE |
| 12865 | `transporter_ddi_prediction` | D3 | 8 FDA transporters, rule-based substrate/inhibitor (Karlgren 2012), FDA basic model R=1+Cmax/IC50 |
| 12866 | `repeated_dose_tox_prediction` | A2 | 25+ structural alerts (hepatotox, cardiotox, nephrotox, bone marrow), NOAEL/safety margin |
| 12867 | `nanoparticle_pk_biodistribution` | B4 | 4-cmt ODE (blood/tumor/liver/peripheral), PEG stealth (brush regime), EPR (Wilhelm 2016) |
| 12868 | `membrane_permeability_prediction` | B5 | Caco-2 QSAR (Hou 2004), PAMPA QSAR (Gao 2008), efflux ratio, BCS permeability class |
| 12869 | `lnp_formulation_optimization` | B1 | RDKit pKa proxy, Henderson-Hasselbalch endosomal escape, tissue targeting, molar ratio sweep |
| 12870 | `target_engagement_kinetics` | C1 | kon diffusion-limit model, koff = kon × Kd, receptor occupancy ODE, 1-cmt biexponential PK |
| 12871 | `proteome_selectivity_profiling` | C2 | ChEMBL REST API similarity search + kNN activity transfer, selectivity entropy + Gini index |
| 12872 | `covalent_warhead_design` | C3 | 15-warhead SMARTS library, GSH t½ per warhead type, kinome Cys selectivity (10 kinases) |
| 12873 | `pbpk_simulation` | D1 | 8-cmt PBPK ODE (Rodgers/Rowland Kp, well-stirred liver), Willmann physiology, OATP1B1/P-gp DDI |
| 12874 | `clinical_trial_simulation` | D2 | BOIN algorithm (Liu & Yuan 2015), 3+3 design, 1-cmt PopPK + Emax ER model, Phase II simulation |

### 2 DB_INSTALLABLE (built as Nextflow wrappers)

| ID | Name | Gap | Key content |
|----|------|-----|-------------|
| 12875 | `metabolite_prediction_biotransformer` | A3 | BioTransformer 3.0 rule-derived SMARTS; 10 phase I + 6 phase II + 3 gut reactions; multi-cycle (up to 3 gen) |
| 12876 | `pharmacogenomics_pgx_report` | D5 | 11 PGx genes, CPIC 2024 activity scoring, 30+ drug-gene recommendation pairs (codeine, warfarin, clopidogrel, 5-FU, etc.) |

---

## Extended Existing Workflow

### `cyp_ddi_panel/main.nf` — R2 TDI Added (A4)

The `DDI_RISK_ASSESSMENT` process previously only computed R1 (reversible) and R1gut. Added:

**TDI structural alerts** (6 MBI SMARTS):
- `methylenedioxy` → CYP1A2/3A4 (berberine, piperone)
- `terminal_alkyne` → CYP3A4 (gestodene, ethinyl estradiol)
- `furan_ring` → CYP3A4/1A2 (furafylline)
- `thiophene` → CYP2C9/2C19 (ticlopidine metabolite)
- `aniline` → CYP1A2/2C19 (procainamide)
- `primary_alkyl_amine` → CYP3A4

**R2 static model** (FDA 2020 Guidance Section 4.3.2):
```
R2 = 1 / (1 + kinact * [I]gu / (kdeg * (KI + [I]gu)))
```
- `kinact_est = 0.04 min⁻¹` (conservative)
- `KI_est = 10 × IC50` (empirical relationship)
- CYP-specific `kdeg` from FDA Table 3
- Thresholds: R2 ≤ 0.79 → INVESTIGATE, R2 ≤ 0.71 → CLINICAL_STUDY_RECOMMENDED

New fields added to `cyp_ddi_flags[isoform]`:
- `R2_TDI_value`, `R2_TDI_flag`, `R2_TDI_alerts[]`
- `tdi_structural_alerts[]` in summary
- `n_tdi_flagged` in summary

---

## Bugs Fixed

### `cns_penetration_prediction/main.nf`
- **Bug**: `predict_cns_mpo(mol, pKa=pka_in, logd=logd_in)` — function signature uses `pka` (lowercase), call used `pKa`
- **Fix**: Changed to `predict_cns_mpo(mol, pka=pka_in, logd=logd_in)`

### `dart_toxicity_prediction/main.nf`
- **Bug**: `params.smiles_list` default was phthalimide `O=C1NC(=O)c2ccccc21` (no glutarimide ring — doesn't trigger the key DART alert), comment said "thalidomide"
- **Fix**: Changed to full thalidomide `O=C1CC(N2C(=O)c3ccccc3C2=O)C(=O)N1` — correctly triggers both `glutarimide_ring` and `phthalimide` SMARTS alerts

### `metabolite_prediction_biotransformer/main.nf` (caught during testing)
- **Bug 1**: `rxn_str = f'[{rxn_smarts_substr}]>>[{rxn_smarts_prod}]'` — double brackets made SMARTS invalid
- **Fix**: `rxn_str = f'{rxn_smarts_substr}>>{rxn_smarts_prod}'`
- **Bug 2**: Ester hydrolysis SMARTS tried to emit two fragments (acid + alcohol) — only one can be produced per reaction SMARTS application
- **Fix**: Changed to `[CX3](=[O])[O:2][#6:3]>>[OH:2][#6:3]` — keeps the alcohol/phenol fragment (e.g. aspirin → salicylic acid)

---

## Smoke Tests — All Pass

| Test | Compound | Result |
|------|----------|--------|
| Allometric scaling | rat + dog CL | human CL = 4.16 mL/min/kg ✓ |
| CNS MPO | aspirin | MPO = 4.30 ✓ |
| DART alerts | full thalidomide | glutarimide + phthalimide hits ✓ |
| NP PK ODE | synthetic | C_blood decays, C_tumor accumulates ✓ |
| BCS classification | aspirin | BCS_IV ✓ |
| BioTransformer | codeine | O-demethylation → 2 products ✓ |
| BioTransformer | aspirin | ester hydrolysis → salicylic acid ✓ |
| PGx phenotype | CYP2D6 *4/*5 | Poor Metabolizer (AS=0) ✓ |
| PGx phenotype | CYP2C19 *1/*17 | Ultrarapid Metabolizer (AS=2.5) ✓ |

---

## Embedding Index Rebuild

The `database/galaxy_ai_workflow_embeddings.npz` was stale (2449 entries, max_id=12860). Rebuilt using:
```bash
python3 rebuild_embeddings.py  # inline script using sentence_transformers BGE-small-en-v1.5
```
Result: **2465 embeddings** (384-dim), all IDs 12861–12876 confirmed present.

The `_ensure_workflow_embeddings()` function in `unified_workflow_search.py` loads the npz on first search call (no staleness check). Rebuilding now ensures all 16 new workflows are immediately reachable via dense retrieval at server startup.

---

## Notes / Open Items

- **A1 (NetMHCPan/epitope prediction)**: Already covered by `nf-core/epitopeprediction` (id=12700). No new workflow needed.
- **A4 CYP TDI**: Extended `cyp_ddi_panel` rather than building a new workflow (it's the right home for R2).
- **Pharmacogenomics input**: `pharmacogenomics_pgx_report` takes pre-called diplotypes (JSON) as input. It does NOT do genotyping from VCF — that requires a full germline pipeline. For real PGx, the user would run `wgs_germline_gatk` + a star-allele caller (e.g. Stargazer, DRAGEN PGx) first, then feed diplotypes here.
- **BioTransformer reaction coverage**: 19 reactions implemented (10 phase I, 6 phase II, 3 gut). Full BioTransformer 3.0 has ~80+ rules. The most clinically relevant transformations are covered; niche reactions (nitro-reduction, azo-cleavage, etc.) are missing but can be added as SMARTS.
- **No E2E Playwright tests yet** for any of the 16 workflows — routing via FTS + dense search should work for natural-language queries since they're in DB.
