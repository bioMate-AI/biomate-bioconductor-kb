# In-depth comparison of baseline, small and large models in the loop — analysis specification (2026-10-29)

Status: specification only; no result here. Models: baseline (fingerprint GBM, L5), small LLMs (atom LM 25 M; v5; v4 on the mapped subset), large LLMs (≥3 families, in-context, via OpenRouter), chemistry-LM baseline (ChemBERTa-class). All run through the same loop replay (L7) with identical seeds, pools, revealed labels and knowledge, and the five controls. Each dimension below is a pre-specified measurement; the paper reports pros AND cons per model from these, not from impression.

## Dimensions (what is measured, how, and the hypothesis it tests)
| # | dimension | measurement | why |
|---|---|---|---|
| 1 | Sample efficiency | learning curve over revealed labels (0, 25, 50, 100, … 600); labels-to-reach-baseline-final; area under curve | H1 (prior reduces labels needed) |
| 2 | Generalisation | held-out target families (retro_recovery run_s3.py), scaffold-shifted and in-distribution regimes, per fold | H4 |
| 3 | Stereo resolution | within-flat-structure-group Spearman; SAR-setting variant (some isomers revealed) | H2; baseline chance by construction |
| 4 | Shortcut reliance | pick provenance by source (single-lab concentration), similarity to revealed examples, correlation of score with source offset | loop may only find one lab's series |
| 5 | Knowledge use | knowledge-on vs off gap vs n; whether predictions change when a rule is removed/contradicted (counterfactual probe) | H3; does the model use the rule or ignore it |
| 6 | Robustness to bad feedback | shuffled labels (must not improve), 10–30 % label noise, label-scale shift between sources | leak/robustness check |
| 7 | Exploration/diversity | scaffold and flat-structure diversity of picks, redundancy among picks, regret vs oracle | greedy models collapse onto one series |
| 8 | Calibration | whether model uncertainty or confidence tracks error (reliability curve, UCB benefit) | selection under uncertainty |
| 9 | Variance and stability | across seeds, prompt variants (large LLMs), temperature; deterministic reruns | large LLMs are non-deterministic and prompt-sensitive |
| 10 | Contamination/memorisation | memorisation probe on public vs non-public compounds; performance on peptides absent from public sources | large LLMs may have seen CycPeptMPDB |
| 11 | Cost and latency | params, FLOPs, tokens, USD, wall-clock per round and per run; cost per additional hit found | "small ≈ large" must include cost |
| 12 | Failure taxonomy | error breakdown by source, N-methyl count, ring size, size, activity cliffs (identical-fingerprint pairs); case studies of confident wrong picks | where each model fails and why |
| 13 | Interpretability | whether the model's stated rationale (large LLM) or attributions (small) agree with held-out SAR; checked against a rule-only predictor | trust and audit |

## Reporting
For each model: a pros/cons table drawn only from the dimensions above, with confidence intervals; one summary figure per dimension; explicit statement where a model has no advantage. Decision rules for the headline claim (small+loop non-inferior to large+loop, margin 90 %) are in the L7 pre-registration. The baseline's error analysis (docs/20261029_BASELINE_ERROR_ANALYSIS.md, to be written from the current diagnostic) defines dimension 12 for the baseline first.
