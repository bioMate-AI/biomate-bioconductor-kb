# DrugDev-Bench: an execution-grounded, decision-centric benchmark suite for drug-development AI agents

**Target venue:** NeurIPS Datasets & Benchmarks / *Journal of Cheminformatics* / *Bioinformatics* (Application Note)
**Prepared:** 2026-10-22
**Status:** benchmark-design and offline-validation manuscript (model leaderboard deferred — see §6, §7)

## Authors
Yaoyun Zhang¹, Andrew Dike¹·²
¹ BioMate AI · ² BizBildr

---

## Abstract

Benchmarks for AI agents in drug development are dominated by two framings: molecular-property
prediction on fixed assay panels, and "did the agent call the right tool" routing checks. Both
under-measure what a development scientist actually does — make a **defensible decision under a
project context, using a tool's output, across the stages of a program**. We present **DrugDev-Bench**,
a benchmark suite organised around two under-covered axes: **context-rich decisions** (a project
vignette → go/no-go, ranking, dose, target call, graded on the decision and its reasoning against
real measured ground truth) and **execution-grounded, cross-stage** tasks (grade a real multi-step
pipeline run against its terminal state and output artifacts). The suite spans five pre-existing
stage benchmarks (ADMET, docking, PBPK, BOIN dose-escalation, target structure), a relative
binding free-energy (RBFE) benchmark built from real experimental ΔΔG, and a 9-archetype / 30-task
**decision suite** with six objective scorers, one adapter, and one runner. Ground truth is drawn
from public measured data (ChEMBL/FDA-label ADMET, the Merck/Schindler FEP set, published BOIN
operating characteristics, the FDA MRSD formula), with the answer hidden from the prompt. This
manuscript reports the **design, the ground-truth sourcing, and offline validity** (self-tests of
all scorers and adapters; a benchmark→training export whose reward contract is verified on 30/30
gold items), together with an offline diagnosis of the multi-step **composer** that the
execution-grounded track targets. We deliberately **do not report a cross-model leaderboard**: the
per-model DrugDev sweep and the live execution-grounded (L5–L6) grading require a gated compute run
and are future work. Our contribution is the suite, its decision/execution framing, its real-data
ground truth, and a reproducible offline-validation protocol — not a ranking of any system.

---

## 1. Introduction and gap

The external drug-development benchmark landscape is, contrary to a common assumption, **well
populated**. A three-pass survey of ~165 benchmarks (recorded in
`docs/20261021_DRUGDEV_BENCHMARK_LANDSCAPE_AND_SERIES.md`) finds mature coverage across ADMET
(TDC/TDC-2, ADMET-AI, PharmaBench), docking and virtual screening (PDBbind, CASF, DUD-E, LIT-PCBA,
PoseBusters, and the leakage-controlled LP-PDBBind / PLINDER / Runs-N-Poses / DockGen / BayesBind),
free-energy (OpenFE, JACS-FEP, Merck/Schindler), generation (GuacaMol, MOSES), retrosynthesis
(USPTO, PaRoutes), target discovery (Open Targets, PrimeKG, GEARS, the Arc Virtual Cell Challenge,
BioDiscoveryAgent), and retrieval/knowledge (PaperQA2, STaRK-PRIME, ChemBench, MoleculeQA,
BioKGBench), plus a rich agent-evaluation ecosystem (Biomni, TxAgent, TxGemma, BixBench, DMPKBench,
DrugAgent). Two cross-cutting lessons recur: structure/affinity tasks are only meaningful under
**leakage-controlled splits** (co-folding models memorise; physics wins on novel targets), and
single-metric success invites reward-hacking ("Beyond Affinity"; GenBench3D).

The gap is therefore **not** another property-prediction panel. It is twofold. First, almost all of
these benchmarks score an **isolated capability** ("predict hERG", "rank these ligands"), not the
**project decision** a scientist makes from that capability under constraints ("which of these
analogues do we synthesise next, and which do we drop, and why"). Second, essentially none grade
**execution end-to-end** — selecting, running, and chaining real workflows and verifying the
produced artifacts. DrugDev-Bench targets exactly these two axes, and cites and competes with the
external benchmarks on the shared molecular-tool tasks rather than claiming novelty there.

We make no "first" or "no-competitor" claim for the suite as a whole; we claim the specific
combination of **context-rich decision framing + execution-grounded grading + real-data,
answer-hidden ground truth**, verified against the benchmarks in our survey.

---

## 2. The suite

DrugDev-Bench is organised into four tracks (`evaluation/datasets/drugdev_export/MANIFEST.json`):
**T1** molecular-tool workflows (compete + cite external), **T2** early-stage target/perturbation
(compete + cite), **T3** search/knowledge (compete + cite), and **T4** execution-grounded /
cross-stage, which is the suite's own white space. Every structure/affinity/target task carries a
mandatory design requirement of leakage-aware splits and multi-objective (anti-reward-hacking)
scoring.

### 2.1 Stage benchmarks (B1–B5)
- **B1 ADMET** — 20 compounds (ChEMBL/FDA-label measured hERG/DILI/Ames/Ro5), `admet_scorer`.
- **B2 Docking / B3 PBPK / B4 BOIN** — already public in the sibling RealBio export
  (`drug_discovery_e2e`, `pbpk_benchmark`, `boin_benchmark`); cited here, not duplicated.
- **B5 Target structure** — 10 targets (FASTA/UniProt → pocket residues), leakage-controlled.

### 2.2 N1 — Relative binding free energy (RBFE / FEP), S3 lead optimisation
The single largest workflow-only white space in free energy. Gold is **8 congeneric series / 264
ligands** with **real experimental ΔΔG** derived from the MIT-licensed Merck/Schindler FEP
benchmark (`github.com/MCompChem/fep-benchmark`; Schindler et al., *JCIM* 2020, 60:5457), computed
as ΔΔG = Exp.ΔG(ligand) − Exp.ΔG(reference); nothing is invented, and ligand structures are
referenced, not re-embedded. `rbfe_scorer` reports RMSE/MUE (accuracy), Kendall-τ/Spearman (rank
fidelity), and a within-1-kcal fraction, combined into a multi-signal composite (the "Beyond
Affinity" lesson). For the ML-training variant the split is leave-target-out.

### 2.3 The decision suite — 9 archetypes / 30 tasks (the core contribution)
Each task is a **project vignette**: the data a scientist has, the real constraint, and the
decision required; ground truth is derived objectively from real measured data and is **hidden
from the prompt** (the agent must reach it from the tool output). Archetypes and task counts
(`evaluation/datasets/drugdev_export/*/data.jsonl`):

| archetype | tasks | decision | ground truth | scorer |
|---|---|---|---|---|
| C lead-op triage | 3 | advance / deprioritise an analogue series + liability | measured ADMET (B1) | decision |
| E FEP selection | 2 | rank vs the lead; advance tighter binders | experimental ΔΔG (N1) | decision |
| H dose-escalation MTD | 3 | call the MTD + safety flags | BOIN operating characteristics | mtd |
| F1/G dose projection | 3 | FIH MRSD / human clearance | FDA MRSD formula; allometry | numeric |
| F2 tissue/organ exposure | 3 | does free drug reach the target site | Kp,uu / organ partition† | categorical |
| F3 dose schedule | 3 | regimen from the PK/PD driver | PK/PD class | categorical |
| F4 special-population dose | 4 | renal/hepatic/DDI adjustment | FDA-label tables† | categorical |
| P process/stage knowledge | 6 | lifecycle gates, prerequisites, sequencing | FDA/ICH process | categorical + set |
| W workflow chain | 3 | plan the ordered multi-stage pipeline + gates | reference stage DAG | chain |

Six scorers implement the grading — `decision_scorer.{score_decision, score_categorical_decision,
score_set_decision, score_numeric_decision}`, `boin_scorer.score_mtd_decision`,
`chain_scorer.score_chain` — dispatched by a single `DecisionBenchmarkAdapter` and driven by one
`run_decision_benchmark.py` runner. Design and rationale: `docs/20261021_DRUGDEV_BENCHMARK_PRACTICAL_REDESIGN.md`.

† F2/F4 numeric ground-truth values are textbook/class-level correct but **web-unverified** as of
this writing (see §7); they are flagged `provisional` in the manifest.

---

## 3. Methods

**Decision grading.** The composite scorers reward the decision and its reasoning, not tool
selection: a deprioritise-set F1 (penalising dropping a keeper), a best-pick check, a
correct-liability/driver term, a numeric within-fold band (full credit ≤ fold, half ≤ fold²), a
controlled-vocabulary verdict with a negation guard, a set-F1 for prerequisite sets, and a chain
score combining stage coverage, order fidelity (longest-common-subsequence vs the reference
order), and before→after gate adherence. Non-colliding compound labels (`C1…C4`, never a bare
`A`) and apostrophe-safe boundaries avoid free-text false matches.

**Answer-hidden design.** Prompts contain the inputs and the required decision, never the
ground-truth conclusion; verified programmatically (the adapter self-test asserts no liability or
measured value leaks into the rendered prompt).

**Benchmark→training export.** Each decision task exports both an SFT target (a synthesised,
scorer-verified gold completion) and a GRPO row (`prompt, gold, scorer, labels`) with the scorer as
a verifiable reward (`decision_reward`). A `route_not_compute` policy tag marks the numeric
dose-projection tasks so the model is trained to route to the engine, not to perform arithmetic.
Train/eval are split **disjointly by template source** with a fail-closed leak guard; details in
`docs/20261021_DECISION_BENCHMARK_TO_TRAINING.md`.

---

## 4. Offline validity

This is a design + offline-validation paper; all results below are reproducible without a live
stack or model API.

- **Scorer/adapter self-tests pass:** `rbfe_scorer` 6/6, `decision_scorer` 15/15, `chain_scorer`
  5/5, `boin_scorer.score_mtd_decision` verified, `DecisionBenchmarkAdapter` 14/14 across all nine
  archetypes, `DecisionBenchmarkAdapter` (lead-op exemplar) 7/7.
- **Gold is self-verifying:** every synthesised SFT gold completion is scored by its own scorer
  before emission; the builder refuses any target below 0.9. Current run: **30/30 score 1.0**.
- **Training reward contract verified:** on the 30 GRPO rows, the gold completion scores high and a
  trivial wrong completion scores lower (`decision_reward --selftest`, 22/22 on the TRAIN split).
- **RBFE gold oracle-scores correctly:** feeding the experimental ΔΔG back through `rbfe_scorer`
  yields RMSE 0 and a composite ≈ 0.98 (the residual is the documented Kendall-τ-a tie deflation on
  tied experimental values, not an error).

### 4.1 Composer diagnosis (the execution-grounded track's target)
Validating the T4 multi-step composer offline revealed a stack of harness/data gates, measured on
real topologies (`docs/20261021_DAG_RESOLUTION_COVERAGE_RESULT.md`):
- On a perfect-decomposition assumption, the workflow resolver reaches **100% confidence** (every
  subtask clears the ≥6 match bar) — but only **4% precision** vs the gold tool when the input is
  fine-grained Galaxy-tool chains (a granularity mismatch: that gold is tool-level, while the
  composer composes nf-core-style workflows).
- **66% of catalogue workflows carry free-text parameter descriptions in `input_types`** (not type
  tokens), so they cannot be a handoff destination regardless of matcher — a data-quality gate; the
  descriptions are preserved structurally in `params_schema` and re-derivable without loss.
- Switching the handoff from exact string match to the sanctioned semantic matcher lifts the
  composer fire-rate from **4.4% → 38.2%** on 68 real topologies, with a further residual explained
  by resolver precision and genuine cross-ecosystem representation gaps (e.g. `counts_matrix` vs
  `ExpressionSet`), not capacity.

These are reported as **benchmark findings about the system under evaluation**, obtained with the
suite's own offline instruments — not as a model score.

---

## 5. Relation to RealBio
DrugDev-Bench is the sibling of RealBio (companion manuscript). Three DrugDev tasks (B2 docking, B3
PBPK, B4 BOIN) are *surfaced* through the shared RealBio public export but are DrugDev benchmarks;
they are described here and cited, not re-counted, in each suite.

## 6. What this paper deliberately does not claim
- **No cross-model DrugDev leaderboard.** Scoring the model roster on these tasks is a gated
  compute run and is not reported.
- **No execution-grounded (L5–L6) results.** The N8 end-to-end pipeline flagship and the N1 RBFE
  Batch runner grade against real terminal + S3 artifacts on a live stack; they are built-to-spec
  but unrun here.
- **No RL/fine-tuning claims.** The SFT/GRPO export is validated as data; the training runs
  (GRPO/DPO) have not been launched, so no capability-improvement claim is made.

## 7. Limitations and future work
- **Seed scale.** The decision suite is 30 tasks (2–6 per archetype) — sufficient to validate the
  design and scorers, not to rank systems; each archetype needs expansion before inferential use.
- **Provisional values.** F2/F4 numeric ground truth is class-level correct but web-unverified;
  flagged `provisional`, to be confirmed against primary sources/FDA labels before any leaderboard.
- **Gated execution + sweep.** Live execution grading and the per-model sweep are the immediate
  next step; the composer fixes above (semantic handoff, `input_types` re-derivation, resolver
  precision) are prerequisites for a meaningful T4 number.
- **Planned tasks.** N2 QSAR, N3 generation, N4 retrosynthesis, N5 stability, N6 novelty/FTO, N7
  IND-narrative, N8 pipeline-e2e (flagship), N9 cross-stage, and T2/T3 target/perturbation/
  retrieval/knowledge are specified but not yet built.

## 8. Availability
Scorers `evaluation/scorers/{rbfe,admet,pbpk,boin,docking}_scorer.py`,
`evaluation/scorers/{decision,chain}_scorer.py`; adapters `evaluation/adapters/*`; gold
`evaluation/datasets/drugdev_export/*/data.jsonl`; manifest + design docs as cited. Ground-truth
provenance: ChEMBL, FDA labels, MIT-licensed Merck/Schindler FEP, published BOIN operating
characteristics, FDA MRSD guidance.
