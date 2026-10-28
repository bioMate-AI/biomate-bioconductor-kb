# State of the Art: De-Novo Peptide Binder Design (sequence+structure co-design), with focus on CYCLIC peptides / macrocycles

Date: 2026-10-01
Scope: Rigorously establish SOTA for de-novo peptide binder design measured by DockQ (plus AAR and RMSD), especially cyclic/macrocycle co-design. Context: we build on PepGLAD; our cyclic fine-tune scores DockQ 0.437 vs PepGLAD's reported 0.592.

> **Headline finding (read this first).** PepGLAD's **0.592 is NOT a co-design DockQ**. It is the DockQ of the **binding *conformation generation*** task — peptide **sequence is given**, the model generates the 3D binding pose — on the **PepBench linear-peptide** test set (93 targets), reported as the median best of 10 samples (Table 3 of the PepGLAD paper). PepGLAD's *co-design* results (Table 1) report **no DockQ at all** — they use Diversity / Consistency / ΔG / Success. So before anything else: **confirm that our 0.437 was computed on the same task (fixed-sequence conformation generation) and NOT on cyclic co-design**, or the 0.437 vs 0.592 comparison is apples-to-oranges (different task AND different molecule class — cyclic vs linear).

---

## 1. PepGLAD (Kong et al., "Full-Atom Peptide Design with Geometric Latent Diffusion", NeurIPS 2024)

Source: arXiv 2402.13555 (NeurIPS 2024). Code: https://github.com/THUNLP-MT/PepGLAD . Data (PepBench + ProtFrag): https://zenodo.org/records/13373108 . **Both code and data are public.** (No released pre-trained weights advertised in the paper's "Software and Data" section — only code + datasets; training is reproducible from those.)

### Architecture
- **Geometric latent diffusion**, three modules:
  1. **Variational autoencoder (VAE)** that encodes variable-size *full-atom* residues into a **fixed-dimensional latent** (per-residue latent = one 8-dim feature `z_i` + one 3D coordinate `z̃_i`), then decodes back to full-atom residues. Built on dyMEAN's adaptive multi-channel E(3)-equivariant encoder. Uses a 25% residue **mask** policy during AE training.
  2. **Receptor-specific affine transformation** `F`: uses the binding-site Cα center + Cholesky decomposition of its covariance to map each complex's geometry into a shared **standard-Gaussian space**, improving cross-target transfer. Proven E(3)-equivariance-preserving.
  3. **E(3)-equivariant latent diffusion** in that standard space (cosine noise schedule; dyMEAN-style equivariant denoiser), with a minor classifier-style guidance on adjacent-residue distances for ordering.
- Full-atom in, full-atom out. Jointly generates sequence (via latent `z_i`) and all-atom structure.

### Training data (linear peptides only — NO cyclic experiment in the paper)
- Start: all PDB dimers, receptor > 30 residues, ligand (peptide) 4–25 residues → dedup at 90% receptor+peptide sequence identity → **6,105 non-redundant complexes**.
- Test = **LNR** ("Large Non-Redundant", from Tsaban et al.) = **93** protein–peptide complexes with canonical amino acids (expert-curated).
- Cluster remaining by receptor at 40% identity, drop clusters overlapping the test set, random-split the rest into train/val. This curated set is named **PepBench** (per the follow-up RADiAnce paper: **4,157 train / 114 val / 93 test**).
- Plus **ProtFrag = ~70,000 unsupervised protein fragments** used to pretrain the VAE (the diffusion needs a smooth latent, and protein–peptide complexes alone are too few).
- A second evaluation split is built on **PepBDB**.

### The exact conditions of DockQ 0.592
PepGLAD reports two distinct tasks:

**Task A — Sequence-Structure Co-Design (Table 1).** Generate both sequence and structure given the binding site. 40 candidates/target. Metrics: **Diversity, Consistency, ΔG (Rosetta), Success**. **No DockQ, no AAR, no RMSD-to-native** (there is no native to compare a *novel* sequence against). PepGLAD on PepBench: Div 0.506, Con 0.789, ΔG −21.94 kcal/mol, Success 55.97%.

**Task B — Binding Conformation Generation (Table 3).** **Sequence is GIVEN**; generate the binding pose (a docking/folding task). 10 candidates/target, report **median best** ("optimal recall of the reference conformation"). Metrics: RMSD_Cα, RMSD_atom, **DockQ**. This is where **0.592** lives:

| Model (Task B, PepBench) | RMSD_Cα ↓ | RMSD_atom ↓ | DockQ ↑ |
|---|---|---|---|
| FlexPepDock | 6.43 | 7.52 | 0.393 |
| AlphaFold2 | 8.49 | 9.20 | 0.355 |
| dyMEAN | 7.96 | 8.35 | 0.374 |
| HSRN | 6.02 | 7.59 | 0.508 |
| DiffAb | 4.23 | 7.60 | 0.586 |
| **PepGLAD** | **4.09** | **5.30** | **0.592** |

On the harder **PepBDB** split, PepGLAD DockQ drops to **0.403**. (DockQ thresholds: >0.23 acceptable, >0.49 medium quality.)

**Bottom line for #1:** 0.592 = **fixed-sequence binding-conformation generation DockQ, PepBench linear peptides, median-of-10**. It is NOT co-design, NOT cyclic, NOT single-shot.

---

## 2. Current SOTA + successors — tabulated (flagging non-comparable benchmarks)

**Three different, mutually-incomparable evaluation universes are in play. Do not cross-compare rows across them.**

- **Universe 1 — PepBench (Kong-lineage; 4,157 train / 93 test; linear).** The only place a DockQ directly comparable to 0.592 exists.
- **Universe 2 — Q-BioLip+PepBDB (~10,348 complexes; ~166–219 test; linear).** Used by PepFlow/PPFlow/THFlow/NS-Pep. DIFFERENT metrics/splits — NOT comparable to PepBench DockQ.
- **Universe 3 — Cyclic / macrocycle design.** Mostly Rosetta-energy, AF2 self-consistency RMSD, or wet-lab Kd. **The cyclic field does not report a canonical co-design DockQ.**

### SOTA table

| Method | Venue/ref | Task | Molecule | Benchmark | DockQ | AAR | RMSD (Å) | Train data size | Public? |
|---|---|---|---|---|---|---|---|---|---|
| **PepGLAD** | NeurIPS'24 (2402.13555) | conf-gen (seq given) | linear | **PepBench** (93) | **0.592** | — | Cα 4.09 / atom 5.30 | 4,157 + 70k ProtFrag | code+data ✓ |
| PepGLAD | " | co-design | linear | PepBench (93) | — | 38.62† | 2.74† | 4,157 + 70k | ✓ |
| **UniMoMo** | ICML'25 (2503.19300) | both | linear (unified) | PepBench (93) | **~0.759**‡ | 38.69† | 2.31† | cross-domain: PepBench+SAbDab+CrossDocked | code ✓ (kxz18/UniMoMo) |
| **RADiAnce** | 2025 (2510.10480) | both (retrieval-aug) | linear | PepBench (93) | **~0.770**‡ | **39.42**† | **2.29**† | PepBench + cross-domain retrieval bank | preprint |
| PepFlow | 2406.00735 | co-design | linear | PepBench (93)† | — | 35.47† | 2.87† | ~10,348 (own split) | code ✓ |
| PepFlow | " | co-design | linear | Q-BioLip/PepBDB | — | 50–53% | — | 10,348 | ✓ |
| RFdiffusion | — | co-design | linear | PepBench (93)† | — | 34.68† | 4.69† | whole-PDB pretrain | ✓ |
| PPFlow | — | co-design | linear | Q-BioLip (219) | — | 8.63 | 9.45 | 10,348 | ✓ |
| THFlow | 2502.15855 | co-design | linear | Q-BioLip (166 test) | — | (stab/aff %) | re-dock RMSD | 10,348 | preprint |
| NS-Pep | 2510.03326 | co-design + NSAA | linear | Q-BioLip+PepBDB (219) | — | 22.53 | 4.92 | 10,348 | preprint |
| **CpSDE** (Harmonic SDE) | 2505.21452 | **co-design** | **CYCLIC** | own (100 pockets) | — (Rosetta only) | — | — | 14,348 small-mol + 20,033 pep | preprint |
| D-Flow | 2411.10618 | co-design | **D-peptide (mirror)** | own | — | — | — | — | code ✓ |
| **RFpeptides** | **Nat. Chem. Biol. 2025** (s41589-025-01929-w) | **de-novo binder design** | **CYCLIC/macrocycle** | wet-lab (4 targets) | — (AF2/RF2 RMSD + Kd) | — | crystal Cα <1.5 (MCL1 0.7) | whole-PDB pretrain (RF2/RFdiffusion) | pipeline from RF2/RFdiffusion ✓ |
| AfCycDesign | Nat. Commun. 2025 (s41467-025-59940-7) | prediction + hallucination design | CYCLIC | crystal set | — | — | crystal <1.0 | AF2 (no retrain) | ✓ (RosettaCommons) |
| HighFold / HF2 / HF3 | Brief. Bioinform. 2024–25 | **structure PREDICTION** | CYCLIC (+NSAA) | own cyclic sets | (pred.) | — | RMSD_Cα | AF2 cyclic-offset (CycPOEM) | ✓ |

† On PepBench, AAR/RMSD are **co-design** numbers as re-reported in the RADiAnce paper's Table 2 (comparable to each other, NOT to Universe-2 AAR). ‡ UniMoMo ~0.7592 and RADiAnce ~0.7698 "peptide DockQ" come from RADiAnce's appendix (Table 13, extended evaluation). **Caveat:** verify the exact task definition of that appendix DockQ (conf-gen vs co-design-then-fold) before citing it as strictly the same task as PepGLAD's 0.592 — but both numbers are from the PepGLAD lineage on PepBench peptides, and both clearly exceed 0.592.

### What is the actual current best for CYCLIC peptide co-design?
There is **no published cyclic co-design DockQ SOTA** — the cyclic field does not compete on that metric. The honest answer by sub-question:
- **Wet-lab-validated cyclic binder design (the real bar):** **RFpeptides** (Baker lab, Nat. Chem. Biol. 2025). RFdiffusion-cyclic backbone → ProteinMPNN sequence → AF2/RF2 self-consistency filter. 21–38% experimental hit rate across 4 targets (MCL1, MDM2, GABARAP, RbtA), Kd 1–10 µM, crystal Cα RMSD 0.7–1.5 Å. This is the credible SOTA for *making real cyclic binders*, and it reports **no DockQ**.
- **Generative cyclic co-design benchmark:** **CpSDE** (Harmonic SDE + atom-bond, 2505.21452) — best cyclic co-design by Rosetta stability/affinity, beats linear PepGLAD/PepFlow on binding energy. **No DockQ.**
- **Cyclic structure prediction (needed for designability filtering):** **HighFold/HighFold2/HighFold3** and **AfCycDesign** (AF2 cyclic-offset), plus newer **CyclicBoltz1**.

---

## 3. What drives the top performers (techniques separating SOTA from the rest)

Ranked by observed impact in the literature:

1. **A large pretrained structure / co-folding prior, or cross-domain transfer, beats in-domain data every time.** The strongest methods do NOT rely on the ~4k–10k peptide complexes alone:
   - RFpeptides inherits **whole-PDB** structural knowledge via RoseTTAFold2 + RFdiffusion (hundreds of thousands of structures).
   - UniMoMo trains **cross-domain** (peptides + antibodies/SAbDab + small molecules/CrossDocked2020) in one model and beats single-domain PepGLAD — multi-domain data is the lever.
   - RADiAnce adds **retrieval augmentation** (retrieve structurally similar interfaces from a bank, condition generation on them) on top of the unified latent — currently the top PepBench numbers.
2. **Full-atom modeling** (vs Cα-only). PepGLAD's own ablation: removing full-atom context drops the composite Avg from 0.619 → 0.574 and tanks success rate. Full-atom is necessary but PepGLAD already has it — it's table stakes, not a differentiator anymore.
3. **Diffusion vs flow-matching is roughly a wash.** PepFlow (flow) ≈ PepGLAD (diffusion) on PepBench co-design (AAR 35.47 vs 38.62). Flow gives fewer sampling steps / efficiency, not a decisive quality jump. Do not expect a big DockQ win from switching the generative formulation alone.
4. **Test-time sampling + a good ranker.** Every DockQ/designability number here is a *best-of-N* (PepGLAD: median-of-10; RFpeptides: generate many → filter by AF2 self-consistency). The ranker (AF2/RF2/co-fold RMSD or pAE) is as important as the generator.
5. **Physics/energy guidance & cyclization handling.** Rosetta/ΔG refinement (RFdiffusion, AnchorExtension) and explicit cyclic-offset positional encoding (HighFold CycPOEM, AfCycDesign) + head-to-tail/disulfide constraints (CpSDE atom-bond) are what make cyclic geometry physically valid and closable.

---

## 4. To BEAT 0.592 DockQ — ranked levers + honest achievability

**First, fix the comparison.** Our 0.437 (cyclic) vs PepGLAD's 0.592 (linear, fixed-sequence conf-gen) are two moves apart. Two prerequisites before chasing 0.592:
- (i) Confirm our 0.437 is the **same task** (fixed-sequence conformation generation, median-of-10) — if ours is cyclic *co-design* DockQ, the number isn't defined the same way and 0.592 is the wrong target.
- (ii) Establish an **apples-to-apples base rate**: run base PepGLAD (and ideally UniMoMo) on *our cyclic test set*, same task/N. Cyclic is intrinsically harder and data-poorer than linear; PepGLAD's own number drops 0.592→0.403 just moving PepBench→PepBDB. The honest target may be "beat PepGLAD-base-on-cyclic," not "beat 0.592-on-linear."

### Ranked levers (expected impact for cyclic conformation-generation DockQ)

1. **Add a co-folding / structure prior + strong ranker (HIGHEST impact).** The jump from PepGLAD 0.592 → UniMoMo ~0.76 → RADiAnce ~0.77 was driven by priors/transfer/retrieval, not more cyclic data. Concretely: (a) initialize/condition on a cyclic-capable folder (HighFold/AfCycDesign cyclic-offset, or a cyclic-aware co-fold), and (b) rank samples by self-consistency RMSD (the RFpeptides recipe). This is the single most reliable way past 0.592.
2. **Cross-domain / transfer data scale (HIGH impact, but bounded for cyclic).** Borrow the abundant **linear** peptide complexes + antibody CDR + small-molecule binding data (UniMoMo recipe) rather than only the few-hundred cyclic complexes. Cyclic-specific data genuinely does not exist at the 4k–10k scale, so pure in-domain cyclic scaling is capped — transfer is the way to get the effect of scale.
3. **Test-time sampling budget (MEDIUM, cheap, immediate).** Every SOTA DockQ is best-of-N. Raising N from 10 → 50–100 with a proper ranker almost always lifts median-best DockQ at no training cost. Do this first as a quick win.
4. **Cyclization-aware geometry (MEDIUM, necessary for validity).** Cyclic-offset positional encoding + explicit head-to-tail/disulfide bond modeling (CpSDE-style atom-bond) — needed so closed macrocycles are physically valid; improves RMSD/DockQ of the ring, and is a prerequisite for the designs to be real.
5. **Flow-matching instead of diffusion (LOW).** Efficiency win, not an accuracy win. Do not bank a 0.437→0.592 jump on this.
6. **Full-atom (ALREADY HAVE IT via PepGLAD).** Keep it; not a new lever.

### Is beating it realistic, and via what path?
- **Yes, 0.592 is beatable** — models in the same lineage already report higher peptide DockQ (UniMoMo ~0.76, RADiAnce ~0.77). The techniques are published and the code is open (PepGLAD, UniMoMo, D-Flow, PepFlow, AfCycDesign, HighFold, RFdiffusion/RF2).
- **Recommended path:** (1) sampling budget N↑ + self-consistency ranker (days, no training); (2) cross-domain transfer — co-train/warm-start on linear PepBench + antibody + small-mol, then fine-tune on cyclic (UniMoMo recipe); (3) add a cyclic-offset structure prior for conditioning and ranking (HighFold/AfCycDesign); (4) only then consider flow-matching for efficiency.
- **Can data scale ALONE close 0.437 → 0.592? No — not pure cyclic data scale.** Cyclic complexes number in the low hundreds in the PDB; there is no 4k–10k cyclic corpus to train on, so you cannot simply out-scale the gap the way linear models did. The gain that *looks* like "data scale" in the SOTA came from **transfer + priors + retrieval + best-of-N**, not from more in-domain cyclic examples. Expect data/transfer to be necessary but **insufficient on its own**; the co-fold prior + ranker + sampling levers are what actually move cyclic DockQ.

---

## 5. Honest check — is 0.592 even the right bar, and is co-design DockQ the field's metric?

- **Is 0.592 the right bar? Partly no.** It is PepGLAD's 2024 **linear, fixed-sequence** conformation-generation number. Within the same research lineage, **higher DockQ already exists** (UniMoMo ~0.76, RADiAnce ~0.77 on PepBench peptides). And it is a **linear** number — using it as the bar for a **cyclic** model conflates molecule-class difficulty with model quality. The correct bar is **PepGLAD-base (and UniMoMo) re-run on our cyclic test set, same task and N**.
- **Is co-design DockQ the metric the field competes on? No.** DockQ requires a reference complex of the *same* sequence, so it is used for the **fixed-sequence conformation-generation / re-docking** subtask, **not** for de-novo co-design (where the generated sequence is novel). The metrics the field actually competes on:
  - **Co-design:** AAR (amino-acid recovery), RMSD-to-native, binding energy (Rosetta ΔG / ΔΔG), diversity/consistency, and increasingly **designability / self-consistency RMSD (scRMSD)** — fold the designed sequence with AF2/RF2 and measure how well it reproduces the designed structure.
  - **Cyclic specifically:** Rosetta energy (CpSDE), **AF2/RF2 self-consistency RMSD + crystal RMSD + wet-lab Kd** (RFpeptides, AfCycDesign). **Wet-lab affinity + hit-rate is the real SOTA currency for cyclic binders**, not DockQ.
- **Implication for us:** optimizing cyclic co-design purely for DockQ-0.592 risks over-fitting to a linear-peptide, fixed-sequence benchmark metric that the cyclic field does not use. If the goal is a credible cyclic-binder product, track **designability (self-consistency RMSD), binding energy, AND a wet-lab-proxy hit-rate** alongside DockQ — DockQ as a fast dev-loop metric, the others as the real bar.

---

## Sources
- PepGLAD: arXiv 2402.13555 (NeurIPS 2024); code https://github.com/THUNLP-MT/PepGLAD ; data https://zenodo.org/records/13373108
- UniMoMo: arXiv 2503.19300 (ICML 2025); code https://github.com/kxz18/UniMoMo
- RADiAnce (retrieval-augmented cross-domain binders): arXiv 2510.10480
- PepFlow (multi-modal flow matching): arXiv 2406.00735
- D-Flow (D-peptide multimodal flow): arXiv 2411.10618
- THFlow: arXiv 2502.15855
- NS-Pep (non-standard AAs, retrieval): arXiv 2510.03326
- CpSDE / cyclic Harmonic SDE: arXiv 2505.21452
- RFpeptides: Nature Chemical Biology 2025, s41589-025-01929-w (+ C&EN, hyper.ai coverage)
- AfCycDesign: Nature Communications 2025, s41467-025-59940-7 (RosettaCommons/AfCycDesign)
- HighFold / HighFold2 / HighFold3: Briefings in Bioinformatics 2024 (bbae215), 2025 (bbaf202, bbaf488)
- Additional 2025 cyclic entries: "Deep learning-enabled design of macrocyclic peptide binders" (s41589-025-02062-4); Latent-X (arXiv 2507.19375); GeoCycler, MacroGuide, APCyc, FAR-DPO, CyclicBoltz1 (emerging preprints)
