# REQUIREMENT — Full Early-Stage Drug-Development Process Tutorial + Videos (for another session)

**Date:** 2026-10-06
**Status:** Requirement / handoff spec. This workstream is to be OWNED and executed by a separate session (video/tutorial-owning session). The session that wrote this is handing it off and returning to its own work.
**Why this exists:** the current drug-discovery tutorials are **ADMET/PK-only, and the one "generation" page is a scripted storyboard, not a real run.** For a layman that is backwards — the compelling part is watching a drug get *generated*, then triaged, then reported. This requirement specifies the real, end-to-end deliverable.

---

## 1. Objective (what "done" means)

A **generation-first, full early-stage drug-discovery tutorial** — page(s) + narrated videos — that shows the entire process run **live on BioMate's own execution engine**, with **real artifacts at every stage**:

1. **GENERATE** novel candidates (`REINVENT4 Generative Lead Design`, real learned backend) → real SMILES.
2. **TRIAGE** those exact candidates: ADMET prediction (hERG / CYP / AMES / bioavailability) **and** molecular docking → filter + rank.
3. **REPORT** a layman-legible findings/methods report tying generation → triage → selected leads.

Deliverables:
- The full-process **walkthrough HTML** (wired to the auto-play `window.__timeline`/`window.__done` pipeline), generation **first**, ADMET/docking as the *filter* (not the headline).
- **EN + ZH videos**, both languages, idiomatic Chinese (not literal calques).
- **High resolution** (see §3 — the current videos are too low-res; this is a hard requirement).
- Uploaded to the shared drive (see §5).

## 2. Current state & blockers (from `docs/20261006_DRUG_GENERATION_EXECUTION_GATE.md`, commit `28bcd950e`)

Generation capability is **present and wired** but **not yet proven live**. The gate work is done; here is exactly what remains:

- **Generation workflow is REAL** (DB id 12800; `.nf` at `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/reinvent4_lead_design/main.nf`); default backend `generator=reinvent4` is genuine learned sampling (fails loudly, never silently enumerates); both ECR images exist (`reinvent4-nf:x86`, `biomni-drug-discovery-nf:x86`).
- **BUG #1 — FIXED, NOT YET DEPLOYED.** A plain "generate drug-like molecules" (`scoring_function=qed_sa`, no receptor) was wrongly rejected `400 missing_required_params` (receptor/docking_ref_ligand/custom_toml). Root cause fixed in `backend/lib/galaxy/ai/ai_assistant.py` (`_OPTIONAL_NULL_PARAMS`). **ACTION: run `scripts/sync_to_dev.sh` to deploy** (pre-sync checklist first), then re-verify search→execute returns those three params as *optional*.
- **BUG #2 — UNVERIFIED IMAGE RISK.** `backend/docker/reinvent4-nf/Dockerfile` pins `REINVENT4_REF=v4.5.5`, a tag that no longer exists (prior URL now 404s). The image predates removal so priors *may* be fine. A live run is the authoritative check — **if `GENERATE_REINVENT4` exits 4/5, rebuild `reinvent4-nf` with `REINVENT4_REF=v4.5.11` (or vendor priors to S3/ECR) and re-push `:x86`.**
- **EXECUTE IS BLOCKED BY PERMISSION, NOT BY BIOMATE.** `POST /api/workflows/execute` (launches Batch compute on shared dev) was denied by the auto-mode permission classifier. **ACTION: this session/owner must run the execute step with execute permission granted, or the user runs the reviewed §1.4 payload manually.** A ready-reviewed CPU payload exists (acetaminophen seed `CC(=O)Nc1ccc(O)cc1`, mode=scaffold_hopping→Mol2Mol, `qed_sa`, gpu=false, n_steps=50/batch=40/top_n=25) — see §1.4 of the gate doc.
- **TRIAGE (ADMET + docking) HAS NO REAL-EXEC EVIDENCE.** Every relevant workflow is `real_exec_status = NULL` (predict_admet_properties, ADMET_pred, herg_cardiac_safety_qsar, docking_autodock_vina, run_diffdock_with_smiles, structure_prediction_docking, schrodinger_glide_docking). Drug_discovery+pharmacology = 6 ok / 4 ok_warnings / 10 exec_error / 219 NULL, and the 10 validated are all Bioconductor pharmacogenomics packages — none ADMET/docking. **ACTION: validate ADMET + docking live on the generated SMILES and backfill `real_exec_status` BEFORE the tutorial claims real triage.** (Discrepancy to settle with memory `project_drugdev_capability`'s "~215 tested" claim — the evidence may live outside this column, e.g. the ADMET hERG QC-gate E2E tests in `CLAUDE.md`; confirm, don't assume.)
- **REPORT** is gated on real Stage-1 + Stage-2 artifacts.

## 3. UI resolution (hard requirement — current videos are too low-res)

The rendered tutorial videos are visibly low-resolution/blurry. **Root-cause the recording pipeline, don't upscale after the fact:**
- The pipeline is auto-play HTML → edge-tts narration → headless record → mux → mp4 (memory `project_educational_video_pipeline`).
- Fix the **record step's viewport + device scale factor**: capture at ≥**1920×1080** with **deviceScaleFactor=2** (retina), and keep a high output bitrate through the mux (no down-scaling, no low-CRF default). Verify the final mp4's actual pixel dimensions.
- Re-render the existing drug-dev/tutorial cuts at the corrected resolution as part of this work.

## 4. Constraints (non-negotiable)

- **BioMate IS the execution engine.** No local REINVENT/Rscript/python install, no substitute model, **no storyboard/mock** standing in for a real run. The tutorial shows *real* generated molecules, *real* ADMET/docking numbers, a *real* report.
- **No fabricated numbers.** If a stage hasn't produced real artifacts, do not ship it as final — mark it clearly and finish the stage first.
- **Root cause over workaround; read the full error before retry** (pre-sync checklist; module-load import check for any `backend/lib/galaxy/**` change).
- **Honesty:** report exactly what ran vs. didn't; real run ids + S3 outdirs + previewed outputs as evidence.
- **Docs in `docs/`**, date-prefixed. **Never the Artifact tool** (publishes publicly) — videos via the render pipeline, docs to `docs/`, uploads via rclone.
- **Live execution path:** fixture `lifeifei163361@163.com` / `WpmFixture!2026`, `BIOMATE_URL=https://dev-public.biomate.ai`, bypass token `biomate-e2e-bypass-token-dev-only`; search→execute→watch→fetch over HTTP (not MCP). Canonical examples `scripts/e2e_use_cases.sh`, `frontend/e2e/allometric-qc-coverage.e2e.ts`.

## 5. Upload target

Shared Drive **`biomateAI_grow`** (team drive `0AMMXec6zCdKbUk9PVA`) → `biomate_growth/tutorial_demo/` → a dated subfolder (e.g. `1006/` or a new `drugdev_fullprocess/`). Provide **direct file links** (not just folder), and share to the user's account if the shared-drive membership is the reason they can't see files. rclone remote: `biomate_drive:`.

## 6. Ordered execution plan

1. Deploy BUG #1 fix (`sync_to_dev.sh` + pre-sync checklist).
2. Launch the §1.4 REINVENT4 payload live (execute permission or manual); capture runId + S3 outdir; preview `top_compounds.sdf` / `generated_molecules.csv`. If exit 4/5 → rebuild image (BUG #2) and re-push.
3. Feed the generated SMILES into ADMET (`predict_admet_properties`, `herg_cardiac_safety_qsar`) + docking (`docking_autodock_vina`); capture real tables/poses; backfill `real_exec_status`.
4. Generate the final report from real Stage-1/2 artifacts.
5. Fix the recording resolution (§3); build the generation-first walkthrough HTML + EN/ZH narration on the real artifacts; render EN + ZH videos at high res.
6. Upload to the shared drive (§5); provide direct links; document in `docs/`.

## 7. Key references

- Execution evidence + reviewed payload: `docs/20261006_DRUG_GENERATION_EXECUTION_GATE.md`
- Generator science/survey: `docs/20261004_MULTIOBJECTIVE_GENERATIVE_SURVEY.md`
- Existing tutorial pages (incl. the storyboard `d3-generative-lead-design`): `reference/claude_design/tutorials/`
- Video pipeline + resolution: memory `project_educational_video_pipeline`
- Catalog DB: `backend/database/galaxy_ai_tools.db`
