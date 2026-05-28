# Phase Index Audit — Findings (#23)

**Date:** 2026-05-28
**Audit CSV:** `docs/20260528_PHASE_INDEX_AUDIT.csv` (2178 rows)

## Headline numbers

- 2178 total subworkflow `.nf` files scanned
- **16 (0.7%) have `// [Phase X]` annotations** — all under `drug_discovery/`
- 2162 (99.3%) unannotated
- Annotated breakdown by distinct groups: 1g:3, 2g:1, 3g:1, 4g:11. All 16 include human labels.

## Root cause of "Phase other"

**Not a parser bug.** Parser at `ai_assistant.py:714-746` handles skip-letters (A/B/D), multi-process-per-phase, and back-scan boundaries correctly. Verified on 4 workflows / 13 processes.

The bug is in the **interaction between the keyword fallback `_GENERIC_PHASE_RULES` (`ai_assistant.py:671-700`) and the frontend grouping at `nextflow-workflow-viewer.tsx:1259-1278`**:

- Frontend line 1260: `hasGroups = some(p => p.phase_group)` — empty string is falsy
- Line 1264: when *no* step has a group → renders `label: 'Steps'` (good)
- Line 1268-1269: when *at least one* step has a group → unmatched siblings fall into `key='other'` → rendered as `"Phase other"`

The mixed state happens when `_GENERIC_PHASE_RULES` matches *some* process names (e.g. anything containing `REPORT`, `VALIDATE`, `ALIGN`, `SIMULATE`) but misses domain-specific siblings — common in unannotated ADMET, docking, AlphaFold workflows.

## Fix recommendations

1. **Frontend** (`nextflow-workflow-viewer.tsx:1269`): change fallback label so `key === 'other'` renders `'Other Steps'`, never `'Phase other'`
2. **Backend** (`ai_assistant.py:_enrich_steps_with_phase_info`): skip `_GENERIC_PHASE_RULES` entirely when the file has zero `// [Phase X]` annotations — forces uniform empty `phase_group` so frontend's "Steps" path fires cleanly
3. **Optional**: for annotated workflows, default residual processes to the *last* declared phase instead of `''`

## Top-20 unannotated workflows to backfill

(High-traffic / demo-critical, ordered)

1. `nextflow_nfcore/subworkflows/cryo_em/cryosparc_standard_spa/main.nf` — would let us delete hardcoded `_CRYOSPARC_STEP_PHASES` map
2. `pharmacology/docking_autodock_vina/main.nf`
3. `pharmacology/predict_admet_properties/main.nf`
4. `pharmacology/ADMET_pred/main.nf`
5. `drug_discovery/ADMET_pred/main.nf`
6. `drug_discovery/structure_prediction_docking/main.nf`
7. `drug_discovery/schrodinger_glide_docking/main.nf`
8. `drug_discovery/p0_docking_validation/main.nf`
9. `drug_discovery/moe_covalent_docking/main.nf`
10. `drug_discovery/drug_moa_rnaseq/main.nf`
11. `drug_discovery/alphafold_db_search/main.nf`
12. `bioconductor/scrnaseqapp/main.nf`
13. `pharmacology/transporter_ddi_prediction/main.nf`
14. `pharmacology/run_diffdock_with_smiles/main.nf`
15. `pharmacology/run_autosite/main.nf`
16. `pharmacology/qsar_rf_model/main.nf`
17. `pharmacology/repeated_dose_tox_prediction/main.nf`
18. `pharmacology/retrieve_topk_repurposing_drugs_from_disease_txgnn/main.nf`
19. `pharmacology/run_3d_chondrogenic_aggregate_assay/main.nf`
20. `pharmacology/sigmoid/main.nf`

Backfilling all 2162 is **not** recommended — the frontend+backend fix alone resolves the user-visible bug, and most unannotated files are rarely-used nf-core stubs where "Steps" is acceptable.

## Parser verification (no bugs found)

| Workflow | Processes | Phases |
|---|---|---|
| `ich_s5_reproductive_tox` | 3 | A, B, D (skip-C handled) |
| `transporter_ddi_pgp_bcrp` | 2 | B, D |
| `amber_pmemd_md` | 7 | A,A,B,B,C,D,D (multi-proc/phase) |
| `p0_pkpd_semaglutide` | 1 | B |
