# The generate–verify–select engine — wired, with a worked example

The "生成-验证-学习" engine, now assembled from the components built this session. This documents the
architecture and demonstrates the **select** (decision) layer on real `1yf4` data — the step that turns
disconnected tools into a loop.

## Architecture (components that now exist)
```
GENERATE   BoltzGen (target-conditioned cyclic-peptide design)         -> designs + iptm/pTM/filters
   |
VERIFY     MM-GBSA (automated psfgen cyclic build -> OpenMM GBn2)       -> physics ΔG per design  [non-circular]
   |       Permeability GBM (CycPeptMPDB, R²0.45/Spearman0.75)          -> predicted logPapp        [ranking]
   |
SELECT     multi-objective (Pareto / combined normalized score)        -> ranked "advance these"
   |
LEARN      (next) surrogate on (design -> verified ΔG) for AL triage; FEP on finalists; feed back
```

## Worked example — multi-objective SELECT over the 8 `1yf4` designs (iptm × MM-GBSA ΔG)
Min-max-normalized combined score (iptm + normalized −ΔG); Pareto = non-dominated on (max iptm, min ΔG):

| seq | iptm | ΔG (kcal/mol) | combined | Pareto |
|---|---|---|---|---|
| **FSRNVGDPY** | 0.739 | **−52.7** | **1.99** | ✅ |
| GSGLLKS | **0.740** | −36.6 | 1.43 | ✅ |
| SFEASGFAPM | 0.636 | −43.3 | 1.17 | – |
| SPSINGPMI | 0.577 | −39.7 | 0.75 | – |
| SSLLFVPG | 0.553 | −42.4 | 0.74 | – |
| YVAGQPDPK | 0.579 | −35.7 | 0.62 | – |
| SIYGTGLVPL | 0.533 | −40.2 | 0.56 | – |
| YSGGGGV | 0.635 | −24.3 | 0.49 | – |

## The concrete value of the loop (this is the point)
- **Generation alone can't decide:** BoltzGen's top two, `GSGLLKS` (iptm 0.7405) and `FSRNVGDPY` (0.7393),
  are **essentially tied** on iptm — the generator is indifferent between them.
- **The physics oracle breaks the tie decisively:** ΔG −52.7 (`FSRNVGDPY`) vs −36.6 (`GSGLLKS`).
- **Integrated recommendation: `FSRNVGDPY`** — near-best ML confidence *and* best physics, dominating the
  combined score (1.99 vs 1.43). The Pareto front is {`FSRNVGDPY`, `GSGLLKS`}; everything else is dominated.
- So the wired generate+verify+select engine advances a design that generation-alone would not have
  singled out — exactly what a non-circular verify loop is for.

## 3-objective SELECT (bind × physics × permeability) — added 2026-09-18
Applied the permeability GBM (retrained on RDKit-computed descriptors for feature consistency; designs
head-to-tail cyclized in RDKit) to all 8 designs. Combined₃ = normalized(iptm) + normalized(−ΔG) +
normalized(predicted logPapp):

| seq | iptm | ΔG | pred logPapp | combined₃ | Pareto₃ |
|---|---|---|---|---|---|
| GSGLLKS | 0.740 | −36.6 | −7.77 | 2.16 | ✅ |
| FSRNVGDPY | 0.739 | −52.7 | −8.28 | 2.12 | ✅ |
| YSGGGGV | 0.635 | −24.3 | −7.54 | 1.49 | ✅ |
| SIYGTGLVPL | 0.533 | −40.2 | −7.69 | 1.39 | ✅ |
| SSLLFVPG | 0.553 | −42.4 | −8.08 | 1.10 | ✅ |

**The permeability axis changes the decision:** in 2-objective, `FSRNVGDPY` dominated (1.99 vs 1.43);
adding permeability (it's predicted *less* permeable, −8.28 vs −7.77) offsets its binding edge → `GSGLLKS`
and `FSRNVGDPY` are **near-tied and both Pareto-optimal** — a real bind-vs-permeability tradeoff.

**Important finding the loop exposed:** all 8 designs are predicted poorly permeable (logPapp −7.5 to −8.4).
Partly OOD/coarse model (R²0.24 on RDKit features — relative ranking only), but mainly because **BoltzGen
optimized binding, not permeability**. → Permeability must become a **generation objective** (or a
permeability-focused redesign step), not just a post-hoc filter. This is the concrete gap the engine surfaces.

## Honest caveats
- Two axes only (iptm, ΔG); MM-GBSA is a relative oracle with residual size bias (designs 7–10-mer).
- The **permeability axis is not yet applied to these designs** (the GBM is trained on CycPeptMPDB; scoring
  our designs needs building their cyclic-peptide SMILES + the matching 216 descriptors) — the clear next
  add to make selection 3-objective (bind × physics × permeability).
- Selection here is post-hoc over one generated batch; a true *loop* iterates (below).

## LEARN step — tested; the cheap-surrogate shortcut does NOT work (honest negative, 2026-09-18)
Tested the survey's active-learning idea (train a cheap surrogate on design features → MM-GBSA ΔG to
pre-screen large batches) on the 28 cross-target scored designs:
- **Spearman(iptm, within-target ΔG_z) = −0.04** — the generator's confidence is **orthogonal to physics
  binding**. Sharpest statement of the non-circular-oracle value: iptm carries ~zero within-target physics signal.
- **Surrogate (BoltzGen features → ΔG_z), leave-one-target-out CV: R² ≈ 0.00, Spearman 0.03** — a cheap
  surrogate on generator features **cannot predict/pre-screen physics ΔG**.
- Feature importance: interface descriptors (plip_hbonds 0.33, hydrophobicity 0.17, ΔSASA 0.14) > iptm (0.07),
  but none generalize across targets at this data size.

**Two reasons the shortcut fails:** (1) BoltzGen features genuinely don't predict physics ΔG (⇒ the verify
oracle is *non-circular* and non-optional), and (2) 28 designs / 4 receptors is far too few for a cross-target
surrogate. **Conclusion:** don't pre-screen with a generator-feature surrogate — *run* MM-GBSA on all designs
(affordable) ; a viable surrogate needs physics-informed cheap features (fast minimized interface energy) +
hundreds of scored designs. This makes the "run physics on everything" design correct for now.

## Remaining wiring to a full iterating loop
1. **Permeability as 3rd objective** — apply the GBM to the designs → 3-way Pareto/qNEHVI.
2. **LEARN step (active learning)** — train a cheap surrogate on (design features → verified ΔG); next round
   BoltzGen generates a larger batch → surrogate pre-screens → only top candidates get MM-GBSA → select →
   update surrogate → repeat (the sample-efficient regime from the optimization survey).
3. **FEP finalist tier** — ATM/FEP+ on the Pareto set (`FSRNVGDPY`, `SFEASGFAPM`) as the length-controlled arbiter.
4. **Productionize on BioMate** — the campaign engine per docs/BIOMATE_CLOSED_LOOP_INTEGRATION.md.
