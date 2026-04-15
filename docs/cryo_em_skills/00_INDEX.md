# Cryo-EM Skill Documents — BioMate Training Index
**Created:** 2026-04-02  
**Source labs:** Chia-Hsueh Lee, Nieng Yan, Yigong Shi, H. Eric Xu  
**Purpose:** Teach BioMate to advise users like a professional structural biologist

## Skill Documents

| File | Study | Lab | Sample type | BioMate gap level | Status |
|------|-------|-----|-------------|-------------------|--------|
| [01_MFSD2B_preprint.md](01_MFSD2B_preprint.md) | MFSD2B S1P transporter | Lee | Membrane transporter (saposin nanodisc) | Medium — missing: nanodisc reconstitution QC, TOPAZ picker, 0.649 Å/pix | ✅ Done |
| [02_VMAT2_nature2023.md](02_VMAT2_nature2023.md) | VMAT2 neurotransmitter transport | Lee | MFS transporter (saposin nanodisc) | Low — SPA pipeline exists; missing: saposin protocol, dual-dataset comparison | ✅ Done |
| [03_CaV1_2_cell2023.md](03_CaV1_2_cell2023.md) | CaV1.2 multi-drug pharmacology | Yan | Membrane ion channel (detergent) | Low — SPA pipeline exists; missing: drug-binding difference map workflow | ✅ Done |
| [04_BAX_pore_science2025.md](04_BAX_pore_science2025.md) | BAX pore formation | Shi | Pore-forming protein (liposome recon) | High — missing: liposome reconstitution + pore-forming protein protocol | ✅ Done |
| [05_muOR_cell2022.md](05_muOR_cell2022.md) | μ-Opioid receptor Gi complex | Xu | GPCR-G protein complex (nanodisc) | Medium — missing: GPCR-Gi coupling protocol, biased agonism analysis | ✅ Done |
| [06_D1_PAM_preprint2025.md](06_D1_PAM_preprint2025.md) | D1 dopamine multi-PAM cooperation | Xu | GPCR-Gs complex (nanodisc) | Medium — missing: multi-ligand combination design, allosteric site mapping | ✅ Done |
| [07_spliceosome_multistate.md](07_spliceosome_multistate.md) | Spliceosome B→Bact activation | Shi | Large RNP, endogenous purification | High — missing: glycerol gradient, multi-state 3DVA, RNA fitting | ✅ Done |
| [08_symmetric_assembly_capsid.md](08_symmetric_assembly_capsid.md) | HBV/HFTV1 viral capsid | External | Symmetric assembly (T=4 icosahedral) | High — missing: symmetry detection, symmetry expansion, ASU model build | ✅ Done |
| [00_GENERAL_FRAMEWORK.md](00_GENERAL_FRAMEWORK.md) | Protocol generation framework | All | All sample types | Meta-document: decision tree, QC gates, parameter tables | ✅ Done |

## BioMate Tool Inventory Summary

### HAVE (already in BioMate)
- CryoSPARC v5 SPA pipeline (23 steps, full QC gating)
- RELION open-source pipeline (motion correction, CTF, picking, classify, refine)
- CTFFIND4 CTF estimation
- crYOLO particle picking (general model)
- Topaz neural network picker (listed in open-source pipeline)
- Phenix (real-space refinement, validation)
- AlphaFold2/3 structure prediction
- DiffDock, AutoDock Vina (docking)
- QC gates for motion, CTF, picking, 2D, refinement, sharpening, local resolution

### NEED TO ADD
- **TOPAZ training workflow** (train on specific protein dataset, not just general model)
- **Saposin nanodisc reconstitution protocol** (guidance + QC parameters)
- **GPCR-G protein complex assembly protocol**
- **Model building pipeline:** Coot + ISOLDE integration (currently only PHENIX)
- **MD validation pipeline:** GROMACS for post-structure validation (CHARMM36m, 310 K, POPC bilayer)
- **DeepEMhancer** post-processing for heterogeneous local resolution maps
- **3D variability analysis (3DVA)** guidance/workflow in cryoSPARC
- **Drug difference map workflow:** subtract apo from drug-bound, validate occupancy
- **RELION 3D multi-body refinement** for large flexible complexes
- ~~**Cryo-ET subtomogram averaging**~~ — **EXISTS**: `et_full_pipeline` (AreTomo2 → WBP → STA). MISSING: cryo-FIB milling prep guidance only.
- **Functional assay templates:** radioactive transport, patch clamp, BRET, cAMP

## Consolidated BioMate Gap Priority List (across all 6 studies)

| Priority | Gap | Affects | Effort |
|----------|-----|---------|--------|
| **P0** | Saposin nanodisc reconstitution protocol + QC | MFSD2B, VMAT2 | Medium |
| **P0** | Drug difference map pipeline (apo subtract, ±3σ, occupancy check) | CaV1.2, D1R PAM | Medium |
| **P0** | GPCR-G protein complex assembly (apyrase, scFv16, SEC) | μOR, D1R | High |
| **P0** | Liposome reconstitution + pore activation assay (ANTS/DPX) | BAX | Medium |
| **P1** | Coot integration in model building pipeline | All studies | High |
| **P1** | TOPAZ training on study-specific particles | MFSD2B, VMAT2, μOR | Medium |
| **P1** | eLBOW CIF generation for small molecule ligands | CaV1.2, μOR, D1R | Low |
| **P1** | RELION 3D multi-body refinement | BAX, flexible complexes | Medium |
| **P1** | Local refinement dual-mask strategy documentation | μOR, D1R | Low |
| **P1** | Functional assay templates (BRET, cAMP, transport, lysis) | μOR, D1R, BAX | Low |
| **P2** | DeepEMhancer post-processing | All | Medium |
| **P2** | 3D Variability Analysis (3DVA) workflow | CaV1.2, GPCRs | Medium |
| **P2** | ISOLDE for strained oligomers | BAX | Medium |
| ~~P2~~ | ~~Cryo-ET + subtomogram averaging pipeline~~ | Already exists as `et_full_pipeline` | ✅ Done |
| **P2** | GPCR/VGIC/MFS biological knowledge base updates | System prompt | Low |

## Cross-Cutting Parameters That BioMate Must Know

| Parameter | Standard value | When to deviate |
|-----------|---------------|----------------|
| Pixel size | 0.83 Å/pix | Use 0.649 for < 80 kDa; 1.08–1.30 for > 500 kDa |
| Defocus range | −0.8 to −2.0 μm | −1.0 to −3.0 for > 1 MDa complexes |
| Total dose | 50–60 e⁻/Å² | 40–45 for radiation-sensitive samples |
| Frame count | 40–60 | More frames = better early-frame signal |
| Blot conditions | 3–4 s, 4°C, 100% RH | 1.5 s for fragile complexes (MFSD2B: 1.5 s at 10°C) |
| Final particle count | > 50K for routine; > 200K for < 3 Å | More particles = better resolution |
| FSC criterion | 0.143 (gold-standard) | Always report; never use 0.5 as primary criterion |
| MolProbity target | < 2.0 | < 1.5 excellent; 0.86 world-class |
| Ramachandran favored | > 97% | < 95% requires explanation |
