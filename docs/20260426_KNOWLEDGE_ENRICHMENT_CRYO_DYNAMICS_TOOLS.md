# Knowledge Enrichment: Cryo-EM + Protein Dynamics Tools

Date: 2026-04-26

## Summary

Enriched the BioMate knowledge DB with 16 new `tool_knowledge` entries, 9 new `cryo_em_tools` entries, and 18 new RAG chunks (all with BGE-small-en-v1.5 embeddings). All information sourced from peer-reviewed primary papers with DOIs verified against publisher websites.

**DB state after enrichment:**
| Table | Before | After |
|---|---|---|
| `tool_knowledge` (cryo/dynamics scope) | 4 | 20 |
| `cryo_em_tools` | 13 | 22 |
| `cryo_em_chunks` | 163 | 181 |
| `cryo_em_chunks_vec` | 163 | 181 |

---

## New `tool_knowledge` Entries (16 total)

All entries written to the `tool_knowledge` table with `primary_citation` JSON (verified DOI), `recommended_parameters`, `use_cases`, `limitations`, and `alternatives`.

### Cryo-EM Pipeline Tools

| Tool | Category | Primary Citation | DOI |
|------|----------|-----------------|-----|
| **RELION 5** | cryo_em | Burt et al., FEBS Open Bio 2024 (tomography); Kimanius & Scheres, NM 2024 (Blush); Schwab et al., NM 2024 (DynaMight) | 10.1002/2211-5463.13873; 10.1038/s41592-024-02304-8; 10.1038/s41592-024-02377-5 |
| **CTFFFind5** | cryo_em | Elferich, Kong, Zottig, Grigorieff, eLife 2024 | 10.7554/eLife.97227 |
| **MotionCor2** | cryo_em | Zheng et al., Nature Methods 2017 (cite for MotionCor2+3) | 10.1038/nmeth.4193 |
| **3DFlex** | cryo_em | Punjani & Fleet, Nature Methods 2023 | 10.1038/s41592-023-01853-8 |
| **3DVA** | cryo_em | Punjani & Fleet, Journal of Structural Biology 2021 | 10.1016/j.jsb.2021.107702 |
| **ModelAngelo** | cryo_em | Jamali et al., Nature 2024 | 10.1038/s41586-024-07215-4 |
| **DynaMight** | cryo_em | Schwab et al., Nature Methods 2024 | 10.1038/s41592-024-02377-5 |
| **TOPAZ** | cryo_em | Bepler et al., Nature Methods 2019 | 10.1038/s41592-019-0575-8 |
| **crYOLO** | cryo_em | Wagner et al., Communications Biology 2019 | 10.1038/s42003-019-0437-z |

### Pocket Detection / Druggability

| Tool | Category | Primary Citation | DOI |
|------|----------|-----------------|-----|
| **PocketMiner** | structural_bioinformatics | Meller et al., Nature Communications 2023 | 10.1038/s41467-023-36699-3 |
| **P2Rank** | structural_bioinformatics | Krivák & Hoksza, J Cheminformatics 2018 | 10.1186/s13321-018-0285-8 |

### Protein Dynamics / Structure Prediction

| Tool | Category | Primary Citation | DOI |
|------|----------|-----------------|-----|
| **ProDy** | molecular_dynamics | Zhang et al., Bioinformatics 2021 (v2.0) | 10.1093/bioinformatics/btab187 |
| **OpenMM** | molecular_dynamics | Eastman et al., J Phys Chem B 2024 (v8) | 10.1021/acs.jpcb.3c06662 |
| **DiffDock-L** | computational_chemistry | Corso et al., ICLR 2024 | 10.48550/arXiv.2402.18396 |
| **ESMFold** | structure_prediction | Lin et al., Science 2023 | 10.1126/science.ade2574 |
| **RoseTTAFold All-Atom** | structure_prediction | Krishna et al., Science 2024 | 10.1126/science.adl2528 |

---

## New `cryo_em_tools` Entries (9 total)

| id | Tool | Category | Status | Notes |
|----|------|----------|--------|-------|
| 14 | RELION 5 | full_spa_pipeline | partial | No container; RELION_multibody (id=6) is partial existing entry |
| 15 | CTFFFind5 | ctf | missing | CTF handled by CryoSPARC internally; standalone not containerized |
| 16 | MotionCor2 | motion_correction | partial | Motion correction in CryoSPARC; standalone not containerized |
| 17 | 3DFlex | heterogeneity_analysis | partial | Available via CryoSPARC (id=1); BETA; not separate BioMate workflow |
| 18 | 3DVA | heterogeneity_analysis | partial | Available via CryoSPARC (id=1); not separate BioMate workflow |
| 19 | ModelAngelo | model_building | missing | No container; Coot (id=3) and ISOLDE (id=5) are existing entries |
| 20 | crYOLO | particle_picking | missing | TOPAZ (id=2) is primary picker; crYOLO not containerized |
| 21 | PocketMiner | pocket_detection | missing | fpocket used as fallback in current workflows |
| 22 | P2Rank | pocket_detection | missing | Not containerized; fpocket is current tool |

---

## New RAG Chunks (18 total, ids 764–781)

All embedded with BGE-small-en-v1.5 (384-dim, cosine similarity). RAG retrieval test confirmed all 5 test queries return correct on-target chunks (cosine distances 0.11–0.22).

| id | Source File | Section | Topic |
|----|-------------|---------|-------|
| 764 | 11_RELION5_innovations.md | Blush Regularisation | RELION 5 Blush — size barrier reduction |
| 765 | 11_RELION5_innovations.md | DynaMight Heterogeneity | DynaMight VAE vs 3DVA linear PCA |
| 766 | 11_RELION5_innovations.md | Tomography Pipeline | RELION 5 cryo-ET subtomogram averaging |
| 767 | 12_CTFFFind5_MotionCor.md | CTFFFind5 | CTFFFind5 tilt + thickness estimation |
| 768 | 12_CTFFFind5_MotionCor.md | MotionCor2/3 | MotionCor2/3 parameters + dose weighting |
| 769 | 13_CryoSPARC_3DVA_3DFlex.md | 3DVA Algorithm | 3DVA PCA heterogeneity + parameters |
| 770 | 13_CryoSPARC_3DVA_3DFlex.md | 3DFlex Algorithm | 3DFlex vs 3DVA — resolution improvement |
| 771 | 14_ModelAngelo.md | Automated Model Building | ModelAngelo GNN + accuracy benchmarks |
| 772 | 15_PocketMiner_P2Rank.md | PocketMiner GNN | Cryptic pocket prediction + benchmarks |
| 773 | 15_PocketMiner_P2Rank.md | P2Rank Binding Site | P2Rank RF surface scoring |
| 774 | 10_protein_dynamics_ensemble_methods.md | BioEmu Architecture | BioEmu Science 2025 detailed benchmarks |
| 775 | 10_protein_dynamics_ensemble_methods.md | ProDy ANM/GNM | ProDy 2.0 normal mode analysis |
| 776 | 10_protein_dynamics_ensemble_methods.md | OpenMM 8 ML Potentials | OpenMM 8 TorchForce + ANI potentials |
| 777 | 11_RELION5_innovations.md | TOPAZ Particle Picking | TOPAZ PU-learning + crYOLO comparison |
| 778 | 10_protein_dynamics_ensemble_methods.md | DiffDock Generative Docking | DiffDock-L SE(3) diffusion + benchmarks |
| 779 | 10_protein_dynamics_ensemble_methods.md | AlphaFold 3 Architecture | AF3 Pairformer + SE(3) diffusion + license |
| 780 | 10_protein_dynamics_ensemble_methods.md | ESMFold MSA-Free | ESMFold vs AF2 accuracy + failure modes |
| 781 | 10_protein_dynamics_ensemble_methods.md | RoseTTAFold All-Atom | RFAA cofactors + MIT license vs AF3 |

---

## Key Facts Added

### RELION 5 — What's New
- **Blush regularisation** (Kimanius & Scheres, NM 2024): denoising CNN embedded in refinement loop → lowers effective size barrier; enable with `--use_blush`
- **DynaMight** (Schwab et al., NM 2024): VAE-based continuous heterogeneity with nonlinear latent manifold (vs 3DVA's linear PCA)
- **Complete cryo-ET pipeline** (Burt et al., FEBS Open Bio 2024): pseudo-subtomogram approach with single-particle CTF refinement concepts
- **ModelAngelo integration**: automated model building callable from within RELION 5 pipeline
- **AMD/Intel GPU support** via HIP/ROCm and SYCL/oneAPI
- Latest version: 5.0.1 (stable, Sep 2024); 5.1.0 pre-release (Mar 2025) adds amyloid filament processing

### 3DVA vs 3DFlex vs DynaMight vs cryoDRGN
| Method | Model | Improves resolution? | Nonlinear? | Speed | Where |
|--------|-------|---------------------|-----------|-------|-------|
| 3DVA | Linear PCA | No | No | Fast | CryoSPARC |
| 3DFlex | Neural deformation field | Yes (flexible regions) | Yes | Slow (12–48h) | CryoSPARC |
| DynaMight | VAE deformation | Yes | Yes | Slow | RELION 5 |
| cryoDRGN | VAE latent space | No (separate volumes) | Yes | Medium | Standalone |

### CTFFFind5 vs CTFFFind4
- Adds: tilt estimation (~1.9° accuracy), thickness estimation, improved Thon ring visibility for tilted specimens
- For flat specimens: equivalent to CTFFFind4
- Tilt estimation adds minutes per micrograph — enable only for cryo-FIB/tilt series

### PocketMiner vs fpocket
- fpocket: detects **existing** pockets from static structures (geometry-based, fast)
- PocketMiner: predicts **where pockets will open** via thermal fluctuations (GNN trained on MD simulations, requires no simulation)
- These are complementary, not competing: use fpocket first, PocketMiner for apo structures with no visible pocket

### AlphaFold 3 License Restriction
- AF3 weights (Nov 2024/Feb 2025): **non-commercial only** — explicitly prohibits commercial research
- AF2 remains Apache 2.0 (commercial use permitted)
- RoseTTAFold All-Atom: MIT license (commercial use permitted), handles cofactors/PTMs explicitly

---

## Open Gaps (Not Yet Containerized in BioMate)

| Tool | Gap | Priority |
|------|-----|----------|
| RELION 5 | No container; RELION_multibody partial | Medium |
| ModelAngelo | No container; Coot/ISOLDE available | Medium |
| PocketMiner | fpocket used as fallback | Medium |
| P2Rank | fpocket used as fallback | Low |
| crYOLO | TOPAZ is primary picker | Low |
| CTFFFind5 | CryoSPARC handles internally | Low |
| ProDy 2.x | No workflow; could be added to protein dynamics | Low |
| OpenMM 8 | GROMACS is primary MD tool | Low |

---

## Sources (All DOIs Verified)

- RELION 5 cryo-ET: https://febs.onlinelibrary.wiley.com/doi/10.1002/2211-5463.13873
- Blush (RELION 5): https://www.nature.com/articles/s41592-024-02304-8
- DynaMight (RELION 5): https://www.nature.com/articles/s41592-024-02377-5
- CTFFFind5: https://elifesciences.org/articles/97227
- CTFFFind4: https://pubmed.ncbi.nlm.nih.gov/26278980/
- MotionCor2: https://www.nature.com/articles/nmeth.4193
- 3DFlex: https://www.nature.com/articles/s41592-023-01853-8
- 3DVA: https://pubmed.ncbi.nlm.nih.gov/33582281/
- ModelAngelo: https://www.nature.com/articles/s41586-024-07215-4
- PocketMiner: https://www.nature.com/articles/s41467-023-36699-3
- P2Rank: https://link.springer.com/article/10.1186/s13321-018-0285-8
- ProDy 2.0: https://pmc.ncbi.nlm.nih.gov/articles/PMC8545336/
- OpenMM 8: https://pubs.acs.org/doi/10.1021/acs.jpcb.3c06662
- DiffDock-L: https://arxiv.org/abs/2402.18396
- ESMFold: https://www.science.org/doi/10.1126/science.ade2574
- AlphaFold 3: https://www.nature.com/articles/s41586-024-07487-w
- RoseTTAFold All-Atom: https://www.science.org/doi/10.1126/science.adl2528
- TOPAZ: https://www.nature.com/articles/s41592-019-0575-8
- crYOLO: https://www.nature.com/articles/s42003-019-0437-z
- BioEmu-1: https://www.science.org/doi/10.1126/science.adv9817
