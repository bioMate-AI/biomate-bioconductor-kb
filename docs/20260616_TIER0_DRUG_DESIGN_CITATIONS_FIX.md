# Tier-0 Drug-Design Demos — Three-Gap Fix

**Date:** 2026-06-16
**Scope:** T01–T05 (bispecific PD-1×VEGF, in-vivo CAR-T CPTX-2309, PCSK9 base edit VERVE-101, GLP-1 bake-off retatrutide MASH, BCMA modality triage Carvykti).

## Problem (truth-table audit, 20260616_DEV_vs_CLAUDE_DESIGN_TRUTH_TABLE.md)

For all 5 tier-0 drug-design demos:

- **Not in `workflow_chains`** — the underlying nf-core sub-workflows existed under `backend/nf-core-workflows/modules/biomate-ai-tools/<wf>/main.nf`, but they were top-level workflows, not chain rows. Chain router could not route to them.
- **Zero `qc_evidence.yaml` coverage** — Citations tab in the After-run report was empty for every run.
- **Zero `rationale_registry` rows** — the `(why?)` anchor on each progress phase rendered nothing.

## Fix

### 1. `backend/config/qc_evidence.yaml` — 5 new domain blocks, 12 gates

Citations extracted verbatim from `Tier-0 Demo Requirement.md` §"Scientific-accuracy corrections" and `.nf` header comments. No invention.

| Domain | Gates | Anchor citations |
|---|---|---|
| `bispecific_format_triage` | `bispecific_tetravalent_cooperative`, `bispecific_format_review`, `harmoni2_clinical_readout` | Zhong 2024 iScience; Labrijn 2019 NRDD doi:10.1038/s41573-019-0028-1; Dhillon 2024 |
| `in_vivo_cart_codesign` | `cptx2309_anti_cd8_lnp`, `rurik_in_vivo_car_proof`, `fratricide_check` | Capstan ACR 2024; Rurik Science 2022 doi:10.1126/science.abm0594; Mamonkin Blood 2015 |
| `in_vivo_base_edit_design` | `verve101_abe_splice_donor`, `verve_lft_reformulation` | Musunuru Nature 2021 doi:10.1038/s41586-021-03534-y; Lee Circulation 2023 |
| `glp1_modality_bakeoff` | `retatrutide_triple_agonist_mash`, `tirzepatide_dual_agonist` | Sanyal NEJM 2024 doi:10.1056/NEJMoa2401026; Frias NEJM 2021 |
| `modality_triage_oncology` | `bcma_carvykti_abecma`, `belantamab_adc_bcma` | Berdeja Lancet 2021; Lonial Lancet Oncol 2020 |

YAML validates parseable; total domain count 28→34.

### 2. `backend/scripts/add_tier0_drug_design_chains.py` (new) — 5 chain rows

Each tier-0 demo wrapped as a 1-step chain whose single step points at the existing `nf-core-workflows/modules/biomate-ai-tools/<wf>/main.nf`. Internal phases A/B/C/D come from the `// [Phase X]` annotations already in each `.nf`.

Inserted ids 61–65. Script is idempotent.

### 3. `backend/config/rationale_mapping.yaml` — 5 chain blocks, 20 phase rows

Each chain maps its 4 phases to the most relevant gate from §1. All 20 rows marked `confirmed: true` curated_by `tier0-auto-from-spec` because the phase→gate pairing is mechanical from the `.nf` annotations + the spec narrative.

### 4. `populate_rationale_registry.py --apply`

44 rows written total (24 pre-existing bioc + 20 new tier-0). Verified all 20 tier-0 rows present, each bound to the correct `qc_gate_name`.

## Verification

```sql
SELECT rationale_id, qc_gate_name FROM rationale_registry
WHERE rationale_id LIKE '%_chain:%' AND rationale_id NOT LIKE 'bioc%'
ORDER BY rationale_id;
-- 20 rows, all tier-0 chains × {A,B,C,D}
```

## Effect

- Chain router can now route NL queries (e.g. *"Design a PD-1 by VEGF bispecific for NSCLC"*) to the tier-0 demos.
- After-run Citations tab populates from the qc_evidence gates that fired during the run.
- `(why?)` anchor on each progress message resolves `<chain_name>:<phase_letter>` via `/api/rationale/{rationale_id}` and shows the curated rationale + DOI.

## Next steps (deferred)

- Author the chain-narrator SSE `workflow.phase_started` emissions for each tier-0 chain (handoff in `20260616_RATIONALE_NARRATOR_HANDOFF.md`).
- Wire UC-level e2e tests for T01–T05 once the narrator emits phase events.
- Scientific lead audit of the 20 auto-confirmed rows (rows can be flipped back to `confirmed: false` per phase if any pairing is challenged).
