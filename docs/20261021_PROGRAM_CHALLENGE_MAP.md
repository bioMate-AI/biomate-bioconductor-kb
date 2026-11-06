# Cyclic-Peptide / Drug-Design Program — Challenge Map (active re-grounding)

**Date:** 2026-10-21 · Purpose: re-ground the program in the FULL documented challenge set after a session
that worked too narrowly (fixated on the novel-target affinity-prediction ceiling) and too passively.
Sources traced inline. Status vocab: solved / validated-with-results / built-synthetic / designed-only /
open / unsolved-SOTA-bound.

**Program's own recurring honest framing** (from `20261005_CHALLENGE_INVENTORY_RECOVERED.md`,
`INNOVATION_ASSESSMENT.md`): the defensible contribution is the **integrated closed-loop SYSTEM +
proprietary data + prospective validation**, and **differentiation = how the pieces fuse + attacking
what commodity generators cannot** — NOT "we beat SOTA on affinity prediction." The recent session
spent itself on the one axis the whole field defers (zero-shot novel-target affinity), re-confirming a
known frontier, while the system/loop/generation challenges that are the actual moat sat idle.

---

## 1. Challenge-by-challenge map

| # | Challenge | Grounded status + number | Documented lever | Being worked? |
|---|---|---|---|---|
| C1 | **Novel-target affinity prediction (zero-shot)** | **unsolved-SOTA-bound.** Convergent ~0.42 ceiling across ECFP/ChemBERTa/concat/interaction/few-shot (2026-10-21); OOD PD-L1 0.18→~0.42; cross-target LLM NULL. In-dist 0.736. Public data SATURATED (ChEMBL+BindingDB already merged). | more data / physics-grounding — NOT a bigger model | **OVER-worked** (whole session); confirmed field frontier (SOTA 3–8% hit) |
| C2 | **Closed-loop LEARNING validated retrospectively** | **built-synthetic only; NOT validated.** DPO/DBTL wired, self-tests green, but fed only VERIFY_SELECT pairs — "close-back works; not yet fed real signal." | **Hold out targets on the 136k real affinities + display-NGS, feed real preference signal, show generator/selector measurably improves — doable NOW, explicitly NOT gated** (inventory). | **IGNORED** — the central thesis, and tractable today |
| C3 | **Generator accuracy (DockQ)** | **built, plateaued.** cyclic-FT DockQ **0.506 vs UniMoMo 0.759** (linear-only, in-dist). UniMoMo-adapter 0.7754 claim is UNCONFIRMED (run failed, MKL). | all-atom FT (untried lever); resolve UniMoMo repro; BoltzGen cyclic FT LOTO (`i-0f77b…` pending) | **PARKED** |
| C4 | **Permeability (the real wall)** | **built, OOD weak.** gate R²0.45, OOD R²**0.19**; ML ECFP R²0.23. Validation-ladder dx: signal is **DYNAMICAL (chameleon H-bond shielding)** — static ECFP structurally can't capture it. | **MD / implicit-solvent PMF / CycPeptMPDB-4D solvent sims + MacroConf NMR (all collected, unused)** — the RIGHT method | **IGNORED** (we kept testing static ML, the wrong tool) |
| C5 | **Novel-target binder design via physics prior** | **built + locally verified, NOT launched.** RFpeptides preflight OK, 0 results. Lit bar 12/39 targets, ~9.4 nM (canonical-AA). | launch `launch_rfpeptides.sh`; physics-prior design is the path ML can't do | **PARKED** (never fired) |
| C6 | **Validation ladder rungs 1–2** (cheap computational) | **partial.** Rung-1 metrics running (`cyclic_official_eval`); self-consistency/designability + Rung-2 physics (relax→MD stability→MM-GBSA) mostly **TODO**. Assets present (PepGLAD OpenMM relaxer — one-line CUDA bug noted). | run the ladder before any wet lab; physics is the non-circular oracle for ML iptm/pae | **PARKED** |
| C7 | **Selectivity / counter-target** | **identified, NOT built.** Omitted from multi-objective (single-target data). | counter-target screen (e.g. PD-L2 for PD-L1; MIDAS-site specificity for αvβ6) | **IGNORED** |
| C8 | **Neurosymbolic generation (rules∧generator)** | **designed/surveyed, not built.** Rounds showed rules = good filter / poor generator (rule-fixed scaffold → only patented genus). | **SNG** (arXiv:2510.23379): ILP learns rules from few instances → constrain a neural generator → (rules, molecules) | **IGNORED** (documented lever, un-built) |
| C9 | **DBTL/DMTA platform loop completeness** | **built (simulated); 40% complete.** BO not API-wired; G6 (real CRO SPR KD) + G7 (checkpoint auto-promotion) OPEN. | wire BO to API; close G6/G7 (G6 needs real assay) | **PARKED (G6 external)** |
| C10 | **Within-target binder ranking / cold-start designability** | **within-target validated but eval was CIRCULAR** (2026-10-21: is_binder ≈ enrichment threshold, abundance null AUC≈1.0; LM < null). Cold-start LOTO ≈ random (0.44). | non-circular label (measured affinity, novel seqs); cofold pre-screen (~43% saved) | **mis-addressed** (circular eval) |
| C11 | **Multi-objective selection** | **validated-with-results.** qNEHVI +37.6%, greedy-HV +115% vs composite (PD-L1). | qNEHVI (done) | **SOLVED-ish** |
| C12 | **Target-ranker generalization** (separate subsystem) | **validated.** 16/16 + 16/16 live; ERBB2 #24→#1. | scorecard ranker (done) | **SOLVED-ish** |
| C13 | **Data scarcity** | **have real data; per-target SPARSE.** 136,730 binding (36,102 cyclic), CREMP 36,198, perm 8,466; but **median 5 cyclic cpds/target**, only 138 targets ≥50 — this sparsity drives C1. | proprietary display-NGS; new assay data | partial |
| C14 | **Safety / tox** | **honest proxy only** (`stability_predictor`). | real tox oracle | **IGNORED** |
| C15 | **Physics↔measured-affinity validation** | **open; capability EXISTS (no build).** openfe_rbfe (FEP, OpenFF, handles SMILES) + diffdock-smiles already present; gate is a wiring/run, not a build. Measured αvβ6/PD-L1 cpds = 100% non-peptidic SMILES. | diffdock screen → **openfe_rbfe FEP** on congeneric measured pairs (FEP ≫ MM-GBSA) | **now being scoped** |

---

## 2. Synthesis

### (a) What the recent affinity-model work did NOT address
The 2026-10-21 session worked **only C1** (and re-touched C10/C15). It produced genuine rigor — leakage-safe
grouped CV, the abundance-null circularity catch, the data-saturation finding, the convergent ~0.42 ceiling —
but every result **re-confirmed a frontier already documented** (`CROSS_TARGET_SOTA_COMPARISON`: SOTA itself is
3–8% and defers zero-shot). It advanced **none** of C2, C3, C4, C5, C6, C7, C8, C9, C14. It mistook one axis
(the hardest, field-unsolved one) for the whole program.

### (b) Highest-leverage challenges currently NOT being worked
1. **C2 — closed-loop retrospective learning on the 136k held data.** This is the *actual thesis* (system +
   data + validation as the moat) and the inventory says it is **doable now, not gated**. Highest leverage ×
   tractable. Being ignored.
2. **C4 — MD-based permeability.** The permeability wall is the documented commercial differentiator, the
   static-ML failure is *diagnosed* (wrong method), and the right-method assets (CycPeptMPDB-4D, MacroConf NMR,
   OpenMM relaxer) are **already collected and unused**. High leverage, tractable.
3. **C3 — generator DockQ plateau + UniMoMo repro.** Generation quality is core; 0.506 vs 0.759 is a real gap;
   the all-atom-FT lever is untried and the UniMoMo 0.7754 claim must be confirmed or killed.
4. **C6 — the cheap validation-ladder physics (relax→MD→MM-GBSA)** on BoltzGen designs: the non-circular oracle
   we keep *planning* and not running.
5. **C7 — selectivity**, never built, and it's a concrete investor/partner objection-remover.

### (c) Untried / under-exploited levers (documented, un-fired)
- **All-atom fine-tune** (C3) — flagged "untried lever"; the prior "modeling can't win" came from SMALL-model fails.
- **Physics-grounding via FEP** (C15) — capability already exists (openfe_rbfe); the gate is unrun, not unbuilt.
- **RFpeptides physics-prior novel-target run** (C5) — built, never launched.
- **CycPeptMPDB-4D / MacroConf-NMR MD permeability** (C4) — collected, unused.
- **SNG neurosymbolic generation** (C8) — the surveyed "rules∧generator" answer to the patented-genus trap.
- **Retrospective loop-learning replay** (C2) — the one that would turn "built-synthetic" into "validated."

---

## 3. What to actively drive next (prioritized, not gated-on-asking)

1. **C2 — Retrospective closed-loop learning (DRIVE NOW).** Hold out targets on `binding_affinity_v1` + display-NGS;
   feed real preference pairs to the DPO/selector; show measurable generator/selector improvement on held-out
   targets. Converts the central thesis from "wired" to "validated." CPU-feasible; no external gate.
2. **C4 — MD permeability (DRIVE NOW).** Run the collected CycPeptMPDB-4D / implicit-solvent PMF / MacroConf-NMR
   pipeline against our designs; replace the static-ECFP R²0.19 with the dynamical method. Fix the OpenMM-relaxer
   CUDA one-liner.
3. **C15 — Physics↔affinity FEP gate (SCOPED, cheap screen running).** Finish the diffdock screen; cost+fire the
   openfe_rbfe FEP on congeneric measured pairs — the result decides whether physics-grounding can lift C1 and
   validates the engine vs experiment.
4. **C3 — Generator: resolve UniMoMo repro + fire the all-atom FT / BoltzGen-cyclic LOTO** (`i-0f77b…` pending).
5. **C6 — Run the validation-ladder physics** (relax→MD stability→MM-GBSA) on BoltzGen designs as the standing
   non-circular oracle.
6. **C7 — Build the selectivity counter-screen** (PD-L2 for PD-L1; MIDAS specificity for αvβ6).
7. **Frame the honest publication** around the SYSTEM + the rigorous negatives (C1 ceiling + abundance-null
   circularity + cross-target = field frontier), per the program's own "moat is the loop, not SOTA" framing.

**Blunt bottom line:** the affinity-prediction ceiling is real and settled — stop re-litigating it. The leverage
is in C2 (retrospective loop learning), C4 (MD permeability), and C3 (generator), all tractable and all currently
idle. Drive those.
