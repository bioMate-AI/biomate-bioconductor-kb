# Physics ↔ measured-affinity gate — can physics break the ~0.42 ceiling?

**Date:** 2026-10-21 · **Question:** does our physics track MEASURED affinity (→ physics augmentation / FEP-grounded system is justified), or not (data wall)?
**Status: SCOPED, not yet run — the valid gate is a bounded GPU cofold→MM-GBSA run; CPU-cheap docking is not a valid test for these ligands (reasons below).**

## 1. Selection + ligand nature (grounded in binding_affinity_v1)
Measured, exact/approx (`relation ∈ {=,~}`) cyclic rows for our two structure-bearing targets:
| target | n (cyclic) | assay mix | affinity range | ligand nature |
|---|---|---|---|---|
| PD-L1 | 162 | IC50 347 / Kd 16 / EC50 16 (full set 379) | 0.019 nM – 94 µM | **peptidic macrocycle** (SMILES len med 123, amide-rich, thioether SC closures) |
| αvβ6 | 165 | IC50 187 | 0.26 nM – 210 µM | **peptidic macrocycle** (SMILES len med 136) |

Good dynamic range (~6–7 log units) on both. The ligands are **peptidic macrocycles given as SMILES**, not small molecules — this is decisive for which physics applies.

## 2. Why CPU-cheap docking is NOT a valid gate here
- **No docking tool is installed** (vina/smina/qvina/obabel all absent; no python-vina).
- Even if installed, **vanilla AutoDock Vina is method-inadequate for macrocycles** (ring flexibility, large flexible peptidic ligands) — a flat Vina↔affinity correlation would be the **(b) docking-method limitation**, NOT a clean **(a) physics-doesn't-track** test. So CPU docking cannot cleanly answer the gate for these ligands.

## 3. Why existing MM-GBSA data cannot be reused
`results/mmgbsa_pdl1_v2.json` / `mmgbsa_avb6_v2.json` are **within-target rankings of OUR DESIGNED peptides** (8–10 designs: PDL1-K-0x, AVB6-K-0x), with **no measured affinity field**. They give a relative design ranking, not a physics↔*measured*-affinity correlation. Unusable for this gate.

## 4. The valid gate = cofold → MM-GBSA on the MEASURED macrocycles (GPU path)
The physics we would actually augment with is **Boltz cofold → MM-GBSA** (the pose generator that handles macrocycles + the metal-aware MM-GBSA already built). To test it against measured affinity:
- Take ~20–25 measured macrocycles per target spanning the IC50/Kd range (weak→strong).
- Cofold each (receptor sequence + macrocycle SMILES ligand) on the Boltz GPU-spot job-def → pose.
- MM-GBSA ΔG on the pose.
- Spearman(ΔG, measured pAff) per target.
**Cost (bounded):** ~20–25 cofolds/target × ~$0.3–0.6 spot ≈ **$10–15/target**, ~$20–30 for both — within the review-before-spend bound. **Not fired in this pass** (it's the GPU path and the target-aware ligand model, below, is the cheaper lever being tested first; if the target-aware model breaks the ceiling CPU-only, the physics gate's role sharpens).
- **Feasibility note:** `json_to_boltz_yaml`/`physics_batch` currently build cofold inputs for receptor chains + CCD cofactors + a **peptide chain** (HELM/sequence); feeding an arbitrary **SMILES macrocycle ligand** needs a small adapter (Boltz-2 accepts SMILES ligands, but the current builder path assumes a peptide chain P). That adapter is the one build step before the gate run.

## 5. Verdict (this pass)
- **Cannot be answered CPU-cheaply or from existing data.** The honest gate is a bounded GPU cofold→MM-GBSA run on measured macrocycles (scoped above, ~$20–30, not fired).
- **Key a-priori distinction preserved:** because CPU docking is invalid for macrocycles, a future flat result from the *cofold→MM-GBSA* path would be a clean **(a) physics-doesn't-track** finding (a real data/physics wall), since cofold is the appropriate pose method — not a (b) docking artifact.
- Recommended order: run the CPU **target-aware ligand model** first (cheaper lever for a standalone model); then, gated on a go, the bounded cofold→MM-GBSA physics gate. Both feed the same question — is the ceiling model-capacity (ligand-only) or data/physics-fundamental.
