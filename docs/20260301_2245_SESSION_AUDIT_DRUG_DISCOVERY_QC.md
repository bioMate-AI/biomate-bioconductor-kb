# Session Audit — Drug Discovery QC & Client Documentation
**Date:** 2026-03-01 22:45
**Branch:** `connection_formal`

---

## Summary

This session completed three bodies of work:
1. Drug discovery QC stack audit and critical workflow-parser mismatch fix
2. QC Gate UX — Tier 1 & Tier 2 implementation (carried over from previous session, confirmed 100% complete)
3. Client-facing drug development capability document

---

## 1. Drug Discovery QC Audit

### Critical Finding: Workflow-Parser Mismatch

The backend QC parsers for ADMET (`_parse_admet_toxicity_metrics()` in `qc_trace_monitor.py`) were complete and tested, but the Nextflow workflow files they depend on were producing wrong output:

| File | Before | After |
|---|---|---|
| `pharmacology/predict_admet_properties/main.nf` | Returned a text research log; no `toxicity_report.json` | Full RDKit-based ADMET screening; structured `toxicity_report.json` output |
| `pharmacology/ADMET_pred/main.nf` | Stub returning `{"status": "Function not available"}` | Full RDKit-based ADMET screening; structured `toxicity_report.json` output |

### Fix Details

Both workflows now implement `compute_structural_safety()` using:
- **hERG IC50**: Aronov 2008 J Med Chem logP-based heuristic — `log10_ic50 = 1.4 − 0.30 × logP`
- **DILI risk**: Lammert 2010 Toxicol Sci lipophilicity + MW model — `logP > 4.0 AND MW > 400 → "high"`
- **Optional ClinTox overlay**: DeepPurpose MPNN model (when installed)

Default SMILES set to terfenadine (known withdrawn hERG blocker, logP=7.01, MW=499.7):
- Computed IC50: 0.198 μM → GOLD gate fires (< 1 μM threshold)
- DILI: "high" → GOLD gate fires

Output format (`toxicity_report.json`):
```json
{
  "compounds_assessed": N,
  "model_type": "rdkit_descriptors",
  "toxicity": {
    "herg_ic50_uM": 0.198,
    "dili_risk": "high",
    "dili_probability": 0.80
  },
  "per_compound": [...]
}
```

Parser reads via `data.get("toxicity", data)` — handles both nested and flat format.

### E2E Verification

Full chain verified manually:
- Terfenadine: IC50 0.198 μM → GOLD blocking gate + DILI high → GOLD blocking gate ✓
- Aspirin (logP=1.31, MW=180.2): IC50 10.2 μM, DILI low → no gate ✓
- AI workflow search "ADMET drug toxicity" → correctly finds `ADMET_pred` ✓
- AI workflow search "predict ADMET properties hERG DILI" → correctly finds `predict_admet_properties` ✓

### Regression Tests Added

File: `backend/tests/test_qc_e2e_domains.py` (class `TestHERGDILIToxicityGates`)

| Test | Purpose |
|---|---|
| `test_predict_admet_properties_process_name_matches` | PREDICT_ADMET_PROPERTIES routes to correct parser |
| `test_new_workflow_format_with_per_compound_nesting` | Nested toxicity_report.json format parsed correctly |

---

## 2. QC Gate UX — Tier 1 & Tier 2 (Confirmed Complete)

All 15 items from the plan at `.claude/plans/federated-cooking-truffle.md` were confirmed implemented in the previous session. No further changes needed.

### Summary of what was verified complete:
- Process name humanisation (PROCESS_DISPLAY_NAMES lookup table, 40+ entries)
- Button consequence subtitles in modal footer
- Confidence-aware suggestion defaults (pre-checked only if ≥ 0.7)
- Summary line showing what will be applied
- Proceed Anyway confirmation step (two-click with audit note)
- Domain-specific troubleshooting fallbacks (TROUBLESHOOTING_STEPS)
- Retry counter in modal title
- Before/after diff panel (previousMetrics prop)
- SSE reconnection loop + banner
- Step QC annotations on workflow steps
- Retry count + previous metrics state management in workflow-artifact
- pilot_qc_passed auto-advance listener
- Skip button consequence note

---

## 3. Drug Discovery Modal UX Additions

File: `frontend/client/src/components/qc-gate-modal.tsx`

Added to `PROCESS_DISPLAY_NAMES`:
```
ADMET_PRED → "ADMET Safety Screening"
PREDICT_ADMET_PROPERTIES → "ADMET Property Prediction"
HERG_SCREEN → "hERG Cardiotoxicity Screen"
DILI_SCREEN → "DILI Hepatotoxicity Screen"
TOXICITY_SCREEN → "Compound Toxicity Screen"
SMILES_QC → "Compound Structure QC"
PGX_COVERAGE → "Pharmacogenomics Coverage"
MOLECULAR_DOCKING → "Molecular Docking"
QSAR_MODEL → "QSAR Modelling"
NCA_PKNCA → "Non-Compartmental Analysis (NCA)"
POPULATION_PK → "Population PK Modelling (nlmixr2)"
PKPD_MODEL → "PK/PD Modelling"
FAERS_MINING → "Adverse Event Mining (FAERS)"
DRUG_REPURPOSING → "Drug Repurposing Analysis"
SCAFFOLD_HOPPING → "Scaffold Hopping"
```

Added to `TROUBLESHOOTING_STEPS` (7 drug discovery domains):
- `ADMET_PRED` / `PREDICT_ADMET_PROPERTIES` — hERG structural modification guidance, DILI daily dose context, scaffold hopping suggestion
- `HERG_SCREEN` — logP reduction, ring system modification, basic amine removal
- `SMILES_QC` — validation tools, salt stripping, stereochemistry specification
- `PGX_COVERAGE` — gene panel expansion, sequencing depth guidance
- `NCA_PKNCA` — sampling schedule requirements, assay sensitivity
- `POPULATION_PK` — data volume requirements, covariate selection

---

## 4. UX Telemetry Fix

File: `frontend/client/src/lib/ux-telemetry.ts`

Added `'workflow.background_action_selected'` to `UxEventName` union type (was causing a TypeScript error from `chat-with-artifacts.tsx:476`).

---

## 5. Client Document

File: `docs/client/biomate_drug_development_overview.md`

Created a client-facing drug development platform overview covering:
- 8-stage drug development capability map (Target Discovery → Drug Repurposing)
- QC Governance explanation (3 tiers, named profiles)
- Research Intelligence section (ResearchAgent, hypothesis generation, protocol guidance, scientific rationale, benchmark evidence)
- Results, Visualization, and Download section (in-browser viewers, download options, report generation, Jupyter integration)
- AI Assistance section
- Compute options
- Honest roadmap (ML Ames, IVIVE, population PK QC gates, regulatory reports, SAR tracking, data ingestion)
- 16 client discussion questions across 5 themes
- "What can be built on top" section for collaboration framing

---

## 6. Test Suite Status

| Suite | Result |
|---|---|
| QC + billing (core) | 495/495 pass, 32 skipped (billing — needs Redis) |
| Full suite (all non-playwright) | 531 pass, 31 fail (billing E2E — needs running billing service) |
| Billing E2E alone | 32/32 pass when billing service + Redis are live |

---

## 7. TypeScript Status

**71 errors** (baseline 74 — 3 net reduction from session start).

Remaining error clusters:
| Cluster | Count | Notes |
|---|---|---|
| Research agent methods not on GalaxyAPIProxy (`queryResearch`, `queryBenchmark`) | 5 | Partially implemented feature |
| `researchAgentUsed` not in metadata response type | 2 | Schema needs extending |
| Execution hook schema drift (`sampledIds`, `milestonePercentages`, `lastLines`) | 4 | Fields added in Python not yet reflected in TS types |
| `WorkflowStep` missing `description`/`status`/`complexity` | 1 | Interface drift |
| `UxEventName` missing `workflow.prereq_recovery_requested` | 1 | New event not in union |
| Sampling strategy `"sequential"` not in union | 1 | New strategy not added to type |
| Stale test/utility files (`token-counter`, `tool-blog`, etc.) | ~30 | Not production code |

---

## Files Changed This Session

**Backend:**
- `biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/ADMET_pred/main.nf` — replaced stub with full RDKit ADMET implementation
- `biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/predict_admet_properties/main.nf` — replaced text log output with structured toxicity_report.json
- `tests/test_qc_e2e_domains.py` — 2 regression tests added

**Frontend:**
- `components/qc-gate-modal.tsx` — 15 drug discovery display names + 7 troubleshooting guides added
- `lib/ux-telemetry.ts` — `workflow.background_action_selected` added to UxEventName

**Docs (new):**
- `docs/client/biomate_drug_development_overview.md` — client-facing capability document
- `docs/20260301_2245_SESSION_AUDIT_DRUG_DISCOVERY_QC.md` — this file
