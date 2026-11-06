# IH-LM: predictions committed BEFORE any hybrid result (2026-10-29)

Purpose: record, from the data, model and knowledge in hand, which components I expect to work and which not, with probabilities, so the stage-1 and later results can be scored against them. These are judgements from the evidence below, not measurements. No hybrid run, baseline evaluation number or held-out verifier outcome for the hybrid existed when this file was written.

## Evidence the predictions rest on
- Lab shift: leave-labs-out skill ~0.22 vs ~0.67 grouped; two labs hold ~65% of peptides (Townsend 2,881, Kelly 1,518); N-methyl effect strongly context-dependent (pooled +0.554, I^2 0.95).
- Verifier quality (Track E, A2/A3): stop verifier LOSO 0.363 (floor met); held-out permeability verifier LOSO 0.229, n-weighted -0.005, -0.129 on its largest source (weak ranker); physics held-out void (-0.008 on random 120; test on 528 completed void under the rule).
- Pilot 3: library enumeration beat unconditioned LLM generators on constraint-satisfying yield (S-LIB 704.6 vs ChemFM 294.3, P0 284.0, PeptideCLM-2 237.2 per 1000); constraints partly built into the metric.
- Ladder: analog retrieval (M3) is the one consistent effect (+9.5 [6.2, 12.8] in regime L confirmatory), yet the full model stays below GBM/GP/kNN in regime L.
- New-target pilots: lookup (GP/NN) leads from k >= 5; LM embeddings added nothing detectable (underpowered).
- Metric saturation (A4): a percentile scale saturates; SD-AUC relative margin is used instead.
- Rule automaton: sound (false-prune 0/900) but 67% of masked rows hit dead ends before fixes.
- Preference updater: toy control works; real LoRA/DPO smoke was plumbing only (no score gain); gap-stop monitor INCONCLUSIVE in simulation (missed-hack rate 0.273 vs 0.20 required).
- Knowledge: 107 verified entries (statements AI-written, quotes verified); direction check 17 agree / 7 mixed / 0 disagree / 83 untestable on two labs; structure priors stable except interface enrichment; extraction pilot 53% of raw rules pass the exact-quote filter.

## Predictions (probability that the stated outcome occurs)
| # | component / claim | prediction | P |
|---|---|---|---|
| 1 | Hard-rule masked decoding gives rule satisfaction = 1.0 | holds by construction (completed rows) | 0.99 |
| 2 | After fine-tuning under the mask, >= 90% of masked rows complete into valid, rule-satisfying molecules | works, after the dead-end fixes | 0.65 |
| 3 | Hybrid (rules on) matches or beats the library enumerator S-LIB on constraint-satisfying unique novel yield | enumeration keeps the edge on this metric | 0.25 |
| 4 | Soft literature priors (L1) shift sampled distributions in the intended direction (N-methyl, HBD, TPSA, cLogP) | mechanical, will work | 0.95 |
| 5 | L1 beats L0 on the TRAIN verifier (A) | likely (same lab directions) | 0.60 |
| 6 | L1 beats L0 on the held-out permeability verifier (F2) by the margin with CI lower bound > 0 | unlikely: held-out verifier weak, effects context-dependent | 0.20 |
| 7 | Structure-derived priors (L2) change F2 held-out scores detectably | permeability verifier is target-agnostic | 0.10 |
| 8 | L2 improves arm-G recovery on targets with templates (PD-L1, FcRn, BAFF) | small n, few templates | 0.25 |
| 9 | Retrieval-conditioned prompts improve the TRAIN-verifier curve vs no retrieval | strongest prior evidence (M3) | 0.60 |
| 10 | Retrieval improves held-out F2 at the pilot budget | analog lookup helps within series, little on the hard stratum | 0.30 |
| 11 | Graded preference tuning raises the train-verifier curve above the frozen model at B = 1,000-3,000 calls | modest | 0.55 |
| 12 | The same tuning improves held-out F2 by the margin | Goodhart gap likely | 0.15 |
| 13 | Gap-based stopping changes final held-out outcomes at the pilot budget | RL will not run long enough to hack | 0.25 |
| 14 | Hybrid point estimate exceeds the best tuned baseline on held-out F2 | GA/GP-BO strong at this budget | 0.30 |
| 15 | Hybrid exceeds the best baseline by the A4/A5 margin with CI lower bound > 0 on held-out F2 | | 0.10 |
| 16 | The pre-registered gate returns GO | physics family void: gate cannot exceed INCONCLUSIVE | 0.00 |
| 17 | Arm G (blind recovery of held-out binders) shows hybrid above tuned baselines | contamination of the base LM and thin templates | 0.25 |
| 18 | Final primary verdict reads INCONCLUSIVE (not clear GO / NO-GO-detectable) | MDE large vs margin | 0.55 |
| 19 | Scaled extraction: statement-level fidelity of exact-quote-verified rules >= 80% (coordinator audit sample) | quote match checks wording, not meaning | 0.45 |
| 20 | Patent mining pilot passes its pre-registered thresholds (audited precision >= 0.80, structure parse >= 0.60, >= 20 patents) | | 0.30 |

## What I expect to be the paper's supported claims
(1) rule-compiled decoding delivers constraint satisfaction with fine-tuning under the mask (predictions 1-2); (2) knowledge augmentation steers the distribution as intended and helps on the train objective (4, 5, 9); (3) held-out generalisation gains are not expected to be detectable at this budget (6, 7, 10, 12, 15). The evaluation machinery (verifier split, A4 scale, gate error rates) is the part most likely to hold up.

## Use
When stage-1 and later results land, score each row (hit / miss) and report calibration (e.g. Brier score) in the progress notes. A prediction is not a claim of the manuscripts.
