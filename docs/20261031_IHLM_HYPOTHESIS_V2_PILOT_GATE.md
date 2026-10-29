# IH-LM hypothesis v2 and pilot gate (written 2026-10-28 ~23:20 CDT, before any backbone result)
Replaces the five-module hypothesis. Reason (owner, 2026-10-28): a hypothesis we cannot expect to hold is not appropriate; keep only what has evidence behind it.

## Evidence by module (what exists today)
| module | evidence | decision |
|---|---|---|
| M3 symbolic analog retrieval (stereo-aware) | nearest-neighbour to revealed compounds beats learned models at k=5/10/25 (AUROC 0.753/0.822/0.869, analysis I); PT-GBM + analog correction leave-labs-out few-label Spearman 0.454/0.429/0.419 | KEEP: the hypothesis |
| M3 neural attention | expected-fail in tests | DROP from hypothesis |
| M1 knowledge-prior fusion | T1/T1b fusion failed its own planted control | DROP (planned, no claim) |
| M2 lab offsets | anchor test null on public data; D1 simulation: no design reaches power 0.80 | DROP (no claim) |
| M4 edit head / M5 dual memory / verifier | verifier AUC 0.529 (expected-fail); edit head recovered 0.835 of planted effect on a toy | no claim |

## Hypothesis H-v2
On held-out laboratories, with 5 to 25 revealed labels, a pretrained peptide-LM backbone (PeptideCLM-2) combined with stereo-aware analog retrieval ranks new peptides better than (a) the same backbone fine-tuned on the revealed labels and (b) fingerprint nearest-neighbour / the PT-GBM + analog-correction baseline.

## Pilot gate (run BEFORE any large compute; CPU/small-GPU, a few USD at most)
Frozen backbone embeddings (no fine-tuning) + the existing retrieval correction vs the strongest existing baseline, same few-label leave-labs-out protocol and folds as the H4b baselines. Hyperparameters chosen on development labs only (source split by sha256(source) mod 2, development half only); gate read on the test half.
- PASS: Spearman on the test half exceeds the best existing baseline (PT-GBM + analog correction, 0.454/0.429/0.419 at the three label budgets) by >= +0.03 at >= 2 of 3 budgets, and the lab-cluster bootstrap 95% CI of the paired difference has lower bound > 0 at those budgets.
- FAIL: otherwise. On FAIL the claim is dropped, reported as a null with its CI, and no fine-tuning compute is spent.
- Margin and rule fixed now, before the backbone has produced any number.
- **Amendment A1 (2026-10-28 ~23:40 CDT, still before any backbone number; owner objection: the data are analog-rich, so nearest-neighbour looks strong):** the PASS criterion above is evaluated on the HARD STRATUM as primary: held-out compounds whose maximum Tanimoto (Morgan r2, 2048 bit, stereo-aware) to ANY revealed compound of that lab/target is in the bottom tercile of the test half (tercile cut computed on the test half's own similarity distribution, per budget). The overall-test-half result is reported as secondary and cannot by itself pass the gate. Baselines in the hard stratum include fingerprint nearest-neighbour (expected near chance there; that is the point) and PT-GBM + analog correction. A win only counts if it beats the best baseline in the hard stratum by >= +0.03 with cluster-CI lower bound > 0 at >= 2 of 3 budgets. If the hard stratum has fewer than 5 held-out labs the gate is reported UNDERPOWERED, not passed.
## After a PASS
Fine-tuned arms (same backbone +/- retrieval, plain larger backbones) in the loop, >= 10 seeds, regimes A/B/L, causal standardisation, controls as in the L7 protocol; cost estimate shown before launch.
