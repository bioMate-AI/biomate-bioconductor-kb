# Real use-case E2E — results (2026-10-06, live dev AWS Batch)

Ran the (now-repaired) `scripts/run_real_workflows.sh` against `https://dev-public.biomate.ai` with the
canonical fixture, `DOMAINS="admet rnaseq wgs"`. Real browser, real backend, real S3, real AWS Batch, no
mocks. Honest outcomes below — one genuine end-to-end success, one known-broken (skipped), one real failure.

## Summary
| Domain | Result | run_id | Note |
|---|---|---|---|
| **RNA-seq (DESeq2)** | ✅ **REAL PASS — completed** | `4dbcc0cf-ce6f-4ef0-9c1f-2b98b02343ea` | GSE227835 MG counts → nf-core/differentialabundance, 1m15s wall, real 4.6 KB DE report |
| **WGS variant calling** | ⚠️ **SKIPPED (not run)** | — | `test.fixme` — known-broken SRA-accession→fetchngs path (`docs/20260730_WGS_CRYOEM_ROOTCAUSE_AND_FIXES.md`). The harness miscounts fixme as PASS (fixed — see below). |
| **ADMET** | ❌ **FAIL (timeout, 25–30 min, no terminal)** | — | Routing + QC gate worked; run did not complete in budget AND the run record was mislabeled. Real anomaly (below). |

## RNA-seq — genuine end-to-end proof ✅
Chat ("bulk RNA-seq counts from GSE227835 … run differential expression with nf-core/differentialabundance")
→ routed chip `nf-core/differentialabundance` → executed on AWS Batch (runId `4dbcc0cf…`) → **COMPLETED** in
1m15s → a real DE report (4624 bytes, abstract + results, not a failure stub). This is the instruction panel's
RNA-seq ability working for real, from counts to report.

## WGS — known-broken, intentionally skipped ⚠️
`e2e/wgs-capstone.e2e.ts:51` is `test.fixme`. Documented root cause: SRA-accession workflows need `fetchngs`
to run on Batch+S3 and thread the S3 samplesheet; until that's fixed the main workflow never starts. This is a
pre-existing, documented open issue — NOT a regression from this session, and NOT a real run.

## ADMET — real anomaly surfaced (worth diagnosing) ❌
The ADMET case exercised the hard parts correctly but did not finish:
- **Routing correct:** chat → `state: workflow_ready`, workflow `predict_admet_properties` (response names hERG/CYP3A4/Ro5).
- **QC gate FIRED:** a live `QC Gate` SSE event for `PREDICT_ADMET_PROPERTIES_WORKFLOW:PREDICT_ADMET_PROPERTIES`
  with **2 failures** — i.e. the hERG cardiotoxicity gate on terfenadine fired as designed (this is the behavior
  the earlier `project_workflow_validation_gaps` memo said had never been seen fire live — it now has).
- **Two defects:**
  1. **Run mislabel / chain-name leak:** the launched run reported
     `invId=chain_1791260333_5f39f9 name="Bulk RNA-seq DE -> Pathway Enrichment (airway/GSE52778 validation)"`
     — an RNA-seq chain name on an ADMET execution (the QC gate confirms ADMET actually ran). A stale chain
     name appears attached to the ADMET run record.
  2. **Non-completion:** the run polled `running` for the full ~30-min budget and the test timed out at the poll
     loop (`realrun-admet.e2e.ts:294`) — no terminal state. Possible causes: AWS Batch cold-start + the
     auto-loop remediation re-running after the 2 gate failures, or a stuck run. Needs a run-state trace to
     distinguish "legitimately slow auto-loop" from "stuck".

Recommended next step (separate task): trace run `chain_1791260333_5f39f9` on dev — confirm whether the ADMET
chain completed on Batch after the gate/auto-loop, and fix the chain-name leak in the run record.

## Harness defect fixed this session
`run_real_workflows.sh` (1) pointed at deleted spec files → "No tests found" for every domain (fixed earlier,
`docs/20261005_REAL_RUN_HARNESS_FIX.md`), and (2) reported a Playwright `skipped`/`fixme` as **PASS**, which hid
that WGS never ran. Fixed to report `SKIP` distinctly so a fixme can't masquerade as a green run.

## Net
The instruction panel's advertised abilities were tested for real: **RNA-seq is proven end-to-end**; **WGS is a
documented known-broken path (not run)**; **ADMET routes and gates correctly but has a real completion/labeling
bug** to chase. CryoEM (GPU, ~$1.50) was intentionally held.
