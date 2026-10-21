# C4 — Dynamical/conformational features break the static permeability ceiling (partial)

**Date:** 2026-10-21 · Challenge C4 (cyclic-peptide permeability). Driven per docs/20261021_PROGRAM_CHALLENGE_MAP.md.

## Question
Static ECFP permeability plateaus at scaffold-R² ≈ 0.23 (`permeability_predictor_metrics.json`). The wall is
diagnosed as *dynamical* ("molecular chameleon": a peptide shields polar surface in membrane vs water).
Do conformational/3D features beat the static ceiling on the same leak-free split?

## Assets (audit — reused, not re-simulated)
- **CycPeptMPDB** (local `data/raw/CycPeptMPDB_Peptide_All.csv`, 8,466 cyclic peptides, log Papp) — carries
  **`CHCl3_3DPSA` + `H2O_3DPSA`**: 3D polar surface area computed in a membrane-mimetic vs aqueous
  environment. Their difference IS the chameleon descriptor (PSA shielding). Collected but unused by the
  static baseline.
- **MacroConf** (`macroconf_acquisition.json`, bigginlab/Macroconf, 331 files NMR+MD) — conformational
  ensembles for ~hundreds of macrocycles; does NOT overlap the 8,466 permeability set, so not directly
  joinable as features here (reserved for the full-MD extension).

## Result — same leak-free Bemis-Murcko generic-scaffold folds (5), 1,441 scaffolds, HistGBM
| Feature set | scaffold R² | MAE | Spearman |
|---|---|---|---|
| **ECFP4 (static baseline)** | 0.237 | 0.641 | 0.498 |
| chameleon-3D alone (computed PSA, no EPSA) | 0.037 | 0.732 | 0.336 |
| **ECFP + chameleon-3D** | **0.301** | **0.585** | **0.624** |
| chameleon-3D + EPSA (experimental) | 0.047 | 0.728 | 0.346 |

(ECFP reproduces the documented 0.231 ceiling → methodology validated.)

## Verdict — YES, partially: conformational signal is real and additive, but not yet SOTA
- 3D/chameleon features **alone are weak** (R² 0.037) — they don't predict permeability by themselves.
- But **added to ECFP they meaningfully beat the static ceiling**: scaffold **R² 0.237 → 0.301 (+0.064, ~27% rel)**
  and **Spearman 0.498 → 0.624 (+0.126)** on the SAME leak-free scaffold split. The conformational PSA-shielding
  (chameleon) signal is **orthogonal** to 2D structure and lifts ranking especially.
- **Honest ceiling check:** still well below published multimodal refs (CPMP 0.67, CycPeptMP 0.77). This cheap
  two-environment-3D-PSA proxy *validates the dynamical direction* — it does NOT reach SOTA. Full MD
  (MacroConf/OpenMM ensembles → explicit shielding dynamics) is the next lever to push toward 0.67+, now
  justified by this positive signal.

## Files
- `research/guangzhou_all_atom/c4_dynamical_permeability.py`
- `research/guangzhou_all_atom/results/c4_dynamical_permeability.json`
