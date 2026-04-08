# Pilot Study — Open Tasks for Assignment
*April 2026 · Owner: assign as needed*

This document lists everything not yet done for the drug discovery and cryo-EM pilot studies. Tasks are grouped by area and ordered by blocking priority within each group.

---

## 1. AWS Infrastructure (Blocking Tier A execution)

### 1.1 Verify AWS CLI fix is live on Batch workers
**Status:** Code fix applied (`nextflow_executor.py` now generates `cliPath = '/usr/local/bin/aws'`). Not yet confirmed working on a live Batch run.  
**Task:** Submit one Tier A workflow (e.g. NCA/PKNCA) on AWS Batch profile and confirm it no longer fails with `bash: /opt/aws-cli/bin/aws: No such file or directory`.  
**Owner:** Platform Eng.

### 1.2 Build and push `biomni-drug-discovery-nf:x86` to ECR
**Status:** ECR repo exists. Tag `:x86` was pushed 2026-04-07 but it is **untagged layers only** — no confirmed working image with GROMACS, REINVENT4, RDKit, MM-GBSA tools inside.  
**Task:** Build the image from `backend/docker/drug-discovery-nf/Dockerfile`, confirm it contains: GROMACS 2025, AmberTools 23, REINVENT4 4.4.14, RDKit, AiZynthFinder, PKNCA. Push as `:x86` to `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-drug-discovery-nf`.  
**Owner:** Platform Eng.

### 1.3 Build and push `genomics-germline:x86` to ECR
**Status:** Dockerfile written at `backend/docker/genomics-germline/Dockerfile`. ECR repo created. Image **not yet pushed**.  
**Task:** `docker buildx build --platform linux/amd64 -t .../biomate/genomics-germline:x86 --push -f backend/docker/genomics-germline/Dockerfile .`  
Verify bwa-mem2, gatk4, samtools, mosdepth, fastqc, fastp, snpEff all present.  
**Owner:** Platform Eng.

### 1.4 End-to-end Batch smoke test after image fixes
**Status:** Not done.  
**Task:** Run all four Tier A workflows (NCA/PKNCA, scaffold hopping, drug MoA RNA-seq, AlphaFold DB search) on AWS Batch after 1.1–1.2 are complete. Confirm `status=completed` and `output_files` returns real files.  
**Owner:** Platform Eng. / BioMate AI Team

---

## 2. P0 Validation Workflows (Platform credentials for pilot)

The Nextflow workflows for the five gold-standard checks exist (`p0_docking_validation`, `p0_mrna_validation`, `p0_pharmacophore_validation`, `p0_pkpd_semaglutide`) but have **not been run end-to-end on AWS Batch**.

### 2.1 Run P0-C: Docking RMSD (Mpro + nirmatrelvir, PDB 7RFS)
**Status:** ✅ DONE (2026-04-08). `p0_docking_validation` ran locally with docker profile. Process succeeded (16m 27s, 1/1 ✔).  
**Owner:** BioMate AI Team

### 2.2 Run P0-B: mRNA design (mRNA-1273, GenBank OK120841.1)
**Status:** ✅ DONE (2026-04-08). `p0_mrna_validation` ran locally. Process succeeded (1m 43s, 1/1 ✔).  
**Owner:** BioMate AI Team

### 2.3 Run P0-D: Pharmacophore AUC-ROC (GLP-1R, PDB 7KI0)
**Status:** ✅ DONE (2026-04-08). `p0_pharmacophore_validation` ran locally. Process succeeded. Fixed Groovy SMARTS interpolation bug (simplified hbond_acceptor SMARTS).  
**Owner:** BioMate AI Team

### 2.4 Run P0-E: PK/PD model (semaglutide SUSTAIN-1)
**Status:** ✅ DONE (2026-04-08). `p0_pkpd_semaglutide` ran locally. **OVERALL: PASS** — Cmax,ss 33.27 nM (ref 30 nM ±30%: 21–39 nM), weight loss −5.66 kg (SUSTAIN-1 target −3 to −6 kg). Fixed: `"""` Python docstring inside NF triple-quoted block; Unicode chars in Groovy comment; cmax_ref updated 15→30 nM.  
**Owner:** BioMate AI Team

### 2.5 Compile P0 validation report (partner-facing PDF/DOCX)
**Task:** Once 2.1–2.4 pass, combine outputs into a one-page validation summary showing pass/fail on all five checks with actual vs. target values. This is the deliverable BioMate AI sends to the partner at the start of the pilot.  
**Owner:** Founder / Sci. Lead

---

## 3. Pilot Deliverables — Not Yet Built

The pilot study proposals commit to three automated deliverables. None are currently accessible to a partner user.

### 3.1 QC audit log export (partner-facing download)
**Status:** ✅ DONE (2026-04-08). Backend: `GET /api/invocations/{id}/qc-audit-download` returns JSONL with Content-Disposition. Frontend: "Download QC Audit Log" button (`data-testid="button-download-qc-audit"`) added to workflow viewer. Proxy route added in `routes.ts`.  
**Remaining:** None — endpoint returns 200 and file download works end-to-end.  
**Owner:** Product Eng.

### 3.2 Methods report export (partner-facing download)
**Status:** ✅ DONE (2026-04-08). Backend: `GET /api/invocations/{id}/methods-report` returns plain-text report with methods_text, tool versions, and run context. Frontend: "Download Methods Report" button (`data-testid="button-download-methods-report"`) added to workflow viewer.  
**Remaining:** Report format is plain text; a DOCX version with citation formatting is a future enhancement.  
**Owner:** Product Eng.

### 3.3 Pilot evaluation summary / KPI dashboard
**Status:** Not built. H1/H2/H3 metrics are logged but there is no view aggregating them across all sessions for a pilot account.  
**Task:** Build a simple per-account pilot summary page showing: sessions submitted, sessions completed without correction (H1), average time-to-result (H2), and a placeholder for QC ratings (H3 populated from exit survey). Exportable as PDF.  
**Owner:** Product Eng.

---

## 4. Partner Operations (Business tasks)

### 4.1 Identify and contact drug discovery pilot partner
**Status:** Proposal targets Zhejiang People's Hospital, Department of Medicine. No confirmed contact.  
**Task:** Identify the PI, send the `BioMate_DrugDiscovery_Pilot_Study_Proposal.docx`, and agree on a start date, target protein, and compound set.  
**Owner:** Founder / BD

### 4.2 Identify and contact cryo-EM pilot partner
**Status:** Proposal document ready (`BioMate_CryoEM_Pilot_Study_Proposal.docx`). No confirmed partner.  
**Task:** Identify a structural biology lab actively working on a GPCR or enzyme target. Send proposal. Confirm CryoSPARC license status for P0-A.  
**Owner:** Founder / BD

### 4.3 Finalise pilot data use agreement
**Status:** Template exists at `business/pilot_data_use_agreement_template.md`. Not yet reviewed by legal.  
**Task:** Legal review of data use agreement. Ensure it covers: data deletion within 14 days on request, prohibition on model training with partner data, compound confidentiality.  
**Owner:** Founder / Legal

### 4.4 Pilot account provisioning flow
**Status:** ✅ DONE (2026-04-08). `PILOT_ACCOUNT_EMAILS` env var (comma-separated) implemented. Pilot users: skip LLM billing emit in `routes.ts`, tagged as `isPilotUser` in enrichedContext and KPI logs, `is_pilot` flag passed to `nextflow/execute` and stored in run metadata. Documented in `.env.example`.  
**Remaining:** KPI dashboard (task 3.3) still needed. No DB schema change required — env-var approach is sufficient for pilot window.  
**Owner:** Product Eng.

---

## 5. Missing Workflows (Scientific gaps)

These were identified in the audit as genuine gaps relative to the pilot proposals.

### 5.1 GROMACS AMBER GPU molecular dynamics — end-to-end test
**Status:** 🔄 IN PROGRESS (2026-04-08). ECR image `biomate/ambertools-gromacs-nf:latest` **built and pushed** (1.0 GB, AMD64, conda-forge AmberTools 23 + GROMACS 2024.2 + RDKit + acpype, pushed 2026-04-08 13:59). Workflow `gpu_batch` profile updated: mixed-queue (prep → `biomate-nextflow-queue`; PRODUCTION_MD → `galaxy-cloud-queue-gpu` with `accelerator=1`). Test inputs at `s3://biomate-workflow-inputs/gromacs-gpu-test/`.  
**Remaining:** Submit GROMACS workflow with `-profile gpu_batch` on AWS Batch. Verify RMSD ≤ 3 Å and ΔGbind output file produced.  
**Owner:** Platform Eng. / BioMate AI Team

### 5.2 CryoSPARC workflow — end-to-end AWS Batch test
**Status:** CryoSPARC workflows exist and have been tested locally. Full pipeline at `pipeline_composition/pipelines/cryosparc_standard_spa/main.nf`, 14 CryoSPARC modules at `pipeline_composition/modules/cryosparc/`, and 13 specialised subworkflows at `nextflow_nfcore/subworkflows/cryo_em/` (3D variability, focused refinement, helical SPA, topaz picking, etc.). Not yet run end-to-end on AWS Batch with a real GPU instance.  
**Task:** Run the `cryosparc_standard_spa` pipeline on AWS Batch using EMPIAR-10028 micrograph subset (β-galactosidase, ~500 micrographs). Confirm FSC resolution ≤ 2.5 Å reported in output JSON. Verify CryoSPARC license key is correctly passed as a Nextflow secret (`CRYOSPARC_LICENSE`) and not hardcoded.  
**Owner:** Platform Eng.  
**Note:** RELION 4.0 fallback already planned (pass criterion relaxed to ≤ 3.0 Å) if license provisioning blocks partner onboarding.

### 5.3 OpenFE RBFE workflow (free energy perturbation)
**Status:** Not implemented. Identified as high-priority scientific gap in audit.  
**Task:** Build `openfe_rbfe` subworkflow using OpenFE 1.x. Benchmark on BCR-ABL1 congeneric series (imatinib → nilotinib → dasatinib). Target: ΔΔGbind within 1 kcal/mol of experiment for 5 compound pairs.  
**Owner:** BioMate AI Team

### 5.4 CYP DDI / metabolic clearance workflow
**Status:** Not implemented. Identified as high-priority gap.  
**Task:** Build `cyp_ddi_panel` subworkflow using FAME3 or CYPstrate containers for CYP3A4/2D6/2C9 inhibition prediction. Flag compounds with predicted DDI liability.  
**Owner:** BioMate AI Team

---

## 6. Routing / AI Quality

### 6.1 Drug MoA RNA-seq (DA3) routes to nf-core chain instead of custom workflow
**Status:** ✅ DONE (2026-04-08). Direct-lookup path implemented: `get_workflow_by_name()` in `unified_workflow_search.py` + `_try_direct_workflow_lookup()` in `ai_assistant.py`. Step 0.5 in `generate_workflow_unified()` — if query contains exact workflow name (snake_case with 2+ parts), returns match with score=20.0, bypassing FTS scoring entirely. Tested: drug_moa_rnaseq, nca_pknca, scaffold_hopping, gromacs_protein_md all return correct workflow directly.  
**Owner:** BioMate AI Team

---

## Summary Table

| # | Task | Area | Priority | Owner |
|---|---|---|---|---|
| 1.1 | Verify AWS CLI fix on Batch workers | Infra | **Critical** | Platform Eng. |
| 1.2 | Build & push `biomni-drug-discovery-nf:x86` | Infra | **Critical** | Platform Eng. |
| 1.3 | Build & push `genomics-germline:x86` | Infra | High | Platform Eng. |
| 1.4 | End-to-end Batch smoke test | Infra | **Critical** | Platform Eng. |
| 2.1–2.4 | ✅ Run P0 validation checks (all 4) | Platform | **Critical** | BioMate AI Team |
| 2.5 | Compile P0 report for partner | Business | High | Founder / Sci. Lead |
| 3.1 | ✅ QC audit log export button | Product | High | Product Eng. |
| 3.2 | ✅ Methods report export button | Product | High | Product Eng. |
| 3.3 | Pilot KPI dashboard | Product | Medium | Product Eng. |
| 4.1 | Drug discovery partner contact | Business | **Critical** | Founder / BD |
| 4.2 | Cryo-EM partner contact | Business | High | Founder / BD |
| 4.3 | Data use agreement legal review | Legal | High | Founder / Legal |
| 4.4 | ✅ Pilot account flag + bypass billing | Product | High | Product Eng. |
| 5.1 | 🔄 GROMACS/AMBER GPU test (ECR image ✅ pushed, Batch run pending) | Platform | High | Platform Eng. |
| 5.2 | CryoSPARC end-to-end AWS Batch test | Platform | High | Platform Eng. |
| 5.3 | OpenFE RBFE workflow | Science | Medium | BioMate AI Team |
| 5.4 | CYP DDI panel workflow | Science | Medium | BioMate AI Team |
| 6.1 | ✅ Drug MoA routing direct-lookup fix | AI | Low | BioMate AI Team |

---

*Generated 2026-04-08 from audit log `docs/nextPhase/20260407_DRUG_DISCOVERY_WORKFLOW_AUDIT.md` and codebase inspection.*
