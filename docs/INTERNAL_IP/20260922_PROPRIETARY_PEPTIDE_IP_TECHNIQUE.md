# Proprietary peptide-generation IP — developability-conditioned all-atom co-design

**Date:** 2026-09-22 · **Purpose:** define the proprietary model technique BioMate holds inside the
platform it sells to pharma. The base peptide co-design model (PepGLAD-class) is public science; the
IP is what we build ON it. This is not a reproduction — it is a novel method.

## Business frame (settled)
We SELL the platform; we HOLD proprietary IP technique. The generator being publicly-reproducible is
irrelevant — the moat is the *technique we own* + the closed loop. This doc specs the technique.

## The technique: developability-conditioned generation (DCG)
Standard peptide generators (PepGLAD, PepFlow, RFpeptides) sample for **binding pose only**, then
filter for developability after the fact. DCG **steers the generative process itself** toward candidates
that are simultaneously high-affinity AND developable — the three tender axes baked in:
- **target affinity** (binding),
- **synthetic accessibility** (makeable),
- **safety/permeability** (drug-like, membrane-crossing for cyclics).

### Method (novel combination)
1. **Property predictors → differentiable guidance heads.** Train/attach lightweight predictors for
   {permeability (3D-PSA/our perm model), SA, predicted ΔG/affinity, hERG-proxy} that operate on the
   model's latent or all-atom output. Each yields a differentiable score.
2. **Multi-objective classifier(-free) guidance during sampling.** At each diffusion/flow step, nudge the
   sample along ∇(weighted sum of property scores) — a Pareto-weighted guidance vector, not a single
   objective. Weights are the customer's target product profile (potency-first vs ADMET-first).
3. **Guidance schedule.** Strong structure/affinity guidance early (get a binder), developability
   guidance ramped late (refine to makeable/permeable) — avoids the NaN/mode-collapse we saw with the
   naive PH penalty.
4. **Closed-loop preference fine-tuning (phase 2).** Fine-tune the generator with DPO on
   (preferred, rejected) pairs ranked by the verify layer (dock/FEP/ADMET), then by real assay data as
   it accrues — the generator improves from the loop. This is the piece competitors structurally cannot
   copy (our accumulating wet-lab data).

### Novelty — honest calibration (do NOT over-claim this piece)
In-sampling multi-objective guidance is **PRIOR ART**, not our invention: classifier / classifier-free
guidance is standard, and property-guided molecular diffusion is published (EEGSDE, multi-objective
guided molecule generation, etc.). We do NOT claim DCG-as-guidance as novel IP — a reviewer would
dismantle that. DCG is **necessary table-stakes capability** (it's how the platform conditions on the
three tender axes) and it is **product-shaped** (outputs developable candidates, not a leaderboard DockQ)
— but it is a *capability we must have*, not the differentiator.

**Where the genuinely defensible IP actually is (relocated here honestly):**
- **#1 — all-atom generation over NON-CANONICAL macrocycle chemistry** (staples / N-methylation / D-amino
  acids / non-peptidic linkers). Public peptide generators are essentially all canonical-20-AA; a
  generator over the *real* macrocycle-drug chemical space is genuinely under-served — this is our
  strongest true-novelty candidate.
- **#4 — closed-loop preference optimization on PROPRIETARY wet-lab data.** The *method* (DPO/RLHF for
  molecules) is not novel; the **moat is the data** — no competitor has our accumulating assay feedback.
  Defensibility here is data + system, not algorithm.
- **#3 — hard cyclic-manifold sampling** in our specific all-atom + non-canonical setting: the general
  idea of manifold-constrained generation exists, but the concrete hard-closure-over-non-canonical-rings
  formulation is where a specific, non-obvious claim can live.

**IP claim should be the composite system** (non-canonical macrocycle generation + developability
conditioning + closed-loop data), emphasizing the non-obvious parts (#1 representation + #4 data loop),
NOT "multi-objective guidance," which is prior art.

### Why it's feasible now (build order)
- **P0 (prototype on the existing 0.516 checkpoint — no retrain needed):** implement guidance heads +
  multi-objective guidance at sampling time; measure whether guided samples improve SA/permeability at
  equal-or-better DockQ vs unguided, on a held-out target set. Fast, cheap (inference-only).
- **P1:** integrate the perm model + SA + a docking/ΔG proxy as the guidance signals.
- **P2:** DPO fine-tune against the verify layer; then wire assay-data feedback.

### Honest contract
These are hypotheses to benchmark, not guaranteed wins. Success = guided generation Pareto-dominates
unguided (better developability at equal affinity) on a leakage-clean held-out set. Report the honest
trade-off curve, not a cherry-picked point.

## The full cyclic stack: 1 + 2 + 3 + 4 (not 1+2+4)
Correction: #3 (hard ring closure) is NOT optional and NOT redundant with #2's guidance — the soft
ring-closure penalty (MacroGuide PH) already FAILED (NaN/no-op). #3 is the principled replacement and is
necessary for any *cyclic* product. #2 and #3 are complementary sampler techniques that compose: guidance
steers WHERE on the ring manifold; the projection keeps the sample ON it.

- **#1 — all-atom generation over non-canonical macrocycle chemistry** (staples/N-Me/D-AA) — biggest gap,
  the real drug space; larger effort (new representation).
- **#2 — developability-conditioned guidance** (this doc) — the three tender axes baked into sampling.
- **#3 — hard ring closure / cyclic-manifold sampling** — every emitted structure a valid macrocycle *by
  construction*, replacing the failed soft penalty. Three ambition levels:
  - **3a (buildable now):** a hard-projection step in the PepGLAD *sampling loop* — after each denoising
    step, SHAKE/LINCS-style project the generated backbone onto the closed-ring manifold (first↔last bond
    length + local geometry). Small sampler-loop edit (not the soft `energy_func` hook). Composes with #2.
  - **3b:** constrained flow-matching on the ring manifold (medium rebuild).
  - **3c:** full Riemannian flow-matching where the closed-ring manifold IS the sample space (ambitious).
- **#4 — closed-loop preference optimization (DPO)** on verify-layer + wet-lab rewards — the compounding
  moat; improves the generator from the loop.
- **(supporting) retrieval-augmented generation** for the data-starved cyclic case.

Build order for the cyclic core: **#2 (guidance, built) + #3a (hard closure, next)** are the two
sampler-level upgrades that ship first and together; #1 and #4 are the larger program.

## Parallel: base model to parity
`pepglad-…195318Z` (i-0a492865087618702): half-batch config, 300 epochs → target DockQ ~0.59 (paper
parity). Parity is the credibility floor; DCG is the differentiation.

## Change log
- 2026-09-22 — created; specs developability-conditioned generation as the first proprietary IP technique,
  with a build order that prototypes on the existing checkpoint (no retrain) and a phase-2 closed-loop DPO.
