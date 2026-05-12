# Self-audit: agent session work, outputs, and logs (2026-05-12)

This document audits **what was changed in git**, **what was executed on AWS Batch / locally**, and **known gaps** so a reviewer can trace evidence without re-running jobs.

---

## 1. Git history (relevant commits, `integration/next-phase`)

| Commit | Scope |
|--------|--------|
| `8ef5b23bc` | `docking_autodock_vina/main.nf`: S3 receptor staging, box trim, Groovy-safe embedded Python, ECR `biomni-structure-to-drug:x86`, `+ NL` newline fix. |
| `27976001e` | `MASTER_ANDV_CAMPAIGN_GUIDE.md`: Plan A routing to nf-core epitopeprediction (id 12700). |
| `0ed979ab4` | Plan B doc routing + `run_inhibitor_stack_smoke.sh` (step 1 only). |
| `e2bb5d7a3` | Plan A epitope template dir, `run_plan_b_codon_lnp_smoke.sh` (print-only examples), Plan B doc table. |
| `072e830f0` | **`run_andv_inhibitor_pipeline_nextflow.py`** first tracked + pharmacophore→ADMET/Vina SMILES wiring; `AUDIT.md` for pre-fix run; `run_inhibitor_computational_to_docking.sh` optional `SMILES_JSON`. |

**Integrity:** `python3 -m py_compile` was run on `run_andv_inhibitor_pipeline_nextflow.py` after the SMILES wiring edit (exit 0).

---

## 2. Inhibitor track — outputs and logs

### 2.1 Canonical “fixed chain” run (use this for scientific claims)

| Item | Value |
|------|--------|
| **Run directory** | `research/anti-virus/runs/andv_nf_pipeline_20260512T185322Z/` |
| **Manifest** | `pipeline_manifest.json` — `through_step`: 4, `user_id`: `andv-inhibitor-chained-20260512` |
| **Chain check** | `02_pharmacophore/filtered_compounds.smi` first column **matches** `03_admet/parameters.json` `smiles_list` JSON (three SMILES). |

**Step run_ids (from manifest):**

1. pocket `a9c05453-4798-49a6-874d-7f701a6ce309` — terminal **`completed`**
2. pharmacophore `2f63eeb8-69d5-4f75-83b0-cc4c99af77a2` — **`succeeded`**
3. admet `e71f59c4-c92d-478e-86c7-20a8cd28d082` — **`succeeded`**
4. docking_vina `d62178e4-39e1-4114-86ef-06559f6942d4` — **`succeeded`**

**QC (pocket):** `01_pocket/structure_qc_result.json` — `status`: **PASS**, `top_druggability_score` 0.563, `top_volume` 562.2 Å³, `evidence_tier` BRONZE.

**Logs:** Primary executor text is in each step’s **`status.json`** (`log_tail`). Large HTML traces: `report.html`, `timeline.html` per step. No separate `.log` files in those dirs.

**Known residual (not fixed in this session):** Original `AUDIT.md` (pre-addendum) noted **DILI inconsistency** between top-level and `per_compound` blocks in `toxicity_report.json` for the **pre-chaining** run; re-audit of `03_admet/toxicity_report.json` in **185322Z** was not repeated line-by-line here — treat as **open** if used for automated gating.

### 2.2 Earlier run (historical; bug documented there)

| Run directory | Note |
|---------------|------|
| `andv_nf_pipeline_20260512T181054Z/` | Pre–SMILES-wiring run; **`AUDIT.md`** + **addendum** explain ADMET/Vina used wrong ligand set until `072e830f0`. |

---

## 3. Plan A — outputs and logs

| Path | Outcome |
|------|---------|
| `plan_a_exec_20260512T184220Z/EXECUTION_REPORT.md` | **partial** — structures fetched (exit 0); epitopeprediction **failed** (NF25 parse, ARM/amd64 Docker, conda pandas, missing vendored `epitopeprediction/conf/base.config` on Galaxy path); AlphaFold DB search **`-preview` exit 0**. |
| `plan_a_exec_20260512T184220Z/logs/` | Referenced in report (`nfcore_epitopeprediction*.log`, `galaxy_epitope_poll.log`, `fetch_guo_structures.log`). |

**Gap:** No successful MHC/peptide prediction artifact from BioMate or nf-core on this host without infra fixes.

---

## 4. Plan B — outputs and logs

| Path | Outcome |
|------|---------|
| `plan_b_exec_20260512T184230Z/EXECUTION_REPORT.md` | **10813**, **10721**, **12869** all **`succeeded`** on Batch; S3 outdirs under `s3://biomate-nextflow-work/nextflow/outputs/plan_b_exec_20260512T184230Z/…`; local **`proof_*_versions.yml`** copies. |
| `submissions.json`, `poll_results.json`, etc. | Machine-readable submit/poll trail per report. |

**Gap:** Status API sometimes returned empty `s3_output_files`; proof used **`aws s3 ls` / `aws s3 cp`** — acceptable but should be noted for automation that expects status-only file lists.

---

## 5. Process / honesty audit

| Claim | Accurate? |
|-------|-----------|
| “Batch is default” | **Yes** for `run_andv_inhibitor_pipeline_nextflow.py` (`compute_config.executor`: `awsbatch`). |
| “Smoke = full project” | **Corrected:** smoke script is step 1 only; full stack is `run_inhibitor_computational_to_docking.sh` or `--through-step 4` without forced `SMILES_JSON`. |
| “Three parallel Task agents” | **Two completed**, Plan B agent previously blocked once by provider policy; later Plan A/B execution agents **did** run. |
| “DB in git” | **Clarified:** `*.db` is gitignored; local SQLite edits are not durable repo state. |

---

## 6. Reviewer checklist (quick)

- [ ] Open `andv_nf_pipeline_20260512T185322Z/pipeline_manifest.json` — four steps, all terminal OK.
- [ ] Diff `02_pharmacophore/filtered_compounds.smi` vs `03_admet/parameters.json` — must match order/SMILES set.
- [ ] Open `04_docking_vina/docking_autodock_vina_results.json` — three compounds, finite affinities.
- [ ] Read `plan_b_exec_20260512T184230Z/EXECUTION_REPORT.md` — three succeeded Batch jobs.
- [ ] Read `plan_a_exec_20260512T184220Z/EXECUTION_REPORT.md` — epitope branch failures are **environment/config**, not silent success.

---

*Generated as a session self-audit; amend if new runs supersede these paths.*
