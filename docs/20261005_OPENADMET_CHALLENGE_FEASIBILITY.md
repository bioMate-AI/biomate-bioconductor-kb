# OpenADMET CYP-Inhibition Blind Challenge — honest feasibility survey

**Date:** 2026-10-05
**Author:** Yaoyun Zhang (xiaoni5122@gmail.com)
**Type:** Capability-gap + go/no-go analysis. **NOT an entry plan.**
**Premise (founder, correct):** BioMate's current commodity ADMET workflow will **not** win this
challenge. This document tests whether a *competitive* entry is achievable by the 2026-11-03 deadline,
what it would take, and whether it is worth the opportunity cost against the committed Q4 work
(the October preprint sprint + the first on-prem pilot).

**Honesty contract:** every challenge rule and SOTA claim is cited with an access date; nowhere do I
assume BioMate can win; I keep a hard line between what BioMate **has** (a stock pretrained ADMET-AI
model) and what winning **requires** (a challenge-data-trained multitask ensemble). The QC auto-loop is
governance, not a predictor, and contributes **zero** to raw accuracy — stated explicitly below.

---

## 1. Challenge requirements (pinned)

All facts below accessed **2026-10-05**.

| Item | Value | Source |
|---|---|---|
| Organizer | OpenADMET (data from **Octant** + **UCSF Fraser lab**) | [1][2] |
| Launch | 2026-08-17 | [1][2] |
| Intermediate leaderboard | 2026-09-24 | [1][2] |
| **Final submissions close** | **2026-11-03** (≈ 4 weeks from today) | [1][2] |
| Isoforms | **CYP3A4, CYP2C9, CYP2D6, CYP1A2** ("core drivers of small-molecule metabolism") | [1][2] |
| Test set | **750 compounds**, blinded, all four isoforms | [1][2] |
| Training data | ~**4,905** labeled compounds; ~**1,500 dose-response curves (DRCs) per isoform**; libraries = **Enamine DDS10** diversity set + **FDA-approved** drugs | [1] |
| **Track 1 — Direct Inhibition (regression)** | Predict **pIC50** per isoform over the 750 test compounds. *"Low-activity compounds are downweighted in the evaluation function."* | [1][2] |
| **Track 2 — Time-Dependent Inhibition (classification)** | Classify whether a compound shows TDI (mechanism-based, >**2-fold** IC50 shift). Evaluated **only for CYP3A4 + CYP2D6**. | [1][2] |

### Scoring metrics (the part that decides everything)

- **Direct track — MA-ST-RAE** (Macro-Averaged **Soft-Threshold Relative Absolute Error**). Error is the
  distance between the prediction and the **credible-interval bound of the fitted dose-response curve**;
  a prediction landing **anywhere inside the DRC credible interval incurs zero error**. Macro-averaged
  across the four isoforms. **Lower is better; a naive mean-prediction baseline scores exactly 1.0 by
  construction.** Secondary (reported with bootstrap CIs): MAE, R², Spearman ρ, Kendall τ. [1][3]
- **TDI track — Matthews Correlation Coefficient (MCC)**, chosen for the imbalanced, threshold-based
  label. [1]
- Rules: **one submission per team/lab**; **mandatory disclosure of proprietary-data use**; separate
  **"most innovative ML approach" award** decoupled from leaderboard rank. [1]

### Is there already a competitive leaderboard? **Yes — and the bar is public.**

There is both a live board (half the test set) and an interim board (full held-out set). A *serious*
published entry — a stacked ensemble (`lachrymator/openadmet-cyp-challenge-public`) — reports, on the
**interim** board (accessed 2026-10-05): [4]

| Track | Rank | Macro metrics |
|---|---|---|
| Direct (regression) | **28 / 219** (their "Tier 6") | MAE **0.688**, R² **0.595**, Spearman ρ **0.747** |
| TDI (classification) | **6 / 114** (top tier) | MCC **0.380**, Acc 0.840, F1 0.484 |

**Read this carefully.** This is a *strong, methodologically sophisticated* entry and it still sits at
rank 28 on regression — meaning the field is deep (**219 regression / 114 TDI submissions**) and ~27
teams are already **ahead** of a full masked-multitask-pretraining + GNN + tabular-FM stacked ensemble.
Macro R² ≈ 0.6 / MAE ≈ 0.7 log-units is roughly where the *good* entries cluster; this is a hard,
well-attended competition, not an empty field. Independent academic/hobby entries are plentiful (Reading
BSc dissertation, several individual GitHub repos [5]), so a mid-pack result carries little marketing
signal.

---

## 2. SOTA for CYP-inhibition prediction — what winning actually takes

What the literature and the strong challenge entries converge on (all accessed 2026-10-05):

1. **Multitask graph neural networks.** Multitask FP-GNN / graph-convolutional / graph-transformer
   models (GTransCYPs, unified attention GCNN) are the reported SOTA for CYP inhibition across the five
   major isoforms; multitask sharing across isoforms is a measurable win, especially under limited
   per-isoform data. [6][7][8]
2. **Chemprop-class MPNNs trained at scale.** The gTPP Chemprop model was trained on **up to 40,000
   compounds per isoform** to cover CYP1A2/2C8/2C9/2C19/2D6/3A4. End-to-end learned representations
   (Chemprop v2) beat fingerprints on mechanism-driven endpoints. [6][9]
3. **Descriptor + gradient-boosting ensembles.** The current TDC SOTA for CYP2D6/3A4 is
   **CatBoost + MapLight + GIN** — i.e. a *hybrid of boosted descriptors and a graph net*, not a single
   model. [9]
4. **Stacking + transfer + augmentation + proper CV** — exactly the recipe of the strong challenge
   entry [4]: masked **multitask pretraining on public bioactivity** → fine-tune; **multiple backbones**
   (SMILES transformer, MPNN, 3D-conformer, tabular foundation model over frozen embeddings, fingerprint
   baseline, additive-fragment); **NNLS/ridge/elastic-net stacking** per endpoint; **Butina
   cluster-disjoint folds** so analog series don't leak across train/test; and **near-neighbor data
   augmentation** (~89k catalog neighbors of the test structures, physchem-filtered). [4]
5. **Uncertainty / calibration matters *for this metric specifically*.** Because MA-ST-RAE gives zero
   error for any prediction inside the DRC credible interval, calibrating predictions toward the
   plausible band (and not over-confidently missing it) is directly rewarded — conformal / ensemble
   uncertainty is a scoring lever, not a nicety. [1][3]

**Bottom line of §2:** a top-quartile entry is a *bespoke, competition-specific cheminformatics ML
pipeline* — multitask GNN **plus** a boosted-descriptor model, pretrained/transfer-warmed, stacked, with
leakage-safe scaffold CV and uncertainty calibration. There is no "run the stock tool" path to the top.

---

## 3. BioMate's current capability — honest read

### 3a. What the ADMET workflow actually is (verified in the repo)

`predict_admet_properties` → `biomni.tool.pharmacology.predict_admet_properties` →
`admet_ai.ADMETModel()` (verified:
`backend/tools/biomni_generated/pharmacology_predict_admet_properties/wrapper.py`,
`backend/biomni_workflows/nextflow/subworkflows/pharmacology/predict_admet_properties.nf`,
`backend/docker/biomni-admet/smoke.py`). This is the **stock, frozen ADMET-AI model** — a Chemprop MPNN
pretrained on the **TDC** ADMET benchmark. [10][11]

Two fatal mismatches for the Direct track:

- **Wrong output type.** ADMET-AI's CYP endpoints (CYP2C9/2D6/3A4) are **binary inhibitor/non-inhibitor
  classification probabilities** from TDC — *not* continuous pIC50. The challenge Direct track grades
  **pIC50 regression against DRC credible intervals**. The stock model does not emit the quantity being
  scored, and it has no CYP1A2 regression head at all. [9][11]
- **Wrong assay / wrong data.** ADMET-AI is trained on heterogeneous public TDC data, **not** the
  Octant/Fraser assay that defines this challenge's labels. Even its classification probabilities are
  off-distribution for this specific assay. It has **never seen the challenge training data.**

So the commodity path is not merely "unlikely to win" — for the Direct track it **cannot produce a valid
competitive submission** without being replaced by a trained-on-challenge-data model. This is the
clearest possible confirmation of the founder's premise.

### 3b. What BioMate *does* have that is trainable (the honest upside)

- **`qsar_rf_model`** (`backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/qsar_rf_model/main.nf`):
  a Random-Forest QSAR workflow that **trains on a user CSV** (`smiles`, target column defaulting to
  **`pIC50`**), 5-fold CV, emits `cv_r2_score`/`cv_rmse`, with a Golbraikh-Tropsha R²<0.5 quality gate.
  This is a real trainable path and *does* take the challenge data format — but it is a **vanilla,
  single-task, single-model RF**: no multitask isoform sharing, no GNN, no pretraining, no stacking, no
  scaffold-disjoint CV, no uncertainty. It is a one-day baseline, structurally a generation behind §2.
- **`run_code` sandbox** (`backend/lib/galaxy/ai/compute/`): a USER-trust compute tier that can run
  arbitrary sklearn / XGBoost / PyTorch / Chemprop on managed (AWS Batch) compute. This is the *vehicle*
  through which a competitive pipeline *could* be built — but the pipeline itself does not exist today;
  it would be hand-authored code, not a BioMate product capability.
- **`herg_cardiac_safety_qsar`**, **REINVENT4**, **openfe_rbfe** — adjacent drug-dev workflows, none of
  which address CYP pIC50 regression.

### 3c. Does the QC auto-loop help? **No — be explicit.**

The hero case study (`docs/20261004_HERO_A_CASE_STUDY.md`, `docs/20261004_AUTOLOOP_LIVE_PROOF.md`) shows
the QC auto-loop halting on `hERG IC50 < 1.0 µM` with a cited threshold and recommending a developability
remediation. That is a **governance / threshold gate over an already-produced prediction** — it decides
*pass/halt/remediate*, it does **not** improve the underlying number. On a blind prediction benchmark it
contributes **exactly zero** to MA-ST-RAE or MCC. It is a genuine differentiator for *trustworthy
screening workflows* (no surveyed competitor demonstrates chat-driven QC-gate + remediation over an
executed pipeline), but it is **irrelevant to the raw-accuracy contest this challenge scores.** Marketing
must not conflate the two.

---

## 4. Gap analysis — what a genuinely competitive entry would require

To reach even the ~R²0.6 / MAE0.7 band of the *strong* entry [4] (which is itself only rank 28), BioMate
would need to build, from scratch, a competition-specific pipeline:

1. **Train on the provided CYP data, multitask across the four isoforms.** Replace stock ADMET-AI
   entirely. Minimum viable competitive core = a **multitask MPNN (Chemprop-class) + a boosted-descriptor
   model (CatBoost/XGBoost over RDKit/Mordred + Morgan)**, the two combined — mirroring the TDC SOTA
   recipe. [6][9]
2. **Transfer / pretraining.** Masked multitask pretraining (or at least warm-start) on public CYP
   bioactivity (ChEMBL/PubChem) before fine-tuning on the 4,905 challenge compounds — the challenge set
   is small per isoform, and transfer is where the strong entries get their lift. [4][6]
3. **Leakage-safe CV + stacking + uncertainty.** Butina/scaffold cluster-disjoint folds (not random CV,
   which over-reports on analog series); a per-endpoint NNLS/ridge stacker; and **calibration toward the
   DRC credible interval** to exploit the soft-threshold metric. [3][4]
4. *(Optional, cheaper, more winnable)* **TDI track** — a focused MCC-optimized classifier for CYP3A4 +
   CYP2D6 only; the strong entry hit **6/114** here, so the TDI field is shallower and the per-task
   surface smaller.

**Effort / compute estimate.** This is a focused, Kaggle-style ML sprint, not a platform feature:
- ~**2–4 weeks of one experienced cheminformatics-ML engineer**, full-time, for a credible top-half
  Direct entry; more to seriously chase the top. The deadline is ~4 weeks out, so this is the *entire*
  budget with zero slack for the data/feature iteration loop that actually separates ranks.
- GPU for GNN training (hours–days on a single modern GPU; BioMate already runs spot GPU Batch).
- The hard part is **not** compute — it is the human iteration loop (feature engineering, CV design,
  ensemble tuning, calibration) that the 27 teams ahead of the strong entry are also grinding.

**Risk.** High. Even executed well, the realistic landing zone with a from-scratch 4-week build is
**mid-pack**, because the leading teams have had since August and the strong published baseline is
*already* only 28/219. A rushed single-task RF (the only thing BioMate ships today) lands **lower**.

---

## 5. Verdict — NO-GO on winning / marketing; conditional PARTIAL as an internal capability build

**Can BioMate be competitive enough to win, or place respectably enough to market, by 2026-11-03 with
what it has? No.**

- **Winning: NO.** BioMate ships a stock pretrained ADMET-AI (binary, off-assay, no pIC50 head for the
  Direct track) and a vanilla single-task RF. Neither is within a generation of the §2 SOTA recipe, and
  the leaderboard shows even a sophisticated stacked ensemble only reaches rank 28/219. There is no path
  from current assets to a winning score in four weeks.
- **A stock-ADMET-AI entry would be actively harmful.** It would produce invalid/low Direct-track output
  and advertise a commodity capability — precisely the "un-backable claim" the marketing discipline
  forbids. A no-go beats this.
- **Partial, *conditional* path (the only defensible "yes"):** treat the **Direct track as an internal
  capability-building exercise**, run through BioMate's own `qsar_rf_model` → `run_code` training path,
  with **no public/marketing claim unless a top-quartile score actually materializes** (it very likely
  won't in the time). The value, if any, is **product**, not placement: it would force the "train a
  multitask ensemble on your own data" pipeline that BioMate's DL/ML module
  (`docs/20261004_DL_ML_MODULE_TUTORIAL_PLAN.md`, Track-3 "build-your-own") currently only *gestures* at.
  That is a real gap worth closing — but on its own timeline, not against this deadline.

**Worth it vs Q4 priorities? No — defer.** The committed Q4 work is the **October preprint sprint — all
preprints online this month** (`docs/20261005_PREPRINT_SPRINT_OCTOBER_2026.md`) **+ the first on-prem
pilot** (`docs/20261005_QUARTERLY_PLAN_AND_3YR_ROADMAP.md`). A competitive challenge entry draws on the
*same scarce cheminformatics-ML engineering hours* as the preprint figures and the pilot, during the
exact four weeks those are due. Spending that budget chasing a realistically mid-pack result in a crowded
public challenge — with downside marketing risk and no credible upside claim — is a poor trade.

### Recommendation (concrete)

1. **Do not enter to win, and do not submit a commodity ADMET-AI entry.** (NO-GO on the headline.)
2. **Optionally log the TDI track only** as a cheap internal probe *after* the preprint sprint, if an
   engineer has slack — it is the shallower field (6/114 reachable), MCC-only, two isoforms. Still **no
   marketing claim** unless the score is genuinely respectable.
3. **Convert the lesson into the roadmap:** the real deliverable is the **multitask-ensemble
   train-on-your-data pipeline** the challenge exposes as missing. Schedule it as a DL/ML-module
   capability (Q1-2027 candidate), *not* as a race against 2026-11-03.

**The three/four things needed to be competitive** (restated for the record): (1) multitask GNN **+**
boosted-descriptor ensemble trained on the challenge data, replacing stock ADMET-AI; (2) public-bioactivity
transfer/pretraining + near-neighbor augmentation; (3) scaffold-disjoint CV with per-endpoint stacking;
(4) credible-interval-aware uncertainty calibration to exploit the ST-RAE metric. BioMate has **none** of
these as shipping capability today; it has the *compute vehicle* (`run_code`/Batch) and a baseline RF.
Four weeks is not enough to build all four and iterate to a markable rank. **Honest answer: we cannot win
it in the time with what we have — so don't pretend otherwise, and don't spend the Q4 budget trying.**

---

## Sources (accessed 2026-10-05)

1. OpenADMET, "Announcing OpenADMET's CYP inhibition blind challenge" —
   https://openadmet.ghost.io/announcing-openadmets-cyp-inhibition-blind-challenge/
2. OpenADMET, "Blind Challenges" — https://openadmet.org/blindchallenges/
3. Scoring-metric detail (MA-ST-RAE; naive-mean = 1.0; DRC credible-interval zero-error band),
   corroborated across challenge repos, incl. `doctawho42/CYPChallenge` — https://github.com/doctawho42/CYPChallenge
4. `lachrymator/openadmet-cyp-challenge-public` — stacked-ensemble method + interim-board scores
   (Direct 28/219: MAE 0.688, R² 0.595, ρ 0.747; TDI 6/114: MCC 0.380) —
   https://github.com/lachrymator/openadmet-cyp-challenge-public
5. Field depth / independent entries: `OpenADMET/CYP-Challenge-Tutorial`
   (https://github.com/OpenADMET/CYP-Challenge-Tutorial); `codie-freeman/OpenADMET-CYP-Blind-Challenge`
   (Reading BSc dissertation, Direct-only); `avnikonenko/openadmet_challenge_cyp_2026`;
   `adlvdl/cyp_competition`; `Rebell-Leader/OpenADMET_CYP`
6. Gong et al. (2024), "Evaluation of ML models for CYP3A4/2D6/2C9 inhibition," *J Appl Toxicol* —
   https://analyticalsciencejournals.onlinelibrary.wiley.com/doi/10.1002/jat.4601 ; multitask FP-GNN
   and graph-based SOTA review, *BioMed Eng OnLine* (2025) —
   https://link.springer.com/article/10.1186/s12938-025-01412-6
7. GTransCYPs graph-transformer for CYP inhibitors —
   https://pmc.ncbi.nlm.nih.gov/articles/PMC11524008/
8. Unified GCNN + attention for CYP450 inhibitors, *Comput Biol Med* —
   https://www.sciencedirect.com/science/article/abs/pii/S001048252200885X
9. TDC ADME CYP tasks + leaderboard SOTA (CatBoost+MapLight+GIN for 2D6/3A4; Chemprop v2) —
   https://tdcommons.ai/single_pred_tasks/adme/
10. ADMET-AI — top average on TDC ADMET leaderboard (22 regression + 31 classification), Chemprop MPNN;
    predicts CYP substrates/inhibitors — https://www.drugdiscoverynews.com/ai-powered-admet-prediction-how-machine-learning-is-changing-drug-candidate-selection-17356
11. BioMate repo (verified source): `backend/tools/biomni_generated/pharmacology_predict_admet_properties/wrapper.py`;
    `backend/biomni_workflows/nextflow/subworkflows/pharmacology/predict_admet_properties.nf`;
    `backend/docker/biomni-admet/smoke.py` (`admet_ai.ADMETModel()`);
    `backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/qsar_rf_model/main.nf`;
    `backend/lib/galaxy/ai/compute/run_spec.py`; `docs/20261004_HERO_A_CASE_STUDY.md`;
    `docs/20261004_DL_ML_MODULE_TUTORIAL_PLAN.md`

## Correction (2026-10-05, founder-flagged): BioMate's training capability is broader than stated above
The claim that BioMate "ships none of these as capability" was **too strong**. The catalog has **68
ML-training workflows**, including train-on-your-own-data paths: `Qsar Rf Model` + `herg_cardiac_safety_qsar`
(trainable QSAR RF), `mlinterfaces_multi_classifier_evaluation` (multi-classifier/ensemble evaluation),
`classifyr` + `classifyr_multi_view_integration` + `classifyr_parameter_tuning` +
`classifyr_advanced_modelling_and_evaluation` (multi-view modeling + tuning), `bambu_custom_model_training_
and_application` / `scclassify_train_custom_model` / `cellity_svm` (custom-model training), and **`run_code`**
(arbitrary sklearn / XGBoost / PyTorch on user data).

**Refined gap + unchanged verdict:** the limiter is NOT missing capability — it is (a) no *turnkey one-click*
**multitask (joint 4-isoform) pIC50-regression stacked-ensemble + scaffold-CV + uncertainty** workflow (you'd
assemble it from the pieces above + `run_code`), and (b) the stock `predict_admet_properties` is a frozen
*classification* model (wrong endpoint for the Direct pIC50 track). So the real OpenADMET constraint is the
**engineering time to assemble + tune** a top-tier ensemble within 4 weeks against the Q4 preprint sprint +
first pilot — not a capability absence. **NO-GO stands** (time/opportunity-cost), with this corrected reason.
The Q1 roadmap item is therefore **"productize a turnkey multitask/ensemble QSAR workflow from the existing
pieces,"** not "build a capability we lack."
