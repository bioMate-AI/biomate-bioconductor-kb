# BioMate as Computational CRO/CDMO — Gap Analysis and Implementation Plan

**Date:** 2026-04-20  
**Status:** Planning  
**Author:** Session analysis

---

## 1. Strategic Question

Can BioMate act as a CRO (Contract Research Organization) or CDMO (Contract Development and Manufacturing Organization) — selling drug development services to pharma clients, not just operating as an internal tool?

**Short answer:**
- **Computational CRO: Yes — today, partially. Fully credible in 4–6 months.**
- **Wet-lab CRO: No. Requires partnerships with physical labs.**
- **CDMO: No, with one exception — computational formulation design as CDMO design input.**

---

## 2. What BioMate Can Already Deliver as a Computational CRO

The following map directly to services that Schrödinger, Insilico Medicine, and XtalPi charge pharma clients for:

| CRO Service | BioMate Capability | Workflow/Module |
|---|---|---|
| ADMET screening (in silico) | hERG QSAR, genotox Ames, ADMET autoloop | `herg_cardiac_safety_qsar`, `genotoxicity_ames_prediction` |
| PK prediction | PBPK 8-compartment, allometric scaling, NCA | `pbpk_simulation`, `allometric_scaling` |
| DDI assessment | CYP panel (R1/R2/TDI), transporter DDI | `cyp_ddi_panel`, `transporter_ddi_prediction` |
| Clinical dose selection | BOIN escalation, Phase 2 simulation, MRSD | `clinical_trial_simulation`, `allometric_scaling` |
| Compound ranking | Bayesian optimizer (GP + EHVI), assay scoring | `BayesianOptimizer`, `AssayIngestionService` |
| CRO order management | Export to WuXi/Pharmaron/Enamine formats | `CROOrderExporter` |
| ELN integration | Benchling OAuth2 connector, pull/push data | `lib/integrations/benchling_connector.py` |
| Instrument data | Plate reader, LC-MS, qPCR, SiLA2 | `lib/integrations/*` |

The DMTA loop is **~70% automated**: compound design → synthesis order → assay data ingestion → re-ranking → next-round proposal. Trigger automation (auto-propose on new assay ingest) is the remaining 30%.

---

## 3. Gap Analysis

### Gap 1 — No Model Validation Package (P1, Critical)

**What's missing:** CRO data feeds IND submissions. FDA accepts computational PBPK for DDI labeling and pediatric extrapolation — but only with a documented model qualification study: % prediction error across ≥10 marketed drugs, fold-error distribution, applicability domain.

**Current state:** Zero published validation for any BioMate model. PBPK bugs were only found by the 2026-04-18 scientific audit. QSAR models (hERG, Ames, CYP) have no stated training set, accuracy, or AD boundaries.

**Impact:** Without validation, no pharma client can cite BioMate outputs in an IND or regulatory filing.

---

### Gap 2 — No Applicability Domain or Confidence Intervals (P2, High)

**What's missing:** Every QSAR/PBPK prediction returns a point estimate. Pharma clients need:
- Confidence intervals (is this prediction ±10% or ±300%?)
- Applicability domain (is this compound structurally too different from the training set?)
- Out-of-domain warnings

**Current state:** The `BayesianOptimizer` GP already computes posterior variance but it is not exposed to the client. QSAR models have no AD module.

---

### Gap 3 — No 21 CFR Part 11 Compliance (P3, High)

**What's missing:** Any data used in a regulatory submission must have:
- Tamper-evident audit trail with user attribution + timestamp
- Electronic signature (21 CFR Part 11.50)
- Immutable change history

**Current state:** The autoloop `AuditLogger` writes JSONL files on disk (mutable). Instrument connectors (Benchling, SiLA2) log events but there is no platform-wide hash-chained audit store. No electronic signature mechanism.

---

### Gap 4 — No Auto-Retrain Loop (P4, Medium)

**What's missing:** When new assay results arrive, QSAR models should automatically retrain on the expanded dataset, updating all predictions and re-ranking compounds without manual intervention.

**Current state:** `AssayIngestionService.ingest()` recomputes ranks using fixed weights but does not trigger GP/QSAR model retraining. Model retraining is entirely manual.

---

### Gap 5 — No IND Section Generation (P5, Medium)

**What's missing:** The highest-value CRO deliverable is a regulatory package — pharmacology summary, ADME section, nonclinical overview for an IND. BioMate generates JSON/CSV outputs but cannot assemble them into IND-formatted documents.

**Current state:** No regulatory document generation. `clinical_trial_results.json`, `human_pk_prediction.json`, `operating_characteristics.json` all contain the right data but no assembly layer exists.

---

### CDMO Assessment

BioMate has **no manufacturing capability** and cannot be a CDMO in the traditional sense. However, there is one credible niche:

**Computational formulation design → CDMO handoff:** The `lnp_formulation_optimization` workflow can design LNP component ratios (ionizable lipid pKa, N/P ratio, PEG-lipid %) computationally. This output can be formatted as a synthesis brief for a wet-lab CDMO (Precision NanoSystems, Evonik, Catalent). BioMate acts as the **design phase** of CDMO, passing ready-to-manufacture formulation specs downstream.

This is a genuine business model — similar to how Lonza's computational formulation team designs formulations for their GMP manufacturing lines.

---

## 4. Implementation Plan

### Phase 1 — Regulatory-Credible Predictions (Weeks 1–8)
**Unlock: computational CRO proposals to pharma; citations in IND pharmacology sections**

#### P1: PBPK/QSAR Model Validation Package

**New file:** `lib/galaxy/ai/drug_discovery/model_validation.py`

```
ModelValidationService
  ├── run_pbpk_validation(reference_dataset)
  │     • 50 marketed drugs (Cmax, AUC, Cl, Vd from DrugBank/PhysPK DB)
  │     • Stored as static JSON: lib/galaxy/ai/drug_discovery/reference_data/pk_marketed_drugs.json
  │     • Metrics: %PE, RMSE, R², AAFE, fraction within 2-fold
  └── run_qsar_validation(model_type, dataset)
        • hERG: ChEMBL hERG IC50 set (n≥200)
        • Ames: Hansen et al. 2009 dataset
        • Metrics: AUROC, MCC, sensitivity/specificity
```

**New endpoint:** `GET /api/drug-discovery/model-validation/{model_type}`  
Returns `ValidationReport` (Pydantic): per-compound errors + aggregate statistics + PDF-ready HTML table.

**Deliverable to clients:** One-page PDF validation report attached to every computational study.

---

#### P2: Applicability Domain + Confidence Intervals

**New file:** `lib/galaxy/ai/drug_discovery/applicability_domain.py`

```
ApplicabilityDomainChecker
  ├── leverage_ad(query_fp, training_fps)
  │     • Hat matrix (sklearn), Williams plot
  │     • out_of_domain = True if leverage > 3 × mean training leverage
  └── gp_confidence_interval(gp_model, X_query)
        • 95% CI = mean ± 1.96 × posterior_std
        • Already computed in BayesianOptimizer — just expose it
```

**Changes to `api_router.py`:**  
- `ProposeResponse` gains `confidence_interval: [float, float]` and `ad_status: "in_domain" | "out_of_domain"` per compound.

---

### Phase 2 — Compliance Infrastructure (Weeks 6–12)
**Unlock: pass pharma IT security reviews; sign MSA with mid-size pharma**

#### P3: 21 CFR Part 11 Audit Trail

**New file:** `lib/galaxy/ai/compliance/audit_store.py`

```
AuditStore (append-only SQLite table)
  • Each row: event_id, user_id, action, entity_id, data_hash, timestamp, prev_hash, row_hash
  • row_hash = SHA-256(prev_hash + event_json) — hash chain, tamper-evident
  • No row ever updated/deleted — append only
```

**New file:** `lib/galaxy/ai/compliance/esig.py`

```
ElectronicSignature
  • TOTP step-up auth (pyotp) for high-risk actions
  • Signs: user_id, timestamp, action, dataset_hash → stored in AuditStore
```

**New middleware:** `lib/galaxy/middleware/audit_middleware.py`  
- Intercepts all `POST`/`DELETE` on `/api/drug-discovery/` and writes to `AuditStore`.

**New endpoint:** `GET /api/compliance/audit-trail?campaign_id=X&from=&to=`  
Returns paginated, hash-verified events with integrity check.

---

### Phase 3 — Auto-Retrain Loop + IND Generation (Weeks 10–20)
**Unlock: continuous DMTA subscription model; regulatory package service**

#### P4: Auto-Retrain on Assay Ingestion

**New file:** `lib/galaxy/ai/drug_discovery/retrain_service.py`

```
QSARRetrainJob
  • Triggered from AssayIngestionService._recompute_ranks() after new data
  • Runs as asyncio background task (FastAPI lifespan)
  • Loads all campaign_assay_results → re-fits GP in BayesianOptimizer
  • Serializes updated model to database/campaigns/{campaign_id}_model.pkl
  • Writes retrain_event to AuditStore (requires Phase 2)
```

**New endpoint:** `GET /api/drug-discovery/{campaign_id}/model-status`  
Returns: last retrain timestamp, N training points, current RMSE, model version.

---

#### P5: IND Section Auto-Generation

**New file:** `lib/galaxy/ai/drug_discovery/ind_generator.py`

```
INDSectionGenerator
  • Inputs: ValidationReport (P1) + ranked compounds + AuditStore entries
  • LLM call (Claude via existing Anthropic client) with structured prompt template
  • Produces structured Markdown/HTML for:
    - IND section 2.6.1 (pharmacology summary)
    - IND section 2.7.1 (ADME summary)  
    - Nonclinical overview
  • Each output includes source_data_hash (AuditStore refs) for traceability
```

**New endpoint:** `POST /api/drug-discovery/{campaign_id}/generate-ind-section`  
Body: `{section: "2.6.1" | "2.7.1" | "nonclinical_overview"}`

---

#### CDMO Angle: LNP Formulation Design → CDMO Brief

**New file:** `lib/galaxy/ai/drug_discovery/lnp_formulation.py`

```
LNPFormulationDesigner
  • Wraps lnp_formulation_optimization Nextflow workflow
  • BO parameters: ionizable lipid pKa, N/P ratio, PEG-lipid fraction, helper lipid %
  • Outputs: top-5 formulation candidates (EE%, endosomal escape score, stability index)
  • Generates CROOrderExporter-compatible synthesis brief for wet-lab CDMO
```

**New endpoint:** `POST /api/drug-discovery/{campaign_id}/formulation/lnp-design`  
Body: `{payload_smiles, target_tissue, budget_constraints}`  
Output: formulation specs ready to send to Precision NanoSystems / Evonik / Catalent.

---

## 5. Gap Classification

| Gap | Build in code | Requires partnership | Blocking Phase |
|-----|---|---|---|
| P1 Model validation | Yes — static reference data + sklearn metrics | No | Phase 1 |
| P2 Applicability domain | Yes — hat matrix + GP CI | No | Phase 1 |
| P3 21 CFR Part 11 | Yes — hash chain + TOTP (Phase 2 for FDA readiness, need 3rd-party audit firm) | 3rd-party audit for actual submission | Phase 2 |
| P4 Auto-retrain | Yes — asyncio background task | No | Phase 3 |
| P5 IND generation | Yes — LLM + template | Regulatory affairs partner for actual filing | Phase 3 |
| CDMO/LNP | Yes — BO formulation wrapper | Wet-lab CDMO for synthesis (business, not code) | Phase 3 |

---

## 6. Billable Services Unlocked by Phase

| Phase | What you can sell |
|---|---|
| **Today** | In silico ADMET/PK screening, compound ranking, CRO order management (WuXi/Pharmaron) |
| **After Phase 1** | Validated ADMET/PBPK computational study reports (citable in IND pharmacology section) |
| **After Phase 2** | GLP-adjacent computational study reports with audit trail; pass pharma IT security reviews |
| **After Phase 3a** | Continuous DMTA subscription (per design cycle); model updates included |
| **After Phase 3b** | Regulatory package preparation (IND pharmacology + ADME section drafts) |
| **After Phase 3c** | LNP formulation design brief → CDMO synthesis handoff |

---

## 7. What Requires Wet-Lab Partnership (Not Buildable in Code)

| CRO Service | Why not code | Partnership type |
|---|---|---|
| In vivo PK studies | Requires animals, dosing, bioanalysis | Tier-1 CRO (Charles River, Covance) |
| Bioanalytical (LC-MS/MS) | Requires instruments + GLP wet lab | Bioanalytical CRO |
| Phase I–III execution | Site management, clinical monitoring, data management | Full-service CRO (ICON, PRA, Syneos) |
| GMP manufacturing | Facility, CMC, QA release | CDMO (Lonza, Catalent, Samsung Bio) |
| FDA Part 11 audit certification | Regulatory inspection | Greenlight Guru / Sparta Systems |

---

## 8. Competitive Positioning

| Company | Model | BioMate vs |
|---|---|---|
| Schrödinger | Physics-based ADMET + FEP, $150M+ revenue | Less physics, more AI/statistical; faster to run, easier to use |
| Insilico Medicine | AI drug design end-to-end (target → IND) | Narrower pipeline but more integrated DMTA loop |
| Certara | PBPK software (Phoenix, Simcyp) | BioMate is open-loop API-first; Certara is GUI-centric |
| WuXi AppTec | Full wet-lab CRO | BioMate is upstream (computational); WuXi is the execution partner |

**Differentiation:** BioMate's value is the closed DMTA loop — computational screening → automated assay ingestion → BO-driven compound proposals → CRO order → re-ingest. No competitor offers this end-to-end automation in a single platform.

---

## 9. Recommended First Client Target

A mid-size biotech (50–200 employees) running a small-molecule discovery campaign with:
- ≥1 HTS hit series
- 6–18 month lead optimization timeline
- No in-house computational chemistry team
- Using Benchling as their ELN (BioMate already has the connector)

**Pitch:** Replace 2–3 FTE computational chemists + manual CRO coordination with BioMate's automated DMTA loop. Deliverable: a validated ADMET report + compound priority list updated weekly as assay data lands.

**Price point:** $50–150K/year per active campaign (comparable to a single computational chemistry FTE).
