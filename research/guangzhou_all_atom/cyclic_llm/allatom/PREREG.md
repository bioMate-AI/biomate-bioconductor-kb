# PRE-REGISTRATION: all-atom cyclic-peptide LLM with rules, knowledge and feedback — retrospective evaluation on measured data (committed 2026-10-27 BEFORE any model is trained)

## Question
Does an atom-level language model of cyclic peptides, with rules/knowledge integrated as constraints/priors/rewards and updated from feedback, recover measured high-permeability cyclic peptides from LABORATORIES IT HAS NOT SEEN better than (a) an unconstrained atom-level LM, (b) the existing monomer-level (HELM) model, (c) a rule-only enumerator, and (d) a trivial rule (rank/generate by N-methylation)? Retrospective, computational; wet-lab confirmation is version 2.

## Data and splits (fixed now)
* Labels: CycPeptMPDB PAMPA rows (log Papp; detection-floor -10.0 removed; duplicate structures averaged), 56 literature sources. Hit = top 10 % of measured permeability in the full set (threshold fixed now: -4.82, as in the loop study).
* Held-out laboratories: sources are split by `Source` into TRAIN-sources and HELD-OUT-sources before anything is trained: sort sources by a hash of the source name, hold out ~25 % of peptides (whole sources). Held-out peptides and every molecule within Tanimoto >= 0.9 (Morgan r=2, 2048 bits) of one are REMOVED from every training, fine-tuning and pretraining corpus, including the large public corpus.
* Pretraining corpus: a large public SMILES corpus (ChEMBL), filtered the same way against the held-out set.
## Systems compared (equal sampling budget N = 20,000 valid unique molecules per system)
S_base: atom-level LM (SELFIES or SMILES with macrocycle closure tokens), pretrained then fine-tuned on TRAIN-source cyclic peptides, no conditioning.
S_cond: S_base + conditioning on a permeability bin (from TRAIN labels only).
S_rule: S_cond + rules as HARD constraints at decoding/rejection (ring size 6-12, valid closure, N-methyl count >= 1, no liability flags from the in-repo liability library).
S_rl: S_cond fine-tuned with a verifiable reward (rule satisfaction + a permeability predictor trained ONLY on TRAIN sources), no held-out label used.
S_loop: S_rl plus 3 feedback rounds in which 200 TRAIN-source peptides per round that the loop selects are "assayed" (their labels revealed) and the model/predictor is updated.
Baselines: B_helm (existing monomer-level model, same budget), B_enum (rule-only enumerator), B_nme (rule: take the most N-methylated valid molecules from the unconditioned S_base samples), B_random (random valid molecules from S_base).
## Metrics
Validity (parses, ring closure valid, macrocycle present); uniqueness; novelty vs TRAIN; and PRIMARY: **hit recovery** = fraction of held-out-source top-decile peptides that have a generated molecule at Tanimoto >= 0.7 (Morgan r=2, 2048 bits), and the same at 0.5 (secondary). The number of near-neighbour matches is the metric; no model-predicted permeability is used to score generation.
Statistics: 5 independent sampling seeds per system; paired bootstrap over held-out peptides (resample held-out peptides, 4,000 resamples); 95 % percentile intervals.
## Claim rules
C1 (rules/knowledge help): S_rule or S_rl exceeds S_cond AND exceeds B_nme in hit recovery at 0.7, with 95 % interval of the difference excluding 0.
C2 (feedback helps): S_loop exceeds S_rl with interval excluding 0.
C3 (atom-level helps): best atom-level system exceeds B_helm with interval excluding 0.
Each claim is reported as supported / not supported; a null is a result. No system, threshold or metric may be changed after any held-out number is seen; changes only as dated amendments here.
## Disclosure
Prior measured facts that motivated this design (2026-10-27): in a retrospective selection loop on the same data, an N-methyl-count rule alone recovered 70-83 % of the learned loop's yield, and adding literature descriptors as model INPUTS did not help; hence rules are tested here as constraints/rewards, and B_nme is a mandatory baseline.

## Amendment A1 (2026-10-27, before any model was trained) — within-source hits and a 4-fold source-grouped design
Why (data checks made before any model existed): (1) with pooled labels, 78 % of top-decile peptides come from one source, and the original hash split held out only 12 hits (see loop_retro PREREG_LOOP L3); (2) with within-source labels the original split holds out 184 hits, but 156 of them come from one laboratory (2021_Kelly), so one split would test one laboratory, not laboratory-to-laboratory generalisation.
Changes. (a) A hit is the top 10 % of within-source standardised permeability (sources with >= 20 peptides standardised separately; smaller sources pooled as one group), threshold 1.093 on the standardised scale. (b) The split is replaced by 4-fold source-grouped cross-evaluation: sources sorted by size, each assigned in turn to the fold with the fewest peptides so far (deterministic; large laboratories land in different folds). For each fold, the model is fit on the other three folds and evaluated on the held-out fold; hit recovery is reported per fold and pooled, with a bootstrap over held-out peptides. (c) The pretraining corpus is filtered ONCE against ALL CycPeptMPDB peptides (Tanimoto >= 0.9, Morgan r=2, 2048 bits) so that a single pretrained model serves every fold without leakage; fine-tuning is per fold on the fold's training peptides, themselves with near-duplicates of the held-out peptides removed.
Unchanged: systems, baselines, budget, metrics, claim rules C1-C3 (now computed on the pooled recovery across folds, plus per-fold direction consistency).
