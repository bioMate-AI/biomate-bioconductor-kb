# BioMate CRO Phase 3 — Benchmark Scripts + Frontend Port Plan
**Date**: 2026-04-20  
**Branch**: `integration/next-phase`

---

## 1. What Was Built This Session

### 1.1 Scientific bug fixes (Phase 1/2/3 backend)

| File | Fix |
|------|-----|
| `backend/lib/galaxy/ai/drug_discovery/ind_assembly.py` | Wrong field keys `observed_Cmax_ug_mL` → `observed_Cmax`; fragile `sections.append()` side-effects inside list literal; `report.dict()` → `report.model_dump()` (Pydantic v2) |
| `backend/lib/galaxy/ai/compliance/audit_store.py` | Race condition on concurrent writes: `BEGIN IMMEDIATE` transaction serialises read-previous-hash + INSERT; added `PRAGMA synchronous = FULL` |
| `backend/lib/galaxy/ai/compliance/esig.py` | Plaintext fallback now raises if `BIOMATE_REQUIRE_ENCRYPTED_ESIG=1`; TOTP token cleanup on successful sign (prune tokens with `time_step < verified_step − 10`) |
| `backend/lib/galaxy/ai/drug_discovery/reference_data/pk_marketed_drugs.json` | Clopidogrel flagged `exclude_from_validation: true`; reason documented (prodrug, CL_true 4167 L/h = 46× hepatic blood flow) |
| `backend/lib/galaxy/ai/drug_discovery/model_validation.py` | `_load_reference_drugs()` filters `exclude_from_validation` entries |
| `backend/lib/galaxy/ai/drug_discovery/applicability_domain.py` | `max_tanimoto_similarity` field added to `ADResult` Pydantic model and populated in `check()` |
| `backend/lib/galaxy/ai/drug_discovery/api_router.py` | `report.dict()` → `report.model_dump()` |

### 1.2 Scientific test suite — `test_scientific_validation.py`

49 tests across 7 classes.  All pass.

| Class | Tests | Authoritative source |
|-------|-------|---------------------|
| `TestPKEquationInvariants` | 10 | Bateman equation; AUC mass balance (no double-F); ke = CL_app × F / Vd; EMA criterion 67%@2-fold; Clopidogrel excluded |
| `TestApplicabilityDomain` | 6 | Hat-matrix leverage + Tanimoto dual criterion; null-space OOD detection; 128-bit FP for test speed |
| `TestAuditChainIntegrity` | 10 | Genesis hash; chain linking; tamper detection (field mod, deletion, insertion); concurrent writes valid; `details` excluded from hash |
| `TestTOTPAndESignature` | 8 | RFC 6238; current/prev window; old window rejected; replay rejected; token cleanup |
| `TestINDAssembly` | 5 | Key names correct; all 6 sections present; EMA criterion text; no `?` placeholders with real data |
| `TestAutoRetrain` | 4 | Round-trip; overwrite; absent returns None; idempotent loop start |
| `TestReferenceDataset` | 6 | Clopidogrel excluded; required fields; CL_true ≤ 180 L/h; F_oral ∈ (0,1]; ≥20 included drugs |

### 1.3 Option A benchmark scripts

All 4 scripts in `scripts/`. Run inside the `biomni-tools` Docker container (RDKit required; fail loudly if missing — no mock fallbacks).

#### `scripts/run_dmta_simulation.py` (606 lines)

3-round DMTA simulation harness for retrospective ChEMBL benchmark.

- `ChEMBLOracle` — ground-truth pIC50 lookup from activity CSV
- `propose_random`, `propose_similarity` — baselines
- `propose_biomate` — wraps `BayesianOptimizer` + `CampaignDataset`; 3-round loop with oracle feedback
- `compute_enrichment_factor` — EF_f per Truchon & Bayly 2007 J Chem Inf Model
- `bootstrap_ci` — 1000-sample bootstrap, 90% CI
- `aggregate_results` — outputs `convergence_curves.csv` (input for Figure 3) and `seed_results.json` (input for Figure 4)
- CLI: `--activity-file`, `--n-rounds 3`, `--n-seeds 30`, `--output`

#### `scripts/download_chembl.py` (461 lines)

Downloads and curates ChEMBL IC50 data for EGFR (CHEMBL203), JAK2 (CHEMBL2971), BACE1 (CHEMBL4822), hERG (CHEMBL240).

Curation pipeline:
1. Filter `standard_relation = "="`, standard IC50
2. Convert all units to nM
3. Geometric mean per compound (dedup)
4. IC50 range filter (0.01–100,000 nM)
5. RDKit canonical SMILES round-trip validation

Output: `{target}_activity.csv` (smiles, compound_id, ic50_nM, pic50) + `{target}_metadata.json`

#### `scripts/run_admet_benchmark.py` (801 lines)

ADMET model AUROC benchmark against 5 published datasets.  **RDKit required at import — no fallbacks.**

| Dataset | Source | AUROC target |
|---------|--------|-------------|
| hERG | ChEMBL240 IC50 ≤ 10 µM | ≥ 0.84 (Cai et al. 2019) |
| DILI | DILIrank vMost vs vNo | ≥ 0.73 (Chen et al. 2016) |
| Ames | Hansen et al. 2009 | ≥ 0.82 (Kazius et al. 2005) |
| ClinTox | MoleculeNet CT_TOX | ≥ 0.80 (Wu et al. 2018) |
| Tox21 SR-MMP | MoleculeNet SR-MMP | ≥ 0.83 (Wu et al. 2018) |

Prediction functions used (mirror `predict_admet_properties/main.nf` RDKit phase):
- **hERG**: `log10(IC50_µM) = 1.4 − 0.30 × logP` → sigmoid score (Aronov 2008)
- **DILI**: Lammert 2010 logP+MW rules
- **Ames**: 12-alert SMARTS ensemble, Kazius 2005 reliability weights
- **ClinTox**: Lipinski violations + logP base + Ames boost
- **Tox21 SR-MMP**: logP + MW (Naven et al. 2013)

Output: `metrics.json`, `per_compound.csv`, `roc_data.json` (input for Figure 2)

#### `scripts/make_paper_figures.py` (678 lines)

4 publication figures, Okabe-Ito palette (Wong 2011 Nature Methods), Nature Chemical Biology style.

| Figure | Content | Input |
|--------|---------|-------|
| Fig 1 | PBPK Cmax parity plot, ±2-fold bands | `results/pbpk_validation/metrics.json` |
| Fig 2 | ADMET ROC curves + AUROC + 90% CI in legend | `results/admet_benchmark/roc_data.json` |
| Fig 3 | Cumulative active recovery per round, mean ± CI | `results/dmta_simulation/*/convergence_curves.csv` |
| Fig 4 | EF₅ bar chart grouped by target, error bars = 90% CI | `results/dmta_simulation/*/seed_results.json` |

Output: `paper/figures/fig{1-4}_*.{pdf,png}` + `figures_manifest.json`

---

## 2. Quick-Start: Full Option A Run

```bash
# All commands inside biomni-tools Docker container

# Step 1 — Download ChEMBL activity data
python scripts/download_chembl.py \
  --targets egfr,jak2,bace1 \
  --output data/chembl/ \
  --max-per-target 10000

# Step 2 — Run DMTA simulation (per target, in parallel)
for target in egfr jak2 bace1; do
  python scripts/run_dmta_simulation.py \
    --activity-file data/chembl/${target}_activity.csv \
    --n-rounds 3 --n-seeds 30 \
    --output results/dmta_simulation/${target}/ &
done
wait

# Step 3 — Run ADMET benchmark
python scripts/run_admet_benchmark.py \
  --datasets herg,dili,ames,clintox,tox21 \
  --data-dir data/admet/ \
  --output results/admet_benchmark/

# Step 4 — Run PBPK validation (via existing API endpoint)
curl -X GET "http://localhost:3000/api/validation?model_type=pbpk" \
  -H "Authorization: Bearer $JWT" \
  -o results/pbpk_validation/metrics.json

# Step 5 — Generate figures
python scripts/make_paper_figures.py \
  --pbpk   results/pbpk_validation/metrics.json \
  --admet  results/admet_benchmark/ \
  --dmta   results/dmta_simulation/ \
  --output paper/figures/
```

---

## 3. Frontend Port Plan (Claude Design → TypeScript)

Source: `reference/claude_design/cro/` (JSX prototype, 7 surfaces)  
Target: `frontend/client/src/components/drug-discovery/` (new) + extend `drug-discovery-action.tsx`

### Porting order (P0 first per UX spec)

| Priority | Surface | New file | Status |
|----------|---------|----------|--------|
| P0 | Surface 3 — Audit Trail | `drug-discovery-audit-viewer.tsx` | ✓ done |
| P0 | Surface 4 — Auto-Retrain | `drug-discovery-auto-retrain.tsx` | ✓ done |
| P0 | Tab bar + routing | extend `drug-discovery-action.tsx` | ✓ done |
| P1 | Surface 2 — Validation | `drug-discovery-validation-panel.tsx` | ✓ done |
| P1 | Surface 6 — IND Assembly | `drug-discovery-ind-assembly.tsx` | ✓ done |
| P2 | Surface 7 — Campaign Wizard | `drug-discovery-campaign-wizard.tsx` | ✓ done |
| P3 | Surface 5 — eSig Modal | `drug-discovery-esig-modal.tsx` | ✓ done |

### Tab bar extension (`drug-discovery-action.tsx`)

```ts
type DrugDiscoveryMode =
  | 'assay-upload' | 'cro-export' | 'dashboard'       // existing
  | 'validation' | 'audit' | 'auto-retrain'
  | 'ind-assembly' | 'new-campaign';                   // new
```

Tabs render only when `campaign_id` is set.

### Primitive mapping (JSX prototype → shadcn/ui)

| Prototype primitive | shadcn equivalent |
|--------------------|------------------|
| `RegChip` | `Badge variant="outline" className="font-mono text-xs"` |
| `Chip` | `Badge` |
| `Callout` | `Alert` |
| `Collapsible` | `<Collapsible>` from `@radix-ui/react-collapsible` |
| `Modal` | `<Dialog>` |
| `Toast` | `useToast()` |
| `CroIcon` | `lucide-react` icons |
| `QrMock` | `qrcode.react` fed from `qr_uri` |

### Backend API endpoints needed (not yet implemented)

See `docs/20260420_CRO_COMPLIANCE_UX_REQUIREMENTS.md` §API Contract.  
Implementation order matches porting order above.

---

## 4. Pending Tasks

1. ✓ Port Surface 3 (Audit Trail) to `drug-discovery-audit-viewer.tsx`
2. ✓ Port Surface 4 (Auto-Retrain) to `drug-discovery-auto-retrain.tsx`
3. ✓ Extend `drug-discovery-action.tsx` with tab bar + mode routing
4. ✓ Add backend endpoints: `GET /audit`, `GET /audit/verify`, `GET|POST /{id}/retrain/*`, `GET|POST /{id}/virtual-library`
5. ✓ Port Surface 2 (Validation) → `drug-discovery-validation-panel.tsx`
6. ✓ Port Surface 6 (IND Assembly) → `drug-discovery-ind-assembly.tsx`
7. ✓ Port Surface 7 (Campaign Wizard) → `drug-discovery-campaign-wizard.tsx`
8. ✓ Port Surface 5 (eSig Modal) → `drug-discovery-esig-modal.tsx`
9. ✓ E2E tests `DD-CRO-1` through `DD-CRO-7` — **7/7 passing** (2026-04-21)
