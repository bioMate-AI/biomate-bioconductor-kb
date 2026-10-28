# Hypotheses: a small LLM with a feedback-and-knowledge loop versus baseline and large LLMs (2026-10-29)

Status: **hypotheses only, written before the L7 replay or any v5 run; not yet registered as a formal amendment.** Each hypothesis states its prediction, the measurement that tests it, and what would falsify it. Registration (dated amendment in `PREREG_LOOP.md` and the v5 prereg) must precede any scored run. Companion: `20261029_MODEL_COMPARISON_ANALYSIS_SPEC.md` (13 measured dimensions).

## 0. Central claim (owner)
A small LLM (≈25 M parameters, atom-level; v5) inside a closed loop with verified feedback and knowledge is **comparable to or better than large LLMs** given the same feedback and knowledge, and better than a fingerprint gradient-boosted baseline, on peptide property/binding ranking.
- **Non-inferiority form:** small+loop yield ≥ 90 % of the strongest large+loop yield, lower 95 % CI bound above 90 %.
- **Superiority form:** lower 95 % bound of (small+loop − large+loop) > 0.

## 1. Facts the hypotheses rest on (measured this session; sources in the audit logs)
1. The loop with a fingerprint GBM beats random selection in the within-source setting (L3: in-distribution 226.7 vs 50.0, +176.7 [146, 209]; scaffold-shifted 62.5 vs 29.9, +32.6 [16, 52]); the in-distribution regime has near-duplicate leakage by design (22.9 % of pool peptides share a fingerprint with an initial peptide).
2. CycPeptMPDB: 6,960 peptides = 2,460 flat structures; 4,912 peptides (71 %) are in groups of ≥2 stereoisomers (largest 116); median within-group label spread 0.86 log units (up to 1.73 in one lab's series). The baseline fingerprint ignores chirality (2,380 distinct fingerprints).
3. v4 audit: binding "win" at chance against hard negatives on 4/5 targets; target prefix barely used; DPO shifts permeability only.
4. Benchmark: all knowledge/rule arms at chance on the family-disjoint analysis (strongest baseline AUROC 0.620); knowledge-base coverage is 0/46 targets for the gate.

5. Baseline error analysis (2026-10-29, `20261029_BASELINE_ERROR_ANALYSIS.md`): chirality-aware fingerprints raise Spearman only ~0.05 (0.713→0.766 random CV; 0.663→0.712 grouped); the worst errors are not concentrated in stereoisomer groups; small/diverse sources are worst (Faris ρ 0.49, Bhardwaj 0.42); 28 % of identical-fingerprint pairs are label cliffs (>1 SD).

## 2. Hypotheses
**H1 — Sample efficiency.** Pretraining plus knowledge gives the small LLM a prior that reduces the number of revealed labels needed. *Prediction:* the LLM's learning curve is above the baseline's at small n (25–100 labels) and the gap shrinks with n (consistent with prior weight w = n0/(n0+n)). *Measure:* labels-to-reach-baseline-final-performance; area under the learning curve. *Falsified if:* the baseline's curve is not below the LLM's at any n in the pre-specified grid, or the labels-to-baseline ratio's CI includes 1.

**H2 — Stereochemical resolution.** Explicit stereo/topology tokens let the LLM rank stereoisomers that the chirality-blind baseline cannot distinguish. *Prediction:* within-flat-group Spearman ≈ 0 for flat-feature baselines (**only under a single seeded revealed/target split per group; leave-one-out evaluation gives an artifactual negative value — a leave-one-out group-mean predictor scores exactly −1.0; see 20261029_BASELINE_ERROR_ANALYSIS.md**) and > 0 for the LLM, in the held-out-group and SAR settings. *Falsified if:* the LLM's within-group Spearman CI includes 0, or it does not exceed a chirality-aware fingerprint GBM (the fair stereo-aware baseline).

**H3 — Knowledge helps when feedback is scarce.** Rules/knowledge-base signals add most at small n and little at large n. *Prediction:* knowledge-on minus knowledge-off gap decreases with n and is positive at the smallest n for the LLM. *Measure:* the gap per n with CI. *Falsified if:* the gap is zero at all n, or if the model's predictions do not change under the counterfactual probe (rule removed or contradicted). Note the benchmark found knowledge arms at chance; the loop test is distinct (knowledge enters as prior/fusion inside feedback), but this is the least supported hypothesis.

**H4 — Transfer.** A pretrained representation transfers across targets and scaffolds, so the small LLM's advantage persists on held-out target families. *Prediction:* positive small-n advantage on family-held-out folds (`folds_v1.csv`), not only in-distribution. *Falsified if:* the advantage appears only in-distribution or only within one lab's series (shortcut check, dimension 4).

**H4b — Few-label new-target adaptation (cross-target with increasing evidence).** For a held-out target family, performance as a function of revealed labels k ∈ {0, 5, 10, 25} for that target. *Predictions (written before any scored run):* (i) at k=0 all arms are near chance (consistent with the zero-shot null; strongest baseline AUROC 0.62 on analysis I); (ii) all arms, including nearest-neighbour to the revealed compounds, improve with k, largely by matching analog series — so the gain over k=0 alone is not evidence for the LLM; (iii) the test is the gap: LLM minus the strongest baseline (nearest-neighbour to revealed; GBM fit on revealed only; pretrained GBM fine-tuned on revealed) at each k, expected steepest between k=0 and 5 and diminishing after 10; (iv) strong heterogeneity across families. Evidence types are separate conditions: binders only; binders plus measured inactives; knowledge (pharmacophore) only; combinations. *Measures:* gain over k=0, learning-curve slope, labels to reach a fixed AUROC, LLM-minus-baseline gap with family-cluster bootstrap CIs, target counts and power per k. *Falsified (for the LLM claim) if:* the gap's CI includes 0 at all k, or the typicality/no-target validity control exceeds chance. Limits: median target has ~5 cyclic compounds (138 targets ≥50), so only ~100–200 targets qualify; zero-shot expected null, as in the field (3–8 %).

**H5 — Small ≈ large when information is equal.** With the same labels and knowledge, the cost-adjusted performance of the small fine-tuned model matches large in-context LLMs, because the task is narrow and the information is in the feedback, not in world knowledge. *Prediction:* non-inferiority rule satisfied at lower cost (parameters, USD, latency). *Falsified if:* a large LLM+loop exceeds the small model by more than the margin on the primary metric, or large LLMs' zero-shot already saturates the task (then the loop adds nothing for them; report).

## 3. Competing and null hypotheses (must be reported if they win)
- **N1:** the fingerprint GBM is as good as or better than any LLM at every n (a known outcome on small tabular chemistry data) → the paper's claim reduces to the evaluation design and the stereo-resolved result, if any.
- **N2:** large LLMs dominate through prior chemical knowledge (including possible contamination) → report the contamination probe; the small-model claim fails on this task.
- **N3:** apparent gains come from locating one laboratory's series (2020_Townsend holds 52.8 % of within-source hits) → report pick provenance; claims restricted to source-diverse subsets.
- **N4:** feedback does not matter (data-matched one-shot equals the loop; shuffled-label feedback also "improves") → leak or no loop effect; either way the loop claim fails.

## 4. What a retrospective test can and cannot show
Supports: learning from graded feedback, better ranking/selection, sample efficiency, stereo-resolved prediction. Does **not** support: that the model generates better novel molecules (new molecules have no labels); that requires a prospective wet-lab round. The paper states this limit.

## 5. Controls and rules applying to every hypothesis
Five loop controls (data-matched one-shot, random feedback, shuffled labels must not improve, frozen model, knowledge off); a planted-signal positive control per adapter before any null is believed; same seeds/pools across models; contamination-controlled reporting; family-disjoint folds; pre-registered decision rules; every null triggers an audit of our code first, then iteration only as a new registered version.
