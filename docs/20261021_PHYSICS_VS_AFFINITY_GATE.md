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

---

## 6. LEVER 2 execution (2026-10-21) — cofold adapter BUILT; MM-GBSA half BLOCKED on a FF pipeline (not fired)
Green-lit to build the SMILES-ligand cofold adapter and run cofold→MM-GBSA. On execution a decisive obstacle surfaced that changes the scope honestly.

**Done (CPU, no spend):**
- **SMILES-ligand cofold adapter built + validated** — `cyclic_llm/smiles_cofold_adapter.py::smiles_cofold_yaml` emits a well-formed Boltz-2 YAML (receptor `protein` chains + a `ligand: smiles:`), the piece `json_to_boltz_yaml` lacked (it only did CCD ligands + peptide-by-sequence). Dry-run YAML validated (`ADAPTER_YAML_WELLFORMED: True`).
- **Measured αvβ6 subset staged** — `results/physics_gate/avb6_measured_subset.csv`: 20 macrocycles spanning pAff 3.68–9.59 (weak→strong), ready for the cofold run.

**The obstacle (newly surfaced) — the MM-GBSA half is not a quick run:**
- **No small-molecule FF toolchain is installed** — antechamber / tleap / parmchk2 / openff / openmm are all MISSING here.
- The **existing MM-GBSA is peptide-CHARMM36m** (psfgen CYCP on standard residues); it **cannot parameterize arbitrary SMILES macrocycles** (non-standard residues, thioether/photo linkers). MM-GBSA on these ligands requires a **SMILES → GAFF (AmberTools/OpenFF) → topology** pipeline that does not exist in the current codebase.
- Therefore "cofold→MM-GBSA on measured SMILES macrocycles" is **not a small adapter + bounded run** — the MM-GBSA half is a real pipeline build.

**Why I did NOT fire a cofold-only GPU run:** cofold alone would yield Boltz-2's own **ML affinity head / confidence**, which tests *Boltz-2's learned model*, not **our physics (MM-GBSA/FEP)** — the wrong question for this gate, and a misleading spend. Review-before-spend → not fired.

**Scoped true gate (for the coordinator's decision):**
1. Build the SMILES→GAFF→MM-GBSA pipeline (AmberTools/OpenFF param of the macrocycle ligand, MM-GBSA on the cofold pose in the GPU container). This is the real remaining build.
2. Then: cofold (adapter ready) the 20 αvβ6 + 20 PD-L1 measured macrocycles → GAFF-MM-GBSA ΔG → Spearman vs measured pAff. Est cost: cofold ~$10–15/target; MM-GBSA GPU bounded; total ~$25–40 **after the FF-pipeline build**.

**Verdict (this pass):** physics gate **NOT run** — blocked on a SMILES-macrocycle MM-GBSA FF pipeline (a build, not a cost/go). The cofold adapter + measured subset are ready. Because CPU docking was excluded and this is genuine MM-GBSA, a future flat result would still be a clean (a) physics-wall finding. **This obstacle itself is informative: our "physics engine" is peptide-sequence-specific; applying it to real measured (SMILES, often non-standard) macrocycles needs a small-molecule FF layer we don't have — a concrete capability gap.**
