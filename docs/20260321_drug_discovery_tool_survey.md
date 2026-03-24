# Computational Drug Discovery Tool Survey — 2025-2026

**Date**: 2026-03-21
**Source**: Live web research (GitHub, recent benchmarks, licensing pages)
**Purpose**: Inform BioMate tool integration priorities. All tools assessed for AWS Batch + Nextflow deployability.

---

## 1. Molecular Dynamics Engines

| Tool | License | GPU | Docker | Citations / Stars | Novelty | Popularity |
|------|---------|-----|--------|-------------------|---------|------------|
| GROMACS | LGPL-2.1 | Yes (CUDA+SYCL) | Yes (official) | ~25k+ citations | 2 | 5 |
| LAMMPS | GPL-2.0 | Yes (CUDA) | Yes | #1 publications 2024-25 | 2 | 5 |
| OpenMM | MIT/LGPL | Yes (CUDA/OpenCL) | Yes (conda-forge) | ~1,800 stars | 3 | 4 |
| AMBER (pmemd) | $0 acad / $25k comm | Yes (pmemd.cuda) | **No (non-redistrib)** | ~20k+ citations | 2 | 4 |
| NAMD | Source-avail (free) | Yes (multi-GPU) | **No (non-redistrib)** | ~15k+ citations | 2 | 4 |
| CHARMM | Free acad / Commercial | Yes | No | ~30k+ citations | 1 | 3 |
| DESMOND | Free (Schrödinger) | Yes | No | N/A | 2 | 3 |

### Key Findings

**GROMACS is the cloud-optimal MD engine.** Official Docker at `gromacs/gromacs`, LGPL-2.1 allows free containerization, AWS has a published Batch workshop, and 2025.3 supports CUDA + AMD SYCL. Most-published MD platform alongside LAMMPS.

**AMBER pmemd cannot be distributed in a shared container.** The license prohibits redistribution even for academic use — pmemd.cuda cannot be baked into a BioMate Docker image and deployed at scale without each user individually signing the license agreement. This is a harder constraint than initially assessed. AmberTools (antechamber, tleap, CPPTRAJ) is free GPL and can be containerized; pmemd cannot.

**LAMMPS** leads in raw 2024-2025 publication count, driven by ML force field simulations (MLMD with MACE, AIMNet2). Less relevant for pharma drug discovery; primary use in materials science.

**OpenMM** is the preferred programmatic backend for FEP/alchemical calculations (OpenFE ecosystem). MIT/LGPL, conda-forge, Python-native.

---

## 2. Molecular Docking

| Tool | License | Stars | Docker | Accuracy (2Å) | Novelty | Popularity |
|------|---------|-------|--------|----------------|---------|------------|
| AutoDock Vina 1.2.7 | Apache-2.0 | ~947 | Yes (unofficial) | ~47-63% | 1 | 5 |
| GNINA | GPL-2.0 / Apache-2.0 | ~876 | Yes (official) | **85.29%** | 3 | 3 |
| DiffDock | MIT | ~1,500 | Yes (unofficial) | ~40-45% (fair bench.) | 4 | 3 |
| AutoDock-GPU | LGPL-2.1 | ~300 | Yes (NVIDIA NGC) | ~60-70% | 3 | 3 |
| Glide SP/XP | Commercial (~$5k+/yr) | N/A | No | Industry gold std. | 2 | 4 |
| GOLD (CCDC) | Commercial | N/A | No | Top-tier | 1 | 3 |
| PLANTS | Academic | N/A | No | Comparable to Vina | 1 | 2 |

### Key Findings

**GNINA is the best open-source docking tool** per 2025 benchmark ([MDPI Molecules](https://www.mdpi.com/1420-3049/30/16/3361)): 85.29% success rate at 2Å RMSD. Official Docker at `hub.docker.com/u/gnina`. BioMate currently uses GNINA in `structure_prediction_docking` — correct choice.

**DiffDock performance is lower than originally reported.** A 2024 fair comparison study ([arXiv 2412.02889](https://arxiv.org/html/2412.02889v1)) found ~20-25 percentage point contamination in original DiffDock benchmarks. Valuable for generating pose diversity, not for best-accuracy use. The commercial DiffDock-L (Chai Discovery) claims improvements.

**AutoDock-GPU** via NVIDIA NGC container is 50-100x faster than serial AutoDock 4. LGPL-2.1, free. Best for HTS campaigns (millions of compounds/day on A100 instances). BioMate should add this for virtual screening scale.

**Glide**: ~$5-25k/yr for tokens. Industry standard at big pharma. No containerization. Schrödinger FEP+ is $100k/yr commercial (not $7.5k as previously estimated — reevaluate integration priority).

---

## 3. Free Energy Perturbation (FEP)

| Tool | License | Stars | Docker | RMSE vs experiment | Novelty | Popularity |
|------|---------|-------|--------|---------------------|---------|------------|
| FEP+ (Schrödinger) | Commercial (**~$100k/yr**) | N/A | No | Gold standard | 2 | 4 |
| OpenFE | MIT | ~262 | Yes | 1.73 kcal/mol (2025) | 4 | 2 |
| Cinnabar | MIT | ~41 | Yes | (analysis tool) | 3 | 2 |
| Lomap | MIT | ~40 | Yes | (network planning) | 3 | 2 |
| Kartograf | MIT | ~35 | Yes | (atom mapping) | 3 | 2 |
| Boltz-2 (ML-based) | MIT | ~3,900 | Yes | FEP-proximate (claims) | 5 | 3 |

### Key Finding: OpenFE has Reached Industrial Readiness

The [2025 large-scale OpenFE assessment](https://chemrxiv.org/doi/full/10.26434/chemrxiv-2025-7sthd) involving AstraZeneca, Janssen, BMS, and Genentech demonstrated **RMSE of 1.73 kcal/mol on 58 public systems** — approaching FEP+ accuracy. This is the most important 2025 development for cloud-based FEP. The full stack:

- `openfe`: protocol execution (MIT, 262 stars)
- `lomap`: perturbation network planning (MIT)
- `cinnabar`: results analysis + plots (MIT)
- `kartograf`: accurate atom mapping (MIT)
- Backend: **OpenMM** (GPU-accelerated on AWS Batch)

**FEP+ revised assessment**: At $100k/yr commercial licensing, FEP+ is only viable for large pharma users with existing Schrödinger enterprise agreements. OpenFE is now the primary FEP recommendation for BioMate.

**GROMACS FEP** (GPU-accelerated): PMC 2025 paper shows up to 800% speedup on A100 vs 32-core CPU. GROMACS 2024+ has first-class FEP support. Alternative backend to OpenMM for RBFE.

---

## 4. Structure Prediction

| Tool | License | Stars | Docker | Accuracy (NP-bench) | Novelty | Popularity |
|------|---------|-------|--------|----------------------|---------|------------|
| Boltz-2 | **MIT** | ~3,900 | Yes | **78%** (vs AF3 73%) | 5 | 3 |
| AlphaFold3 | CC-BY-SA (weights restricted) | ~13,000 | Yes (complex) | 73% | 5 | 4 |
| Chai-1 | Apache-2.0 | ~2,000 | Yes | ~72% | 5 | 3 |
| ESMFold | MIT | ~3,000 | Yes | Sequence-only (fast) | 4 | 4 |
| OpenFold | Apache-2.0 | ~3,300 | Yes | AF2-level | 3 | 3 |
| RoseTTAFold2 | MIT (code) / Rosetta-DL (weights) | ~1,200 | No official | — | 3 | 3 |
| OpenFold-3 | Apache-2.0 | ~700 | No | — | 5 | 2 |

### Key Findings

**Boltz-2 is the standout**: MIT license (zero restrictions), outperforms AlphaFold3 on NP-bench (78% vs 73%), 15x faster than AF3 for typical drug-like molecules, **jointly predicts structure AND binding affinity** — a unique capability. Single A100 GPU. `pip install boltz`. BioMate already has Boltz-2 integrated.

**AlphaFold3 weight bureaucracy**: "Nobody outside DeepMind/Isomorphic really uses it for prod" — the CC-BY-SA weight access requires per-researcher registration + non-commercial agreement from EBI, creating user friction. ABCFold wraps AF3+Boltz+Chai-1 for parallel comparison.

**ESMFold**: 60x faster than AF2 for short proteins, sequence-only, MIT, in nf-core/proteinfold. Use for HTS protein structure pre-screening.

**BioMate assessment**: The Boltz-2 binding affinity prediction capability is not yet exploited by BioMate workflows — currently only structure is used. Surfacing ΔG predictions from Boltz-2 would be a differentiating feature.

---

## 5. Generative / AI Drug Design

| Tool | License | Stars | Docker | Published | Novelty | Popularity |
|------|---------|-------|--------|-----------|---------|------------|
| REINVENT4 | Apache-2.0 | ~709 | Yes (unofficial) | J. Cheminformatics 2024 | 4 | 4 |
| DiffSBDD | MIT | ~491 | No official | NeurIPS 2022 | 4 | 2 |
| DiffLinker | MIT | ~373 | No official | Nat. Mach. Intell. 2024 | 4 | 2 |
| FlowSite | MIT | ~300 | No | 2024 (Hannes Stark) | 5 | 2 |
| FABind+ / FABFlex | MIT | ~400 | No | ICLR 2025 | 4 | 2 |
| NeuralPLexer3 | **Proprietary** | N/A | No | NeurIPS 2025 | 5 | 2 |
| FragGen | MIT | ~200 | No | 2024 | 4 | 2 |
| PocketCrafter | Commercial (Relay TX) | N/A | No | — | 4 | 1 |

### Key Finding

**REINVENT4** (AstraZeneca, Apache-2.0, 709 stars) is the pharma industry workhorse for generative drug design: RL-guided de novo design, scaffold decoration, R-group enumeration, SMILES-based. IBM OpenAD integrates it. Docker-able. **BioMate has no generative design workflow — this is the clearest gap for a drug discovery platform.**

**NeuralPLexer3** (Iambic Therapeutics) is the most novel model (NeurIPS 2025): flow-based, physics-inspired, 78% blind docking success. **Not open source** — only benchmark code released; beta API proprietary.

**DiffLinker** ([Nat. Mach. Intell. 2024](https://www.nature.com/articles/s42256-024-00815-9), 373 stars, MIT): Best tool for fragment linker design (FBLD). Pocket-conditioned, equivariant E(3) diffusion. Most relevant for fragment-to-lead campaigns.

**Trend**: 3D equivariant diffusion and flow-matching are displacing SMILES/graph generative models for structure-based design. NeuralPLexer3 and FlowSite represent the frontier.

---

## 6. ADMET Prediction

| Tool | License | Installable | API | Stars | Novelty | Popularity |
|------|---------|------------|-----|-------|---------|------------|
| ADMETlab 3.0 | Free (web + REST API) | No | Yes | N/A | 4 | 4 |
| SwissADME | Free (web only) | No | No | ~8k citations | 2 | 4 |
| Chemprop v2 | MIT | Yes (pip) | No | ~2,300 | 4 | 4 |
| ADMET-AI | MIT | Yes (pip) | Yes | ~350 | 4 | 3 |
| DeepPurpose | MIT | Yes (pip) | No | ~1,800 | 3 | 3 |
| pkCSM | Free (web only) | No | No | N/A | 2 | 3 |

### Key Finding

**Chemprop v2** (MIT, 2,300 stars, [JCIM 2024](https://pubs.acs.org/doi/10.1021/acs.jcim.3c01250)) is `pip install chemprop`. The underlying DMPNN architecture behind ADMETlab 3.0 and ADMET-AI. 2x faster, 3x less memory than v1. Best for training custom ADMET models on proprietary data.

**ADMET-AI** (MIT, 350 stars): Chemprop pre-trained on 41 TDC datasets, #1 on TDC ADMET Leaderboard. `pip install admet_ai`. REST server mode. Easiest self-hosted ADMET — **the right choice for BioMate's ADMET workflow**.

**SwissADME / pkCSM**: Web-only, ~8k citations each, but not automatable at scale. Good for manual triage only.

**ADMETlab 3.0** ([NAR 2024](https://academic.oup.com/nar/article/52/W1/W422/7640525)): 119 ADMET endpoints, uncertainty quantification, REST API. Best web API for comprehensive screening. No local install needed — call from Nextflow via `curl`.

---

## 7. Protein-Protein Docking & Binder Design

| Tool | License | Stars | Docker | Novelty | Popularity |
|------|---------|-------|--------|---------|------------|
| HADDOCK3 | Apache-2.0 | ~227 | Yes | 4 | 4 |
| RFdiffusion | **Non-commercial** | ~2,800 | Yes (Singularity) | 5 | 4 |
| BindCraft | Mixed (PyRosetta commercial for industry) | ~1,000 | Yes (conda) | 5 | 3 |
| AlphaFold2-Multimer | Apache-2.0 | (in AF2 repo) | Yes | 3 | 4 |
| ClusPro | Free (web only) | N/A | No | 2 | 3 |

### Key Findings

**BindCraft** ([Nature 2025](https://www.nature.com/articles/s41586-025-09429-6), 1,000 stars): One-shot protein binder design, 10-100% experimental success rates, published March 2025. Uses RFdiffusion + ProteinMPNN + PyRosetta. **License constraint**: PyRosetta requires commercial license for industry use; RFdiffusion is non-commercial only. For academic BioMate users: green light. For commercial: blocked.

**HADDOCK3** ([JCIM 2025](https://pubs.acs.org/doi/10.1021/acs.jcim.4c01372), Apache-2.0): Full rewrite as modular Python package. Docker-ready. Best fully-open containerizable PP-docking. Supports NMR/mutagenesis restraints and protein-glycan docking.

---

## 8. Quantum Chemistry / QM-MM

| Tool | License | Stars | Docker | Cloud-ready | Novelty | Popularity |
|------|---------|-------|--------|-------------|---------|------------|
| xTB (GFN2-xTB) | LGPL-3.0 | ~767 | Yes (conda-forge) | Yes | 4 | 4 |
| CREST v3 | LGPL-3.0 | ~400 | Yes (conda-forge) | Yes | 4 | 3 |
| Psi4 | LGPL-3.0 | ~850 | Yes (conda) | Yes | 3 | 3 |
| CP2K | GPL-2.0 | ~550 | Yes (official) | Yes | 3 | 3 |
| ORCA 6.x | Free acad (**non-redistributable**) | N/A | **No** | No | 2 | 4 |
| Gaussian | Commercial | N/A | **No** | No | 1 | 4 |

### Key Finding

**xTB + CREST are the cloud QM winners.** `conda install -c conda-forge xtb crest`. LGPL-3.0. GFN2-xTB runs in seconds-minutes for drug-sized molecules. BioExcel's tblite Python library wraps it. ORCA 6 ships xTB binaries (but ORCA itself cannot be containerized).

**ORCA is the most-used QM in pharma (~30k citations) but cannot be dockerized.** License prohibits redistribution/containerization. Can only run on HPC nodes with module-system installation. Serious blocker for AWS Batch automation — require users to provide ORCA via EFS or accept the non-Docker workaround.

**Gaussian**: ~50k citations, commercial, no containers, not cloud-automatable.

---

## 9. Licensing Summary Matrix

| Tool | Cloud-Ready | BioMate Master | User Brings Own |
|------|------------|----------------|-----------------|
| GROMACS | ✅ LGPL | ✅ (in ECR image) | — |
| OpenMM | ✅ MIT | ✅ (in ECR image) | — |
| AutoDock-GPU | ✅ LGPL | ✅ (NVIDIA NGC) | — |
| GNINA | ✅ GPL/Apache | ✅ (in ECR image) | — |
| REINVENT4 | ✅ Apache-2.0 | ✅ (in ECR image) | — |
| Chemprop/ADMET-AI | ✅ MIT | ✅ (in ECR image) | — |
| xTB + CREST | ✅ LGPL | ✅ (conda-forge) | — |
| OpenFE | ✅ MIT | ✅ (in ECR image) | — |
| Boltz-2 | ✅ MIT | ✅ (already in BioMate) | — |
| ESMFold | ✅ MIT | ✅ (in ECR image) | — |
| HADDOCK3 | ✅ Apache-2.0 | ✅ (in ECR image) | — |
| DiffLinker | ✅ MIT | ✅ (build image) | — |
| AMBER pmemd | ⚠️ Signed license required | ❌ cannot redistribute | ✅ user signs |
| ORCA | ❌ Cannot dockerize | ❌ | ❌ (HPC only) |
| Schrödinger FEP+ | ❌ $100k/yr | ❌ | ✅ user's FlexLM |
| Glide | ❌ Commercial | ❌ | ✅ user's FlexLM |
| NeuralPLexer3 | ⚠️ API only | ⚠️ (API key) | ✅ |
| RFdiffusion | ⚠️ Non-commercial | ⚠️ (academic users only) | ✅ |

---

## 10. Emerging Trends (2024-2025)

1. **Flow-matching superseding diffusion**: NeuralPLexer3, Boltz-2 use continuous normalizing flows (faster, better mode coverage than DDPM). This is the frontier generation method.

2. **Boltz-2 as "cheap FEP"**: First model to jointly predict structure + ΔGbind, claims FEP-accuracy at 1000x lower cost. Watershed moment for early-stage screening.

3. **OpenFE reaching FEP+ parity**: 2025 multi-company assessment establishes open RBFE is now industry-grade. The $100k/yr FEP+ moat is eroding.

4. **GPU-accelerated QM via xTB**: Grimme lab's ecosystem sees explosive adoption for conformer generation, pKa, reactivity screening — replacing expensive Gaussian QM calculations in HTS contexts.

5. **BindCraft / binder design explosion**: 10-100% experimental success rates are transforming biologics discovery. Non-commercial licensing creates platform tension.

6. **No nf-core modules for comp chem**: 1,400+ nf-core modules but zero for GROMACS, AutoDock, OpenFE, REINVENT4, Chemprop. Clear infrastructure gap and market opportunity for BioMate.

---

## Integration Priority Ranking for BioMate

### Tier 1 — Implement Now (fully open, containerizable, high clinical/scientific impact)

| Priority | Tool | Workflow Name | Effort |
|----------|------|--------------|--------|
| 1 | GROMACS | `gromacs_protein_md` | 1 day |
| 2 | REINVENT4 | `reinvent4_lead_design` | 1 day |
| 3 | ADMET-AI / Chemprop v2 | Upgrade existing ADMET | 0.5 days |
| 4 | AutoDock-GPU | `autodock_hts_screen` | 0.5 days |
| 5 | xTB + CREST | `xtb_conformer_gen` | 0.5 days |
| 6 | OpenFE | `openfe_rbfe` | 1.5 days |
| 7 | HADDOCK3 | `haddock3_pp_docking` | 1 day |
| 8 | DiffLinker | `difflinker_fbld` | 1 day |

### Tier 2 — Implement with Some Configuration

| Priority | Tool | Notes |
|----------|------|-------|
| 9 | OpenMM | FEP backend (used by OpenFE) |
| 10 | ESMFold | Fast structure prediction (nf-core/proteinfold exists) |
| 11 | DiffSBDD | Generative; needs manual Docker image |
| 12 | BindCraft | Academic users only (RFdiffusion non-commercial) |

### Tier 3 — License-Gated (user brings own)

| Tool | Constraint | Notes |
|------|-----------|-------|
| Schrödinger (Glide/FEP+) | $100k/yr commercial | Only viable for enterprise customers |
| MOE | ~$5k/yr | On-demand, covalent docking use case |
| AMBER pmemd | Signed license required | User must sign; GROMACS preferred alternative |
| ORCA | Non-redistributable | HPC module system only; xTB sufficient for most tasks |

### Revised AMBER Assessment

**AMBER is demoted from Tier 1 to Tier 3.** The non-redistribution clause means BioMate cannot ship pmemd in a shared Docker image. GROMACS (LGPL, official Docker) is the correct Tier-1 MD engine. Use AmberTools (free GPL) for ligand parameterization (antechamber, tleap) within the GROMACS workflow.

---

*Sources: GitHub (live star counts), MDPI Molecules benchmark 2025, arXiv 2412.02889, ChemRxiv 2025 OpenFE assessment, Nature 2025 BindCraft, NeurIPS 2025 NeuralPLexer3, NAR 2024 ADMETlab 3.0, J. Cheminformatics 2024 REINVENT4, JCIM 2025 HADDOCK3, ambermd.org license page, schrodinger.com/platform/products/fep/academics*
