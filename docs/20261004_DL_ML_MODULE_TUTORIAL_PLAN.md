# BioMate DL/ML + statistical-modeling module — tutorial plan

**Date:** 2026-10-04
**Why:** BioMate trains/runs ML/DL/statistical MODELS, not only fixed pipelines (memory
`project_dl_ml_module`). Needs a background-first tutorial track (per `project_edu_tutorial_series`:
task → SOTA → classical baseline → how BioMate does it → interpret; EN+CN via the
`project_educational_video_pipeline`: auto-play HTML → edge-tts → record → mux). Two example tracks the
founder specified: **drug-development models** and **statistical models**. Honesty: predictions are
estimates; experimental validation required (each workflow's `do_not_use_when`).

## Track 1 — Drug-development models (classical ML → DL → generative/RL → physics)
| Ep | Topic | BioMate workflow(s) | Model class |
|---|---|---|---|
| D1 | **QSAR** activity/tox from structure | `Qsar Rf Model`, `herg_cardiac_safety_qsar` | classical ML (random forest) |
| D2 | **ADMET deep learning** (ties to the QC-gate hero) | `predict_admet_properties` (ADMET-AI Chemprop/MPNN graph NN) | deep learning |
| D3 | **Generative lead design** | `REINVENT4 Generative Lead Design` | reinforcement learning (de-novo) |
| D4 | **Binding free energy** | `openfe_rbfe` | physics-based (FEP) |

## Track 2 — Statistical models (PK → population dosing → adaptive trial → survival)
| Ep | Topic | BioMate workflow(s) | Model class |
|---|---|---|---|
| S1 | **Non-compartmental PK** | `Nca Pknca`, `Dose Response` | statistical PK |
| S2 | **PBPK simulation** | `pbpk_simulation`, `simcyp_pbpk`, `pbpk_pediatric/pregnancy` | mechanistic ODE |
| S3 | **Adaptive dose-escalation** | BOIN | Bayesian decision |
| S4 | **Survival analysis** | `survival_analysis_km`, `rlassocox` (Cox) | survival statistics |

## Track 3 — Build-your-own (advanced)
| Ep | Topic | How |
|---|---|---|
| B1 | **Train a custom model on your data** | `run_code` (sklearn/XGBoost/PyTorch) — classification/regression on user CSV |
| B2 | **On-prem domain LLM (enterprise)** | SFT/CPT/DPO stack (`evaluation/local_trial/*`) — advanced; ties to the on-prem cost/compliance hero |

## Per-episode structure (each)
1. The scientific task (plain language). 2. SOTA + why it's hard. 3. Classical baseline. 4. BioMate:
chat → route to the model workflow → run on managed compute → **QC/interpret** (for D2, the hERG QC gate
fires — reuse the live hero). 5. Read the outputs/plots; honest caveats (estimates, validation needed).
Each produced EN+CN. Ground model context with the external DBs (ChEMBL/PubChem for D1–D4).
