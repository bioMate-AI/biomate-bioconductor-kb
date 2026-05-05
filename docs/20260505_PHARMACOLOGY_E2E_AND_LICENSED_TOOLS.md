# Pharmacology E2E Tests + Licensed Tool Integration
2026-05-05

## What was built

### New Nextflow Workflows (IDs 12911–12923)

| ID | Name | Domain | Quality Tier |
|----|------|--------|--------------|
| 12911 | bispecific_antibody_design | drug_discovery | — |
| 12912 | sirna_offtarget_analysis | drug_discovery | — |
| 12913 | survival_analysis_km | drug_discovery | IND-ready |
| 12914 | fcrn_antibody_pk | drug_discovery | — |
| 12915 | ich_s7a_safety_pharmacology | drug_discovery | ICH S7A |
| 12916 | pbpk_pediatric | drug_discovery | IND-ready |
| 12917 | simcyp_pbpk | drug_discovery | regulatory_submission (BYOL) |
| 12918 | nonmem_poppk | drug_discovery | fda_submission_grade (BYOL) |
| 12919 | pk_sim_pbpk | drug_discovery | ema_accepted_open_source |
| 12920 | evo2_variant_effect | genomics | — |
| 12921 | alphagenome_track_prediction | genomics | — |
| 12922 | ich_s5_reproductive_tox | drug_discovery | ICH S5(R3) |
| 12923 | transporter_ddi_pgp_bcrp | drug_discovery | FDA 2020 DDI |

### License Registry Updates (`license_registry.py`)
- AlphaFold3: `user_must_provide: True` (each user registers at alphafold.ebi.ac.uk — free, ~1 day)
- Boltz-2: `user_must_provide: False` (key optional — local weights fallback available without any key)
- Added: Simcyp, NONMEM, GastroPlus, Schrödinger FEP+, StarDrop, Monolix (all BYOL)
- Clarified: BioMate does NOT hold AlphaFold3 or Boltz-2 master keys; local weights only for Boltz-2

### galaxy-assistant.ts Routing Rules Added
- pk_sim_pbpk — "PK-Sim", "OSP Suite", "Open Systems Pharmacology"
- simcyp_pbpk — "Simcyp", "Certara PBPK", "population PBPK"
- nonmem_poppk — "NONMEM", "FOCE-I", "nmfe75", "population PK"
- survival_analysis_km — "Kaplan-Meier", "survival analysis", "HR table"
- fcrn_antibody_pk — "FcRn", "IgG half-life", "YTE mutation"
- ich_s7a_safety_pharmacology — "ICH S7A", "hERG safety", "core battery"
- pbpk_pediatric — "pediatric PBPK" WITHOUT pregnancy (pregnancy → pbpk_pediatric_pregnancy)
- ich_s5_reproductive_tox — "ICH S5", "DART", "reproductive toxicity"
- transporter_ddi_pgp_bcrp — "P-gp inhibition", "BCRP", "OATP", "transporter DDI"
- evo2_variant_effect — "Evo 2", "DNA language model variant"
- alphagenome_track_prediction — "AlphaGenome", "Enformer successor"

### Named-tool PBPK gate bypass
- Added `_isNamedPkToolQuery` check at lines 1784+1852 in galaxy-assistant.ts
- PK-Sim/Simcyp/NONMEM/FcRn/ICH-S7A/Survival/Pediatric/nlmixr2 queries skip the generic PBPK prereq gate (SMILES/CLint check) and route directly

## E2E Test Suite
`frontend/e2e/pharmacology-e2e.e2e.ts` — 7 tests (PH-1 through PH-7)

| Test | Workflow | Status |
|------|----------|--------|
| PH-1 | pk_sim_pbpk | 7/8 assertions ✓ (findings card didn't appear — page idle during long poll) |
| PH-2 | simcyp_pbpk | running |
| PH-3 | survival_analysis_km | pending |
| PH-4 | fcrn_antibody_pk | pending |
| PH-5 | ich_s7a_safety_pharmacology | pending |
| PH-6 | pbpk_pediatric | pending |
| PH-7 | nonmem_poppk | pending |

## Scientific Validation

### ICH S5 (ich_s5_reproductive_tox) — tested locally
- Thalidomide analog `N1C(=O)CCC1=O`: correctly flagged RED, 1 HIGH structural alert (glutarimide)
- Correct margin of safety: 20x, EFD required before first dose in WOCBP
- Placental Kp: 1.0 (MW < 300, logP 0.38 — small neutral, good transfer)

### Transporter DDI (transporter_ddi_pgp_bcrp) — tested locally
- Itraconazole (MW=705.6, pgp_ic50=0.8µM, 200mg dose): correctly flagged RED
  - P-gp R=1418 (Igut=1135µM >> IC50=0.8µM) → clinical DDI with digoxin
  - BCRP R=455 (Igut >> IC50=2.5µM) → clinical DDI with rosuvastatin
  - OATP1B1 R=20 → clinical DDI with atorvastatin

## Known Issues
- pbpk_pediatric vs pbpk_pediatric_pregnancy FTS score gap (3 pts); LLM routing rule handles correctly
- Galaxy-assistant.ts routing rules are getting long (~30+ rules); deferred optimization to domain-gate injection
- findings-card-appeared assertion in PH-1 fails (page goes idle during 10-min Batch poll); not a workflow failure

## Open Items
- PH-2 through PH-7 E2E tests completing
- GastroPlus NF wrapper (P2, knowledge in DB, no NF file yet)
- Schrödinger FEP+ NF wrapper (P2)
- Dev verification after sync
