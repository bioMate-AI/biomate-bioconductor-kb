# What a benchmark battery would need for method-selection to be a real contribution

Date: 2026-08-11. Follows the Lane-B NO-GO (docs/20260811_MULTIOMICS_LANE_B_GONOGO.md).
Scopes the dataset battery + validation protocol that would let "auto-select the
integration method" become a defensible methods contribution — and the gates that kill it
early if it won't.

## The two conditions selection MUST satisfy (both, or there's no paper)

1. **Winner varies.** The best method must differ across datasets. On our 3 cohorts it
   didn't (MCIA won 2, was tied-oracle on those) → nothing to select.
2. **Winner is predictable from observable features.** There must exist a learnable map
   `data-shape features → best method`. Our own robustness work already found the winner
   was NOT predictable from cheap per-view properties (standalone recovery, label-alignment,
   affinity-concordance all r ≈ 0 to −0.53). **This is the single biggest risk.** If winners
   are unpredictable even in controlled simulation, selection is impossible in principle and
   the program should stop.

A battery that only satisfies (1) gives you a "no universal winner" benchmark (a tool-note
finding, already known). You need (2) for a *selector*.

## Reframe: route across REGIMES, not rank within one

The strongest, most defensible version is NOT "which of 7 paired-bulk methods scores
highest" (that's the MCIA-dominated regime where selection barely helps). It is **"which
integration REGIME does this data require?"** — a *capability* boundary, not a soft score:

| Regime | Data it needs | Methods | Why wrong-regime FAILS (not just scores lower) |
|---|---|---|---|
| Paired-bulk factor/cluster | fully-paired samples, bulk | MOFA2, MCIA, SNF, intNMF, JIVE, MFA, iClusterPlus | already covered |
| Single-cell mosaic / diagonal | partial cell/feature overlap, sc | StabMap, GLUE, MultiVI, MIDAS, scMoMaT | paired methods DROP non-shared samples → inapplicable |
| Vertical single-cell (paired sc) | same cells, multi-modal (CITE-seq, Multiome) | WNN, totalVI, Multigrate | bulk methods ignore per-cell structure |

Routing across regimes is genuinely necessary (using a paired method on mosaic data is a
*correctness* failure, per the prior-art scan), and no shipped tool does it via a plain-
English front door. **But it requires we FIRST package ≥2 mosaic/sc methods (we have none
runnable — StabMap is unpackaged).** That build is the price of admission to Lane B.

## The battery

Use BOTH simulation (controls the axes + gives ground-truth "which method should win") and
real data (external validity). Simulation answers condition (2) cheaply before any real-data
or cloud spend.

### Axes of variation (chosen because they plausibly flip the winner, grounded in method assumptions)

- **Sample/cell overlap:** fully-paired · partial-overlap (mosaic, e.g. 30/60/100%) · disjoint
- **Resolution:** bulk · single-cell
- **Signal structure:** shared-variation-dominant (favors factor: MOFA2/MCIA) · modality-
  specific-clusters (favors fusion: SNF) · non-negative parts (favors intNMF)
- **Degenerate/noise view present:** yes/no (our one validated axis: ARD downweights it;
  equal-weight SNF degrades −0.18)
- **#modalities:** 2 · 3 · 5 ; **dimensionality:** filtered (~5k) · full (~20k+)
- **Goal:** clustering/subtypes · continuous-factor recovery · survival · feature selection

### Simulation arm (condition-2 gate — do this FIRST, ~no cloud cost)

- Bulk multi-omics with known clusters + controllable shared/specific structure:
  **InterSIM** (Chalise & Fridley, CRAN — verify version) or the momix/Cantini simulator.
- Single-cell / mosaic: **scDesign3**, **dyngen**, or **SymSim** for paired sc; hold out
  cells/features to synthesize mosaic overlap.
- Grid: ≥6 axis combinations × **≥20 replicate datasets each** (for CIs) = ~120+ sim datasets.
- **GATE 1:** on simulation, does best-method vary across cells AND can a simple classifier
  (features → best method) beat always-MCIA out-of-fold? If NO → STOP, selection is not
  learnable even under control. If YES → proceed to real data.

### Real-data arm (external validity)

- **Paired bulk, ground-truth subtypes/survival:** TCGA (≥8–10 cancer types with PAM50 /
  iCluster subtypes / survival), CPTAC (proteogenomics), METABRIC. Target ≥15 cohorts.
- **Vertical single-cell:** CITE-seq (RNA+ADT), 10x Multiome (RNA+ATAC), SHARE-seq — cell
  type as ground truth. ≥8 datasets.
- **Mosaic single-cell:** reuse the scMultiBench (2025) curated mosaic scenarios so we
  compare on an established battery. ≥8 datasets.
- Total real: ~30+ datasets so per-regime cells have ≥8 for CIs.

## Validation protocol (what makes it a contribution)

- **Nested cross-validation over DATASETS:** learn the selection rule on a training fold of
  datasets, evaluate on held-out datasets. The selector never sees its test datasets.
- **Baselines it must beat, with CIs (bootstrap over datasets):** always-MOFA, **always-MCIA**
  (the one to beat), always-SNF, random-from-menu, and the current hand-authored cascade.
- **Ceiling:** per-dataset oracle. Report the fraction of oracle−MCIA gap the selector closes.
- **Metric:** task-appropriate (ARI/NMI for clustering, C-index for survival), z-scored per
  dataset so cohorts are comparable, then averaged.
- **GATE 2 (the paper bar):** selector **strictly > always-MCIA** on held-out datasets with
  non-overlapping 95% CIs, AND closes a meaningful share of the oracle gap. If the win is
  driven only by the regime boundary (route sc-mosaic away from bulk methods) and within-
  regime it ties MCIA — that's still a legitimate, honest contribution ("regime routing is
  necessary and sufficient; within-regime, use MCIA").

## Effort, cost, kill criteria

- **Build first:** package ≥2 mosaic/sc integrators (StabMap + GLUE or MultiVI) as
  subworkflows. ~1–2 weeks each incl. validation. Without this, Lane B cannot test its
  strongest claim.
- **Simulation gate:** ~days of compute, cheap. **Do this before anything else** — it's the
  fast kill switch for condition (2).
- **Real-data runs:** ~30 datasets × ~8 methods on AWS Batch = a few hundred jobs; batch it,
  cache normalized inputs (as we already do), budget accordingly.
- **Kill criteria:** (a) Gate 1 fails (winners unpredictable in sim) → stop, write the
  negative result as a caution. (b) Gate 2 fails but regime-routing wins → pivot the paper
  to "regime routing" (narrower, still honest). (c) Both fail → Lane A only.
- **Honest prior:** weak-to-moderate. The within-bulk regime is MCIA-dominated and our prior
  work found winners unpredictable; the live upside is concentrated in the regime boundary,
  which is exactly the part we haven't built yet. So the expected outcome is "regime router,
  not performance selector."

## Recommendation

Sequence: (1) build the simulation harness + run **Gate 1** — cheapest, decides feasibility;
(2) only if Gate 1 passes, package the mosaic/sc methods and run the real battery for Gate 2.
Do not start real-data/cloud spend before Gate 1. In parallel, ship **Lane A** (tool note)
which does not depend on any of this.

### Source-verification note
Named datasets/simulators (InterSIM, scDesign3, dyngen, SymSim, scMultiBench, CPTAC, METABRIC,
CITE-seq/10x Multiome/SHARE-seq) are cited from memory and MUST be verified (exact package
names, availability, licenses) before committing the plan — flagged per citation-integrity.
