# Drug-Development Tutorials — Information-Flow Handoff for Claude Design

**Date:** 2026-10-23
**For:** Claude Design — tutorial generation on the **data-centroid v2** UI.
**What this is:** the input→output information flow for each of the 9 drug-development
use cases, mapped onto the real v2 surfaces, so each tutorial can be generated
without guessing at intent. Format follows the Research-Agent handoff
(`reference/claude_design/research_agents/HANDOFF_RESEARCH_AGENT_UI.md` +
`Demo Narratives.md`); the **UI target is `data_centroid_design_v2`**, NOT the
research-agent prototype.

**Read §1–§2 first.** They define the shared v2 frame every use case instantiates;
the per-use-case sections (§3) only state what differs.

Grounding: every parameter, output and number below is read from the committed
narrations/decks (`tutorials_v2_design/narration/*`, `tutorials/*-narration.md`) and
the v2 spec (`data_centroid_design_v2/spec/*`). Where a use case is a **stub**, a
**source contradiction**, or deliberately carries **no result numbers**, it is
flagged — do not invent figures or imply validation that isn't there.

---

## 1. The shared v2 surface model (apply on every step)

- **Two lanes, always labelled:** **Instant** (seconds, in the conversation, no run
  object) vs **Cloud** (minutes–hours, produces a run object with gates + an
  audit-ready report). BioMate picks the lane and states it back as a **lane chip**;
  the switch is adjacent but lane-switching is Advanced, not every-user. All drug-dev
  use cases are **Cloud**.
- **Domain chip + run-card-by-domain (Spec 13):** the panel is a *function of the
  routed domain/modality* — it must never open a generic RNA-seq panel. Mapping:
  - hERG/ADMET ask → **ADMET liability screen · Workflow v2.4** (Drug discovery)
  - de novo / scaffold-hop / multi-objective → **Design run · design pipeline v3.1**
  - "train a model on my data" → **Model training run · harness v2.0**
  - docking / FEP / stability / novelty → **validated pipeline card** (Drug discovery)
- **Workflow panel = 3 section tabs (Spec 07):** **Workflow settings** · **Phases** ·
  **After run** (disabled until completion, then a dot when the report is ready).
  Run states: Ready / Running / **Halted** (gate card takes over top of Phases) /
  Awaiting approval / Cancelled / Completed / Blocked.
- **After run = 3 tabs only (Spec 07/12, SIMPLIFICATION_DECISIONS):**
  **Summary** (report + findings, every number links to its output) · **Outputs**
  (each artifact by producing step, evidence-badged) · **Reproducibility record**
  (Methods, resolved Parameters, Software, Citations, QC audit, Trajectory as
  *expandable sections* — not competing top-level tabs). Do **not** render the old
  7-tab after-run.
- **Full step view (Spec 08):** click a step's **Full view** (or a number in a
  report) → provenance row → one output tab per artifact with a **rendered/raw**
  toggle → resolved-parameters table (origin badges) → prev/next/lineage/re-run.
- **Param provenance badges (Spec 07):** every param row carries `default /
  inherited / recommended / confirmed / edited`, each with a `why` expansion.
- **Quality gate card (Spec 07):** `measured rows / evidence level / suggested
  before→after diff / three actions (apply · keep my parameters · cancel)`. Override
  needs Reviewer/Owner and is recorded in QC audit. Gates **halt**, never silently
  pass.
- **Molecular viewers (Spec 03 §3.8, 05 §5.5, 14):**
  - **Structure** = 3D fold + **per-residue pLDDT bar chart linked to the 3D view** +
    pairwise-error heatmap; a structure without its confidence chart is half a viewer.
  - **Screening / candidates** = ranked hit **table OR 2D depiction grid** (toggle).
  - **Docking** = pose shown *with* its score; pose plausibility gated separately.
  - **Multi-objective** = per-objective bars keeping their own units/targets;
    **never a blended/composite score**; **safety is a hard gate, not a tradeable
    objective**; rejected candidates stay visible with the gate reason.
  - **Censored values** kept as inequalities (`IC50 > 30 µM`, never coerced to 30).
- **Vocabulary:** output types are only **Table / Figure / Structure / Report / Log**.
  Chat uses **reference/attach** (`@file.csv`), reserve "citation" for literature.
  **Never a bare predicted number** — model name + version + confidence travel with it.
- **Honesty constraints:** distinguish **validated model / project-adapted model /
  heuristic**; a heuristic must never look like a decision gate. Do **not** present
  report ask-to-edit / versioning as already deployed (persistence contract undecided).

---

## 2. The canonical information-flow skeleton

Every drug-dev tutorial is an instance of this spine (keep the "normal path small"):

```
Cold start (Spec 00): "What are you trying to do?" → type the goal
  → Router restates it as  [lane chip: Cloud] + [domain chip] + Start   (seeds the composer; never auto-runs)
  → Routed RUN CARD opens (Spec 13)  — the right panel / full-width workflow panel
  → WORKFLOW SETTINGS tab: clarification → global params (provenance badges) → inputs (slots: resolved/unresolved/blocked) → phases-to-run → permissions
  → Confirm and run
  → PHASES tab (live): phases auto-open; steps show status/tool+version/2 headline params/output chips; a GATE halts at the top of Phases if evidence says so
  → Completion → AFTER RUN opens:
        Summary  (findings; every number → its output)
        Outputs  (each file by step; opens in its class viewer)
        Reproducibility record (Methods / Parameters / Software / Citations / QC audit / Trajectory)
  → FULL STEP VIEW (Spec 08) for deep audit on any step or any number
  → Report (Spec 12): immutable original + reproducibility bundle (.zip)
```

Tutorial pacing: ~5–8 s per callout, calm presenter voice (same as
`Demo Narratives.md`). Each tutorial = one scenario walked on these surfaces.

---

## 3. The 9 use cases

Each section gives: **lane/domain/run-card**, **input**, **settings**, **phases/gates**,
**outputs & viewers**, **findings**, **reproducibility**, **hero beat**, **honesty
flag**, and a **suggested scene sequence** for the tutorial.

### D1 — QSAR, classical ML
- **Lane/card:** Cloud · Drug discovery / Pharmacology · validated-workflow card. Two
  workflows: `Qsar Rf Model` (activity) and `herg_cardiac_safety_qsar` (toxicity).
- **Input:** activity → CSV with `smiles` + target col (`pIC50`), ≥10 compounds;
  toxicity → SMILES list + optional measured hERG IC50, dose (mg), plasma free fraction.
- **Settings:** 5 CV folds, 200 trees, Morgan fp r2/1024 (`morgan_fp_r2_1024`), fixed
  seed, ≥10 compounds. hERG: physicochemical model (MW, logP, pKa, cationic density) +
  Nav1.5 alerts.
- **Phases/gates:** featurize → train RF w/ 5-fold CV → report CV metrics + feature
  importance. Gate: **CV R² < 0.5 → SILVER (blocking)**; **n < 50 → BRONZE (advisory)**.
  hERG → safety margin → ICH E14 risk tier + Nav1.5 alerts.
- **Outputs/viewers:** `qsar_results.json` (`cv_r2_score`, `cv_rmse`, `n_compounds`,
  `featurizer`) + `qsar_model_report.txt` (Report); `herg_risk.json` + `nav15_alerts.csv`
  (Table). Feature importance = Figure.
- **Findings:** taught conceptually — **no single-run numbers**; thresholds are the
  content (R²<0.5 blocks; <50 bronze; hERG IC50 ~1 log-unit uncertainty by design).
- **Reproducibility:** Methods = RF on Morgan fp + k-fold CV, hERG proxy; Citation =
  Golbraikh & Tropsha 2002. Honesty beat: if RDKit missing, RF falls back to mock
  features — the `featurizer` field must read `morgan_fp_r2_1024`.
- **Hero beat:** a QSAR is a **filter, not a verdict** — validate before you trust; the
  gate blocks a weak model rather than passing it silently.
- **Honesty flag:** live workflows; no fabricated figures.
- **Scenes:** goal → settings (CV/trees/fp, ≥10 gate) → run → CV metrics + feature
  importance → SILVER/BRONZE gate explained → hERG risk tier + Nav1.5 alerts → "filter
  not verdict."

### D2 — ADMET, deep learning *(the canonical, fully-numbered example)*
- **Lane/card:** Cloud · Drug discovery · **ADMET liability screen · Workflow v2.4**.
  Workflow `Predict ADMET Properties (AI)` — ADMET-AI / Chemprop D-MPNN (frozen).
- **Input:** `smiles_list` ("screen these for ADMET + cardiac safety"). Hero run:
  aspirin + terfenadine; safe re-run: aspirin/caffeine/ibuprofen.
- **Settings:** `smiles_list`; `ADMET_model_type = MPNN`; shard size. No blanket
  accuracy number. Missing required → block + "Fix now."
- **Phases/gates:** ADMET-inference shard → predict-and-merge → worst-case aggregation
  → **GOLD hERG gate: worst-case `herg_ic50_uM = 0.012 < 1.0` → HALT**; **DILI high →
  GOLD halt**. Remediation (advisory, before→after diff): `logp_max 5.0→≤4.0`,
  `mw_max_da 500→400`. Safe re-run completes with `qc_gates: []`.
- **Outputs/viewers:** `toxicity_report.json`, `qc_metrics.json` (hERG IC50 µM, 10 µM
  margin, Ames call, DILI risk+prob vs threshold), `pk_summary.json`, main results,
  `versions.yml`. 15 endpoints (hERG, DILI, BBB, Caco-2, CYP panel, solubility, PPBR,
  half-life, LD50, oral bioavailability, clinical tox…). Per-compound = Table.
- **Findings (REAL, run id `d0ff684b`):** aspirin logP 1.31 / MW 180.2 / hERG 10000 µM
  → **safe**; terfenadine logP 7.01 / MW 499.7 / hERG **0.012 µM → HALT**. Benchmark:
  AUROC > 0.85 on 20/31 TDC tasks; trained on 2M+ measurements (ChEMBL + TDC).
- **Reproducibility:** Methods = Chemprop D-MPNN, frozen published model. Citations:
  ADMET-AI (Swanson 2024), Sanguinetti & Tristani-Firouzi 2006, FDA E14, DILIrank/Chen
  2016. Record (one JSON): run id, params, model+software versions, outputs + SHA-256,
  citations; empty fields shown. Honesty: native hERG output is a **blocker-risk
  probability**; IC50 is derived (power law anchored to terfenadine); low-risk sits at
  the ceiling (~10 mM).
- **Hero beat:** the GOLD hERG gate halts terfenadine at 0.012 µM < 1 µM with a cited
  threshold — "a naive pipeline would have shipped this silently" — and stays silent on
  safe chemistry.
- **Honesty flag:** fully live; the reference case for depth/numbers.
- **Scenes:** goal → settings strip (MPNN, shard) → run → stream with the **gate HALT
  on DILI/hERG** → remediation diff → After-run Summary (per-compound table) → Outputs
  (qc_metrics.json previewed) → Reproducibility (checksums + citations) → safe re-run
  proves the gate discriminates.

### D3 — Generative lead design (REINVENT4)
- **Lane/card:** Cloud · **Design run · design pipeline v3.1** (de novo candidate
  design). Workflow `REINVENT4 Generative Lead Design`.
- **Input:** seed scaffold SMILES + "what good means." `Synthesizability` pre-filled
  `CC(=O)Oc1ccccc1C(=O)O` (aspirin), overridable. Design mode: de novo / scaffold
  decoration / linker / scaffold hopping.
- **Settings:** scoring = `qed_sa` (default) / `docking_gnina` (needs `receptor.pdb`) /
  `custom_toml`. RL loop: `n_steps` **500** (~15 min GPU; 200 quick), `batch_size`
  **128**, `sigma` **120**, `learning_rate` **0.0001**, temperature.
- **Phases/gates:** validate seed (QED/SA/MW) → REINVENT4 generator → **FILTER_RANK**
  (QED ≥ 0.4, SA ≤ 5.0, MW ≤ 500, PAINS removed, Tanimoto novelty vs seed, diverse
  top-N by Murcko scaffold) → write outputs. Chemistry validity gate reports the
  rejection profile ("N of M passed; k failed SA; j hit an alert"). Fails **loudly** if
  model/prior missing — never silent enumeration.
- **Outputs/viewers:** `generated_molecules.csv` (SMILES+score, QED, SA, MW — Table),
  `top_compounds.sdf` (top-N 3D via ETKDG — Structure), HTML report (**2D depiction
  grid** + score breakdown + settings — Report/Figure), score-vs-epoch plot (Figure),
  JSON config.
- **Findings:** **no fabricated scores**; `qed_sa` from descriptors, `docking_gnina` is
  an in-silico pose not measured affinity.
- **Reproducibility:** Methods = RL generator + reward-driven policy + med-chem filters.
  Citation: REINVENT4 (Loeffler 2024, J. Cheminform. 16:20; Apache-2.0). A `brics`
  enumeration baseline is offered as a labelled **non-RL comparator**, never a training
  curve.
- **Hero beat:** RL optimizes **exactly the reward you give it** — the ranking is only
  as good as the scoring function; candidates are a hypothesis queue, the lab decides.
- **Honesty flag:** live; rank surface must show rejected candidates with reason, no
  blended score.
- **Scenes:** goal + seed → constraints (mode, scoring, n_steps/batch) → run → validity
  gate rejection profile → Rank candidates (**2D grid toggle**, per-objective values,
  `why?` into the model) → outputs (SDF structure viewer) → "reward is the lever."

### D4 — Binding free energy (FEP / RBFE)
- **Lane/card:** Cloud · Drug discovery · validated-workflow card. Workflow
  `openfe_rbfe` (OpenFE + OpenMM 8, MIT), one phase, GPU queue, 90-day output retention.
- **Input:** 3 required — Receptor (PDB + bound pose) + Ligand A (reference SDF) +
  Ligand B (query analog SDF); a congeneric pair. A series = pairwise network edges.
- **Settings:** 3 required + 9 optional (collapsed). Defaults: 298.15 K, 1 ns equil,
  **5 ns production/λ**, **11 λ windows**, **3 repeats** (SEM), LOMAP max3d 1.0 Å,
  ETKDG conformers.
- **Phases/gates:** PREP (standardize + 3D conformers; protein prep) → RBFE_SETUP
  (LOMAP atom-mapping + ligand network + alchemical task graph — **no ΔΔG yet**) →
  OPENFE_ANALYSIS (OpenMM MD across λ windows → MBAR per-edge ΔΔG ± SEM). Gate = **cycle
  closure**: around a ≥3-edge loop ΔΔG should sum to ~0; deviation (~1 kcal/mol) flags
  weak edges. `validate` mode compares an edge to a published ΔΔG (Tyk2/CDK2).
- **Outputs/viewers:** `ddg_summary.json` — per-edge ΔΔG (kcal/mol) ± SEM + network/
  mapping quality (Table). Negative ΔΔG → ligand B binds stronger.
- **Findings:** **no invented ΔΔG** by design; accuracy framed as a general expectation
  (well-converged RBFE ~1 kcal/mol of experiment, system-dependent, "checked not
  assumed").
- **Reproducibility:** Methods = alchemical λ transformation, thermodynamic cycle, MBAR,
  cycle-closure convergence. Software: OpenFE + OpenMM 8; OpenFE benchmark pairs.
- **Hero beat:** FEP computes the **ΔΔG difference between close analogs with its
  uncertainty attached** — a tight converged edge is distinguishable from a noisy one.
- **Honesty flag:** live; show ΔΔG **with SEM**, never a bare value.
- **Scenes:** congeneric pair in → settings (λ windows, repeats, collapsed optionals) →
  run (PREP → SETUP → ANALYSIS) → ddg_summary table with ΔΔG ± SEM → cycle-closure
  check → "make the winners, not the series."

### D5 — Molecular docking (AutoDock Vina)
- **Lane/card:** Cloud · Drug discovery · validated-workflow card. Workflow
  `Docking Autodock Vina` (Vina on managed compute).
- **Input:** `smiles_list` + `receptor_pdb_file` + pocket (`box_center` + `box_size`).
  Optional `reference_ligand_smiles` → validation mode.
- **Settings:** `exhaustiveness` 8, `n_poses` 9. Blind variants: `Run Autosite`
  (`pdb_file`, `spacing` 1.0) detects cavities; `Run Diffdock With Smiles` (`pdb_path`,
  `smiles_string`, `use_gpu`) — diffusion, no box. Site-directed Vina is default.
- **Phases/gates:** PREP (SMILES→3D; receptor+box grid) → SEARCH (Vina stochastic
  optimizer, exhaustiveness controls thoroughness) → SCORE & RANK (Vina affinity
  kcal/mol, n_poses, most-negative first). **No pass/halt gate**; quality = validation
  mode **pose RMSD ≤ 2.0 Å** to the crystal pose.
- **Outputs/viewers:** ranked poses per ligand (score kcal/mol + 3D coords) — **Structure
  viewer (pose shown with its score)**; RMSD added in validation mode. (Deck names no
  distinct JSON files.)
- **Findings:** **no invented affinities**.
- **Reproducibility:** Methods = Vina empirical scoring, grid pose search, RMSD
  validation. Software: AutoDock Vina (+ AutoSite / DiffDock). Limits: a gate not a
  ruler (escalate fine ranking to D4 FEP), rigid receptor by default (no induced fit),
  a score is a pose hypothesis.
- **Hero beat:** **the pose travels with the score** — never a bare number; recovering
  the crystal pose within 2.0 Å is what makes new-ligand scores credible.
- **Honesty flag:** live; pose plausibility gated separately from score.
- **Scenes:** ligand + receptor + box → settings (exhaustiveness/n_poses) → run (PREP →
  SEARCH → SCORE) → ranked poses in the structure viewer → validation-mode RMSD → "pose
  + score, not a bare number."

### D6 — Chemical novelty & freedom-to-operate  ⚠️ STUB
- **Lane/card:** Cloud · Drug discovery · validated-workflow card. Workflow
  `Compound Novelty Scorer`. **Flag: narration calls it a "workflow stub" — present as
  aspirational / not a verified live run; do not imply a real run.**
- **Input:** `query_smiles` (shortlist) + `fpsim2_db` (mounted FPSim2 `.h5` library,
  e.g. ChEMBL/BindingDB). Both required.
- **Settings:** `novelty_tanimoto_cutoff` **0.85**; `check_patents` **false**.
- **Phases/gates:** FINGERPRINT (Morgan/ECFP4) → NEAREST NEIGHBOUR (FPSim2 Tanimoto →
  max + closest neighbour) → PATENT SCREEN (if on; SureChEMBL/PubChem; peptides use
  Needleman–Wunsch). The **novelty call IS the gate** at the pre-CRO chokepoint: max
  Tanimoto < 0.85 → NOVEL; ≥ 0.85 → occupied (auto-dropped; borderline → human patent
  attorney). Fails **open** (unreachable source → reports the gap, never a false "clear").
- **Outputs/viewers:** per candidate — max Tanimoto + nearest known neighbour + novel/
  occupied verdict (+ patent flag if on). Neighbour travels with the verdict (Table).
- **Findings:** **no invented figures**.
- **Reproducibility:** Methods = ECFP4/Morgan + Tanimoto (FPSim2); patents via
  SureChEMBL/PubChem; Needleman–Wunsch for peptides. Honesty: a **structural** screen,
  NOT a legal FTO determination; fingerprint blind spots (scaffold-hops, bioisosteres);
  fail-open means no hit ≠ proof of novelty.
- **Hero beat:** **Novel ≠ clear** — structural novelty and legal clearance are distinct;
  the screen narrows cheaply, a patent attorney makes the FTO call.
- **Honesty flag:** **STUB** — the tutorial should teach the concept/flow but not claim
  a live run; mark the method as heuristic.
- **Scenes:** shortlist + library → settings (0.85 cutoff, patents off) → run →
  per-candidate Tanimoto + neighbour + novel/occupied → "novel ≠ clear, attorney
  decides." (No real run id.)

### D7 — Accelerated stability
- **Lane/card:** Cloud · Drug discovery · validated-workflow card. Workflow
  `Analyze Accelerated Stability Of Pharmaceutical Formulations`.
- **Input:** `formulations` (JSON: name, API, concentration, excipients),
  `storage_conditions` (temp °C, %RH, desc), `time_points` (days,
  `[0,30,60,90,180,365]`). Chat ask: "predict 40 °C/75% RH stability of my ibuprofen
  tablet over 6 months."
- **Settings:** pre-filled ICH set (25/60 long-term, 40/75 accelerated, 50/90 stress);
  every formulation × condition × time point.
- **Phases/gates:** per formulation × condition — ACCELERATE (Arrhenius maps hot-rate →
  25 °C) → ADJUST (empirical humidity factor) → PROJECT (API potency + degradant vs
  time). **No pass/halt gate**; output is a robustness ranking (triage). Limits:
  single dominant temp-activated pathway assumed.
- **Outputs/viewers:** projection curves (potency + degradant vs time, per formulation/
  condition — Figure) + comparative formulation-robustness ranking (Table).
- **Findings:** **no invented shelf-life figures**.
- **Reproducibility:** Methods = Arrhenius acceleration + humidity adjustment +
  projection, grounded in ICH Q1A. Honesty: triage/study-design tool, confirm in a
  real-time ICH chamber study.
- **Hero beat:** a **short hot study stands in for the long cool one** via Arrhenius +
  humidity — enough to rank recipes and design the formal study, never to replace the
  chamber.
- **Honesty flag:** live workflow framed as in-silico triage.
- **Scenes:** formulations + conditions → settings (ICH set, time points) → run
  (ACCELERATE → ADJUST → PROJECT) → projection curves (Figure) → robustness ranking →
  "rank recipes, then run the chamber."

### drug-dev — omnibus pipeline
- **Lane/card:** Cloud · Drug discovery. A **chain**, not one workflow; render each
  stage on its own domain run-card, linked by provenance.
- **Input:** demo SMILES aspirin/caffeine/ibuprofen (`SMILES.csv`); Stage 1 frames
  target/objectives/constraints in prose.
- **7 stages:** (1) frame goal (target e.g. JAK1; objectives bind/absorb/hERG-safe;
  constraints novel/makeable) → (2) design candidates (enumerate-around-seed, filter,
  rank with why-this-one + nearest known molecule) → (3) ADMET predict (reuse D2 flow:
  pre-run → running w/ gates → completed) → (4) **multi-objective Pareto ranking (each
  goal its own column/units, NEVER blended)** → (5) QC gate → (6) PK/PBPK → (7)
  provenance/lineage.
- **Gates:** Stage 5 — native hERG = blocker-risk **score** (IC50 at ceiling ~10 mM for
  the safe demo set); **DILI high > 0.5 limit → safety gate flags** for follow-up; firing
  gate suggests a before→after param diff (advisory).
- **Outputs/viewers:** grouped by producing step — ADMET table (`admet.csv` from
  `SMILES.csv`), quality metrics, toxicity report; **Pareto front (Figure, per-objective
  bars)**; reproducibility record (one JSON: run id, params, software versions, outputs,
  SHA-256, citations; empty fields shown); **navigable lineage view** (backward to
  inputs/params, forward to consumers).
- **Findings:** low hERG blocker-risk (IC50 ~10 mM ceiling); **DILI high > 0.5 → gate
  flags**. If an output can't be read, the finding is withheld and said so.
- **Reproducibility:** Methods span ADMET + Pareto MPO + PK/PBPK chain (allometric
  scaling → PBPK organ-by-organ w/ renal/hepatic-impairment sub-model → virtual-patient
  Monte-Carlo; reads Cmax, AUC, projected starting-dose scenario — projection, not
  validated absolute numbers).
- **Hero beat:** the advantage is **not any one model — it's the closed design→test loop
  + audit-grade provenance**, with a gate that fires on a real liability (DILI high) and
  proposes a fix, every number traceable.
- **Honesty flag:** omnibus of the above; PK/PBPK numbers are projections.
- **Scenes:** frame goal (target/objectives/constraints) → design candidates (why-this-
  one + nearest known) → ADMET run w/ gate → **Pareto front** (unblended bars) → DILI
  gate flag + fix diff → PK/PBPK exposure (Cmax/AUC) → **lineage view** end-to-end.

### b1 — Train a custom model  ⚠️ SOURCE DIVERGENCE + dormant routing
- **Lane/card:** Cloud · **Model training run · harness v2.0** (Models/Train track).
  Maps to the Spec 10 **"Train" worked case** (`potency-gp v3`: RMSE vs floor, scaffold
  split, censored labels kept, **not auto-registered**).
- **Input:** one clean labeled CSV (rows=samples, feature cols, exactly one target col);
  state the target col + task (classification vs regression). Read with pandas; report
  shape/types/missing before training.
- **Settings:** model-family routing — tabular AutoML (Ludwig), molecular GNN (Chemprop),
  ADMET-style scorer, LLM fine-tune (LoRA/QLoRA, DPO/GRPO via TRL). Core: target col +
  task. Auto: held-out split, cross-validation (stratified + balancing for small data),
  model = RF / GBT / small NN. **No invented hyperparameter defaults** (data-dependent).
  Split = **scaffold 70/15/15** (random split leaks for molecules); censored values kept
  as inequalities.
- **Phases/gates:** describe+upload → route to learner → hold out test → CV on training
  → fit on training rows only → **held-out QC gate vs a quality floor** (not a
  leaderboard) → offer for registration (Owner only; a failed-gate model is **not
  registered**). Overfitting signal = train-vs-held-out gap shown side by side.
- **Outputs/viewers:** trained model artifact (Model object — Identity/Evidence/Lineage/
  Used-by/Interface/Versions, Spec 03) + held-out metrics (classification: accuracy/AUC/
  F1 + confusion matrix; regression: RMSE/MAE/R² — each **training beside held-out**) +
  feature importance (Figure) + `train_report.md` (Report). Model must be badged
  **candidate / validated / heuristic**.
- **Findings:** **no specific AUC/MAE invented** (data-dependent). Spec 10 example
  figure: RMSE 0.62 clears floor, not registered. Honesty: training-data scores flatter;
  feature importance = what the model *used*, not causation.
- **Reproducibility:** Methods = split, CV, learner, held-out scoring, feature
  importance. Software: Ludwig / Chemprop / sklearn / TRL (per family). No external
  citations. Record: a model is an estimate shaped by your data; small data overfits;
  held-out + CV required.
- **Hero beat:** the **honest number is the held-out score beside the training score** —
  the gap is the clearest overfitting sign, shown plainly.
- **Honesty flags (two — important for Design):**
  1. **Source contradiction:** v2 narration = dedicated **ML Training Platform** on AWS
     Batch; older deck = **`run_code` sandbox** (sklearn). Present the **ML Training
     Platform on the workflow run surface** (Spec 10/13) as the intended target.
  2. **Dormant routing:** `ML_TRAINING_ROUTING` is **default OFF** — today a "train a
     model" chat request falls through to normal workflow search (see
     `docs/20261023_ML_DL_CAPABILITY_MAP_FOR_UI_ENRICHMENT.md`). The tutorial should
     depict the intended platform flow; live capture must wait until the flag is on.
     `chemprop_gnn` is a **stub**; Diffusion has no backend trainer.
- **Scenes:** upload labeled CSV (shape/types/missing) → choose target + task → settings
  (family routed, scaffold split, censored kept) → run (split → fit → **held-out eval**)
  → metrics **train beside held-out** (the gap) → feature importance → Model object
  (candidate badge, floor table) → "register or not" decision (not automatic).

---

## 3A. Worked-example render data (literal on-screen content)

The exact values to fill each screen, extracted from the current decks. **d1–d4,
drug-dev, b1 are data-rich** (real result rows in the markup — use as-is). **d5/d6/d7
are data-thin** (prose/concept decks: parameter defaults only, no result rows) — Design
needs to flesh an illustrative output, clearly **labelled "illustrative — not a
validated result,"** consistent with the method. d2/drug-dev are from the **real run
`d0ff684b`**; the rest are the decks' existing illustrative values.

**d1 — QSAR.** Settings: 200 trees · 5 CV folds · `morgan_fp_r2_1024` · fixed seed;
workflows `Qsar Rf Model` (activity) / `herg_cardiac_safety_qsar` (tox). Concept:
predicted **pIC50 = 7.4**. Result scorecard: **CV R² 0.72 · pass** (bar 72%), **CV RMSE
0.61** log-units, **hERG risk MEDIUM**. Gate notes: R²<0.5 → SILVER·blocking; n<50 →
BRONZE·advisory.

**d2 — ADMET (real run d0ff684b).** Settings: SMILES list + model type MPNN; ADMET-AI/
Chemprop, 15 endpoints, 2M+ ChEMBL/TDC. Input: **aspirin, terfenadine**. Stream:
ADMET_INFER_SHARD done → PREDICT_ADMET_PROPERTIES → **QC gate paused on dili_risk high →
"adjusting parameters" → Workflow finished**. **Hero gate table** (Compound/logP/MW/hERG
IC50/verdict): aspirin **1.31 / 180.2 / 10000 µM / safe**; terfenadine **7.01 / 499.7 /
0.012 µM / HALT** (GOLD threshold **1.0 µM**; cite Sanguinetti 2006, FDA E14).
**qc_metrics.json:** `herg_ic50_uM` 432.42, `herg_safe_above_10uM` true, `ames_positive`
false, `ames_probability` 0.1, `dili_risk` high, `dili_probability` **0.875** vs
threshold **0.5**. Remediation diff: `logp_max` 5.0→4.0, `mw_max` 500→400 (advisory).
Outputs: qc_metrics.json + reproducibility JSON (run id + versions + SHA-256). Findings
endpoints: hERG, DILI, oral-bioavailability, BBB, ClinTox, PPB, Caco-2, CYP2D6/3A4.

**d3 — generative.** Settings: **n_steps 500** (200 quick) · **batch_size 128** ·
**temperature 1.0**; scoring `qed_sa`(default)/`docking_gnina`/`custom_toml`; engine
REINVENT4; `brics` baseline. **Candidate table** (Candidate/score*/QED/SA/verdict):
**BM-0001 0.94 / 0.71 / 2.8 ✓ accepted**; BM-0002 0.91 / 0.66 / 3.1 ✓; BM-0003 0.88 /
0.63 / 3.4 ✓; **BM-0014 0.52 / 0.31 / 5.6 ✗ PAINS** (stays visible with reason). Outputs:
`generated_molecules.csv`, `top_compounds.sdf`, `report.html`.

**d4 — FEP/RBFE.** Settings: OpenFE+OpenMM, GPU; **11 λ windows**; LOMAP; validation vs
Tyk2/CDK2. **Network edges (kcal/mol):** L1–L2 **−1.2 ± 0.3**, L2–L3 **+0.8 ± 0.2**,
L3–L1 **+0.5 ± 0.3**; **cycle closure Σ ≈ 0.1 → closes ✓**. **Decision:** analog **B2
ΔΔG −1.4 → make**, **B5 −0.6 → make**, **B3 +0.9 → park**.

**drug-dev — omnibus.** Input: **aspirin, caffeine, ibuprofen**; target **JAK1**;
objectives Bind/Absorb/hERG-safe; constraints Novel/Makeable; `SMILES.csv` → `admet.csv`.
**QC-gate card** (Endpoint/Value/Limit/Verdict): hERG blocker-risk **Low / — / safe**;
DILI liver-injury **High / 0.5 / HALT**; diff `logp_max` 5.0→4.0. Outputs: 6 files (ADMET
table, qc_metrics.json, toxicity report) + reproducibility JSON (SHA-256). Pipeflow tools:
Generate=REINVENT4, Predict=ADMET/QSAR/docking, Rank=Pareto+QC, Refine=FEP/RBFE, PK=PBPK/
NCA (Cmax/AUC/dose — concept).

**b1 — train.** Example CSV — features logP/MW/assay_A/H_bonds, target active?: rows
`3.1/342/0.82/2/yes`, `1.7/298/0.21/4/no`, `4.4/410/0.91/1/yes`, `2.3/271/0.37/3/no`,
`3.8/388/0.74/2/yes`. Split **80/20 + 5-fold CV**. **Metric scorecard (train/held-out):**
Accuracy **0.96/0.89**, AUC **0.98/0.92**, F1 **0.94/0.86** (the GAP = memorization).
**Feature importance:** logP **0.28**, assay_A 0.21, MW 0.16, H_bonds 0.11, TPSA 0.07.
Families: random forest / gradient boosting / small NN.

**d5 — docking (DATA-THIN).** Settings: Docking Autodock Vina; **exhaustiveness 8**,
**n_poses 9**; blind: Autosite (`spacing` 1.0) / DiffDock. Inputs: `smiles_list`,
`receptor_pdb_file`, `box_center`+`box_size`, optional `reference_ligand_smiles`.
Output rule: poses ranked by Vina affinity (kcal/mol, more-negative tighter) + RMSD;
validation pass **RMSD ≤ 2.0 Å**. *No result rows — Design fleshes an illustrative pose
table (pose, score kcal/mol, RMSD), labelled illustrative.*

**d6 — novelty/FTO (DATA-THIN, STUB workflow).** Settings: Compound Novelty Scorer;
`query_smiles` + `fpsim2_db`; `novelty_tanimoto_cutoff` **0.85**, `check_patents`
**false**. Steps FINGERPRINT → NEAREST NEIGHBOUR → PATENT SCREEN. Output rule: max
Tanimoto + nearest neighbour + novel(<0.85)/occupied(≥0.85) verdict. *No result rows —
Design fleshes an illustrative per-candidate table (candidate, max Tanimoto, nearest
neighbour, verdict), labelled illustrative; also flag the workflow itself as a stub.*

**d7 — stability (DATA-THIN).** Settings: Analyze Accelerated Stability; params
`formulations` / `storage_conditions` / `time_points`. Conditions **25°C/60%RH (long),
40°C/75%RH (accel), 50°C/90%RH (stress)**; time points **[0,30,60,90,180,365] days**.
Example: ibuprofen tablet over 6 months. Steps ACCELERATE → ADJUST → PROJECT. Output
rule: potency/degradant curves + robustness ranking. *No result rows — Design fleshes
illustrative projection curves + a formulation ranking, labelled illustrative.*

---

## 3B. Findings & Outputs presentation — a design PROBLEM (not prescribed here)

The current After-run **Findings** rendering is a known weak point (flat table; redundant
per-row "Source" column repeating one filename; "Compound 1/2/3" with no real identity;
plain styling). **The layout is a question for Claude Design, not something to prescribe
in this doc** — it is written up as **Problem 2 in
`docs/20261023_UI_DESIGN_PROBLEMS_FOR_CLAUDE_DESIGN.md`** (how to present per-entity
findings: real identity, grouped without redundancy, headline verdict, v2 styling), for
Design to think through and spec in writing.

**One code prerequisite (Claude Code, regardless of the chosen layout):** the backend
findings generator must emit the **real compound identity** (name / SMILES) as a
structured `entity` field instead of embedding "(Compound N)" in the interpretation text,
so any design has real labels to render. Also verify the **Outputs** tab groups by
producing step (Spec 07/14) rather than flat-listing.

---

## 4. Cross-cutting rules for generation (quick checklist)

- Lane chip + domain chip on every step; never the generic RNA-seq panel.
- Workflow panel: 3 tabs; After-run: **Summary / Outputs / Reproducibility** only.
- Output types: **Table / Figure / Structure / Report / Log**; molecular viewers per §1.
- **Never a bare number** — model/version/confidence (and SEM/CI where relevant) travel
  with it. Censored values stay inequalities.
- Safety is a **hard gate**, not a blended objective; rejected candidates stay visible
  with the gate reason; gates halt, never silently pass.
- Only **d2** and **drug-dev** carry real result numbers (d2 run `d0ff684b`); d1 shows
  thresholds only; **d3, d4, d5, d6, d7, b1 invent no result figures** — teach the
  structure, show the fields, not fake values.
- Mark maturity honestly: **d6 = stub**, **b1 = dormant routing + source divergence**;
  distinguish validated / project-adapted / heuristic; don't present report editing/
  versioning as live.

## 5. Open items for Design to note
- Spec 13: only the transcriptomics run has fixtured step-level detail; **design/
  training step detail is an open item** — these tutorials will define it.
- Figure previews are currently thumbnails (full viewer unbuilt).
- Report ask-to-edit / version history retained but not yet deployed — show as capability,
  not as a live feature.
- b1 live capture blocked until `ML_TRAINING_ROUTING=1` on dev (frontend + backend) and
  `llm_fill` wired.

---

## Appendix — source files
- Narrations: `reference/claude_design/tutorials_v2_design/narration/{d1-qsar-classical-ml,
  d2-admet-deep-learning,d3-generative-lead-design,d4-binding-free-energy,drug-dev,
  b1-train-custom-model}.en.md`; `reference/claude_design/tutorials/{d5-molecular-docking,
  d6-novelty-fto,d7-accelerated-stability}-narration.md`.
- v2 UI spec: `reference/claude_design/data_centroid_design_v2/spec/*.html` +
  `SIMPLIFICATION_DECISIONS.md`.
- Format reference: `reference/claude_design/research_agents/{HANDOFF_RESEARCH_AGENT_UI,
  Demo Narratives}.md`.
- Platform capability + wiring: `docs/20261023_ML_DL_CAPABILITY_MAP_FOR_UI_ENRICHMENT.md`.
