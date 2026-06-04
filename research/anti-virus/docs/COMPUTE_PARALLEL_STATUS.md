# ANDV compute parallel sprint — status

Last updated: 2026-06-03 (UTC — ZINC600 merge + synthesizability triage)

**Scope:** in silico only (BioMate workflow demo). No wet-lab framing.

---

## Completed

| Track | Artifact | Result |
| --- | --- | --- |
| Plan A | `PLAN_A_CHILE_PANEL_mhcnuggets.tsv` / `mhcflurry.tsv` | 95,965 rows; **17 alleles** |
| Plan A | `PLAN_A_CHILE_CONSENSUS_BINDERS.tsv` | **247** dual-tool pairs |
| Plan A | `PLAN_A_CHILE_POPULATION_COVERAGE.md` | Tier A+B Chile **48.81%** (strict dual, 17 alleles) |
| Plan A | `FigA8_chile17_population_coverage_curve.png` | 17-allele panel figure |
| Inhibitor | Ensemble top-15 | **COMPLETE** |
| Inhibitor | **ZINC600 Vina screen** | **600/600** → `zinc150_screen/vina/docking_autodock_vina_results.json` |
| Inhibitor | `ZINC600_TOP20_ADMET_TRIAGE.md` | **20/20** top hits with ADMET-AI |
| Inhibitor | `ZINC600_TOP20_SYNTHESIZABILITY.md` | **20/20** SA ≤ 5 (RDKit SA score) |
| Inhibitor | Rank-1 pose QC (Z600-R1) | **IN FLIGHT** — GROMACS `b89f1662` |
| Package | `compute_package/COMPUTE_CANDIDATES.md` | Refreshed with 600-dock ranking + Chile coverage line |
| QC | `inhibitor_science_qc/INHIBITOR_SCIENCE_QC.md` | ZINC600 complete; MM-GBSA still **FAIL** (aspirin control) |

### Chile coverage (tier A+B surface)

| Method | Pairs | Tier A+B coverage |
| --- | ---: | ---: |
| 8-allele dual (original) | 47 | 36.13% |
| 17-allele hybrid (sensitivity only) | 61 | 65.25% |
| **17-allele strict dual-tool** | **247** | **48.81%** |

### ZINC600 top-5 (full screen, 9P3I)

| Rank | Vina (kcal/mol) | Notes |
| ---: | ---: | --- |
| 1 | **−6.527** | New global best vs ZINC150 subset |
| 2 | −6.275 | |
| 3 | −6.267 | Prior INH-01 SMILES (guanidine-pyrimidine) |
| 4 | −6.099 | |
| 5 | −6.065 | |

**Compute lead (Vina + pose QC):** still the validated **INH-01** chemotype (`N=C(N)NC(=O)c1nccnc1N`, −6.267 kcal/mol) with ligand RMSD ~0.20 nm; rank-1 full-screen hit is a related guanidine scaffold (−6.527) — needs pose QC before promoting.

---

## In flight

| Job | Status |
| --- | --- |
| Z600-R1 GROMACS MD | `run_id=b89f1662` — poll with `poll_zinc600_rank1_pose_qc.py` |

---

## Optional follow-ups

| Item | Action |
| --- | --- |
| IEDB cross-check | Upload `plan_a_epitope/PLAN_A_CHILE_POP_COVERAGE_INPUT.tsv` → compare to **48.81%** |
| ADMET on ZINC600 top 20 | **DONE** — `poll_zinc600_top20_admet.py` |
| SA score on ZINC600 top 20 | **DONE** — `triage_zinc600_synthesizability.py` |
| FigA4 MultiQC (full GP) | Not done |
| Plan B LNP variants | Spec only |

---

## Regenerate artifacts

```bash
PUB=research/anti-virus/runs/publication_20260528T223525Z

python3 research/anti-virus/scripts/poll_merge_zinc600_docking.py

python3 research/anti-virus/scripts/assemble_wet_lab_candidates.py \
  --publication-run "$PUB" \
  --conservation-json "$PUB/cross_species_conservation_full_gp.json" \
  --docking-json "$PUB/zinc150_screen/vina/docking_autodock_vina_results.json"

python3 research/anti-virus/scripts/build_inhibitor_science_qc.py
python3 research/anti-virus/scripts/triage_zinc150_admet_top20.py --publication-run "$PUB"
python3 research/anti-virus/scripts/triage_zinc600_synthesizability.py --publication-run "$PUB"
```
