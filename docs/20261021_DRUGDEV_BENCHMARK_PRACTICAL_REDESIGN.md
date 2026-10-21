# DrugDev Benchmark — Practical Redesign: Decision Tasks, Not Tool-Routing

**Date:** 2026-10-21
**Status:** design + three exemplars built on real gold — archetype C (lead-op triage),
E (FEP-guided selection), H (dose-escalation MTD)
**Related:** `docs/20261021_DRUGDEV_BENCHMARK_LANDSCAPE_AND_SERIES.md` (landscape + 4-track series),
`docs/20260427_DRUG_DEV_BENCHMARK_PLAN.md` (original B1–B5 plan),
`evaluation/local_trial/execution_grader.py` (the end-to-end run grader).

## 1. The problem this fixes

The first-cut B1/N1 adapters graded **plumbing**, not drug-development judgement.
A task looked like: *"given a SMILES, did the agent route to the ADMET workflow and
extract the `smiles_list` param?"* — with `complete` / `incomplete` /
`negative_control` variants. That is a tool-selection test. A model can score 1.0 on
it and still be useless to a project team, because real drug-development work is not
"pick the tool" — it is **making a defensible decision under a project context, using
the tool's output**.

> Design principle: **grade the decision and its reasoning, not the route.** Tool
> execution is the *means*; the run is graded end-to-end by `execution_grader.py`
> (terminal success + S3 output-content validation), and the recommendation it
> produces is graded against a real-data ground truth.

## 2. What a practical task looks like

Each task is a **project vignette**:

1. **Context** — project stage, prior data, the real constraint (e.g. "potency is
   comparable across the series; you can carry at most three forward").
2. **Inputs** — the data a scientist actually has (structures, measured properties,
   PK, a screen hit-list), referenced by a single source of truth (e.g. the B1 ADMET
   case id) rather than re-embedded.
3. **Decision required** — the go/no-go, the ranking, the dose, the target call.
4. **Ground truth** — the correct decision, derived objectively from **real measured
   data** (ChEMBL/FDA-label ADMET, Merck experimental ΔΔG, BOIN operating
   characteristics, clinical PK). Never invented.
5. **Scoring** — the decision (advance/deprioritize set), the liability/driver named,
   and whether the rationale cites the right mechanism/threshold.

The ground truth is **hidden from the prompt** (the agent must reach it from the
tool output), and the answer is grounded in a measured fact, so scoring stays
objective — not an LLM-judge vibe check.

## 3. Archetypes — the decisions that matter across the pipeline

Each is anchored to real ground-truth data we have or can source.

| # | Stage | The decision | Real ground truth | Data status |
|---|-------|--------------|-------------------|-------------|
| A | S0 target | Pursue or deprioritize this target? | Open Targets assoc + known druggability | to source |
| B | S1 hit | Which screen hits are real vs PAINS/artifact? | known actives vs frequent-hitters | to source |
| **C** | **S3 lead-op** | **Which analogue to make next; which to drop & why** | **measured ADMET/potency** | **BUILT (D1)** |
| D | S3 lead-op | Compound has a liability → what structural fix? | matched-pair that fixed it (ChEMBL MMP) | to source |
| **E** | **S3 lead-op** | **FEP-rank the series; which analogues advance** | **Merck experimental ΔΔG** | **BUILT (D2)** |
| F | S4 DMPK | Project the human dose from preclinical PK | observed clinical PK | to source |
| G | S5 | First-in-human starting dose | NOAEL→HED→MRSD (FDA guidance) | formula + labels |
| **H** | **Ph I** | **Dose-escalation MTD decision** | **BOIN operating characteristics** | **BUILT (D3)** |
| I | regulatory | IND §2.6.1 nonclinical narrative | skeleton/MRSD/adversity checklist | partial (regulatory_v6) |

Archetypes **C/E/H are built** on real gold (D1/D2/D3 below); A/B/D/F/G/I need a
sourcing pass (all from public measured data — no fabrication).

### 4b. E and H (built)

- **E — FEP-guided selection** (`fep_selection/data.jsonl`, 2 tasks c-Met/SHP2):
  present a congeneric series vs the lead, agent runs RBFE/FEP and must advance the
  meaningfully-tighter binders and drop the clearly-weaker one. Ground truth = real
  experimental ΔΔG from the N1 gold (advance ≤ −1 kcal/mol, drop ≥ +2). Analogues
  relabelled L1…L5 (the raw ligand ids like `SHP099-1/Example 7` are messy). Scored
  by `decision_scorer`; the live FEP run's ranking is graded by `rbfe_scorer`.
- **H — dose-escalation MTD** (`dose_decision/data.jsonl`, 3 tasks): a BOIN DLT curve
  + target DLT rate → call the MTD (level/mg) and safety flags. Covers the clean case,
  **MTD-not-reached** (all doses tolerated → flag, name no dose), and
  **toxic-at-starting-dose** (MTD = lowest level + flag). Ground truth = B4 BOIN
  operating characteristics. Scored by a new text-level `boin_scorer.score_mtd_decision`
  (exact/adjacent MTD + flag recognition), reusing the Yuan-2016 thresholds. This
  **reframes the old routing-style BOIN adapter as a real decision task.**

One adapter (`DecisionBenchmarkAdapter`) serves every archetype: it dispatches to the
scorer each task declares (`"scorer": "decision" | "mtd" | "categorical"`) and loads
any archetype via `config["dataset"]` (`DECISION_DATASETS` registry). `--selftest` 22/22.

### 4c. Dosing is multi-axial — F expanded into F1–F4 (F2, F4 built)

"Human-dose projection" (a single systemic number) is reductive. A real dosing
decision spans **four axes**: (1) systemic amount, (2) **tissue/organ site exposure**,
(3) **schedule/timing**, (4) **special-population/comorbidity adjustment**. Built so
far:

- **F2 — tissue/organ exposure** (`tissue_exposure/data.jsonl`): does FREE drug reach
  the target tissue above threshold (CNS Kp,uu) — or does a tox organ over-accumulate?
  Plasma PK alone misleads. Cases: P-gp-excluded (loperamide-like → `excluded`),
  active brain uptake (oxycodone-like → `reaches_target`), liver over-exposure
  (`organ_risk_flag`). This is BioMate's **PBPK white space** (and where LLMs are
  weakest — PBPK scored ~0.075 before).
- **F4 — special-population dose** (`special_population/data.jsonl`): renal/hepatic/DDI
  adjustment — metformin at eGFR 25 (`avoid`), simvastatin + strong CYP3A4 inhibitor
  (`avoid`), enoxaparin at CrCl 20 (`reduce`), + a no-adjustment negative control. GT =
  FDA-label dose-adjustment sections. **This is label-grounded decision/knowledge, NOT
  PopPK model fitting** (that stays out of scope, per the data-boundary rule).

Both use a new **categorical-verdict scorer** (`score_categorical_decision`): controlled
vocabulary match (structured `verdict:`/`action:` line, free-text fallback with a
negation guard) + optional numeric within-fold + rationale coverage.

> **PROVISIONAL (honesty):** F2/F4 gold VALUES are textbook/class-level correct but the
> exact Kp,uu numbers and label cutoffs were **not web-verified this session** (search
> budget exhausted). Datasets are flagged `status: provisional_values_unverified` with a
> per-item `verify` field and cited sources. The scoring machinery is final; the numbers
> get a verification pass when search budget returns. Nothing was fabricated — uncertain
> values are flagged, and TISSUE-03 is deliberately principle-level (no compound asserted).

## 4. First exemplar built — archetype C (lead-op multi-parameter triage)

**Gold:** `evaluation/datasets/drugdev_export/leadopt_triage/data.jsonl` — 3 scenarios
(easy / medium / hard), each a 4-analogue series where the decision turns on
developability, not potency. Compounds are referenced by **B1 ADMET case id** (single
source of truth; no SMILES duplication, no propagation of any SMILES errors in the
existing gold). The ground-truth liabilities are literature-correct measured facts:

- **LEADOPT-01 (easy):** one Terfenadine-like analogue with a hERG IC50 of 0.2 µM →
  drop it (hERG/QT); the rest are hERG-safe.
- **LEADOPT-02 (medium):** one Thalidomide-like, Ames-positive analogue → drop it
  (genotoxicity is the single hard stop; hERG-safe, DILI-negative).
- **LEADOPT-03 (hard):** *no* clean compound — every analogue has a moderate hERG
  signal; the drop is the one stacking Ames+ / DILI+ / Ro5-fail, the advance set is
  the two with clean DILI/Ames and the widest hERG margins. A genuine trade-off.

**Scorer:** `evaluation/scorers/decision_scorer.py` — `score_decision(response, gt,
labels)` → composite in [0,1]:

- `0.60` decision = deprioritize-set F1 (penalises dropping a keeper) + best-pick
  acceptable (and *not* advancing a must-drop compound)
- `0.25` liability = named the correct dominant liability (alias hit)
- `0.15` rationale = coverage of the mechanism/evidence terms

Parses a trailing `DECISION:` block (robust, format-light) and falls back to a
tolerant clause-level free-text parse. Labels are non-colliding tokens (`C1`…`C4`,
never bare `A`, which collides with the English article); boundary matching excludes
apostrophes so label `D` never matches the `d` in "I'd". Pure/stdlib, `--selftest` 5/5.

**Adapter:** `evaluation/adapters/decision_benchmark_adapter.py` —
`DecisionBenchmarkAdapter` loads any decision-task jsonl (point it with
`config["dataset"]`), renders the vignette, and scores via `decision_scorer`.
Exported from `evaluation/adapters/__init__.py`; `--selftest` 7/7 (verifies the gold
does not leak the answer into the prompt).

## 5. How execution grading plugs in (L5–L6, gated)

The offline score grades the stated recommendation. The **live** variant:

1. agent runs `predict_admet_properties` on the series (real Batch run),
2. `execution_grader.grade_detailed(run, deep=True)` confirms terminal success + the
   ADMET output parses with the expected per-compound keys (register a contract via
   `register_contract` if needed),
3. `decision_scorer` grades whether the agent's advance/drop recommendation is
   consistent with those real predictions vs the thresholds.

That live path is the gated piece — it needs the dev/Batch loop and is **not** run
speculatively.

## 6. Next

- ~~Roll the vignette shape across C→E→H~~ **DONE** (D1/D2/D3, all on real gold).
- Source A/B/D/F/G/I from public measured data (no fabrication). F/G (human-dose
  projection, FIH starting dose) add a numeric-tolerance scorer (reuse `pbpk_scorer`);
  A/B (target go/no-go, hit triage) reuse `decision_scorer` with Open-Targets /
  known-actives ground truth.
- ~~A `run_decision_benchmark.py` runner that iterates `DECISION_DATASETS`~~ **DONE**
  (`evaluation/runners/run_decision_benchmark.py`): `--dry-run` lists all tasks
  offline; live mode health-checks the BioMate server and **skips execution when it is
  down** (never a speculative live run); per-archetype + per-difficulty score summary,
  JSON metrics out. Still to add: roster sweep wiring (run across models) + the gated
  L5–L6 execution-grading path (ADMET/FEP run → `execution_grader` → decision
  consistency).

**Honesty note (carry forward):** report baselines unedited. The value of this suite
is that it exposes where an agent *looks* capable (routes correctly) but makes the
wrong call — which the routing-only design could never show.
