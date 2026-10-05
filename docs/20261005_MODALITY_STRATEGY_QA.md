# Modality Strategy — Cyclic Peptides, Data Landscape, and the Unified All-Atom Framework

**Date:** 2026-10-05 · Captures three strategic questions and the honest answers, to anchor the
Path-A all-atom fine-tune work in the program's direction.

---

## Q1. If cyclic peptides have trouble crossing membranes, why pursue them?

Membrane permeability is a real constraint but **neither universal nor a dealbreaker** — it only
binds for *intracellular* or *orally-dosed* targets.

- **Many high-value targets are extracellular / cell-surface**, where permeability is irrelevant:
  protein–protein interaction (PPI) interfaces, cell-surface receptors, surface antigens. **Our own
  targets are exactly these** — PD-L1 and αvβ6 are cell-surface, so a binder never has to cross a
  membrane. Most approved peptide drugs are injectable, a large market where permeability does not
  apply at all.
- **When permeability IS required, it is achievable.** Cyclization + N-methylation + "chameleonicity"
  get cyclic peptides across membranes (cyclosporine is an oral cyclic peptide). This is precisely why
  CycPeptMPDB exists and why we carry permeability as *one objective* (field R² ≈ 0.77) in the
  multi-objective selection — we optimize it where it matters and do not require it where it does not.
- **Why pursue them at all:** cyclic peptides reach targets small molecules cannot (large, flat PPI
  interfaces; shallow pockets) with antibody-like specificity, while being smaller and synthesizable.
  That "undruggable-by-small-molecule" space is the prize; permeability is a solvable sub-problem.

**Takeaway:** permeability is a constraint to optimize for intracellular/oral targets, not a reason to
avoid the modality — and it is moot for our current cell-surface targets.

---

## Q2. The modalities are small molecule + peptide — and the data balance (correction)

The two modalities in scope are **small molecules + peptides** (the all-atom models also cover
proteins/ligands). But on the data balance, the common intuition is **backwards**:

- **Small molecules are the data-RICH modality:** ChEMBL/PubChem (millions of compounds +
  bioactivities), ZINC (billions), large PDB protein–ligand co-crystal sets, QM datasets.
  Small-molecule ML is the most data-abundant area of the field.
- **Cyclic peptides are the data-STARVED modality** — the "data wall": only low hundreds of cyclic
  co-crystal structures, ~8.5k permeability measurements (CycPeptMPDB), ~136k binding affinities (but
  mostly linear/general, not cyclic co-structures).
- Where small molecules *are* thin is narrow: a *specific* target's actives, or 3D poses of truly
  novel chemotypes. Broadly, small-molecule data ≫ peptide data.

**Implication for strategy:** the **peptide axis is where a model trained on our data adds value**
(scarce public data → our proprietary loop + fine-tune move the needle). The **small-molecule axis is
already well-served** by abundant public data + our existing drug-dev tooling.

---

## Q3. Are we building a unified all-atom framework for both peptide and small molecule? — Yes, by design

The unification lives in the **shared all-atom backbone** — we are leveraging a unified framework,
not building two separate models.

- The all-atom models we adopted — **BoltzGen / Boltz-2**, and **UniMoMo** (which we reproduced) — are
  *inherently multi-modal*. AF3-style **CCD atom-level tokenization represents proteins, peptides
  (canonical + non-canonical), and small-molecule ligands/cofactors in one all-atom representation.**
  UniMoMo is literally "unified generative modeling of 3D molecules" across small molecules + peptides
  + antibodies; BoltzGen targets "universal binder design." This is the all-atom unification the
  program originally intended.
- **What the current Path-A work does:** fine-tune that unified backbone on the **peptide (cyclic +
  ncAA) axis** — the data-scarce, high-value-add dimension. The **small-molecule axis the base model
  already handles natively**, and on our side it is covered by the existing drug-dev stack
  (~215 tested docking / QSAR / RBFE / ADMET workflows + the ADMET auto-loop), which is strong
  *because* small-molecule data is abundant.
- **Honest framing:** we specialize the peptide axis (scarce data) and ride the base model + richer
  tooling for small molecules. A single model fine-tuned by *us* on both cyclic peptides *and*
  small-molecule complexes is a natural extension once the peptide path is proven — but **peptide-first
  is the right order**, because that is where our data moves the needle and small molecules are already
  strong.

**Takeaway:** one unified all-atom backbone (BoltzGen/Boltz-2/UniMoMo) covers both modalities; we are
specializing its peptide axis now and leaning on the base model + drug-dev tooling for small molecules,
with a both-modalities fine-tune as the follow-on once peptide is validated.

---

## How this anchors the current work
The Path-A fine-tune (fine-tuning the unified all-atom backbone on cyclic + non-canonical peptide
complexes) is consistent with the unified vision: it does not fork a peptide-only model; it specializes
the peptide dimension of a backbone that already represents small molecules all-atom. See
`docs/20261005_BOLTZGEN_CYCLIC_CONVERTER.md` (validated converter) and the fine-tune launcher work.
