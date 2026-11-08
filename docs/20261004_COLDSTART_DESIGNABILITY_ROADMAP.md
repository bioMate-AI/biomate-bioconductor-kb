# Cold-Start Designability Generalization — Why It's Open and How to Close It

**Date:** 2026-10-04 · Companion to [`20261004_SPEED_SURROGATE_DESIGNABILITY.md`](20261004_SPEED_SURROGATE_DESIGNABILITY.md).
**Scope:** the one unsolved piece of the "faster" axis — predicting designability (refold
self-consistency, scRMSD < 2 Å) for a design on a **brand-new target with zero prior folds**.
Within-target triage is already solved (~43 % PD-L1 co-fold saved); this doc is only about cold-start.

## What is solved vs open
- **Solved — within-target triage.** Fold a seed batch, train, triage the rest. Combined
  (sequence + generation-time confidence) features: triage-relevant AUC 0.624; seed-and-triage sim
  saves ~43 % ± 9 of remaining co-folds on 5o45/PD-L1 at 80 % recall. This is the operational win.
- **Open — cold-start.** Predict designability on a target with no prior folds. Current status:
  chance-to-unreliable (LOTO combined 5o45 0.73 but 1u8p 0.44).

## Why cold-start fails (two separable causes)
1. **Wrong features.** Designability = *sequence↔structure compatibility* (does the sequence's energy
   landscape fold to the designed backbone). Sequence composition and CA-trace geometry are both too
   coarse to measure that — both ≈ chance (sequence-only within AUC 0.544; CA-geometry within-run
   0.470). The generator's own `design_iptm`/`pae` *does* capture it (learned, structure-conditioned),
   which is why it works within-target.
2. **Base-rate non-transfer.** Designable rate swings 8 %→98 % across targets. A classifier that
   learns absolute probabilities cannot transfer when the base rate itself does not — `design_iptm`
   learned a 5o45-appropriate operating point (0.73) that was wrong for 1u8p (0.44).

Ruled out (tested, negative): sequence-only features, CA-only backbone geometry, a richer 127-feature
scalar BoltzGen set (no macro gain vs 8).

## Routes to close it (ranked by expected payoff)

### A. Inverse-folding self-consistency likelihood (ProteinMPNN / cyclic-aware variant) — strongest bet
Score `P(sequence | designed backbone)` under a structure-conditioned inverse-folding model trained on
the whole PDB. High likelihood = sequence fits its backbone = designable. **Transferable by
construction** (generic sequence-structure physics, not target-specific) and the field-standard
designability proxy — the exact quantity the slow refold pipeline approximates. It is **distinct from
BoltzGen's `design_iptm`** (different model and objective), so it is new information, not a re-derivation.
- Cost: one forward pass (~seconds, no MSA) vs ~90 s co-fold. CPU-feasible.
- Dependency: ProteinMPNN (or a cyclic inverse-folding model) stood up locally.
- Risk: cyclic head-to-tail topology needs a cyclic-aware model or a linear approximation with a
  closure correction.

### B. Rank-transform + learning-to-rank — cheap, no new data, testable immediately
Attack the base-rate problem directly: rank-normalize the label (and features) **within each training
target** before pooling, and train to predict the *relative* designability ranking, not an absolute
probability. Removes the per-target operating point that broke transfer. Does not fix the "wrong
features" problem, but should recover 1u8p-type failures. **Runs on the existing 949-design set today,
zero dependencies.**

### C. Scale target coverage — data work, no wet-lab
7 targets is far too few for cross-target ML. More of our own runs are on S3, plus public cyclic
designability benchmarks (RFpeptides / HighFold / AfCycDesign self-consistency sets). Train on 20–50
targets → cold-start becomes interpolation with coverage rather than extrapolation from 6.

### D. Richer structure + target-context features — partial
Full-backbone (N/Cα/C/O) local geometry, Ramachandran / clash / rotamer-strain of the designed pose
(local foldability CA-only missed), plus a target-pocket embedding so an unseen target is placed
relative to known ones. Cheaper than A, weaker.

## Honest ceiling caveat
Part of designability is genuinely **target-specific** (pocket geometry drives the 8 %-vs-98 % spread).
A target-agnostic surrogate therefore has a ceiling: route A captures the peptide's *own* foldability
(the transferable part) but not "is this pocket easy." Full cold-start parity with within-target may
require a target embedding and may simply cap below within-target performance. This is stated up front,
not promised away.

## Recommended order
1. **Now, free:** B (rank-transform / learning-to-rank) on existing data — measure whether it moves
   1u8p off sub-chance.
2. **Next, model (CPU-ish):** A — ProteinMPNN / cyclic inverse-folding self-consistency likelihood as
   a feature. The real lever.
3. **In parallel:** C — harvest more targets for coverage.

## Pointers
- Surrogate + data + results: `speed_surrogate.py`, `data/processed/designability_v1.csv`,
  `results/speed_surrogate_loto.json`.
- Pose featurizer (tested infra for D / any structure model): `pose_features.py`.
- Full results and negative results: `20261004_SPEED_SURROGATE_DESIGNABILITY.md`.
