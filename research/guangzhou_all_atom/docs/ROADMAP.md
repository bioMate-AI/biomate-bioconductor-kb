# Roadmap — consolidated answers + plan (cyclic-peptide all-atom generator)

Single source of truth tying together the design/eval/survey docs. See also: [[SURVEY_2026_UPDATE]],
[[VALIDATION_LADDER]], [[CLOSED_LOOP]], [[PHASE2_DEVELOPABILITY]], [[PHASE1_CYCLIC_SCOPING]],
[[INNOVATION_ASSESSMENT]], [[BASELINE_RESULTS]].

## Are we doing all-atom modeling?
- **Generation: YES, all-atom.** PepGLAD (our baseline) and the SOTA successors (UniMoMo — same
  authors; BoltzGen — 14 atoms/residue) generate full-atom structures via geometric latent diffusion.
- **Developability so far: NO — it dropped to 2D.** Stability/permeability were scored from ECFP
  fingerprints on linear SMILES, discarding the generated 3D structure; PepTune is also SMILES-based.
- **Correction (governing rule):** keep the *whole* pipeline all-atom. The verify/learn side must use
  the 3D all-atom structure via **physics/MD** (force-field energy, MD stability, MM-GBSA, MD/solvation
  permeability) — not a 2D fingerprint shortcut. 2D predictors are cheap pre-filters only.

## Where we honestly stand
- Validated cyclic generator: DockQ 0.51, Cα-RMSD 3.7 Å, Slide AAR 0.34, Consistency 0.64 (< paper
  0.79 → undertrained, 60 epochs / 564 peptides). Decent, not best.
- Developability loop (2D): stability AUROC 0.84 (good); permeability R² 0.23 (weak); generate→
  verify→select works (best-of-16 stability 0.47→0.77). Multi-property screen: **0/1088 dual-
  developable** — designs bind but are predicted non-permeable (too big, 0 N-methyl, high HBD/TPSA).
- Loop is **open** (manual scripts, no feedback); physics tier **not yet run**; no wet lab.

## Multi-objective optimization — where we actually are (corrected)
We do multi-objective **selection** (score the fixed pool on stability+permeability, equal-weight
rank) — NOT multi-objective **optimization**: nothing steers *generation* toward the Pareto front,
and the combined rank is a crude weighted sum, not a Pareto/hypervolume objective. Real MOO to
adopt: **Ax/BoTorch qNEHVI** (hypervolume-based multi-objective acquisition) or **PepTune MCTG**
(Pareto-guided discrete diffusion over permeability/solubility/hemolysis/binding). This is a gap,
not a solved item.

## Backbone decision is an EARLY FORK, not a "later" step (corrected)
Earlier I ranked adopting UniMoMo/BoltzGen "later" — that was questionable. The backbone choice
gates everything downstream (closure, unification, permeability integration), so it should be
decided NOW:
- **Patch PepGLAD** (cyclic positional encoding + PeptideCLM + guidance): lower-risk, familiar,
  but the patches (esp. closure) may be **throwaway** if we later switch.
- **Adopt BoltzGen** (MIT, all-atom, cyclic peptides *native* via covalent-bond spec, wet-lab
  validated across 26 targets): solves our #1 gap (closure) and the unification thesis **for free**,
  but is a bigger lift to stand up (larger model, newer code, more compute).
- **Adopt UniMoMo** (our own PepGLAD lineage's successor; unified graph-of-blocks): most natural
  migration, joint-training gains, but less wet-lab validation than BoltzGen.
Recommendation: evaluate the BoltzGen/UniMoMo fork **before** sinking effort into PepGLAD patches.
Physics/MD (below) is backbone-agnostic and worth doing regardless.

## The plan (survey-informed, ranked) — modeling first, wet lab last
Each maps to a gap we hit AND a published fix ([[SURVEY_2026_UPDATE]]):

1. **Physics/MD tier (all-atom verify) — START NOW.** OpenMM relax + energy + clash (PepGLAD ships
   it) → MD stability → MM-GBSA ΔG → conformational vs MacroConf NMR → MD/solvation permeability
   (the all-atom, non-circular oracle; the RIGHT tool for permeability chameleonicity).
2. **Macrocyclic closure (all-atom structural fix).** Adopt RFpeptides cyclic positional encoding /
   BoltzGen covalent-bond spec / GeoCycler (96% pass@5). Fixes our #1 open gap.
3. **Stronger permeability oracle.** Swap ECFP→**PeptideCLM** (PAMPA ROC-AUC 0.78 vs our 0.23); we
   already collected PeptideCLM-2. Or CycPeptMP (3D-aware, all-atom-consistent).
4. **Chemistry steering.** PepTune-style MCTG inference-time multi-objective guidance (permeability/
   N-methylation/binding) — steers chemistry our structure-only guidance can't. (SMILES-based → use
   as an outer objective, keep the all-atom generator.)
5. **Non-natural monomers (Phase-1b).** N-methylation is the proven permeability lever; blocker was
   no 3D non-natural structures → **MeDCycFold Rosetta-distillation** generates them.
6. **Backbone upgrade.** Toward UniMoMo/BoltzGen (unified, wet-lab-validated) + flow-matching (FLOWR)
   + explicit-H/pretraining/data-quality engineering (each materially helps; we used none).
7. **Close the loop** (reuse Ax/BoTorch + REINVENT/PMO + BioMate campaign optimizer; build only the
   structure+physics glue). Physics = the non-circular oracle.
8. **Wet lab (LAST).** Only designs surviving 1–7. CRO protocol drafted separately.

## Immediate action
Start the **physics/MD tier** (all-atom, keeps the pipeline consistent): OpenMM force-field
relaxation + potential energy + clash on generated cyclic complexes — the cheapest physics gate and
the first non-circular verify signal for the loop. Then MD stability + MM-GBSA.
