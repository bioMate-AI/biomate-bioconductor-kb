# WGS + Cryo-EM UI e2e — findings (non-project domain extension)

**Date:** 2026-07-30
**Status:** tests written (real UI e2e, canonical fixture, to-completion + report audit); both routed
correctly; **neither reached `completed`** — one infra, one launch-failure. Both committed `fixme`.
**Tests:** `frontend/e2e/wgs-capstone.e2e.ts`, `frontend/e2e/cryoem-capstone.e2e.ts`

---

## Cryo-EM SPA — BLOCKED BY INFRA (not code, not test)

- **Routing:** ✅ query → `CryoSPARC Standard Single-Particle Analysis`.
- **Execution:** ❌ the **CryoSPARC GPU host `52.42.49.175:30000` is down/unreachable** — a TCP
  connect from the Galaxy container reports the **port closed**. The frontend has the CryoSPARC AMI
  configured (`hasCryoSPARCInstance=true, CRYOSPARC_AMI_ID=true`) but the instance isn't running.
- **Action:** start the CryoSPARC GPU instance (infra), then un-`fixme` the test. Real pre-staged data
  exists (`s3://biomate-cryo-data/empiar-10028/…`) and a license/host are configured in the workflow
  — so once the GPU box is up, a real SPA run should complete.

## WGS variant calling — LAUNCH FAILURE (needs root-cause)

- **Routing:** ✅ `Wgs Germline Gatk` (high-confidence, score 163.93),
  `nextflow_nfcore/subworkflows/genomics/wgs_germline_gatk/main.nf`. The schema exposes `req=1`,
  `opt=11` (`max_spots, reference, known_sites, dbsnp_vcf, caller, scatter_count, ploidy, …`).
- **Execution:** ❌ run `634d6eea` failed at launch — **steps=0/0, returncode=1** (died before any
  pipeline step ran).
- **Likely cause:** the single **required** param (the input — SRA accession / reads) not auto-filling
  from the query, so Nextflow launches without an input. This is the same *class* of gap as the
  project-file bug (a required input not threaded to the workflow), but for **SRA-accession input**
  rather than uploaded files. Needs confirmation of which param is required and where the SRA
  accession should be extracted (rule-based extraction of `SRR…` → the required input param).
- **Next step:** inspect the `wgs_germline_gatk` required param name + the nextflow command actually
  launched (params passed), then add rule-based SRA-accession extraction if that's the gap.

## What IS verified (for contrast)

The execution path itself is healthy — `nf-core/differentialabundance` (project, real DE) and
`predict_admet_properties` (iptacopan) both **completed** on dev in the same window. So WGS/Cryo-EM
failures are domain-specific (WGS input param; Cryo-EM GPU host), not a general execution regression.

## Recommendation

1. **Cryo-EM:** infra — bring the CryoSPARC GPU host up; then the test verifies a real SPA completion.
2. **WGS:** worth a focused root-cause (required-input param extraction for SRA accessions). Likely a
   small rule-based fix mirroring the project-file resolution, but confirm the exact required param
   first.
