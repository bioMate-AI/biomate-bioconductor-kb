# Bet 1 design — developability-aware, experiment-native cyclic-peptide generation

The differentiated capability from [[INNOVATION_ASSESSMENT]] Bet 1, made concrete on the
now-validated PepGLAD backbone ([[BASELINE_RESULTS]]: DockQ 0.51, Cα-RMSD 5.1 Å, Consistency
0.91 on LNR test) and the data we collected ([[DATA_COLLECTION_PLAN]]).

## Thesis
Collapse "generate → filter → Bayesian-optimize" into **one learned system**: a pocket-
conditioned all-atom generator that samples cyclic peptides **guided toward a target
developability profile under predictor uncertainty**, so each design round proposes candidates
that are both promising and maximally informative for the next assay. Developability is
first-class, not a post-hoc filter. This is the capability that makes the shared-backbone /
per-modality-plugin architecture valuable and lets the private-data moat compound.

## Foundation (reuse, do not rebuild)
- **Backbone:** PepGLAD autoencoder (72% reconstruction) + latent diffusion, pocket-conditioned,
  all-atom. Validated. Crucially, PepGLAD already has a **latent-guidance mechanism**
  (`setup_latent_guidance.py` + `latent_geometry_guidance`) — we graft property guidance onto
  the same hook rather than inventing a sampler.
- **Eval harness:** official `generate.py` + `cal_metrics.py` (DockQ/RMSD/Consistency/Diversity)
  + our `generate_validation.py` (slide_aar + baselines). Trusted.

## Components

### A. Cyclic-peptide plugin (Axis-1: chemistry/topology)
The first plugin on the backbone. Adds what general PepBench lacks:
- **Macrocyclization**: head-to-tail and disulfide closure as explicit edges + a closure loss;
  validate requested-vs-observed topology (cyclic ≠ correct closure).
- **Non-natural monomers**: map the HELM monomer library into the atom/block vocabulary
  (stapled / N-methylated / D-amino-acid support).
- **Train/eval data**: PepBDB cyclic subset (799 train / 91 test, leak-free), RCSB cyclic index
  for breadth; CycPeptMPDB structures for permeability-paired cyclics.

### B. Developability predictors (the "verify", learned + calibrated)
- **Permeability**: train on CycPeptMPDB (~7k PAMPA); reuse the existing permeability models in
  S3 as a starting point.
- **Stability**: train on PepMSND using the **leak-free folds we rebuilt** ([[pepmsnd-fold... ]]
  → `results/pepmsnd_fold_rebuild.json`).
- **Uncertainty**: deep ensemble or evidential head → calibrated predictive variance (required
  for the acquisition objective, not just point estimates).
- **Applicability domain**: flag out-of-domain candidates independently of novelty.

### C. Developability-guided generation (Axis-2: conditioning)
Two routes, start with (i):
- **(i) Guidance at sampling time** — add a property-gradient guidance term to the latent
  diffusion sampler (analogous to PepGLAD's geometry guidance): steer samples toward the target
  permeability/stability profile, weighted by predictor confidence. Cheap, reuses existing
  machinery, no retraining of the backbone.
- **(ii) Reward fine-tuning** — if guidance underperforms, fine-tune the generator with a reward
  = property gain + info-gain. Heavier; only if (i) plateaus.

### D. Experiment-native acquisition
Rank candidates by **expected property improvement + expected information gain** under the
predictor's uncertainty (not just predicted mean). Validate the *policy* with the offline
replay we already built (`replay_permeability.py`): hide labels → select → reveal → retrain →
compare to random at equal label budget (the pilot already showed guided > random on
top-decile recovery).

## Phased plan
1. **Cyclic plugin** — closure + monomer handling; train on PepBDB cyclic; success = DockQ/RMSD
   comparable to the general baseline **and** ≥95% correct-closure validity on held-out cyclics.
2. **Predictors** — permeability + stability with calibrated uncertainty; report AUROC/MAE +
   calibration (ECE) on the leak-free test folds.
3. **Property-guided generation** — add guidance; measure predicted-developability uplift vs
   unguided **at equal validity/diversity/DockQ** (must distinguish real improvement from
   stronger filtering or a bigger sampling budget — PLAN §4).
4. **Acquisition** — EI + info-gain selection; offline-replay validation vs random and vs
   greedy-mean.
5. **(gated) Prospective DMTA** — needs a wet-lab / CRO feedback channel (the moat's gating
   resource; not currently available). Until then, in-silico surrogate only.

## Evaluation
- **Design quality**: DockQ, Cα-RMSD, Consistency, Codesign Diversity (official harness).
- **Cyclic validity**: closure correctness, stereochemistry, monomer legality.
- **Developability**: predicted permeability/stability distribution of generated cyclics +
  calibration; uplift vs unguided baseline.
- **Acquisition**: label-efficiency curves (top-decile recovery, MAE-vs-budget) vs random/greedy.

## Risks & honesty
- **The moat needs wet-lab.** Without a real assay-feedback channel, "learn" is simulated
  (offline replay), not prospective. State this to the partner; do not imply a closed DMTA loop.
- **Guidance can trade off validity/diversity for predicted property** — always report the
  tradeoff, and never claim improvement that's actually just heavier filtering.
- **Predictor domain limits** — CycPeptMPDB/PepMSND are modest; predicted developability is a
  surrogate, not measured potency/PK. Applicability-domain warnings mandatory.
- **Compute** — A10G OOMs at `ubound_per_batch=60000`; cyclic-plugin runs use ~40k or a bigger GPU.
- **No leaderboard/experimental claim** until blinded held-out results (and, for the moat,
  prospective measured endpoints) exist ([[vcc-external-intel-is-hypotheses]]).

## Immediate next step
Phase 1: implement the cyclic plugin (closure edges + loss + HELM monomer mapping) and train on
the 799 PepBDB cyclic complexes; evaluate closure validity + DockQ/RMSD on the 91 held-out
cyclics with the trusted harness.
