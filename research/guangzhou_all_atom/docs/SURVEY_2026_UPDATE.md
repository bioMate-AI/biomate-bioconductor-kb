# Recent drug-generation SOTA (2024–2026) → mapped to our gaps

Cited, adversarially-verified survey (deep-research run, 24 primary sources, 25 claims verified,
1 refuted). Scoped to improving our PepGLAD-based cyclic-peptide generator. Bottom line: **our two
hardest gaps (macrocyclic closure; permeability/N-methylation) are solved-in-principle by
published methods, and there's a stronger permeability predictor and a way around our Phase-1b
data blocker.** So "the model has a long way to go" is true — but the path is now concrete.

## Direct hits on OUR gaps
| Our gap (what we found) | Published fix to adopt |
|---|---|
| **Macrocyclic closure** — our latent guidance only reached N–C ~7 Å, 0% true closure | **RFpeptides** cyclic *relative positional encoding* (flip +→− relative positions past halfway → N/C covalently linked; Nat Chem Biol 2025); **BoltzGen** explicit *covalent-bond specification* (disulfide/head-to-tail/staple; ~88% exp. confirmation, sizes 10–18); **GeoCycler** head-to-tail cyclization **96% pass@5** vs CP-Composer 75% (LNR). |
| **Permeability predictor weak** (our ECFP HistGBM, scaffold-R² 0.23) | **PeptideCLM** — peptide-aware SMILES language model, PAMPA **ROC-AUC 0.78** leave-one-cluster-out (> ChemBERTa 0.74); we already collected PeptideCLM-2. **CycPeptMP** (atom+monomer+peptide fusion) = the 0.77 reference. Replace our ECFP model. |
| **Can't steer chemistry via structure-only guidance** (PepGLAD guidance is X-only) | **PepTune** (ICML 2025) — discrete diffusion over peptide **SMILES** + **Monte Carlo Tree Guidance**: inference-time **multi-objective** optimization of permeability/solubility/hemolysis/binding, **no retraining**; trained on 11M peptide SMILES incl. non-natural AAs + cyclizations. |
| **Phase-1b blocker: no 3D non-natural-monomer structures to train on** | **MeDCycFold** — fine-tunes AlphaFold via **Rosetta distillation** to model cyclic peptides with **N-methylated + D-amino acids (56 non-natural)**, generating the training conformations because experimental data is scarce. This is the recipe to unblock Phase-1b. |
| **Unified backbone thesis** (our "one backbone, plugins") | **UniMoMo** (ICML 2025, *same authors as PepGLAD*) — extends PepGLAD's geometric latent diffusion to peptides+antibodies+small-molecules via a shared "graph of blocks"; joint training beats single-modality (peptide AAR 37.6→39.5, ΔG −28.7→−34.4). **BoltzGen** — single all-atom model, geometry-based 14-atom/residue encoding, wet-lab validated across 26 targets (nanomolar binders for 66%). MIT-licensed. |

## Architecture / engineering levers (transferable, from SBDD)
- **Flow-matching > diffusion**: **FLOWR / FLOWR.root** (Nat Comp Sci 2026) — pocket-conditioned all-atom flow matching beats diffusion on validity (0.92 vs 0.83)/pose/interaction, up to **70× faster**, and FLOWR.root unifies generation + affinity scoring in one SE(3) backbone. (Small-molecule; architectural transfer.)
- **Controlled SBDD ablations** (J. Cheminf. 2026): explicit-H training (validity 66→86%, PoseBusters pass ~2×), large-scale unconditional **pretraining** then fine-tune (strain 10.6→6.6), and **crystal-data quality** each materially help. Cheap to transfer; our run used none.
- **Boltz-2** — joint structure+affinity foundation model → usable as a binding oracle. ⚠️ its "FEP-parity at ~1000×" claim was **refuted** in verification (0-3) — do NOT cite FEP parity.

## Top adoptions (ranked) to go beyond PepGLAD
1. **Cyclic positional encoding (RFpeptides) or covalent-bond conditioning (BoltzGen)** → real macrocyclization (our #1 open gap). GeoCycler if we stay latent-diffusion.
2. **PeptideCLM as the permeability predictor** → replace ECFP 0.23 with 0.78 ROC-AUC; makes the developability loop's weak axis reliable.
3. **PepTune-style MCTG inference-time multi-objective guidance over SMILES** → steer permeability/N-methylation/binding *without* retraining — the chemistry-steering our structure-only guidance couldn't do.
4. **MeDCycFold-style Rosetta distillation** → generate non-natural-monomer training data → unblock Phase-1b (N-methylation = the permeability lever we proved matters).
5. **Move toward UniMoMo/BoltzGen** as the unified backbone (our own lineage) + flow-matching + explicit-H/pretraining/data-quality engineering.

## Honest caveats (from the verification pass)
- Many benchmarks are **self-reported** on authors' own datasets (FLOWR/SPINDR, UniMoMo cross-domain, BoltzGen campaigns) — external head-to-head is limited.
- **Modality transfer unproven**: FLOWR/FLOWR.root/Boltz-2-affinity/SBDD-ablations are small-molecule; lessons *plausibly* but not empirically transfer to macrocyclic peptides.
- RFpeptides diffuses *backbones* (sequence by ProteinMPNN after) → not strictly "all-atom".
- UniMoMo's cross-domain gain isn't disentangled from simply-more-data; joint training slightly cut peptide diversity.
- **Refuted:** Boltz-2 ≈ FEP at 1000× speed (0-3). Don't cite.

Full cited findings + sources: deep-research run wf_893c6674-6c2 (see task output). Primary sources
incl. RFpeptides (Nat Chem Biol s41589-025-01929-w), PepTune (PMLR v267 tang25n / arXiv 2412.17780),
UniMoMo (arXiv 2503.19300), BoltzGen (bioRxiv 2025.11.20.689494), FLOWR (arXiv 2504.10564),
FLOWR.root (2510.02578), SBDD ablations (PMC13292534), Boltz-2 (bioRxiv 2025.06.14.659707),
PeptideCLM, MeDCycFold, GeoCycler, CycPeptMP.
