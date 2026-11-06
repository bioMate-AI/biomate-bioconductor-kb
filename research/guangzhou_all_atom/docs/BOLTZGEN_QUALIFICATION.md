# BoltzGen qualification — PASSED, and it supersedes much of our bespoke work

The backbone pivot (PepGLAD → BoltzGen) qualified on the first clean run.

## Result
`boltzgen run <cyclic example> --protocol peptide-anything` produced **55 ranked cyclic designs
in ~12 min** (10 intermediate → diversity-optimized final set). Native macrocyclization via the
covalent-bond design spec — the closure gap our PepGLAD latent-guidance could not close (stalled
at ~7 Å, 0% bond-distance) is handled out of the box. Artifacts:
`results/boltzgen_qualify.json`, `results/boltzgen_cyclic_designs_metrics.csv`.

## What BoltzGen gives natively (rank-1 design STDLLKGK, 8-mer cyclic)
| Category | BoltzGen output | We had built this as… |
|---|---|---|
| Native cyclic closure | covalent-bond spec (head-to-tail/disulfide/staple) | latent closure guidance (failed) |
| Binding | design_to_target_iptm 0.63, design_ptm 0.88, interface PAE | DockQ via separate cal_metrics |
| Structure/designability | filter_rmsd 1.13, bb_designability_rmsd<2 = True | RMSD via cal_metrics; no self-consistency |
| Interface | PLIP H-bonds, ΔSASA, salt bridges | — |
| **Developability liabilities** | DPP4/tryptic proteolysis, Met/Trp oxidation, hydrophobic patch, Asp cleavage | our stability predictor (AUROC 0.84) — a subset |
| Ranking + filters + diversity | quality_score, num_filters_passed, diversity-optimized set | our best-of-N selection |

## Strategic implication (honest)
BoltzGen provides — MIT-licensed, wet-lab-validated, out of the box — most of what this session
built piecemeal on PepGLAD: cyclic generation + closure + binding/structure/designability scoring
+ developability-liability flags + ranked/diverse selection. So the bespoke PepGLAD work (closure
guidance, cyclic fine-tune, stability predictor, best-of-N selection) is largely **superseded** as
a foundation. That's the right outcome of the pivot — build on the validated frontier, not a
bounded reproduction.

## What is NOT superseded (our remaining value-add)
- **Physics/MD verify** — BoltzGen's iptm/pae/liabilities are ML-predicted (Boltz-2-style) and
  rule-based, NOT physics or measured. MM-GBSA / MD-stability / MD-permeability remain the
  non-circular, all-atom oracle (physics run in flight). This is where the closed loop's honesty
  comes from.
- **Our targets** — qualification used a provided example; the real test is BoltzGen on the
  Guangzhou program's actual target(s) + our cyclic test set.
- **Permeability specifically** — BoltzGen flags hydrophobic patches but not membrane permeability
  per se; PeptideCLM/CycPeptMP + MD-permeability still needed, and N-methylation permeability lever
  still applies (BoltzGen's covalent-bond spec may admit some non-natural chemistry — verify).
- **The closed loop** — BoltzGen is the generator+scorer; wiring generate→physics-verify→select→
  learn (Ax/BoTorch + BioMate campaign optimizer) is still ours to build.
- **Wet lab** — still the ultimate gate.

## Next
1. Run BoltzGen `peptide-anything` on OUR cyclic target(s) + test set; compare designs' metrics to
   the PepGLAD cyclic model (honest head-to-head, though BoltzGen is expected to win).
2. Feed BoltzGen designs into the physics/MD verify (MM-GBSA / MD stability) — the non-circular check.
3. Check BoltzGen's non-natural / N-methylation support for the permeability lever.
4. Close the loop with BoltzGen as generator + physics oracle.
