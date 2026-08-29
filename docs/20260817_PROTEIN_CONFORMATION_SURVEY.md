# The State of the Art in Protein Conformational Ensemble & Dynamics Prediction

*A methods survey for a public research audience — every citation verified against its primary source (publisher DOI page, PubMed, or arXiv). Last verified 2026-08-17. No DOIs are fabricated. This is a general survey of the public field only.*

## Introduction

For two decades, the central goal of structural biology was to determine *the* structure of a protein — a single set of coordinates. Deep learning has largely solved that problem: AlphaFold2 and its successors now predict static folds at near-experimental accuracy for most proteins. But proteins are not statues. They breathe, flex, and cycle between functionally distinct conformational states — open/closed enzymes, active/inactive receptors, inward/outward-facing transporters, folded/disordered regions. Function *is* motion. A single static coordinate set captures, at best, one snapshot of a distribution, and can actively mislead when the biologically relevant state is a minor or transient one. This survey organizes the field by **approach family** — from static baselines through physics-based simulation, generative machine-learning ensemble models, cryo-EM heterogeneity analysis, and integrative multi-state modeling of disordered systems — giving for each what it is, how it works, key tools, evidence, strengths, and limitations, closing with an honest assessment of what is actually winning.

---

## Family 1 — Static structure prediction as the baseline

**What it is.** End-to-end deep-learning models that map a protein sequence (plus, usually, an MSA) to a single 3D structure — the modern baseline every dynamics method builds on or reacts against.

**Mechanism.** AlphaFold2 uses an attention-based "Evoformer" over MSA and pairwise residue representations feeding a structure module that produces atomic coordinates end-to-end. RoseTTAFold uses a three-track architecture coupling 1D/2D/3D reasoning. ESMFold replaces the MSA with a protein *language model* (ESM-2), predicting structure from a single sequence at metagenomic scale. AlphaFold3 generalizes to a diffusion-based generative head over all-atom coordinates, extending to protein–ligand, protein–nucleic-acid, and multi-chain complexes.

**Key tools.** AlphaFold2; AlphaFold3; RoseTTAFold / RoseTTAFold All-Atom; ESMFold (ESM-2); open re-implementations (OpenFold; Boltz-1/2).

**Evidence.** AlphaFold2 achieved median backbone accuracy near experimental error at CASP14; ESMFold folded hundreds of millions of metagenomic sequences; AlphaFold3 extended high accuracy to biomolecular interactions.

**Limitations — why a single structure is insufficient for dynamics.** These models are trained to reproduce the *one* deposited PDB structure and by default return a single high-confidence conformation. They do not report populations, do not sample alternative functional states, and give no free energies or kinetics. For allosteric enzymes, GPCRs, transporters, and disordered regions — where the *distribution* of states is the biology — a single prediction is at best incomplete. This gap motivates every family below.

**Citations.** Jumper et al. 2021, *Nature* — [10.1038/s41586-021-03819-2](https://doi.org/10.1038/s41586-021-03819-2) (PMID 34265844); Abramson et al. 2024, *Nature* (AlphaFold 3) — [10.1038/s41586-024-07487-w](https://doi.org/10.1038/s41586-024-07487-w) (PMID 38718835); Baek et al. 2021, *Science* (RoseTTAFold) — [10.1126/science.abj8754](https://doi.org/10.1126/science.abj8754); Lin et al. 2023, *Science* (ESMFold) — [10.1126/science.ade2574](https://doi.org/10.1126/science.ade2574).

---

## Family 2 — Physics-based molecular dynamics & enhanced sampling

**What it is.** Simulation of protein motion by numerically integrating Newton's equations under a molecular force field. MD is the only family that produces genuine *time-ordered trajectories* — real "movies" — with physically grounded free energies and kinetics.

**Mechanism.** An empirical force field (AMBER, CHARMM, OPLS) assigns energies to bonds/angles/torsions/non-bonded terms; atoms are propagated in femtosecond steps. Because functional transitions occur on µs–s timescales, the field relies on **enhanced sampling**: *metadynamics* adds history-dependent bias along collective variables; *replica-exchange MD (REMD)* swaps temperature replicas to cross barriers; *accelerated MD* raises low-energy regions to speed rare events. **Markov State Models (MSMs)** stitch many short trajectories into a kinetic network of metastable states. *AlphaFold-seeded MD* uses predicted structures as diverse starting points. *Special-purpose hardware* (Anton, D. E. Shaw) reaches millisecond all-atom trajectories directly.

**Key tools.** Engines: GROMACS, AMBER, CHARMM, NAMD, OpenMM. Force fields: ff14SB, CHARMM36. Enhanced sampling: metadynamics (PLUMED), REMD, accelerated MD, weighted-ensemble/string methods. MSMs: PyEMMA, MSMBuilder. Hardware: Anton.

**Evidence.** Anton produced the first atomic-level millisecond folding and conformational-change trajectories; MSMs matured into a rigorous statistical framework; metadynamics/REMD/aMD are standard, heavily validated free-energy and rare-event methods.

**Strengths.** Physically principled; yields free energies, kinetics, and mechanism — the gold standard for *how* a protein moves, transition pathways, and coupling (e.g., ion/substrate coupling in transporters, ligand-induced allostery).

**Limitations.** Expensive (large systems / long timescales); force-field inaccuracies (especially IDPs and some ion interactions); enhanced sampling needs well-chosen collective variables; large collective transitions can remain under-sampled. This cost/timescale wall is what generative ML tries to leapfrog.

**Citations.** Laio & Parrinello 2002, *PNAS* (metadynamics) — [10.1073/pnas.202427399](https://doi.org/10.1073/pnas.202427399); Sugita & Okamoto 1999, *Chem Phys Lett* (REMD) — [10.1016/S0009-2614(99)01123-9](https://doi.org/10.1016/S0009-2614(99)01123-9); Hamelberg et al. 2004, *JCP* (aMD) — [10.1063/1.1755656](https://doi.org/10.1063/1.1755656); Husic & Pande 2018, *JACS* (MSM) — [10.1021/jacs.7b12191](https://doi.org/10.1021/jacs.7b12191); Shaw et al. 2010, *Science* (Anton) — [10.1126/science.1187409](https://doi.org/10.1126/science.1187409); Abraham et al. 2015, *SoftwareX* (GROMACS) — [10.1016/j.softx.2015.06.001](https://doi.org/10.1016/j.softx.2015.06.001); Maier et al. 2015, *JCTC* (ff14SB) — [10.1021/acs.jctc.5b00255](https://doi.org/10.1021/acs.jctc.5b00255).

---

## Family 3 — Generative / ML conformational ensemble models

**What it is.** Deep generative models that sample *many* conformations for a sequence, aiming to approximate the equilibrium (Boltzmann) distribution — populations included — orders of magnitude faster than MD. **Crucial caveat:** most are **equilibrium-ensemble generators** (states and populations, *no time axis*), not true trajectory/"movie" models. Only a few (e.g., MDGen) generate time-ordered dynamics, and those remain small-scale.

**Mechanism.** Sub-strategies: **(a) MSA manipulation of AlphaFold** — subsampling/clustering the input MSA induces AF2 to output alternative functional states (AF-Cluster; subsampling recovers transporter/receptor endpoints and approximate populations). **(b) Repurposing folding networks as samplers** — AlphaFlow/ESMFlow retrain under a flow-matching objective; EigenFold and Str2Str use diffusion/score-based sampling. **(c) Learned Boltzmann samplers** — Boltzmann Generators (normalizing flows with exact reweighting); DiG (Distributional Graphormer) predicts equilibrium distributions; BioEmu emulates equilibrium ensembles at scale. **(d) Force-guided diffusion** — ConfDiff injects force guidance into SE(3) diffusion. **(e) Trajectory generation** — MDGen models MD trajectories directly (true dynamics, tetrapeptide-scale).

**Key tools.** AF-Cluster; MSA-subsampling (del Alamo; AFsample2; subsampled AF2); AlphaFlow/ESMFlow; EigenFold; Str2Str; ConfDiff; Boltzmann Generators; DiG; idpGAN; BioEmu; MDGen.

**Evidence.** MSA-subsampled AF2 recovers both outward- and inward-facing transporter states across many transporters and GPCRs. BioEmu reports thousands of conformers per GPU-hour, capturing cryptic pockets and domain motions at accuracy approaching long MD but ~10⁵× faster. Boltzmann Generators demonstrated correctly reweighted equilibrium sampling. AF-Cluster resolved a known fold-switching protein's two states.

**Strengths.** Dramatically cheaper than MD; produce diverse conformers and (for the best methods) calibrated populations; excellent for cryptic-pocket discovery and structural-prior/hypothesis generation.

**Limitations.** Most give *no kinetics or time ordering*; population calibration is uneven; large collective transitions (full transporter alternating-access) are systematically under-sampled by equilibrium generators; many are single-chain (BioEmu is single-chain, Cα-level); accuracy is bounded by PDB training bias toward stable states.

**Citations.** Wayment-Steele et al. 2024, *Nature* (AF-Cluster) — [10.1038/s41586-023-06832-9](https://doi.org/10.1038/s41586-023-06832-9); del Alamo et al. 2022, *eLife* (MSA subsampling) — [10.7554/eLife.75751](https://doi.org/10.7554/eLife.75751); Kalakoti & Wallner 2025, *Commun Biol* (AFsample2) — [10.1038/s42003-025-07791-9](https://doi.org/10.1038/s42003-025-07791-9); Monteiro da Silva et al. 2024, *Nat Commun* — [10.1038/s41467-024-46715-9](https://doi.org/10.1038/s41467-024-46715-9); Zheng et al. 2024, *Nat Mach Intell* (DiG) — [10.1038/s42256-024-00837-3](https://doi.org/10.1038/s42256-024-00837-3); Noé et al. 2019, *Science* (Boltzmann Generators) — [10.1126/science.aaw1147](https://doi.org/10.1126/science.aaw1147); Janson et al. 2023, *Nat Commun* (idpGAN) — [10.1038/s41467-023-36443-x](https://doi.org/10.1038/s41467-023-36443-x); Jing et al. 2023 (EigenFold) — [arXiv:2304.02198](https://arxiv.org/abs/2304.02198); Lu et al. 2024 (Str2Str) — [arXiv:2306.03117](https://arxiv.org/abs/2306.03117); Jing et al. 2024 (AlphaFlow/ESMFlow) — [arXiv:2402.04845](https://arxiv.org/abs/2402.04845); Wang et al. 2024 (ConfDiff) — [arXiv:2403.14088](https://arxiv.org/abs/2403.14088); Lewis et al. 2025, *Science* (BioEmu) — [10.1126/science.adv9817](https://doi.org/10.1126/science.adv9817); Jing et al. 2024 (MDGen) — [arXiv:2409.17808](https://arxiv.org/abs/2409.17808).

---

## Family 4 — Cryo-EM conformational heterogeneity

**What it is.** Methods that extract *multiple* conformational states — or continuous motion — from a single cryo-EM dataset, treating structural heterogeneity as signal. Each of the hundreds of thousands to millions of imaged particles is a frozen snapshot of a distinct conformation; the task is to recover the distribution.

**Mechanism.** **cryoDRGN** trains a VAE that learns a continuous low-dimensional latent space of conformations; **cryoDRGN-AI** extends this to neural *ab initio* reconstruction. **3D Variability Analysis (3DVA)** in cryoSPARC solves for linear variability components (continuous flexibility + discrete states). **3DFlex** models the map as a deformable canonical density plus a learned flow field. **ManifoldEM** places particle snapshots on a manifold to retrieve functional pathways and energy landscapes. **RECOVAR** uses regularized covariance estimation with kernel regression. **DynaMight** estimates per-particle deformations.

**Key tools.** cryoSPARC (+ 3DVA + 3DFlex); cryoDRGN / cryoDRGN-AI; ManifoldEM; RECOVAR; DynaMight; RELION (classification-based discrete heterogeneity).

**Evidence.** cryoDRGN resolved compositional and conformational heterogeneity in ribosome and spliceosome datasets; 3DFlex resolved continuous membrane-protein motion (e.g., TRPV1); ManifoldEM recovered functional energy landscapes from experimental snapshots.

**Strengths.** Grounded in real experimental data (not a model prior); resolves both discrete states and continuous motion; the definitive way to observe the conformational distribution a specific sample actually populates; extends to native context via cryo-ET.

**Limitations.** Requires a good particle stack; states below the reconstruction floor (rare conformers, or those lost to vitrification / air-water-interface bias) never enter the data; independent comparisons show learned deformation densities can diverge from ground truth, so orthogonal validation (smFRET, HDX-MS) is advisable.

**Citations.** Zhong et al. 2021, *Nat Methods* (cryoDRGN) — [10.1038/s41592-020-01049-4](https://doi.org/10.1038/s41592-020-01049-4); Levy et al. 2025, *Nat Methods* (cryoDRGN-AI) — [10.1038/s41592-025-02720-4](https://doi.org/10.1038/s41592-025-02720-4); Punjani & Fleet 2021, *J Struct Biol* (3DVA) — [10.1016/j.jsb.2021.107702](https://doi.org/10.1016/j.jsb.2021.107702); Punjani & Fleet 2023, *Nat Methods* (3DFlex) — [10.1038/s41592-023-01853-8](https://doi.org/10.1038/s41592-023-01853-8); Dashti et al. 2020, *Nat Commun* (ManifoldEM) — [10.1038/s41467-020-18403-x](https://doi.org/10.1038/s41467-020-18403-x); Gilles & Singer 2025, *PNAS* (RECOVAR) — [10.1073/pnas.2419140122](https://doi.org/10.1073/pnas.2419140122); Schwab et al. 2024, *Nat Methods* (DynaMight) — [10.1038/s41592-024-02377-5](https://doi.org/10.1038/s41592-024-02377-5); Punjani et al. 2017, *Nat Methods* (cryoSPARC) — [10.1038/nmeth.4169](https://doi.org/10.1038/nmeth.4169).

---

## Family 5 — Intrinsically disordered proteins & integrative multi-state modeling

**What it is.** Methods for proteins (or regions) with *no single* folded structure — intrinsically disordered proteins (IDPs) — and integrative approaches combining sparse experimental measurements into an ensemble or multi-state model. Here the "structure" is fundamentally a distribution.

**Mechanism.** IDP ensembles are built by generating large candidate-conformer pools then selecting/reweighting a sub-ensemble whose *averaged* observables match experiment. **Flexible-meccano** generates disordered pools from residue-specific backbone statistics; the **Ensemble Optimization Method (EOM)** selects a sub-ensemble to fit SAXS; **ENSEMBLE** optimizes against combined NMR (chemical shifts, RDCs, PREs) and SAXS restraints. More broadly, the **Integrative Modeling Platform (IMP)** formalizes Bayesian combination of heterogeneous data (EM, cross-linking MS, SAXS, FRET, prior structures) to determine multi-state structures of large assemblies. ML generators (idpGAN) now emit disordered ensembles directly.

**Key tools.** Flexible-meccano; EOM (SAXS); ENSEMBLE (NMR+SAXS); IMP (integrative/Bayesian); idpGAN; NMR/SAXS-restrained MD.

**Evidence.** SAXS-based EOM and NMR-restrained ensembles are the established route to quantitative IDP descriptions; IMP underlies landmark integrative structures of large assemblies (e.g., the nuclear pore complex).

**Strengths.** Directly experiment-restrained; principled treatment of proteins with no single structure; IMP scales to very large heterogeneous assemblies; naturally multi-state.

**Limitations.** Under-determined — many ensembles fit the same averaged data, so results need maximum-entropy/regularization and are not unique; heavily dependent on data quality/quantity; labor-intensive; force-field and pool-generation biases propagate.

**Citations.** Russel et al. 2012, *PLoS Biol* (IMP) — [10.1371/journal.pbio.1001244](https://doi.org/10.1371/journal.pbio.1001244); Bernadó et al. 2007, *JACS* (EOM) — [10.1021/ja069124n](https://doi.org/10.1021/ja069124n); Krzeminski et al. 2013, *Bioinformatics* (ENSEMBLE) — [10.1093/bioinformatics/bts701](https://doi.org/10.1093/bioinformatics/bts701); Ozenne et al. 2012, *Bioinformatics* (Flexible-meccano) — [10.1093/bioinformatics/bts172](https://doi.org/10.1093/bioinformatics/bts172); Jensen et al. 2014, *Chem Rev* — [10.1021/cr400688u](https://doi.org/10.1021/cr400688u).

---

## What's Winning / The Honest State

- **No single method wins; the field is converging on hybrids.** The most reliable multi-state models in 2026 *combine* families: a fast generative or MSA-subsampled prior proposes states, physics-based MD/enhanced sampling gives mechanism and free energies, and experimental data (cryo-EM heterogeneity, NMR/SAXS, smFRET, HDX-MS) validates and anchors. Any purely computational ensemble is a hypothesis until experimentally checked.
- **Static prediction is effectively solved; dynamics is not.** AlphaFold-class models give near-perfect single structures but no distributions, populations, kinetics, or alternative functional states by default.
- **Generative ensemble models are the fastest-moving frontier — with real caveats.** BioEmu, DiG, AlphaFlow, MSA-subsampling deliver conformers at a tiny fraction of MD cost and are excellent for cryptic-pocket discovery. But most produce *equilibrium ensembles, not trajectories*; population calibration is uneven; large collective transitions are under-sampled. "Protein movie" claims are frequently over-stated — true trajectory generators (MDGen) remain peptide-scale.
- **MD remains the gold standard for mechanism** — the only family giving time-ordered pathways, kinetics, and free energies — at a cost generative models race to undercut.
- **Cryo-EM heterogeneity is the strongest experimental grounding** — cryoDRGN(-AI), 3DVA/3DFlex, RECOVAR, DynaMight recover multi-state distributions directly from data, but only for states that enter the particle stack, and learned densities need orthogonal validation.

### BioMate Positioning

BioMate operates here as an **execution platform**, not a new algorithm. On its AWS-Batch compute layer it provides indexed, production **cryo-EM workflows** — including single-particle processing and conformational-heterogeneity analysis (the cryoSPARC / cryoDRGN-family methods of Family 4) — letting users resolve multiple states and continuous motion directly from their own particle data. It additionally offers a **generative conformational-ensemble capability** (Family-3-style equilibrium ensemble generation) producing many candidate conformers for a sequence, useful for cryptic-pocket discovery and as structural priors. BioMate's contribution is making these published methods runnable end-to-end at scale with live progress and downloadable results — orchestration and accessibility of the state of the art, not a proprietary replacement for it. The honest boundaries described throughout (equilibrium ensembles are not trajectories; computational ensembles need experimental validation; large collective transitions are hard) apply equally to results produced on the platform.

---

*Verification note: all references confirmed against primary sources (publisher DOI, PubMed, or arXiv); no DOIs fabricated. Companion showcase: `blog-protein-conformation.html`. Related BioMate surveys: target identification, patient stratification, multi-omics integration, virtual cell modeling.*
