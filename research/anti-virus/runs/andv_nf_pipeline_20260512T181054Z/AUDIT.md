# ANDV inhibitor Nextflow pipeline run — audit

**Run directory:** `andv_nf_pipeline_20260512T181054Z`  
**Manifest:** `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/pipeline_manifest.json`  
**Audit date:** 2026-05-12 (workspace clock)  
**Scope:** Steps `01_pocket` → `02_pharmacophore` → `03_admet` → `04_docking_vina` (per manifest `through_step`: 4).

---

## Executive summary

| Verdict | Rationale |
|--------|-----------|
| **CONCERNS** | All four Nextflow substeps report **`status`: `succeeded`**, `returncode`: 0, and expected primary artifacts are present and non-empty locally. **However:** (1) **ADMET and docking inputs are a fixed `smiles_list` in `03_admet/parameters.json` and `04_docking_vina/parameters.json`**, not the ligands from `02_pharmacophore/filtered_compounds.smi`, so **steps 3–4 are not scientifically chained to the pharmacophore filter output** for this run. (2) **`03_admet/toxicity_report.json`** mixes a top-level `toxicity` block (e.g. `dili_risk`: `"high"`, `dili_probability`: 0.675) with **`per_compound`** rows that label the same aspirin SMILES as **`dili_risk`: `"low"`** — inconsistent presentation of DILI for downstream readers. (3) **Nextflow `status.json`** on ADMET and docking records **Graphviz missing** (DAG rendering only; non-fatal). (4) **`04_docking_vina/status.json`** lists **`run_id`** and **`invocation_id`** that **differ** — metadata hygiene only. |

**PASS** would require demonstrable use of pharmacophore-filtered structures in ADMET/docking (or explicit documented override in manifest). **FAIL** is not assigned: no step failed execution or omitted critical outputs for the parameters actually used.

---

## Run identification

| Item | Value |
|------|--------|
| Preferred / latest run | `andv_nf_pipeline_20260512T181054Z` (present; newer than `andv_nf_pipeline_20260509T223205Z` / `...222413Z`) |
| `pipeline_manifest.json` `created_at` | `2026-05-12T18:10:54.137145+00:00` |
| `user_id` | `andv-inhibitor-full-20260512` |
| Input structure | `s3://biomate-nextflow-work/inputs/andv_campaign/20260507/9P3I.pdb` |

---

## Step 01 — pocket (`01_pocket`)

| Field | Value |
|-------|--------|
| **`run_id`** | `1383259f-ec1f-44c6-ab4d-3595e60b5d15` |
| **Terminal status** (`status.json`) | `succeeded`, `returncode`: 0 |
| **Wall time** (`status.json`) | ~204 s (`duration_s`) |
| **Manifest step status** | `succeeded` |

### Key outputs (local path, size)

| Path | Approx. size |
|------|----------------|
| `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/01_pocket/structure_pockets.json` | 2 477 B |
| `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/01_pocket/structure_qc_result.json` | 320 B |
| `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/01_pocket/structure_druggability_report.tsv` | 583 B (~11 data lines + header) |
| `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/01_pocket/structure_top_pocket.pdb` | 189 B (single `HETATM` marker + remarks) |
| `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/01_pocket/report.html` | ~2.9 MB |
| `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/01_pocket/timeline.html` | ~252 KB |
| `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/01_pocket/versions.yml` | 193 B |

### QC / science checks

- **`structure_qc_result.json`:** `status`: **`PASS`**, `num_pockets_evaluated`: **10**, `top_pocket_id`: 1, `top_druggability_score`: **0.563**, `top_volume`: **562.2** Å³, thresholds met (`threshold_score` 0.35, `threshold_volume` 200), `evidence_tier`: **BRONZE**.
- **`structure_pockets.json`:** `num_pockets`: **10**; top pocket center **[173.607, 208.847, 174.042]** (matches manifest `top_pocket_center` and docking box center).
- **Druggability TSV:** 10 pockets with scores/volumes/centers; consistent with JSON.

### Issues / gaps

- **`status.json`** reports `completedSteps`: **0** with `totalSteps`: **2** while `status` is `succeeded` and `progressPercent`: 100 — **counter fields look wrong**; does not affect artifact presence.
- **No dedicated `*.log`** under this folder; executor tail is embedded in `status.json` `log_tail`.
- **`structure_top_pocket.pdb`** is a **minimal marker** (not a full binding-site surface); acceptable if downstream only needs center/box.

---

## Step 02 — pharmacophore (`02_pharmacophore`)

| Field | Value |
|-------|--------|
| **`run_id`** | `b09456e7-b758-4e81-8d15-57fb0470f761` |
| **Terminal status** | `succeeded`, `returncode`: 0 |
| **Wall time** | ~270 s |
| **Manifest step status** | `succeeded` |

### Key outputs (local path, size)

| Path | Approx. size |
|------|----------------|
| `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/02_pharmacophore/summary.json` | 392 B |
| `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/02_pharmacophore/filtered_compounds.smi` | 81 B (**3** lines) |
| `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/02_pharmacophore/match_report.tsv` | 383 B (**7** lines = header + 6 compounds) |
| `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/02_pharmacophore/pharmacophore_model.json` | 1 586 B |
| `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/02_pharmacophore/screened_scores.json` | 1 493 B |
| `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/02_pharmacophore/report.html` | ~2.95 MB |
| `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/02_pharmacophore/timeline.html` | ~253 KB |

### QC / science checks

- **`summary.json`:** `n_library_screened`: **6**, `n_passed_filter`: **3**, `pass_rate_pct`: 50, `n_model_features`: 7, `min_features`: 3 — internally consistent with `match_report.tsv` (**3** `PASS` rows: CPND0001, CPND0002, CPND0006).
- **`filtered_compounds.smi`:** **3** lines — SMILES for aspirin, phenol, and `CC(=O)Nc1ccc(O)cc1` with compound IDs.
- **`parameters.json`:** library and reference actives on S3 under `inputs/andv_campaign/pipeline_demo_20260509/`.

### Issues / gaps

- Same **`completedSteps`: 0** vs **`totalSteps`: 3** pattern in `status.json` as pocket step.
- Downstream **does not** use this file as ligand source (see step 03).

---

## Step 03 — ADMET (`03_admet`)

| Field | Value |
|-------|--------|
| **`run_id`** | `38e3404a-1456-4642-8ed3-03256e85fe51` |
| **Terminal status** | `succeeded`, `returncode`: 0 |
| **Wall time** | ~161 s |
| **Manifest step status** | `succeeded` |

### Key outputs (local path, size)

| Path | Approx. size |
|------|----------------|
| `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/03_admet/predict_admet_properties_results.json` | 1 501 B |
| `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/03_admet/predict_admet_properties_output.txt` | 1 451 B (~41 lines) |
| `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/03_admet/pk_summary.json` | 1 607 B |
| `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/03_admet/toxicity_report.json` | 3 002 B |
| `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/03_admet/dag.dot` | 961 B |
| `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/03_admet/report.html` | ~2.96 MB |
| `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/03_admet/timeline.html` | ~252 KB |

### QC / science checks

- **`predict_admet_properties_results.json`:** `"success": true`; text `result` block covers **CCO**, **CC(=O)O**, **CC(=O)Oc1ccccc1C(=O)O** (ADMET-AI-style properties).
- **`parameters.json`:** `"smiles_list": "[\"CCO\",\"CC(=O)O\",\"CC(=O)Oc1ccccc1C(=O)O\"]"` — **not** the three structures from `filtered_compounds.smi`.
- **`pk_summary.json`:** `"status": "predicted"`, `per_compound` array length **3** for the same three SMILES as above.
- **`toxicity_report.json`:** `compounds_assessed`: **3**; `per_compound_admet_ai` includes DILI_prob **0.6746** for aspirin — aligns with ADMET-AI text. **Top-level `toxicity.dili_risk` / `dili_probability` (high / 0.675) vs `per_compound` third row `dili_risk`: `"low"` and `dili_probability`: 0.106** — **inconsistent labeling** for the same compound across sections.

### Issues / gaps

- **Ligand source:** fixed list in **`03_admet/parameters.json`**; **no evidence in saved artifacts** that pharmacophore **`filtered_compounds.smi`** drove this step.
- **`status.json` `log_tail`:** `WARN: Graphviz is required to render the execution DAG in the given format` — **cosmetic** for HTML DAG; `dag.dot` still present.
- **`completedSteps`: 0** vs **`totalSteps`: 1** again.

---

## Step 04 — docking Vina (`04_docking_vina`)

| Field | Value |
|-------|--------|
| **`run_id`** (`status.json`) | `f468aa94-a009-42e8-95b8-a89301107038` |
| **`invocation_id`** (`status.json`) | **`2519835c-2dc0-4c47-b89f-36a8948bad39`** (≠ `run_id`) |
| **Terminal status** | `succeeded`, `returncode`: 0 |
| **Wall time** | ~250 s |
| **Manifest step `run_id`** | Matches `f468aa94-a009-42e8-95b8-a89301107038` |

### Key outputs (local path, size)

| Path | Approx. size |
|------|----------------|
| `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/04_docking_vina/docking_autodock_vina_results.json` | 1 954 B |
| `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/04_docking_vina/docking_autodock_vina_output.txt` | 916 B (~29 lines) |
| `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/04_docking_vina/pose_000.pdbqt` | ~5.8 KB |
| `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/04_docking_vina/pose_001.pdbqt` | ~6.8 KB |
| `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/04_docking_vina/pose_002.pdbqt` | ~14.7 KB |
| `/home/yzhang/biomate/research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/04_docking_vina/versions.yml` | 165 B |

### QC / science checks

- **`docking_autodock_vina_results.json`:** `"success": true`, `"n_ligands_docked": 3`, **`best_score_kcal_mol`: -4.917** (field name in JSON: `best_score_kcal_mol`; per-ligand **`best_affinity_kcal_mol`**: -2.498 / -2.559 / **-4.917** for CCO / acetic acid / aspirin). **`n_poses`:** 9 each; poses map to `pose_000`–`pose_002` locally.
- **Box:** center **(173.607, 208.847, 174.042)** matches pocket step (from **`04_docking_vina/parameters.json`** and output text).
- **`docking_autodock_vina_output.txt` (first lines):**

```text
BioMate: AutoDock Vina Molecular Docking
============================================================

  Receptor PDB trimmed to search box (+ 8 A pad): 1327 ATOM/HETATM records (large assemblies -> tractable PDBQT)
Step 1: Preparing receptor receptor_staged.pdb
  Receptor PDBQT written (125648 bytes)
Step 2: Box center=(173.607,208.847,174.042) size=(20.27508093773169,20.27508093773169,20.27508093773169)
        Exhaustiveness=8, CPUs=4, poses=9
```

- **`parameters.json`:** same **`smiles_list`** as ADMET; receptor **`9P3I.pdb`** on S3.

### Issues / gaps

- **Same ligand chain-of-custody gap** as ADMET: inputs are **not** pharmacophore-filtered hits from this run’s `filtered_compounds.smi`.
- **Graphviz** warning again in `status.json` `log_tail`.
- **`invocation_id` ≠ `run_id`:** tracking/metadata only unless your orchestration keys on `invocation_id`.
- **`qc_report`:** `null`, **`qc_gates`:** `[]` in `status.json` — no automated docking QC gate in this artifact bundle.

---

## Logs and HTML

- **No standalone `*.log` files** in the four step directories; executor messages live in each **`status.json`** (`log_tail`).
- **`report.html`:** large Nextflow reports; grep shows **0 failed tasks** in sampled ADMET HTML; UI strings include “0 tasks failed”. **Graphviz** warnings are confirmed from **`status.json`**, not from a separate log file.

---

## Follow-up actions (**blocking** only)

1. **If the scientific claim is “ADMET and Vina operated on pharmacophore-filtered ANDV hits”:** this run **does not support that claim** — **blocking** until orchestration passes **`02_pharmacophore/filtered_compounds.smi`** (or equivalent channel file) into steps 3–4 **or** the manifest explicitly records an intentional fixed `smiles_list` demo path.

2. **If `toxicity_report.json` is consumed by reporting or gates:** reconcile **top-level `toxicity` vs `per_compound` DILI** for aspirin — **blocking** for automated risk labeling until the schema/aggregation rule is fixed or documented.

---

## Evidence cross-reference (ligand sets)

| Source | SMILES / IDs |
|--------|----------------|
| `02_pharmacophore/filtered_compounds.smi` | Aspirin (`CPND0001`), phenol (`CPND0002`), `CC(=O)Nc1ccc(O)cc1` (`CPND0006`) |
| `03_admet/parameters.json` & `04_docking_vina/parameters.json` | **`CCO`**, **`CC(=O)O`**, **`CC(=O)Oc1ccccc1C(=O)O`** only |

Only the third structure overlaps between the pharmacophore pass list and the ADMET/docking list; **ethanol and acetic acid were not pharmacophore-filtered outputs in this artifact tree.**

---

## Addendum (2026-05-12) — chain-of-custody **fixed** and re-executed

`run_andv_inhibitor_pipeline_nextflow.py` now builds steps **3–4** `smiles_list` from **`02_pharmacophore/filtered_compounds.smi`** (first column per line) when that step is present in the manifest.

**Verification run:** `research/anti-virus/runs/andv_nf_pipeline_20260512T185322Z/` — `03_admet/parameters.json` contains:

`["CC(=O)Oc1ccccc1C(=O)O", "Oc1ccccc1", "CC(=O)Nc1ccc(O)cc1"]`

matching the pharmacophore file. Docking results include all three ligands with non-degenerate affinities.

Follow-up **#1** above is **resolved** for future runs. **#2** (toxicity aggregation) remains a separate workflow/schema concern.
