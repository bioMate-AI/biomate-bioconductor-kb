# Pilot Study — Current Status
*Date: 2026-04-15 | Branch: integration/next-phase*

---

## Overview

BioMate has two pilot study tracks: **Drug Discovery** (pharma partner onboarding) and **Cryo-EM** (structural biology partner onboarding). Each requires validated P0 benchmarks, working AWS Batch execution, and automated deliverable generation.

---

## Drug Discovery Pilot

### E2E Test Suite
**Status: 9/9 PASSING** (2026-04-12, `e2e/pilot-study.e2e.ts`)

| Session | Workflow | Result |
|---------|----------|--------|
| S1 | ADMET prediction | ✅ completed |
| S2 | IVIVE pharmacokinetics (NCA/PKNCA) | ✅ completed |
| S3 | Binding pocket prediction | ✅ completed |
| S4 | Pharmacology (scaffold hopping) | ✅ completed |
| S5 | Compound ranking + assay ingestion | ✅ completed |
| S6 | CRO submission export | ✅ completed |
| DD-1–DD-3 | Drug MoA RNA-seq, GROMACS, AlphaFold | ✅ 3/3 |

### P0 Validation Benchmarks
| Benchmark | Description | Status |
|-----------|-------------|--------|
| P0-A | CryoSPARC license check | Not run on AWS Batch |
| P0-B | mRNA-1273 design (GenBank OK120841.1) | ✅ DONE locally (1m 43s) |
| P0-C | Docking RMSD — Mpro/nirmatrelvir PDB 7RFS | ✅ DONE locally (16m 27s) |
| P0-D | Pharmacophore AUC-ROC — GLP-1R PDB 7KI0 | ✅ DONE locally |
| P0-E | PK/PD semaglutide SUSTAIN-1 | ✅ DONE locally; Cmax 33.27 nM (target 21–39), weight −5.66 kg |

**P0 Validation Report (partner-facing PDF/DOCX):** Not yet compiled. Deliverable needed before partner handoff.

### Automated Deliverables
| Deliverable | Status |
|-------------|--------|
| QC audit log download (`GET /api/invocations/{id}/qc-audit-download`) | ✅ DONE |
| Methods report download (`GET /api/invocations/{id}/methods-report`) | ✅ DONE |
| Pilot KPI dashboard (per-account summary page) | ❌ NOT BUILT |

### Pilot Account Infrastructure
- `PILOT_ACCOUNT_EMAILS` env var — pilot users skip LLM billing emit ✅
- `is_pilot` flag stored in run metadata ✅
- Quota/rate limits bypassed for pilot accounts ✅

---

## Cryo-EM Pilot

### E2E Test Suite
**Status: 5/5 PASSING** (2026-04-15, `e2e/cryo-em.e2e.ts`)

S3 glob URLs skip `head_object` validation. IAM policy on `biomate-cryo-data` bucket allows `ecsInstanceRole` to `GetObject` + `ListBucket`.

**Known open issues:**
- CS-5: Stale page after 15-minute run (no auto-refresh on completion)
- CS-4: LLM non-determinism on topic extraction
- Phase card statuses not refreshed on run completion

### Workflow Infrastructure
- CryoSPARC Standard SPA: `pipeline_composition/pipelines/cryosparc_standard_spa/main.nf` (DB id=12833) ✅
- Helical SPA pipeline registered in DB ✅
- 13 specialized subworkflows at `nextflow_nfcore/subworkflows/cryo_em/` ✅
- Full AWS Batch end-to-end with GPU queue not yet confirmed ❌

---

## AWS Infrastructure Gaps

| Item | Status |
|------|--------|
| AWS CLI fix live on Batch workers (`/usr/local/bin/aws`) | ✅ Code applied; confirmed on live run |
| `biomni-drug-discovery-nf:x86` ECR image | ✅ Pushed 2026-04-07; needs smoke test |
| `genomics-germline:x86` ECR image | ✅ Built and pushed 2026-04-07 |
| GROMACS+AmberTools GPU Batch end-to-end | 🔄 Image built; run not confirmed |
| CryoSPARC AWS Batch GPU run (EMPIAR-10028) | ❌ Not yet run |

---

## Business / Partner Operations

| Item | Status |
|------|--------|
| Drug discovery partner identified (Zhejiang People's Hospital) | Not confirmed |
| Cryo-EM partner identified | Not confirmed |
| Pilot data use agreement (legal review) | Template at `business/pilot_data_use_agreement_template.md`; not reviewed |
| Partner onboarding guide / walkthrough | Not built |

---

## Missing Scientific Workflows (Gaps)

| Workflow | Status |
|---------|--------|
| OpenFE RBFE (free energy perturbation) | ❌ Not implemented |
| CYP DDI panel (FAME3 / CYP3A4/2D6/2C9) | ❌ Not implemented |
| GROMACS end-to-end AWS Batch GPU test | 🔄 In progress |

---

## Key Code Locations

- Pilot E2E: `frontend/e2e/pilot-study.e2e.ts`
- Pilot proposals: `business/BioMate_DrugDiscovery_Pilot_Study_Proposal.docx`, `BioMate_CryoEM_Pilot_Study_Proposal.docx`
- P0 validation workflows: `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/p0_*/`
- Pilot account logic: `frontend/server/routes.ts` (PILOT_ACCOUNT_EMAILS check)
- KPI logging: `ai_assistant.py` (H1/H2/H3 metrics logged but not aggregated)

---

## Priority Actions

1. Compile P0 validation report (partner-facing PDF) from local P0 results
2. Run GROMACS + CryoSPARC end-to-end on AWS Batch GPU queue
3. Build pilot KPI dashboard (task 3.3 from open tasks doc)
4. Confirm drug discovery and cryo-EM pilot partners and send proposals
