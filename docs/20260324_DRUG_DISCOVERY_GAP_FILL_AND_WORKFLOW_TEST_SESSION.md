# Drug Discovery Gap Fill + Workflow Testing — Session Summary

**Date:** 2026-03-24  
**Branch:** feature/nfcore-reindex  
**Status:** Complete — all 5 workflows pass, 3 API tracks wired, 1 ranking bug fixed

---

## Context

`business/BioMate_DrugDiscovery_Introduction.md` describes BioMate's drug discovery
capabilities to clinical research partners (Zhejiang People's Hospital pilot). This session
verified that every capability described in that document has a working backend implementation,
and filled the remaining gaps.

---

## Work Completed

### 1. Workflow Fixes — Groovy String Parsing

Three pharmacology Nextflow workflows were broken by a Groovy GString parsing conflict:
Python docstrings using `"""..."""` inside Nextflow `"""..."""` script blocks closed the
GString early. The same class of bug was fixed in `aizynthfinder_retrosynthesis` in the
previous session.

**Files fixed:**

| File | Fix |
|---|---|
| `pharmacology/ADMET_pred/main.nf` | Triple-quote docstrings → `'''...'''`; SMILES parameter injection hardened with pre-computed Groovy variable + single-quote export |
| `pharmacology/predict_admet_properties/main.nf` | Triple-quote docstrings → `'''...'''`; SMILES list written via heredoc to file instead of fragile `replace('"', '\\"')` GString substitution |
| `pharmacology/ivive_hepatic_clearance/main.nf` | Triple-quote docstrings → `'''...'''` |

---

### 2. Workflow Testing — All Pass

All five workflows run with `docker.enabled = true` using `biomate/biomni-tools:latest`.

#### `pharmacology/ADMET_pred`

Test compound: **Terfenadine** — a known hERG channel inhibitor withdrawn from market in
1998. Used as a positive-control QC gate trigger.

| Endpoint | Result | Scientific expectation |
|---|---|---|
| hERG IC50 | **0.198 µM** | < 1 µM = high cardiac risk ✓ |
| DILI risk | **high (70.1%)** | logP=7.01, MW=499.7 → Lammert 2010 criteria ✓ |
| Ames | negative | No structural alerts ✓ |

#### `pharmacology/predict_admet_properties`

Test: aspirin (safe control) vs. terfenadine (positive control).

| Compound | hERG IC50 | DILI Risk | Discrimination |
|---|---|---|---|
| Aspirin | 10.16 µM | low (10.6%) | ✓ Safe |
| Terfenadine | 0.198 µM | high (70.1%) | ✓ Correctly flagged |

51× hERG IC50 discrimination, 6.6× DILI probability discrimination.

#### `pharmacology/ivive_hepatic_clearance`

Test compound: **Midazolam** (CYP3A4 reference substrate, CLint 100 µL/min/mg microsomal).

| Output | Value | Literature expectation |
|---|---|---|
| CLh predicted | 7.42 mL/min/kg | Intermediate extraction ✓ |
| CLh/QH fraction | 0.358 | 0.35–0.55 published ✓ |
| Extraction class | intermediate | Gorski et al. 1998 ✓ |
| 95% CI | 1.30–13.54 | ~3–4× IVIVE error ✓ |

#### `drug_discovery/pocket_detection_druggability` (mock mode)

Target: EGFR kinase (synthetic data). Top pocket: druggability 0.78, volume 847 Å³ → **PASS**.  
Pocket 3 (druggability 0.21, 156 Å³) correctly excluded from docking tier.

#### `drug_discovery/pharmacophore_filtering` (mock mode)

3 reference actives → 4-feature pharmacophore model → 10-compound library → **2 hits (20%)**,
a realistic pharmacophore hit rate for a selective scaffold.

---

### 3. Drug Discovery API Endpoints Created (Tracks C / D / E)

The `business/BioMate_DrugDiscovery_Introduction.md` claims:
- *"When wet lab or CRO assay results return, they are uploaded to BioMate in a structured CSV"* — **was not wired**
- *"CRO-ready compound export"* — **was not wired**
- *"Custom model integration"* — **was not wired**

All three are now wired:

**New files:**
- `backend/lib/galaxy/ai/drug_discovery/api_router.py`
- `backend/lib/galaxy/webapps/galaxy/api/drug_discovery.py` (shim)

**Routes:**

| Method | Path | Feature |
|---|---|---|
| POST | `/api/drug-discovery/{id}/ingest-assay` | CRO/wet-lab CSV upload |
| GET  | `/api/drug-discovery/{id}/compounds` | Ranked compound list |
| GET  | `/api/drug-discovery/{id}/export/cro-order?fmt=wuxi\|pharmaron\|enamine\|generic` | CRO export CSV |
| POST | `/api/drug-discovery/{id}/models/register` | Register Docker or REST scoring model |
| GET  | `/api/drug-discovery/{id}/models` | List models + run history |
| POST | `/api/drug-discovery/{id}/models/{name}/run` | Score SMILES with registered model |
| GET  | `/api/drug-discovery/availability?smiles=...` | PubChem batch availability check |

---

### 4. hERG Ranking Bug Fixed

**File:** `backend/lib/galaxy/ai/drug_discovery/assay_ingestion.py`

**Bug:** hERG IC50 was in `_LOWER_IS_BETTER`, treating a low hERG IC50 (= high cardiac
liability) as good potency. Terfenadine (hERG 0.198 µM) was ranking #2 out of 4 compounds.

**Fix:**
- Moved hERG out of `_LOWER_IS_BETTER`
- Added dedicated hERG handling: safety penalty if IC50 < 10 µM (ICH S7B-informed gate),
  plus a normalised reward for high IC50 (safe compounds score well)
- Added `_HIGHER_IS_BETTER = {"hERG", "solubility", "permeability"}` for correct handling
  of other safety metrics

**Verified ranking (BCR-ABL inhibitor panel):**

| Rank | Compound | IC50 (µM) | hERG IC50 (µM) | Score |
|---|---|---|---|---|
| 1 | Dasatinib | 0.001 | 15.0 (safe) | 1.000 |
| 2 | Imatinib | 0.025 | 12.0 (safe) | 0.399 |
| 3 | Bosutinib | 0.004 | 3.5 (penalty) | 0.249 |
| 4 | Terfenadine | — (no target data) | 0.198 (high-risk) | 0.000 |

Scientifically correct: dasatinib leads (potent + safe), terfenadine last (withdrawn drug).

---

## Files Changed

| File | Type | Change |
|---|---|---|
| `pharmacology/ADMET_pred/main.nf` | Fix | Triple-quote + SMILES injection |
| `pharmacology/predict_admet_properties/main.nf` | Fix | Triple-quote + heredoc SMILES |
| `pharmacology/ivive_hepatic_clearance/main.nf` | Fix | Triple-quote |
| `drug_discovery/api_router.py` | New | 7 FastAPI routes |
| `drug_discovery/custom_model_registry.py` | Add | `get_run_log()`, `run_named_model()` |
| `drug_discovery/assay_ingestion.py` | Fix | hERG ranking direction + safety penalty |
| `webapps/galaxy/api/drug_discovery.py` | New | Router shim |
| `docs/QC/20260324_PHARMACOLOGY_ADMET_WORKFLOW_AUDIT.md` | New | QC audit |

---

## Introduction Document Coverage

Every claim in `business/BioMate_DrugDiscovery_Introduction.md` now maps to a tested component:

| Claim | Implementation | Status |
|---|---|---|
| ADMET profiling (hERG, DILI, Ames, ClinTox) | `ADMET_pred`, `predict_admet_properties` | ✅ Tested with real RDKit |
| IVIVE / metabolic stability | `ivive_hepatic_clearance` | ✅ Tested |
| Pocket detection + druggability | `pocket_detection_druggability` | ✅ Tested (mock) |
| Pharmacophore pre-filtering | `pharmacophore_filtering` | ✅ Tested (mock) |
| Retrosynthesis (AiZynthFinder) | `aizynthfinder_retrosynthesis` | ✅ Tested (prior session) |
| Drug MoA from RNA-seq | `drug_moa_rnaseq` | ✅ Tested (prior session) |
| Bayesian optimisation (DMTA) | `bayesian_optimizer.py` | ✅ 35/35 unit tests |
| CRO compound export | `cro_order_export.py` + `/export/cro-order` API | ✅ Tested |
| Assay data upload from CRO | `assay_ingestion.py` + `/ingest-assay` API | ✅ Tested |
| Custom model integration | `custom_model_wrapper.py` + `/models/register` API | ✅ Tested |
| Commercial availability check | `commercial_availability.py` + `/availability` API | ✅ Tested |

---

---

## P1–P3 Extension Work (same session)

### P1a — Live-mode pocket detection (real ABL1-imatinib structure, PDB: 1IEP)

Ran against the crystal structure of c-Abl kinase bound to imatinib (STI-571).
10 real pockets detected using geometric cavity detection (BioPython + SciPy/cKDTree).

| Pocket | Druggability | Volume (Å³) | Hydrophobicity | Centre |
|---|---|---|---|---|
| 1 (top) | **0.567** | 879.2 | 0.491 | (14.9, 57.2, 0.9) |
| 2 | 0.560 | 532.6 | 0.530 | (20.5, 48.0, 3.8) |
| 3 | 0.560 | 762.2 | 0.497 | (18.7, 52.8, 1.4) |

QC status: **PASS** (druggability 0.567 ≥ 0.5, volume 879 Å³ ≥ 300 Å³). Top-pocket centre
at (14.9, 57.2, 0.9) is consistent with the ABL1 ATP-binding cleft (imatinib binding site).

### P1b — Live-mode pharmacophore filtering (real ABL1 inhibitors)

Reference actives: imatinib, bosutinib, dasatinib, nilotinib scaffold (4 compounds).
Library: 20 compounds (known actives + structurally diverse negatives).

| Result | Value |
|---|---|
| Pharmacophore features derived | 6 |
| Library screened | 20 compounds |
| Passed filter (≥ 3 features) | 16 (80% hit rate) |

Notable: imatinib exact match and imatinib analogue both pass (correct). Simple fragments
(methylimidazole, benzothiazole, quinoline) correctly fail. High pass rate (80%) reflects
the diverse feature space of the four reference actives — production use benefits from a
more homogeneous reference set or tighter min_features threshold.

### P2 — Chat interface wiring for assay upload + CRO export

Added intent detection in `routes.ts` (stream endpoint):
- **Assay upload intent**: "upload/ingest/submit assay data/CSV/CRO results"
  → `drug_discovery_action: { type: "assay_upload", campaign_id, endpoint }`
- **CRO export intent**: "export/download/prepare for WuXi/Pharmaron/Enamine/CRO order"
  → `drug_discovery_action: { type: "cro_export", campaign_id, formats }`
- **Campaign dashboard intent**: "show/view campaign dashboard/ranking"
  → `drug_discovery_action: { type: "campaign_dashboard", campaign_id, endpoint }`

**New component**: `frontend/client/src/components/drug-discovery-action.tsx`

Three sub-widgets rendered inline in chat response cards:

| Widget | Behaviour |
|---|---|
| `AssayUploadWidget` | File picker → `POST /api/drug-discovery/{id}/ingest-assay` → shows updated ranking inline |
| `CROExportWidget` | Format selector (WuXi / Pharmaron / Enamine / Generic) → `GET /export/cro-order?fmt=...` → browser download |
| `CampaignDashboardWidget` | Campaign ID input → `GET /compounds` → bar-chart compound ranking table |

Inserted into `chat-message.tsx` rendering pipeline, rendered above Galaxy recommendations.

### P3 — Campaign dashboard

Implemented as the `CampaignDashboardWidget` inside `drug-discovery-action.tsx`. Inline
compound ranking with colour-coded score bars (green ≥ 80%, amber ≥ 50%, red < 50%).
Accessible via the campaign dashboard chat intent or directly embedded in any chat response.

---

## What Is Not Yet Done

| Item | Priority | Effort |
|---|---|---|
| DMTA Pareto front visualisation (from `BayesianOptimizer.get_pareto_summary`) | P2 | ~1 day |
| CampaignDashboard round history tab (show all previous BO proposals) | P2 | ~1 day |
| Server-side campaign ID extraction from session context (not just message text) | P2 | ~0.5 day |
| Test chat intent detection end-to-end with live server | P2 | ~0.5 day |
| Expand AiZynthFinder stock (81 → ZINC/Enamine REAL building blocks) | P3 | Large model download |
| Live-mode pharmacophore with `--generate_3d true` (3D distance constraints) | P3 | Needs conformer gen |
