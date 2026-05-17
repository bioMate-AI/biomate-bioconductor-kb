# Preprint manuscript — ANDV small-molecule inhibitor track (in silico draft)

> **Superseded for publication-style prose:** use **`MANUSCRIPT_ANDV_INHIBITOR_v1_0.md`** (manuscript v1.0). This file remains as a checklist-heavy working draft.

**Target venue:** bioRxiv (Computational biology / Medicinal chemistry informatics).  
**Framing:** Reproducible **structure-to-triage** ladder: pocket detection, pharmacophore filtering, **in silico** ADMET, **AutoDock Vina** docking, optional MD/MM-GBSA, optional **REINVENT4** generative follow-up — executed via **BioMate** + **Nextflow** on **AWS Batch**.  
**Companion:** `ANDV_INHIBITOR_INSILICO_PREPRINT_STACK.md`, `20260509_ANDV_NEXTFLOW_PIPELINE_EXECUTION.md`, `scripts/run_andv_inhibitor_pipeline_nextflow.py`, `runs/andv_nf_pipeline_20260512T181054Z/AUDIT.md`, `runs/andv_nf_pipeline_20260513T032000Z/pipeline_manifest.json`.

**Status:** Draft **v0.2** — full resource narrative; **§9** = **computational extension programme only** (no wet lab). Wet-laboratory validation is explicitly **out of scope** for this revision.

---

## Title (working)

**Cloud-resident Nextflow workflows for Andes virus glycoprotein pocket analysis, pharmacophore triage, ADMET screening, and docking: a reproducible in silico inhibitor campaign**

**Short title:** ANDV GP inhibitor informatics via BioMate

---

## Authors and affiliations

| Author | ORCID | Affiliation | Email |
|--------|-------|-------------|-------|
| [Name] | [0000-…] | [Dept, Institution] | [ ] |

**Corresponding author:** [ ]

---

## Keywords

Andes virus; hantavirus; molecular docking; pharmacophore; ADMET; AutoDock Vina; GROMACS; MM-GBSA; REINVENT4; Nextflow; AWS Batch

---

## Abstract (draft)

Andes virus (ANDV) surface glycoproteins are attractive targets for **small-molecule** intervention. We describe a **computational resource**: a **manifested** multi-step **Nextflow** pipeline executed through **BioMate**, covering **pocket detection and druggability**, **pharmacophore-based library filtering**, **ADMET** profiling, **AutoDock Vina** docking, optional **molecular dynamics** with **MM-GBSA-class** estimates, and **REINVENT4** generative elaboration when resources allow. We publish **per-step parameters**, **run identifiers**, **HTML reports**, and **machine-readable JSON** for audit. We disclose **chain-of-custody** limitations for **`andv_nf_pipeline_20260512T181054Z`** (`AUDIT.md`) where **ADMET and docking did not consume the pharmacophore-filtered SMILES list**, and we present **`andv_nf_pipeline_20260513T032000Z`** as the **chained** reference (`pipeline_manifest.json`) where **filtered_compounds.smi** feeds downstream steps. **Step 5 (GROMACS)** did **not** complete successfully for the chained run on the full tetramer; **step 6 (REINVENT4)** **succeeded** under `06_reinvent4/` with `run_id` **`d7c8e6e8-7faf-49cc-8191-65579153480b`**. We do **not** report **measured antiviral potency** or **clinical outcomes**. **§9** lists **computational-only extensions** (pose reproducibility, orthogonal scoring, public bioactivity crosswalks, optional RBFE/PBPK **demos** on disclosed synthetic inputs) — **wet lab is out of scope** for this manuscript revision.

---

## 1. Introduction

### 1.1 Scientific background

ANDV entry and membrane biology motivate targeting the **viral glycoprotein** ectodomain. Structure-guided campaigns benefit from consistent **pocket definitions** and **docking boxes** [PDB citations].

### 1.2 Informatics gap

Modular tools exist, but **auditable cloud execution** with **frozen handoffs** between ligand sets is less commonly published. **Nextflow/nf-core** patterns and **S3-resolved** inputs reduce ad hoc drift.

### 1.3 Contribution type

This manuscript is a **workflow integration and execution study**. It is **not** a drug discovery claim for a specific clinical candidate. **All “validation” in scope** is **computational** (§9); **wet-laboratory** potency is **not** part of this revision.

### 1.3a Frozen reference execution (for Tables)

| Step | Key | API `run_id` (chained manifest) | Artifact dir |
|------|-----|----------------------------------|--------------|
| 1 | pocket | `550c7001-4e47-44ff-bf04-53e323a9452c` | `…/01_pocket` |
| 2 | pharmacophore | `22982db3-de8e-4241-89d4-f1e24f26a414` | `…/02_pharmacophore` |
| 3 | admet | `da163d67-9796-4338-8837-ec6fa75860c4` | `…/03_admet` |
| 4 | docking_vina | `cb1b4fdd-8f30-4564-8e67-020721ad223a` | `…/04_docking_vina` |
| 6 | reinvent4 | `d7c8e6e8-7faf-49cc-8191-65579153480b` | `…/06_reinvent4` |

**Step 5 (GROMACS):** not present as **succeeded** in this manifest; describe **failure / timeout / not attempted** honestly in §3.5 and Discussion. Paths above are under `research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z/`.

## 2. Methods

### 2.1 Structures and ligand libraries

- **Primary chained manifest:** `research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z/pipeline_manifest.json` — receptor **`s3://biomate-nextflow-work/inputs/andv_campaign/20260507/9P3I.pdb`**; reference actives and library under `…/pipeline_demo_20260509/*.smi` (exact URIs in manifest `parameters.json` per step).  
- **Audit / disclosure run:** `research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/AUDIT.md` — use **only** for the **ADMET/docking ligand-feed** caveat in Methods + Discussion; do **not** mix numerical tables across runs without relabeling.

### 2.1a Ranking and pose-selection rule (authors must pre-register)

State **before** extracting docking numbers: (i) how many poses per ligand; (ii) whether poses are **clustered** by RMSD; (iii) whether **best affinity** or **best pose energy after visual inspection** defines “top hit.” This prevents post hoc tuning in Results.

### 2.2 Pipeline steps (reference: `run_andv_inhibitor_pipeline_nextflow.py`)

| Step | Workflow (short) | Role |
|------|------------------|------|
| 01 | Pocket detection + druggability | Pockets JSON, druggability TSV, QC, optional `structure_top_pocket.pdb`. |
| 02 | Pharmacophore filtering | Filtered SMILES, match report, pharmacophore model JSON. |
| 03 | Predict ADMET | MPNN-class path in default runner; JSON + toxicity outputs. |
| 04 | AutoDock Vina | Box from pocket center when `--use-top-pocket-box`; poses as PDBQT/JSON. |
| 05 | GROMACS MD + MM-GBSA (optional) | Ligand on S3 or SMILES per workflow contract; **resource-intensive**; may fail on oversized receptors — disclose. |
| 06 | REINVENT4 (optional) | Seed SMILES; generative **hypotheses**; requires downstream re-scoring. |

### 2.3 Orchestration and compute

BioMate **Nextflow execute** + status polling; **AWS Batch**; **S3** `outdir` / workdir. Document **retries** on long polls (5xx) per `ANDV_CAMPAIGN_LESSONS_LEARNED.md`.

### 2.4 Critical disclosure — demonstration vs chained runs

- **`andv_nf_pipeline_20260512T181054Z`:** reproduce **verbatim** from `AUDIT.md` that **`smiles_list` for ADMET and docking did not enumerate the pharmacophore-filtered set**.  
- **`andv_nf_pipeline_20260513T032000Z`:** confirm from `03_admet/parameters.json` and `04_docking_vina/parameters.json` that **`smiles_list`** is derived from **`02_pharmacophore/filtered_compounds.smi`** (chained). Cite this manifest for **all** main-text inhibitor tables unless explicitly comparing to the audit run.

### 2.5 Computational validation ladder (in-manuscript)

Follow **`ANDV_INHIBITOR_INSILICO_PREPRINT_STACK.md` §2**. No model output substitutes for **measured** antiviral IC50/EC50.

---

## 3. Results

### 3.1 Pocket and druggability (step 01)

Using manifest **`andv_nf_pipeline_20260513T032000Z`**, extract from **`01_pocket/structure_pockets.json`** and **`structure_druggability_report.tsv`**: **top pocket** identifier, **volume (Å³)**, **druggability** score, and **`structure_qc_result.json`** tier. The manifest records **`top_pocket_center`** coordinates for docking — reproduce in **Figure F1** with the receptor surface. If **`structure_top_pocket.pdb`** is only a **marker** geometry (minimal atoms), say so; do not imply a trimmed MD receptor unless you explicitly built one.

### 3.2 Pharmacophore screen (step 02)

From **`02_pharmacophore/match_report.tsv`** and **`summary.json`**: **library coverage**, **hits passing** feature thresholds, and **representative** matched scaffolds. Confirm **`filtered_compounds.smi`** line count matches downstream `smiles_list` provenance for the **chained** run.

### 3.3 ADMET (step 03)

From **`03_admet/predict_admet_properties_results.json`** (and **`pk_summary.json`**, **`toxicity_report.json`**): build **Table T2** (per-compound key endpoints). **If** aggregate toxicity blocks disagree with per-compound rows (known issue class in `AUDIT.md` for the **audit** run), **exclude inconsistent aggregates** everywhere and cite **per-row** tables only. **Do not** mix ADMET numbers from **`181054Z`** with docking from **`032000Z`**.

### 3.4 Docking (step 04)

From **`04_docking_vina/docking_autodock_vina_results.json`** and **`pose_*.pdbqt`**: report **Vina scores** for each retained pose, **box definition** provenance (pocket center from step 01), and **Figure F3** (poses). Apply the **pre-registered** pose-selection rule from §2.1a.

### 3.5 MD (step 05) and REINVENT4 (step 06)

- **GROMACS / MM-GBSA:** For **`032000Z`**, step **05** is **not** listed as **succeeded** in `pipeline_manifest.json`. Summarize **attempt history** (timeout vs failed build vs not submitted) from any `05_gromacs_mmgbsa/` logs if present, and explain **system-size / receptor trimming** lessons (`ANDV_CAMPAIGN_LESSONS_LEARNED.md`). **Do not** imply MM-GBSA ranks without a completed trajectory.  
- **REINVENT4:** Step **06** **succeeded** (`run_id` **`d7c8e6e8-7faf-49cc-8191-65579153480b`**). Summarize **`06_reinvent4/design_summary.json`**, **`score_history.json`**, **`filter_stats.json`**, and **`top_compounds.csv`**; cite **`report.html`** / **`timeline.html`**. State **RL steps** and **scoring mode** from `parameters.json`. If **filter pass count is zero**, report **zero** without reframing as hidden hits.

---

## 4. Discussion

### 4.1 Chain of custody and end-to-end validity

Unchained ligand feeds validate **modules**, not **pipelines**. Use a schematic with **solid** vs **dashed** edges (see combined campaign Fig 2 in `MANUSCRIPT_DRAFT_ANDV_CAMPAIGN.md`).

### 4.2 Comparison to prior integrated platforms

Galaxy public servers, workflow managers, commercial ELNs — position BioMate as **institutional** reproducibility + Batch scale.

### 4.3 Limitations

Rigid-receptor docking, scoring-function error, ADMET domain shift, **absent completed MD** for the reference chained run, **absent** measured **antiviral** potency, and **absent** biophysical binding validation. Generative outputs require **re-docking and ADMET** before any prioritization narrative.

### 4.4 Conclusions

We provide a **manifested** inhibitor-oriented **Nextflow** ladder with **chained** pharmacophore → ADMET → Vina execution on **`andv_nf_pipeline_20260513T032000Z`**, plus **REINVENT4** hypotheses under **`06_reinvent4/`**. We transparently separate an **audit** run with **broken ligand handoff** (`181054Z`) from this **reference** execution. **Computational extensions** (§9) define how to strengthen claims **without wet lab**. Therapeutic language remains **out of scope** until Tier B/C assays exist (not planned here).

---

Manifests under `research/anti-virus/runs/andv_nf_pipeline_*`; audit under `runs/andv_nf_pipeline_20260512T181054Z/AUDIT.md`. Zenodo recommended.

---

## 6. Ethics, CRediT, competing interests

**Ethics:** Not applicable (computational).

---

## 7. Tables, figures, and supplementary layout

| ID | Description |
|----|-------------|
| **Table T1** | Run registry (may duplicate §1.3a for PDF): step key, `run_id`, status, artifact dir. |
| **Table T2** | ADMET per-compound panel (from `03_admet/`). |
| **Figure F1** | Pocket + docking box on GP surface. |
| **Figure F2** | ADMET heatmap (reconciled rows only). |
| **Figure F3** | Docking poses + affinity bar chart. |
| **Figure F4** | MD/MM-GBSA (**only** if step 05 succeeds in a future manifest). |
| **Figure F5** | REINVENT score trajectory (`score_history.json` → plot). |

| Supplement | Contents |
|------------|----------|
| **S1** | Full `pipeline_manifest.json` + per-step `parameters.json` / `submit.json` (redacted). |
| **S2** | Collated `versions.yml` per step. |
| **S3** | Long docking + ADMET tables. |
| **S4** | REINVENT4 outputs (`raw_molecules.csv`, `top_compounds.csv`, `validated_input.json`). |
| **S5** | Computational extension outputs (§9): pose RMSD matrices, ChEMBL crosswalk, optional RBFE inputs/outputs. |

---

## 8. References (seed)

1. AutoDock Vina.  
2. GROMACS / MM-PBSA or workflow-specific MM-GBSA citation as implemented.  
3. REINVENT4 / related generative de novo literature.  
4. ADMET model papers matching deployed containers.  
5. ANDV structures / reviews.

---

## 9. Extension programme — **computational validation only** (no wet lab)

**Scope:** All packages below are **in silico** or **public-database** work. They strengthen **reproducibility**, **uncertainty quantification**, and **external plausibility** — they **do not** measure antiviral potency.

### 9.1 Package P1 — Pose ensemble and reproducibility

| Field | Detail |
|-------|--------|
| **Goal** | Show docking ranks are not single-seed artifacts. |
| **Actions** | Re-run Vina (or GNINA if available) on top-*N* ligands with **±1 Å** box jitter and **alternate exhaustiveness**; cluster poses by heavy-atom RMSD. |
| **Artifacts** | Supplement **S5** panel: ligand × condition rank matrix. |
| **Acceptance** | Spearman rank correlation ≥ pre-set threshold **or** explicit Discussion of **instability** cases. |

### 9.2 Package P2 — Orthogonal rescoring

| Field | Detail |
|-------|--------|
| **Goal** | Reduce single-score-function bias. |
| **Actions** | If **`docking_gnina`** or workflow registry path is enabled, rescore **same poses**; else run **second Vina** protocol (different random seed / exhaustiveness). |
| **Artifacts** | Scatter plot: score₁ vs score₂ per ligand. |
| **Acceptance** | Outliers discussed as **model disagreement**, not as biological validation. |

### 9.3 Package P3 — Public bioactivity crosswalk (ChEMBL / PubChem)

| Field | Detail |
|-------|--------|
| **Goal** | Contextualize scaffolds against **known** medicinal-chemistry space (not ANDV-specific). |
| **Actions** | InchiKey / Murcko scaffold match vs ChEMBL; annotate **max documented potency** and **target class** for **unrelated** proteins. |
| **Artifacts** | Supplement table + explicit disclaimer: **no cross-target potency transfer**. |

### 9.4 Package P4 — Strain and interaction sanity (RDKit)

| Field | Detail |
|-------|--------|
| **Goal** | Flag chemically unreasonable docked geometries. |
| **Actions** | Torsion strain heuristics, clash counts, simple interaction fingerprints on **`pose_*.pdbqt`** converted to mol. |
| **Artifacts** | Flag column in Table T2 extension. |

### 9.5 Package P5 — Generative follow-through

| Field | Detail |
|-------|--------|
| **Goal** | Treat REINVENT outputs as **candidates**, not leads. |
| **Actions** | Take **top_k** from `06_reinvent4/raw_molecules.csv` / `top_compounds.csv`; **re-run ADMET + Vina** (new manifest or manual API). |
| **Acceptance** | Any “improved” claim requires **both** better docking **and** acceptable ADMET vs parent. |

### 9.6 Package P6 — MD on trimmed receptor (optional compute)

| Field | Detail |
|-------|--------|
| **Goal** | Obtain **completed** MM-GBSA-class readout where full tetramer failed. |
| **Actions** | Pocket-only or domain-trimmed PDB on S3; drastically reduced `--gromacs-n-steps`; document `CONTINUE_INHIBITOR.md` pattern. |
| **Acceptance** | Trajectory + MM-GBSA table **or** honest **aborted** log in supplement. |

### 9.7 Package P7 — Alchemical / PBPK **demos** (synthetic inputs only)

| Field | Detail |
|-------|--------|
| **Goal** | Illustrate optional workflows (`openfe_rbfe`, `pbpk_simulation`, `nca_pknca`) per **`ANDV_INHIBITOR_INSILICO_PREPRINT_STACK.md`**. |
| **Actions** | Run with **disclosed synthetic** ligand pairs / PK parameters; **never** label outputs as ANDV-measured. |
| **Acceptance** | Separate **“workflow demo”** subsection, not Results for ANDV. |

### 9.8 Language guardrails (still mandatory)

- Use **“prioritized virtual hit”** not **“lead”**.  
- **IC50 / EC50** numerals only from **cited experimental deposits** or **illustrative** synthetic curves (`ANDV_INHIBITOR_INSILICO_PREPRINT_STACK.md` §2).

### 9.9 Wet-laboratory validation (explicitly **not** in this revision)

Plaque assays, SPR, PK in animals, and clinical measures remain **future directions** for a **different** manuscript revision; **do not** reserve main-text Results tables for them here. One sentence in **Discussion** may cite them as **non-goals** for this resource paper.

---

## Internal versioning

| Version | Notes |
|---------|--------|
| v0.1 | Skeleton + early wet-lab tier sketch (superseded). |
| v0.2 | Full Results/Discussion; frozen manifest IDs; §9 = P1–P9 computational-only extensions + supplement layout; wet lab deferred to §9.9 one-liner. |
| v0.3 | Numeric tables from JSON; optional MD completion or trimmed GROMACS appendix. |
