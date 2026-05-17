# ANDV campaign — engineering lessons learned (in silico)

Audience: anyone rerunning **inhibitor**, **Plan A epitope**, or **Plan B mRNA** tracks via BioMate Nextflow + AWS Batch. These are **process** lessons from real runs in `research/anti-virus/runs/` (2026-05).

---

## 1. Never hardcode `run_id` when polling Galaxy

**Symptom:** Log line like `POLL_SKIPPED: submit.json run_id is X (not Y); no GET …/status poll`.

**Cause:** An automation step compared the **current** `submit.json` to a **stale** UUID pasted from an earlier resume note. Every successful `POST /api/nextflow/execute` issues a **new** `run_id`; re-submits **must** change it.

**Rule:** Always `jq -r '.run_id' …/submit.json` (or read `status.json` from the same attempt) and poll **that** id until terminal.

**Doc fix:** `research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z/STEPS_5_6_RESUME.md` now uses dynamic `RID=`.

---

## 2. Long Batch jobs + Galaxy status = transient HTTP errors

**Symptom:** `urllib.error.HTTPError: 500` on `GET /api/nextflow/status/{run_id}` mid-poll (especially GROMACS MD).

**Mitigation (implemented):** `research/anti-virus/scripts/run_andv_inhibitor_pipeline_nextflow.py` uses `request_json_retry` for status and output-file fetches (5xx / transient URL errors, bounded retries).

**Operational:** Keep `--step-timeout` generous for MD (e.g. **43200** s); do not treat a single 500 as “job dead” without checking Batch / S3 outdir.

---

## 3. Chain-of-custody for ligands (inhibitor)

**Lesson:** ADMET + Vina must consume the **same** SMILES set as pharmacophore output when that is the scientific claim.

**Implementation:** `run_andv_inhibitor_pipeline_nextflow.py` reads `02_pharmacophore/filtered_compounds.smi` into steps 3–4 when the manifest contains that artifact.

**Evidence run:** `andv_nf_pipeline_20260512T185322Z/` (contrast audited demo `181054Z`).

---

## 4. ADMET `toxicity_report.json`: aggregate vs per-compound DILI

**Lesson:** Phase-1 RDKit heuristics in `per_compound` could disagree with ADMET-AI aggregate `toxicity` after Chemprop.

**Code fix:** `predict_admet_properties/main.nf` syncs per-row DILI from `per_compound_admet_ai` with the same thresholds as the aggregate.

---

## 5. nf-core/epitopeprediction on Batch

**Lessons:**

- Vendored tree `backend/nf-core-workflows/epitopeprediction` must include `conf/` — run `ensure_nfcore_epitopeprediction_worktree.sh` if sparse-checkout stripped it.
- Samplesheet on S3: each row’s `filename` must be an **absolute** `s3://…` path (see `plan_a_epitope_samplesheet_template/`).
- **Profile:** use **`docker`** with `executor: awsbatch` — the pipeline does **not** ship an `aws` Nextflow profile.
- **Submission helper:** `research/anti-virus/scripts/run_plan_a_epitopeprediction_batch.py` — status polling **retries transient HTTP 5xx**; use **`--poll-run-id <uuid>`** to resume watching after a client failure **without** a second `POST /execute`.

---

## 6. Local Docker images for ADMET

**Lesson:** `biomate/biomni-admet:latest` is **not** on Docker Hub; local dev builds from `backend/docker/biomni-admet/Dockerfile` with optional `BASE_IMAGE=biomate-nextflow-base:local` (see `build-pharma-images.sh biomni-admet-local`).

---

## 7. GROMACS MM-GBSA scale (inhibitor step 5)

**Observation:** Failed run `05_gromacs_mmgbsa/status.json` shows **very large** solvated systems (e.g. on the order of **10⁶** “residues” in tleap output in `log_tail`) — likely **intractable** for default Batch memory / wall time for a full viral assembly.

**Publication / demo strategy without wet lab:**

- Prefer **trimmed receptor** (binding-site-only PDB) for MD/MM-GBSA narratives, **or**
- Skip MD in the minimal story and cite **docking + ADMET + REINVENT** only, **or**
- Use a lighter workflow from `ANDV_INHIBITOR_INSILICO_PREPRINT_STACK.md` (e.g. shorter MD path, OpenFE RBFE only between two ligands with explicit scope).

**Manifest hygiene:** On `--append-to-run`, the driver now **`pop("error", None)`** so a previous step’s `error` string does not linger across a new append attempt.

---

## 8. Agent / CI guardrails

- Do **not** “assign” the user a manual run without also leaving a **one-command** script path in-repo.
- When the parent chat **shell** is unreliable, use a **subagent shell** with `all` + network for real execution, and write **`RESULT.txt`** artifacts under `research/anti-virus/runs/`.

---

## Related files

| Topic | Path |
|--------|------|
| Inhibitor preprint stack | `research/anti-virus/docs/ANDV_INHIBITOR_INSILICO_PREPRINT_STACK.md` |
| Plan A vaccine checklist | `research/anti-virus/docs/PLAN_A_VACCINE_INSILICO_PUBLICATION_CHECKLIST.md` |
| Session audit | `runs/SESSION_SELF_AUDIT_20260512.md` |
| Capability map | `BIOMATE_CAPABILITY_GAP.md` |
