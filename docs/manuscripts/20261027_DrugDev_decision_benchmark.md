# DrugDev-Bench: Open Decision Benchmarks for Phase-I Dose Selection and Pharmacokinetic Exposure, Anchored to a Mechanistic Reference

### Version 1 — two measured decision tasks, with a designed cross-stage track

**Authors:** [Author names — to be completed]
**Affiliations:** [Affiliations — to be completed]
**Corresponding author:** [name, email — to be completed]

*Preprint, 2026. Benchmark items, references, deterministic scorers, the mechanistic baseline, and per-item predictions released under CC-BY-4.0; repository and archival DOI: [to be added].*

**Keywords:** benchmark; drug development; Phase-I dose selection; pharmacokinetics; mechanistic modeling; language-model evaluation.

> **Scope and terminology.** The mechanistic **reference** in this paper is an *oracle*: the standard dose-selection rule applied to the benchmark's hidden true toxicity curve. It is **not** an end-to-end pipeline that derives the curve from the solver-visible inputs, and it is **not** guaranteed to be an upper bound (a different rule could agree with the benchmark's labels more often). Where we report it, we mean the oracle rule, and we state this at each use.

---

## Abstract

The public benchmark landscape for AI in drug development is dominated by **single-stage prediction** (property/ADMET, docking and binding affinity, molecule generation, retrosynthesis). Two decisions that gate real programs — **Phase-I dose selection** and **pharmacokinetic exposure prediction** — have essentially no open, graded agent benchmark, and no existing benchmark grades whether a system carries a decision *correctly across consecutive development stages*. We introduce **DrugDev-Bench**, whose measured version-1 contribution is a pair of execution-relevant decision tasks graded against a mechanistic reference, and whose design includes a cross-stage, execution-grounded track reported here as a roadmap with a pilot, not as a measured headline. We report baselines unedited. On Phase-I dose selection, language models are weak (frontier 0.11–0.50) while a small on-premises model reaches 0.78; the **oracle reference — the standard selection rule applied to the hidden true toxicity curve — scores 0.85**, showing that the task is far from solved by any language model. The oracle's three misses of 20 reflect differences between the selection policy and the benchmark's author-defined answers (tie-handling and no-safe-dose criteria), which we discuss as a target-definition question rather than task difficulty. On pharmacokinetic prediction, once the target endpoint is specified unambiguously, capable models reach only ~0.40–0.47 within two-fold. We make no claim of a model capability win; the contribution is an open, mechanistically-anchored decision benchmark on development stages the field has left unmeasured — scored **end-to-end and multi-dimensionally** (the executed outcome alongside safety and exposure–response fidelity), so a wrong answer is localized to *where* the reasoning chain broke.

---

## 1. Introduction

Most public benchmarks for computational drug development score a single predictive step: a property, a binding pose, an affinity, a generated molecule, a synthetic route. These are valuable, and we compete on and cite them. But two decisions that determine whether a program advances are largely unbenchmarked in the open:

- **Phase-I dose selection** — choosing a maximum tolerated dose from an exposure–response model is a decision made in every oncology program; the design methodology is standard, yet there is no shared, graded agent benchmark for the *decision*.
- **Pharmacokinetic exposure prediction** — predicting peak plasma concentration from physicochemical and clearance inputs is a daily task with no open agent benchmark.

And no benchmark grades the property that most distinguishes an agent from a predictor: whether it carries a decision **correctly across consecutive stages** (Figure 1).

![Figure 1. DrugDev-Bench scope across the development pipeline.](figures/drugdev_fig1_design.png)

**Figure 1. Study design.** Single-stage prediction tracks (left) compete with and cite external benchmarks. The measured version-1 contribution (right) is the decision and execution tracks — pharmacokinetic exposure and Phase-I dose selection — graded against a mechanistic reference. The cross-stage, execution-grounded track (bottom band) is designed and piloted, reported here as a roadmap.

## 2. Scope and honesty statement

This version reports the **measured** decision tasks: Phase-I dose selection (**40 scenarios**) and pharmacokinetic exposure prediction (**30 compounds**). Each task has two tiers. The **hand-authored tier** (20 dose scenarios, 15 compounds) is the set used for the oracle-versus-model comparison in §5. The **generated tier** (20 dose scenarios, 15 compounds) is produced from explicit models so that the ground truth is internally consistent: each dose scenario draws pharmacokinetic and Emax exposure–response parameters, derives the per-dose toxicity curve from those inputs, and sets the gold maximum tolerated dose by the *same* selection rule used for scoring — so the generated scenarios are mechanistically coherent and, by construction, free of the target-definition mismatch present in three hand-authored items (§5.1). Each generated PK compound draws physicochemical and volume parameters and sets a one-compartment modeled reference concentration. The generated tier therefore expands the **language-model** evaluation (the oracle is trivially correct on it by construction) and removes label-definition ambiguity, while the hand-authored tier carries the oracle-versus-model contrast. The single-stage prediction tracks (property, docking, binding free energy, structure–activity modeling, synthesis) exist to position against external work and are not the headline. The **cross-stage execution-grounded track is designed and piloted but not yet scored across a model roster**; we present it as the benchmark's roadmap, not a result.

## 3. Related work and positioning

**Single-stage prediction with leakage-aware design.** The drug-discovery benchmark landscape is rich but
largely single-step. The **Therapeutics Data Commons** standardizes property/ADMET/toxicity datasets with
scaffold and cold-start splits (while cautioning that scaffold splitting does not remove all leakage).
**PLINDER** and **PINDER** (2024) provide *task-specific* leakage-aware splits for protein–ligand and
protein–protein prediction, because what counts as leakage differs by task. **PoseBusters** (2024) scores
*physical validity* (geometry, clashes) rather than a single accuracy number, and reports that classical,
mechanistic docking still beats deep-learning methods on validity and generalization. **Polaris** (industry-led,
2024–2025) runs rigorous blind challenges and meta-analyzes common pitfalls. We adopt from this line two
commitments: **leakage-aware, task-specific splits** for any structure/affinity task, and a **mechanistic
baseline** as a first-class reference — the PoseBusters finding that a mechanistic method beats a learned one is
precisely our result in a new domain (dose selection), not an anomaly.

**Clinical-trial datasets.** The nearest public anchor for the dose decision is **TrialBench** (2024), a
collection of AI-ready clinical-trial datasets spanning eight prediction tasks *including drug dose-finding* —
and dose-finding is explicitly one of its hardest tasks. TrialBench is *predictive-dataset* in form; our
contribution is the complementary **decision-and-simulation** framing (choose and justify a dose under a
mechanistic model), not a duplicate dataset.

**Execution-grounded agent benchmarks.** The scoring form we adopt comes from the agent-benchmark line —
**ScienceAgentBench** (ICLR 2025) grading a runnable program by its execution output and cost, and **MLE-bench**
(OpenAI, 2024) grading on a held-out metric against a human baseline. DrugDev's measured tasks follow this
spirit: the headline is a computed, reference-anchored outcome, not a recalled fact.

**What is new here.** No open benchmark grades Phase-I dose selection or pharmacokinetic exposure as an
execution-relevant *decision* with a mechanistic reference, and the cross-stage, execution-grounded track we
design has no open counterpart. We make scoped-novelty claims only, and cite the benchmarks above as the
baselines and design sources we build on.

## 4. Methods

Each task is graded by one deterministic scorer. Language models are reported directly and, where a knowledge layer applies, with it. For context, every task is anchored to a **non-model mechanistic reference** so that a model's score is read against the right instrument, not only against other models.

- **Phase-I dose selection.** Each scenario provides pharmacokinetic and exposure–response inputs and a dose grid; the system must select the maximum tolerated dose. The grader holds the true per-dose toxicity curve, which the solver does not see. The **mechanistic reference** is the standard dose-selection rule (eliminate doses whose toxicity exceeds the target by more than the standard band; otherwise select the admissible dose whose rate is closest to target), applied to the true curve. This rule is the established methodology in the field (Liu & Yuan, 2015).
- **Pharmacokinetic exposure.** Each compound provides molecular weight, lipophilicity, ionization, plasma binding, and clearance inputs; the system predicts peak plasma concentration in micromolar, scored as the fraction of compounds within two-fold of the reference.

## 5. Results

### 5.1 Phase-I dose selection: models versus the mechanistic rule

![Figure 2. Dose-selection accuracy.](figures/drugdev_fig2_boin.png)

**Figure 2.** Dose-selection (maximum-tolerated-dose) accuracy over 20 scenarios. Language models span 0.11–0.50 (frontier) with a small on-premises model at 0.78; the dashed line is the mechanistic rule applied to the true exposure–response curve (0.85).

Three readings:

1. **The mechanistic rule, on the true curve, scores 0.85 (17/20).** Its three misses are not curve errors but selection-rule edge cases — two "no safe dose" declarations that a fixed elimination band does not trigger, and one closest-dose-versus-higher-dose tie. These mark scenarios where "the maximum tolerated dose" is itself a judgment call, a useful signal about the benchmark's own hardest items.
2. **Frontier language models are weak here (0.11–0.50).** Dose selection from an exposure–response model is not something they do reliably.
3. **A small on-premises model reaches 0.78** — above every frontier model on this task, though below the mechanistic rule. We flag this as notable but do not over-read it: the proper solution is the mechanistic exposure–response calculation, which the benchmark exists to motivate, not a language model's unaided guess.

### 5.2 Pharmacokinetic exposure prediction

The originally reported near-zero scores came from a prompt that did not state **which** pharmacokinetic endpoint to predict (each compound has several reference values), so the grader matched the wrong one. With the endpoint specified unambiguously and the full roster re-run, the best models reach only **~0.40–0.47 within two-fold** (a frontier model at 0.47), **most of the roster scores below 0.33, and several models place no compound within two-fold (0.00)**. This is an honest construct-validity correction: the task is hard, but "near-useless" was partly a specification artifact; we do not claim a model wins, and no system reaches the two-fold bar reliably.

### 5.3 A metric caveat we surface rather than hide

An early ligand-ranking task reported a score that was nearly identical across every model. On inspection this was a **metric-resolution artifact**: the rankings had only three items, on which the rank-correlation metric can take just four values, and all models mis-ranked the same small subset. We report this transparently and demote that task to a low-resolution probe pending a rebuild with longer rankings; we do not fabricate longer reference rankings to inflate resolution.

### 5.4 End-to-end scorecard: scoring the outcome alongside the component dimensions

The dose decision is also scored **end-to-end and multi-dimensionally**, in the spirit of execution-grounded
agent benchmarks that grade a program *and* its execution result. Here the system receives the inputs with the
true toxicity curve **hidden**, and must return the toxicity it models at each dose, the selected dose, and a
no-safe-dose flag. Three dimensions are scored (n = 20): **outcome** (**exact** selected-dose match to the
hidden reference — the primary, end-to-end score, identical to the benchmark's own dose scorer), **safety**
(correct no-safe-dose calls and no selection above the elimination band), and **fidelity** (did the system
actually model the exposure–response curve, or guess).

The mechanistic oracle scores **0.85 / 0.90 / 1.00** on these three dimensions; language models trail it by a wide margin. We report the *gap to the oracle* and a qualitative decomposition rather than precise per-model scores, for two reasons given below.

**A measured harness requirement (empties).** This task demands a long structured output — a per-dose toxicity curve plus the selected dose. Reasoning models exhaust a small token budget on internal reasoning and return *empty* content, which a naive scorer records as a zero; a flat zero across items is therefore a harness failure, not a capability result. We budget very generously (20,000 completion tokens) and report the **empty-response count** alongside every result. Even at that budget the requirement is model-dependent: the heaviest reasoner we tested (GPT-6.1-sol) still returns 1–4 empty responses out of 20 on these items, so its scores are reported with that count and read as a lower bound.

**Hand-authored tier (implicit exposure–response).** Language models trail the oracle (0.85) by a wide margin and are noisy at n = 20. Measured via direct provider APIs with the empties count shown: Claude Opus 5 scores an outcome of 0.25–0.30 (0/20 empty) with partial curve fidelity (~0.60–0.68 — it reconstructs the curve in part but mis-selects); GPT-6.1-sol scores ~0.10 (1–4/20 empty) with near-zero fidelity (~0.01 — when it answers, its curve is far from the truth). The large and consistent gap to the oracle is the robust finding; the precise per-model values are noisy and should be pinned down by a larger evaluation.

**Generated tier (explicit exposure–response parameters).** When the Emax parameters are provided explicitly, every frontier model tested reconstructs the curve and selects correctly: **Claude Opus 5, GPT-6.1-sol, and Gemini-3.1-Pro each reach an outcome of 1.0 with fidelity 1.0 and zero empties** (Opus is additionally stable across three runs: 0.95, 1.00, 1.00). This consistent three-model result localizes the hand-authored failure precisely — language models fail to *infer the exposure–response relationship from implicit clinical inputs*, not to do the arithmetic once the relationship is specified. The on-premises model requires its own serving endpoint and is reported separately.

The **fidelity** dimension is what makes this diagnostic: a low outcome with *low* fidelity means the system never reconstructed the curve, whereas a low outcome with *high* fidelity would mean it reconstructed the curve but mis-applied the selection rule — different failures that a single outcome number would hide.

![Figure 3. End-to-end dose-decision scorecard.](figures/drugdev_fig3_e2e_scorecard.png)

**Figure 3.** Illustrative single-run scorecard (mechanistic oracle vs. language models). The language-model bars are a single earlier run at a smaller token budget and are superseded by the budget-verified ranges in the text above; the figure is retained to show the three-dimensional structure (outcome, safety, fidelity), not the exact per-model values.

## 6. Limitations

- **Statistical power.** Each task now has 40 and 30 items (a hand-authored tier and a generated tier); this is larger than a single-tier pilot but still modest, and we report the tasks as decision probes with the mechanistic anchor, not high-precision model rankings. The generated tier reduces label-definition ambiguity by construction but does not substitute for an independently-authored, externally-adjudicated test set.
- **No wet-lab ground truth.** Exposure and toxicity references are modeled; we are explicit that modeled references are not experimental validity.
- **Cross-stage track unmeasured.** The execution-grounded cross-stage track is design and pilot only; its results are future work, and the abstract and title are scoped accordingly.
- **Mechanistic reference as oracle.** The 0.85 dose-selection reference uses the true exposure–response curve, which the solver does not see; it is an upper bound on rule-based selection, not an end-to-end system score.

## 7. Discussion

DrugDev-Bench's contribution is to place two gate-keeping drug-development decisions — dose selection and pharmacokinetic exposure — into an open, deterministically-scored benchmark anchored to an oracle mechanistic reference, and to specify an execution-grounded cross-stage track as the next milestone. The measured finding is that on dose selection, language models trail the oracle selection rule by a wide margin; interpreting this requires first fixing the decision policy (target toxicity, tie-handling, no-safe-dose criteria), since the oracle itself disagrees with three of the author-defined answers. We release the items, references, scorers, generators, and the mechanistic baseline so every number can be reproduced and contested, and we present the result as an initial methodological demonstration on 40 dose scenarios and 30 compounds (a hand-authored and a generated tier each), not a broad benchmark claim.

## 8. Data and code availability

The dose scenarios and PK compounds, their references, the deterministic scorers, the mechanistic dose-selection baseline (with its exact selection algorithm), and the complete per-item predictions are released under CC-BY-4.0 at [repository URL — to be added], archived at [DOI — to be added]. The mechanistic reference implements the selection step of the Bayesian Optimal Interval design (ref. 1) applied to the hidden true toxicity curve; its relationship to the full sequential BOIN trial design is described in §4.

## Ethics and intended use

The benchmark uses modeled (not experimental) toxicity and exposure references and synthetic scenarios; it contains no patient data. It is a nonclinical methodological benchmark and must not be used for clinical dosing decisions.

## Author contributions, funding, and competing interests

Author contributions: [to be completed]. Funding: [to be completed]. Competing interests: the on-premises model and the mechanistic pipeline are developed by the authors; items, scorers, and the baseline are released for independent audit. [Formal declaration to be completed.]

## References

1. Liu, S. & Yuan, Y. Bayesian optimal interval designs for phase I clinical trials. *J. R. Stat. Soc. C* 64, 507–523 (2015).
2. TrialBench: Multi-Modal AI-Ready Clinical Trial Datasets. 2024 (arXiv:2407.00631).
3. Therapeutics Data Commons (PyTDC): AI-ready therapeutic datasets and benchmarks with scaffold/cold-start splits.
4. PLINDER: The Protein–Ligand Interactions Dataset and Evaluation Resource. bioRxiv 2024.07.17.603955.
5. PINDER: The Protein Interaction Dataset and Evaluation Resource. bioRxiv 2024.07.17.603980.
6. PoseBusters: Are deep learning docking methods ready for production? *Chem. Sci.* 2024.
7. Polaris: an industry-led benchmarking platform for ML-based drug discovery (Valence Labs, 2024–2025).
8. ScienceAgentBench. ICLR 2025 (arXiv:2410.05080); MLE-bench. OpenAI, 2024 (arXiv:2410.07095).
