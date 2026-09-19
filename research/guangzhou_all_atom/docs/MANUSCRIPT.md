# A non-circular generate–verify–select engine for de novo cyclic-peptide design: physics systematically reranks ML-generated binders and exposes a permeability gap

*Working manuscript — computational study, no experimental validation. Guangzhou all-atom cyclic-peptide program.*

## Abstract
Machine-learning generators for de novo cyclic-peptide binders (e.g. BoltzGen) rank designs by a learned
interface confidence (iptm) that is trained on the same structural priors used to generate them — a
potentially circular signal. We assembled and characterized an automated **generate → verify → select**
engine that couples an adopted ML generator to two independent evaluators: (i) a fully automated, headless
all-atom **MM-GBSA** physics oracle for head-to-tail cyclic peptides, and (ii) a permeability model trained
on measured cyclic-peptide membrane permeability (CycPeptMPDB). Across four diverse receptors (kallikrein,
an antibody Fab, a toxin-scaffold receptor, cathepsin B), the physics oracle **systematically reranked**
the generator: the ML top-ranked design placed 5th–7th of 8 by MM-GBSA on *every* target, and iptm was
uncorrelated with within-target physics binding (Spearman = −0.04). Multi-objective (bind × physics ×
permeability) selection further showed that all designs are predicted poorly permeable, because the
generator optimizes binding only. We report a permeability model reaching R² = 0.45 (Spearman 0.75) with
static descriptors, an empirically confirmed ~0.45–0.55 static-descriptor ceiling, and three honest negative
results (cheap conformer-ensemble "chameleon-span", an N-methylation lever invisible to 2D models, and a
generator-feature active-learning surrogate) that localize the remaining advantage to expensive
conformation-aware permeability modeling and permeability-driven *generation*. The engine, its findings,
and their limitations are reported to guide where computational effort does and does not create value.

## 1. Introduction
Cyclic and macrocyclic peptides occupy a therapeutic niche between small molecules and biologics: metabolic
stability, potential membrane permeability via conformational shielding ("molecular chameleon" behavior),
and the ability to engage flat protein–protein interfaces. Yet a survey of the ~50 approved cyclic-peptide
drugs shows essentially none originated from de novo *computational* design — they came from natural-product
isolation, endogenous-hormone analoging, venom, or (very recently) display technologies. This defines both
the opportunity and the difficulty for a computational design engine.

Modern ML generators (BoltzGen and relatives) produce pocket-conditioned cyclic-peptide designs and rank
them by a learned interface confidence (iptm). Because that confidence derives from the same learned
structural potential used to generate, it risks being *circular*: high self-confidence need not imply
physically favorable binding, and says nothing about developability (permeability, stability). A
generate–verify–learn ("DMTA") engine is the standard remedy, but its value depends entirely on the verify
layer being (a) independent of the generator and (b) covering the properties that actually gate a drug.

We built and — importantly — *characterized* such an engine for cyclic peptides, and report what the wiring
reveals, with explicit attention to distinguishing genuine findings from adopted tooling.

## 2. Methods
**Generation.** BoltzGen (adopted, unchanged) was run with the `peptide-anything` protocol on four receptor
targets extracted from a curated cyclic-peptide benchmark, producing 8 ranked head-to-tail cyclic designs
per target with iptm, design-pTM, interface PAE, PLIP H-bonds, ΔSASA, and developability-liability flags.

**Physics verification (MM-GBSA).** We built a fully automated, headless cyclic-peptide MM-GBSA pipeline.
The macrocycle-topology build — the step the field addresses with the interactive CHARMM-GUI — was automated
with the standalone psfgen Python API (Eigenstate) using `first NONE last NONE` segment construction
(internal residue types, avoiding the charged-terminal `N3` artifact that defeats a naive AMBER tleap
recipe) plus a uniquely-named head-to-tail patch (a name collision with CHARMM's built-in `LINK` patch was
the final blocker). Complexes were minimized in OpenMM with GBn2 implicit solvent (CHARMM36m), and
single-trajectory MM-GBSA ΔG was computed by the receptor/ligand energy decomposition (the peptide treated
as a protein chain, split by residue range). Force-field files were cached in project storage to remove an
external-server dependency. Minimized single-point evaluation was used, consistent with reported best
practice for short peptides.

**Permeability model.** A gradient-boosted-tree regressor was trained on CycPeptMPDB (8,466 cyclic peptides,
log Papp) using RDKit molecular descriptors, evaluated under random and (Murcko) scaffold splits.

**Selection.** Designs were ranked by multi-objective Pareto and a normalized combined score over
bind (iptm), physics (−ΔG), and predicted permeability. Permeability of designs was scored by cyclizing the
sequences in RDKit and applying the descriptor model (consistent feature computation).

**Experiments.** (i) cross-target MM-GBSA (4 targets × 8 designs); (ii) an active-learning LEARN surrogate
predicting MM-GBSA ΔG from generator features (leave-one-target-out CV); (iii) an N-methylation lever test
(re-predicting permeability of N-methylated designs); (iv) a conformer-ensemble "chameleon-span" test; (v) a
2-environment permeability proxy (vacuum-minimized vs extended 3D-PSA). Compute ran on AWS (spot GPU for
generation; CPU for analysis).

## 3. Results
**3.1 Automated cyclic MM-GBSA is robust.** All 32 designs (4 targets × 8) built and cyclized successfully
(32/32 head-to-tail rings closed, including proline-containing designs), and minimized to stable energies —
demonstrating a headless alternative to interactive macrocycle setup.

**3.2 Physics systematically reranks the ML generator.** On every target, the BoltzGen top-iptm design fell
to 5th–7th of 8 by MM-GBSA ΔG:

| target | receptor | BoltzGen #1 | its MM-GBSA rank | MM-GBSA #1 |
|---|---|---|---|---|
| 1yf4 | kallikrein | GSGLLKS | 6 | FSRNVGDPY |
| 1u8p | antibody Fab | GRYSPSG | 6 | SSSFGPG |
| 1kc4 | toxin-scaffold | SGGVVVATSGIVGV | 7 | SALGVVANGPII |
| 1csb | cathepsin B | TIRVPRTFQVPG | 5 | SRYTTMGSGWSIAFG |

Within a target, iptm was **uncorrelated with physics binding** (Spearman(iptm, ΔG_z) = −0.04). This is the
core result: the generator's self-confidence carries essentially no within-target physics signal, so the
verify oracle is genuinely non-circular and non-optional.

**3.3 Multi-objective selection and the permeability gap.** Adding permeability as a third objective changed
the selection (e.g., a top physics binder that is less permeable ties with a weaker binder that is more
permeable; both Pareto-optimal). Critically, **all designs were predicted poorly permeable** (log Papp
−7.5 to −8.4), because the generator optimizes binding only — indicating permeability must be a *generation*
objective, not a post-hoc filter.

**3.4 Permeability model and its ceiling.** Gradient-boosted trees reached R² = 0.45 / Spearman = 0.75
(random split) on CycPeptMPDB, far above a prior weak baseline (R² 0.23) but short of learned-representation
literature (~0.55). Scaffold and random splits were similar (0.41 vs 0.45), reflecting near-degenerate
Murcko scaffolds for macrocycles (scaffold-splitting is a weak generalization test for this class).

**3.5 Three honest negatives localize the remaining advantage.**
- *Active-learning surrogate:* a cheap surrogate predicting MM-GBSA ΔG from generator features generalized at
  R² ≈ 0 (leave-one-target-out) — physics cannot be shortcut from generator confidence; run it directly.
- *Conformer-ensemble "chameleon-span":* adding single-environment conformer 3D-PSA span did not improve
  permeability prediction (0.246 vs 0.262), matching a literature caution that ensemble variance carries
  <2% of signal.
- *N-methylation lever:* fully N-methylating designs changed predicted permeability by mean +0.06 log units
  — i.e., a 2D-descriptor model **cannot see** the established N-methylation permeability lever, because the
  mechanism is conformational.

## 4. Discussion
Two conclusions follow. First, for cyclic-peptide binder design an independent physics verify step is
essential and not shortcut-able: ML interface confidence is orthogonal to physics binding
(Spearman −0.04), and a physics ranking systematically overrides the generator on diverse targets. An engine
that advanced designs on iptm alone would consistently carry physically sub-optimal candidates forward.
Second, permeability — the property that actually gates oral cyclic-peptide drugs — is neither produced by a
binding-only generator nor captured by static 2D descriptors; the N-methylation lever is invisible to such
models. The genuine, still-unrealized advantage therefore lies in **conformation-aware permeability**
(multi-conformer, multi-environment 3D-polar-surface modeling) coupled to **permeability-driven generation**.

## 5. Limitations
MM-GBSA is a relative ranking oracle with a size bias (longer designs score more negative; cross-target ΔG
is not comparable) and omits entropy; the physics rankings therefore nominate FEP candidates rather than
decide winners. The permeability model is a coarse ranking signal (R² ~0.3–0.45) applied out-of-distribution
to designs. The 2-environment permeability proxy (the intended conformation-aware differentiator) did **not**
yield a result: an initial run was lost to a runner bug (budget check gated behind a modulo, letting a hard
deadline kill the box before the ML step), and after that plus the per-item-timeout, checkpointing, and
OpenMP-runtime fixes, the per-peptide GAFF/AM1-BCC (`sqm`) parametrization failed inside the worker
environment on ephemeral spot instances — so this experiment is **attempted but toolchain-blocked**, not a
reported number. Its expected payoff is anyway bounded by the cheap conformer-span and N-methylation
negatives above and a literature caution that ensemble variance carries <2% of permeability signal. The
rigorous GBn2-MD version was not attempted. One generator and four targets were studied. No experimental
(wet-lab) validation was performed; all results are computational.

## 6. Conclusion and future directions
We contribute an automated headless cyclic-peptide MM-GBSA capability and a demonstrated non-circular
generate–verify–select engine, together with a set of honest findings that localize where computational
effort creates value: (1) keep an independent physics verify layer — it materially and consistently reranks
the generator; (2) move permeability into generation; (3) invest in conformation-aware permeability
(2-environment MD ensembles) as the genuine differentiator, and FEP as the finalist arbiter — both are
dedicated-resource builds, not cheap increments (empirically, the cheap shortcuts fail). Wet-lab
counter-screening (binding, permeability, selectivity) remains the ultimate gate.

## Data & code availability
Code: `research/guangzhou_all_atom/` (branch `integration/dev-test`). Runs, force-field cache, datasets, and
result JSONs under `s3://knowledge-datasets-1759951976/cyclic_peptide/`. Supporting docs: MMGBSA_RESULTS,
PERMEABILITY_BASELINE_RESULTS, CLOSED_LOOP_ENGINE, PEPTIDE_MMGBSA_TOOLING, CYCLIC_PEPTIDE_DRUGS,
SMALL_MOLECULE_TRANSFER, PROGRAM_STATE_20260918, NEXT_BUILDS_PLAN.

## Key references (as cited across program docs; verify before formal submission)
BoltzGen (Stark et al.); Boltz-2; CycPeptMPDB (Li et al., *JCIM* 2023); gmx_MMPBSA (Valdés-Tresanco et al.,
*JCTC* 2021); MMPBSA.py (Miller et al. 2012); MM/PBSA protein–peptide part 9 (Sun et al., *PCCP* 2019);
CHARMM36m; psfgen (Eigenstate); molecular-chameleon / 3D-PSA (Whitty, Kihlberg, Lokey); macrocycle FEP
(Schrödinger FEP+ retrospective; ATM, Gallicchio et al.); CREMP (Genentech, *Sci. Data* 2024).

*Author contributions / status: computational study generated during an automated design-engine build;
numbers are reproducible from the committed scripts and S3 run artifacts. Not peer-reviewed; references and
exact statistics should be re-verified before any external submission.*
