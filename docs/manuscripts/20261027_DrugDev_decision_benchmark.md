# DrugDev-Bench: Execution-Grounded Drug-Development Decision Tasks for AI Agents

### Version 1 — dose-finding and pharmacokinetics, with a cross-stage design

*Preprint — October 2026. Benchmark data and scorers released under CC-BY-4.0.*

---

## Abstract

The public benchmark landscape for AI in drug development is dominated by **single-stage prediction** (property/ADMET, docking and binding affinity, molecule generation, retrosynthesis). Two decisions that gate real programs — **Phase-I dose selection** and **pharmacokinetic exposure prediction** — have essentially no open, graded agent benchmark, and no existing benchmark grades whether a system carries a decision *correctly across consecutive development stages*. We introduce **DrugDev-Bench**, whose measured version-1 contribution is a pair of execution-relevant decision tasks graded against a mechanistic reference, and whose design includes a cross-stage, execution-grounded track reported here as a roadmap with a pilot, not as a measured headline. We report baselines unedited. On Phase-I dose selection, language models are weak (frontier 0.11–0.50) while a small on-premises model reaches 0.78; critically, the **established dose-selection rule applied to the true exposure–response curve scores 0.85**, so the task is far from solved by any language model and the mechanistic tool is the right instrument. On pharmacokinetic prediction, once the target endpoint is specified unambiguously, capable models reach only ~0.40–0.47 within two-fold. We make no claim of a model capability win; the contribution is an open, mechanistically-anchored decision benchmark on development stages the field has left unmeasured — scored **end-to-end and multi-dimensionally** (the executed outcome alongside safety and exposure–response fidelity), so a wrong answer is localized to *where* the reasoning chain broke.

---

## 1. Introduction

Most public benchmarks for computational drug development score a single predictive step: a property, a binding pose, an affinity, a generated molecule, a synthetic route. These are valuable, and we compete on and cite them. But two decisions that determine whether a program advances are largely unbenchmarked in the open:

- **Phase-I dose selection** — choosing a maximum tolerated dose from an exposure–response model is a decision made in every oncology program; the design methodology is standard, yet there is no shared, graded agent benchmark for the *decision*.
- **Pharmacokinetic exposure prediction** — predicting peak plasma concentration from physicochemical and clearance inputs is a daily task with no open agent benchmark.

And no benchmark grades the property that most distinguishes an agent from a predictor: whether it carries a decision **correctly across consecutive stages** (Figure 1).

![Figure 1. DrugDev-Bench scope across the development pipeline.](figures/drugdev_fig1_design.png)

**Figure 1. Study design.** Single-stage prediction tracks (left) compete with and cite external benchmarks. The measured version-1 contribution (right) is the decision and execution tracks — pharmacokinetic exposure and Phase-I dose selection — graded against a mechanistic reference. The cross-stage, execution-grounded track (bottom band) is designed and piloted, reported here as a roadmap.

## 2. Scope and honesty statement

This version reports the **measured** decision tasks: Phase-I dose selection (20 scenarios) and pharmacokinetic exposure prediction (15 compounds). The single-stage prediction tracks (property, docking, binding free energy, structure–activity modeling, synthesis) exist in the benchmark to position against external work and are not the headline. The **cross-stage execution-grounded track is designed and piloted but not yet scored across a model roster**; we present it as the benchmark's roadmap and do not report it as a result. This scoping is deliberate: we would rather publish the mechanistically-anchored decision tasks we can defend than claim an execution-grounded capability we have not yet measured.

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

![Figure 3. End-to-end dose-decision scorecard.](figures/drugdev_fig3_e2e_scorecard.png)

**Figure 3.** Outcome (exact MTD match), safety, and exposure–response fidelity (20 scenarios). The mechanistic
pipeline computes the curve and scores 0.85 / 0.90 / 1.00; language models trail on all three.

| System | outcome (exact MTD) | safety | fidelity |
|---|---|---|---|
| **Mechanistic pipeline (execution reference)** | **0.85** | **0.90** | **1.00** |
| Claude Opus 5 | 0.30–0.40 | 0.75 | 0.46–0.64 |
| Gemini 3.1 Pro | 0.25 | 0.80 | 0.16–0.62 |
| GPT-6.1-sol-pro | 0.10 | 0.20 | 0.01 |

(Single-run LLM outcome at n = 20 is noisy — Opus-5 spans 0.30–0.40 and fidelity 0.46–0.64 across runs — so
LLM rows are reported as ranges, not points; The
**fidelity** dimension is what makes this diagnostic rather than a single opaque number: GPT-6.1-sol-pro's
outcome is 0.10 *because* its curve fidelity is ~0.01 — it never modeled the exposure–response and effectively
guessed; Opus-5 modeled the curve partially and still landed only a third to two-fifths of the exact doses; the
mechanistic pipeline computes the curve (fidelity 1.00) and reaches 0.85. A low outcome with low fidelity
("never modeled it") and a low outcome with high fidelity ("modeled it, mis-selected") are different failures,
and scoring the outcome end-to-end *alongside* the component dimensions is what separates a system that
computes the answer from one that guesses it.

## 6. Limitations

- **Statistical power.** The two measured tasks have 20 and 15 items; we report them as decision probes with the mechanistic anchor, not as high-precision model rankings, and we do not pool heterogeneous micro-tasks to manufacture power.
- **No wet-lab ground truth.** Exposure and toxicity references are modeled; we are explicit that modeled references are not experimental validity.
- **Cross-stage track unmeasured.** The execution-grounded cross-stage track is design and pilot only; its results are future work, and the abstract and title are scoped accordingly.
- **Mechanistic reference as oracle.** The 0.85 dose-selection reference uses the true exposure–response curve, which the solver does not see; it is an upper bound on rule-based selection, not an end-to-end system score.

## 7. Discussion

DrugDev-Bench's contribution is to put two gate-keeping drug-development decisions — dose selection and pharmacokinetic exposure — into an open, deterministically-scored benchmark anchored to the established mechanistic methods, and to lay out an execution-grounded cross-stage track as the next milestone. The headline finding is sober and useful: on dose selection, language models trail the standard mechanistic rule by a wide margin, which is exactly the argument for routing such decisions through the mechanistic tool rather than a model's unaided judgment. We release the items, references, scorers, and the mechanistic baseline so every number here can be reproduced and contested.

## 8. Data and code availability

Items, references, the deterministic scorers, and the mechanistic dose-selection baseline are released under CC-BY-4.0. Dose-selection methodology follows Liu & Yuan, *Journal of the Royal Statistical Society: Series C* (2015).

## References

1. Liu, S. & Yuan, Y. Bayesian optimal interval designs for phase I clinical trials. *J. R. Stat. Soc. C* 64, 507–523 (2015).
2. TrialBench: Multi-Modal AI-Ready Clinical Trial Datasets. 2024 (arXiv:2407.00631).
3. Therapeutics Data Commons (PyTDC): AI-ready therapeutic datasets and benchmarks with scaffold/cold-start splits.
4. PLINDER: The Protein–Ligand Interactions Dataset and Evaluation Resource. bioRxiv 2024.07.17.603955.
5. PINDER: The Protein Interaction Dataset and Evaluation Resource. bioRxiv 2024.07.17.603980.
6. PoseBusters: Are deep learning docking methods ready for production? *Chem. Sci.* 2024.
7. Polaris: an industry-led benchmarking platform for ML-based drug discovery (Valence Labs, 2024–2025).
8. ScienceAgentBench. ICLR 2025 (arXiv:2410.05080); MLE-bench. OpenAI, 2024 (arXiv:2410.07095).
