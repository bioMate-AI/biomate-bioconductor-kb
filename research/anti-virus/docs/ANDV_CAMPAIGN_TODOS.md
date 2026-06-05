# ANDV publication campaign — tracked todos

**Run:** `publication_20260528T223525Z`  
**Last updated:** 2026-06-05  
**Scope:** compute-only (BioMate workflow demo)

---

## Priority lanes (active this session)

| Lane | Task | Status | Owner script / artifact |
|------|------|--------|-------------------------|
| **Inhibitor** | Z600-R1 GROMACS pose QC → promote or keep INH-01 | **Done** | RMSD **0.26 nm** PASS; **keep INH-01** as primary lead |
| **Plan A** | IEDB population cross-check vs **48.81%** Chile tier A+B | **Done** (local) | `PLAN_A_IEDB_CROSSCHECK.md` — web upload pending |
| **Plan A** | FigA4 MultiQC (full GP, not 90-aa smoke) | **Done** | `FigA4_multiqc_summary.png` (45,160-row run) |
| **Plan A** | Git: commit Chile panel + science tiers + coverage | **Done** | this commit |
| **Publication** | Manuscripts: **600** dock + **48.81%** Chile | **Done** | `MANUSCRIPT_ANDV_INHIBITOR_v1_2.md`, `MANUSCRIPT_PLAN_A_VACCINE_v1_1.md` |
| **Inhibitor** | Refresh `compute_package` + science QC | **Done** | 600 docked; INH-01 lead; Z600-R1 backup |
| **Inhibitor** | Ensemble ZINC600 top-5 live | **Running** | `science_sprint/runs/20260605T025716Z/track_inh_ensemble/` |
| **Inhibitor** | ZINC purchasability top-5 | **Done** | `zinc600_library.tsv` + multi-backend lookup |
| **Plan A** | FigA4 + FigA8 regen | **Done** | `manuscript_figures_v1/plan_a/` |

---

## Completed (recent)

- [x] ZINC600 Vina **600/600** merged
- [x] ZINC600 top-20 ADMET triage
- [x] ZINC600 top-20 SA-score synthesizability
- [x] Session Q&A doc (`SESSION_20260603_INHIBITOR_ZINC600_QA.md`)
- [x] Chile 17-allele strict dual coverage **48.81%** tier A+B
- [x] Git push: inhibitor ZINC600 triage (`a683c3830`)

---

## Inhibitor — backlog

| Task | Priority | Notes |
|------|----------|-------|
| Z600-R1 pose QC complete | **Done** | PASS 0.26 nm; INH-01 remains primary lead |
| Ensemble dock ZINC600 top-5 | **Done** | `20260605T025716Z` + `reconcile_ensemble_docking.py` |
| Pharmacophore-filter AAAC → dock | **Done** | `zinc600_pharmacophore/vina/` — **91/91** docked |
| Publication ZINC deck build (multi-tranche) | **Done** | `publication_zinc/` — **5,006** dock set |
| Publication ZINC Vina (5k) | **Running** | `run_publication_zinc_docking.py` — log `/tmp/publication_zinc_dock.log` |
| ZINC purchasability IDs (top 5) | **Done** | `zinc600_library.tsv` + multi-backend lookup |
| SynCraft / retrosynthesis | P2 | Workflow stub today |
| REINVENT4 from INH-01 seed | P3 | Last run: 0 retained |
| MM-GBSA recalibration | P3 | Aspirin control fails — do not rank by MM-GBSA |
| Expand library beyond 600 | P2 | Pharmacophore deck started (`zinc600_pharmacophore/`) |

---

## Plan A — backlog

| Task | Priority | Notes |
|------|----------|-------|
| IEDB web upload cross-check | **P0** | Manual: [IEDB Population Coverage](https://tools.iedb.org/population/) + `PLAN_A_CHILE_POP_COVERAGE_INPUT.tsv` |
| FigA4 full-GP MultiQC | **Done** | `FigA4_multiqc_summary.png` |
| Commit Chile + tiers to git | **Done** | pushed in `2d7af53a8` |
| NetChop/TAP processing proxy | P2 | Optional science gate |
| FigA4 + FigA8 regen in manuscript | **Done** | Full-GP MultiQC + Chile 17-allele curve |
| NetMHC / MixMHC (policy: no NetMHCpan) | — | Out of policy |

---

## Plan B — backlog

| Task | Priority | Notes |
|------|----------|-------|
| LNP / construct variants | P2 | Supplement only — not deployable vaccine |
| Keep supplement-only framing | P0 | Per `ANDV_SCIENCE_COMPLETION_GATES.md` |

---

## Publication / repo

| Task | Priority | Notes |
|------|----------|-------|
| Inhibitor manuscript → **600** compounds | **Done** | v1.2 |
| Plan A manuscript → **48.81%** Chile 17-allele | **Done** | v1.1 |
| `COMPUTE_PARALLEL_STATUS.md` sync | **Done** | 2026-06-04 |
| PR to `main` | P2 | When science gates satisfied |

---

## Regenerate commands

```bash
PUB=research/anti-virus/runs/publication_20260528T223525Z

# Inhibitor
python3 research/anti-virus/scripts/poll_zinc600_rank1_pose_qc.py
python3 research/anti-virus/scripts/poll_merge_zinc600_docking.py

# Plan A
python3 research/anti-virus/scripts/crosscheck_plan_a_chile_iedb.py --publication-run "$PUB"
python3 research/anti-virus/scripts/generate_manuscript_plan_a_figures.py \
  --multiqc-dir "$PUB/plan_a_epitope/multiqc_full_gp/multiqc_data"

# QC package
python3 research/anti-virus/scripts/build_inhibitor_science_qc.py
```
