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

## C4-forward: explicit conformer-ENSEMBLE dynamics (2026-10-21)

**Goal:** push past the single-point 3D-PSA proxy (R²=0.301) toward multimodal SOTA (CPMP 0.67 / CycPeptMP 0.77) with EXPLICIT conformer-ensemble chameleon-dynamics (Rg distribution, intramolecular-H-bond dynamics, shape spread), reusing collected data before simulating.

**Audit:** CycPeptMPDB (8,466) carries only SINGLE-POINT CHCl3/H2O_3DPSA (the 0.301 proxy's inputs); no explicit conformer ensembles in-repo; MacroConf (331 NMR+MD) does not overlap the permeability set (confirmed). So ensembles must be generated.

**Honest obstacle — explicit ensembles are CPU-compute-bound:**
- RDKit ETKDGv3 on these 117–167-atom macrocycles: naïve params gave 1 conformer / ~13 s/mol; fixed with `useRandomCoords=True`+multithread, no `pruneRmsThresh` (pruning collapsed macrocycles to 1 conf) → 20 confs/mol at **~9 s/mol including ensemble-feature extraction**.
- Full 8,466 ≈ **~21 h CPU** — exceeds a compute window.
- Small subsets are UNDERPOWERED: at n=250, even the ECFP baseline gives leak-free scaffold-CV **R²=−0.247** (vs 0.237 at full 8,466) — the subset is non-representative, so any ensemble-vs-proxy comparison at n≈250 is meaningless.
- (Also fixed en route: broken-anaconda-py3.9 scipy ABI → pinned python3.14; HistGBM binning crash on constant feature columns → drop-degenerate-columns guard.)

**Status:** built a CACHED + RESUMABLE ensemble featurizer (`c4_ensemble_permeability.py`, cache `results/c4_ensemble_cache.jsonl`) that accumulates across windows and runs the leak-free CV once ≥600 mols are cached. A trustworthy explicit-ensemble verdict requires either (a) this multi-hour (~21 h) chunked CPU accumulation to a representative n, or (b) the GPU full-membrane-MD lever (explicit shielding dynamics — the proper route to 0.67).

**C4 bottom line (unchanged + bounded):** the *dynamical direction is validated* (static proxy +0.064 R² → 0.301, full 8,466). Reaching SOTA (0.67) is NOT achievable within a CPU window via explicit ETKDG ensembles — it is compute-bound, and the honest next lever is GPU membrane MD (or the long chunked accumulation). The static-proxy 0.301 stands as the deployable C4 result today.
