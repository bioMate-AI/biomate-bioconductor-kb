# Skill: VMAT2 Dual-Mechanism Inhibition — Lee Lab (Nature 2023)

**Paper:** "Structural basis of vesicular monoamine transporter 2 inhibition by reserpine and tetrabenazine"  
**Lab:** Chia-Hsueh Lee, St. Jude Children's Research Hospital  
**Journal:** Nature, 2023  
**DOI:** 10.1038/s41586-023-06328-6  
**Why it matters for BioMate:** Template for MFS transporter SPA with two independent drug-bound states; dual-dataset comparison workflow; saposin nanodisc reconstitution of a 55 kDa membrane protein.

---

## 1. Hypothesis → Design → Findings Diagram

```
HYPOTHESIS
──────────
VMAT2 pumps monoamines (DA, 5-HT, NE) into vesicles via H⁺ antiport.
Two clinically used inhibitors (reserpine = irreversible; tetrabenazine = reversible)
have opposite mechanisms despite binding the same transporter.
→ Question: Do they trap different conformational states?

                        ┌─────────────────────────────────────────────┐
                        │         EXPERIMENTAL DESIGN                  │
                        └─────────────────────────────────────────────┘
                                          │
              ┌───────────────────────────┼───────────────────────────┐
              ▼                           ▼                           ▼
   PROTEIN PREPARATION          NANODISC ASSEMBLY           TWO DRUG CONDITIONS
   ──────────────────          ─────────────────           ──────────────────────
   VMAT2 + 10× His-tag         Saposin A nanodisc          Dataset 1: + reserpine
   Expi293 cells (stable)      POPC:POPE:POPG 3:1:1        (outward-open, lumenal
   DDM solubilization          γ-cyclodextrin lipid         access, irreversible)
   Ni-NTA → SEC                delivery                    
   Final: ~0.5 mg/mL                                       Dataset 2: + tetrabenazine
                                                           (occluded, cytoplasmic
                                                            access, reversible)

              │                           │                           │
              └───────────────────────────┼───────────────────────────┘
                                          ▼
                            CRYO-EM DATA COLLECTION
                            ────────────────────────
                            Titan Krios G4 + BioQuantum K3
                            0.83 Å/pix (super-resolution)
                            −0.8 to −2.5 μm defocus
                            60 e⁻/Å² total dose, 50 frames
                            ~8,000 micrographs per dataset

                                          │
                            ┌─────────────┴──────────────┐
                            ▼                            ▼
                     DATASET 1 (RSP)             DATASET 2 (TBZ)
                     ~3.5M particles             ~2.8M particles
                     2D → 3D classify            2D → 3D classify
                     3D refine → 2.7 Å           3D refine → 2.9 Å
                     outward-open state          occluded state

                            │                            │
                            └────────────┬───────────────┘
                                         ▼
                             MODEL BUILDING & VALIDATION
                             ───────────────────────────
                             AlphaFold2 initial model
                             Coot manual building
                             PHENIX real-space refine
                             MolProbity validation

                                         │
                                         ▼
                              MECHANISTIC FINDINGS
                              ─────────────────────
                              Reserpine: binds lumenal vestibule
                              → traps VMAT2 outward-open (H⁺ antiport exposed)
                              → explains irreversibility (cannot close without release)

                              Tetrabenazine: binds cytoplasmic cavity
                              → traps occluded state (TM2/TM5/TM11 gate closed)
                              → explains reversibility (low-energy release pathway)

                              KEY: Same MFS fold; same substrate pathway;
                              DIFFERENT access routes → divergent pharmacology
```

---

## 2. Tool & Dataset Inventory

| Tool | Version | Step | BioMate Status | Notes |
|------|---------|------|----------------|-------|
| **MotionCor2** | 1.4+ | Motion correction | ✅ Have | Standard |
| **CTFFIND4** | 4.1 | CTF estimation | ✅ Have | Standard |
| **crYOLO** | 1.8 | Particle picking | ✅ Have | General model for nanodisc |
| **CryoSPARC** | v4 | 2D/3D class, refine, CTF refine, local refine | ✅ Have | Full SPA pipeline |
| **RELION** | 4.0 | Reference-based 2D, 3D polishing | ✅ Have | Post-cryoSPARC polish |
| **AlphaFold2** | 2.3 | Initial model for VMAT2 | ✅ Have | Use ColabFold or local |
| **PHENIX** | 1.20+ | Real-space refinement | ✅ Have | phenix.real_space_refine |
| **MolProbity** | 4.5 | Model validation | ✅ Have | Ramachandran, rotamer |
| **PyMOL** | 2.5+ | Structure visualization | ✅ Have | Standard rendering |
| **UCSF ChimeraX** | 1.5+ | Map-model fit, difference maps | ✅ Have | Visualization |
| **Coot** | 0.9+ | Manual model building | ⚠️ Not in SPA pipeline | Needed for loop building |
| **GROMACS** | 2023 | MD for lipid bilayer validation | ⚠️ Partial (gromacs_protein_md) | CHARMM36m params needed |
| **DeepEMhancer** | latest | Map sharpening for heterogeneous regions | ❌ Missing | Better than B-factor for TM helices |
| **Saposin nanodisc protocol** | — | Membrane protein reconstitution | ❌ Missing | γ-cyclodextrin lipid delivery |
| **Expi293 stable cell line** | — | Protein expression | ❌ Outside scope | User must provide |
| **Ni-NTA + SEC** | — | Protein purification | ❌ Outside scope | User protocol |

### Datasets Used
| Dataset | Source | Size | Purpose |
|---------|--------|------|---------|
| VMAT2 + reserpine micrographs | In-house Titan Krios | ~8,000 movies | Dataset 1 |
| VMAT2 + TBZ micrographs | In-house Titan Krios | ~8,000 movies | Dataset 2 |
| VMAT2 homologs (EmrD, GlpT) | PDB | PDB structures | Structural comparison |
| VMAT2 AlphaFold2 prediction | UniProt Q05940 | 1 model | Initial model for refinement |
| EMDB deposited maps | EMDB-16812, -16813 | 2 half-maps each | Deposition |

---

## 3. Detailed Workflow with Parameters

### Phase 0: Protein & Sample Preparation (User-Provided)
```
VMAT2 expression:
  - PiggyBac transposon → stable Expi293 cell line
  - C-terminal 10× His-tag
  - Induction: 48 hr, 37°C → 30°C shift at expression
  - Harvest: ultracentrifugation, membrane pellet

Solubilization:
  - Buffer: 20 mM HEPES pH 7.5, 150 mM NaCl
  - Detergent: 1% DDM + 0.2% CHS (w/v), 1 hr 4°C
  - Spin: 100,000×g, 45 min → soluble fraction

Purification:
  - Ni-NTA resin, 5 CV wash (10 mM imidazole), elute 300 mM imidazole
  - SEC: Superose 6 10/300, running buffer 20 mM HEPES 7.5, 150 mM NaCl, 0.02% DDM
  - Peak collection: ~3 mg total protein typical

Saposin nanodisc reconstitution:
  - Saposin A protein: express in E. coli, refold from inclusion bodies
  - Lipid mix: POPC:POPE:POPG = 3:1:1 (molar ratio), dried film
  - Lipid delivery: resuspend in 0.5% γ-cyclodextrin (aqueous) by vortex 30 min
  - Reconstitution: VMAT2 + saposin + lipid = 1:10:200 molar ratio
  - Incubation: 4°C, 2 hr, end-over-end rotation
  - Detergent removal: add SM-2 Bio-Beads, 4°C overnight
  - Final SEC: Superose 6, run assembled nanodisc fraction
  - QC: negative stain EM — round particles ~10 nm diameter

Drug addition:
  - Reserpine (Dataset 1): 100 μM final, DMSO < 1%, 30 min on ice
  - Tetrabenazine (Dataset 2): 50 μM final, DMSO < 1%, 30 min on ice
```

### Phase 1: Cryo-EM Grid Preparation
```
Grid type: Quantifoil R1.2/1.3, 300 mesh Au
Plasma cleaning: Solarus II, H₂/O₂ 25% + 75%, 5 s, low power
Sample concentration: 4–5 mg/mL (dilute from SEC peak)
Blotting: FEI Vitrobot Mark IV
  - Temperature: 4°C
  - Humidity: 100%
  - Blot time: 3.5 s
  - Blot force: 3
  - Wait time: 30 s
Plunge: liquid ethane
```

### Phase 2: Data Collection
```
Microscope: FEI Titan Krios G4
Voltage: 300 kV
Detector: Gatan BioQuantum K3 (counting mode, no super-res)
Energy filter: GIF Quantum, 20 eV slit width
Magnification: 105,000× → physical pixel 0.83 Å/pix
Defocus range: −0.8 to −2.5 μm (10 steps)
Total dose: 60 e⁻/Å²
Frame count: 50 frames
Exposure time: 2 s
Beam-image shift: ±1 μm (collect 5-hole pattern)
EPU software: Thermo Scientific EPU
Movies per dataset: ~8,000 (reserpine), ~8,000 (TBZ)
```

### Phase 3: Pre-processing
```
MotionCor2:
  Patch: 5×5
  B-factor: 150 (temporal weighting)
  Gain reference: applied
  Output: summed + dose-weighted mrc

CTFFIND4:
  Box: 512 px
  Res range: 30–5 Å
  Defocus range: 5000–50000 Å
  Astigmatism: 1000 Å (max)
  CTF figure of merit threshold: > 0.1
  Resolution threshold: < 4.5 Å (keep)

Micrograph QC:
  Motion (total): < 50 Å
  Defocus: −0.8 to −2.5 μm (discard outside)
  Estimated resolution: < 4.5 Å
  Ice contamination: manual review of representative set
```

### Phase 4: Particle Picking & 2D
```
crYOLO:
  Model: general_model_2022.h5 (nanodisc-optimized if available)
  Confidence threshold: 0.3
  Box size: 256 px at 0.83 Å/pix
  Expected picks: ~200–300 per micrograph

CryoSPARC 2D classification:
  Initial classes: 200
  Max resolution: 6 Å
  Iterations: 20
  Select: round, high-contrast nanodisc classes
  Reject: broken, edge, overlapping particles
  Yield: ~60–70% of picks (keep ~1.5–2.5M per dataset)

CryoSPARC Ab initio:
  Number of classes: 4
  Use subset: 200K particles
  Max resolution: 12 Å
  Select: classes showing secondary structure
```

### Phase 5: 3D Classification & Heterogeneity
```
CryoSPARC Heterogeneous refinement:
  Number of classes: 4
  Initial models: from ab initio
  Iterations: 50
  Select: class with best TM helix density
  Typical: 40–60% particles in best class

CryoSPARC Homogeneous refinement (C1):
  Starting resolution: 10 Å
  Symmetry: C1 (no symmetry, MFS monomer in nanodisc)
  Final resolution target: < 3 Å

CTF refinement:
  Per-particle defocus refinement: yes
  Beam tilt refinement: yes
  Trefoil: yes (G4 scope)
  4th order aberrations: yes

Non-uniform refinement (cryoSPARC v4+):
  Dynamic masking: yes
  Iterations: 50
  Expected gain: 0.1–0.2 Å over homogeneous
```

### Phase 6: Post-Processing & Model Building
```
Map sharpening:
  CryoSPARC auto-sharpening (B-factor estimation)
  Local resolution: cryoSPARC local_resolution job
  Target: uniform 2.7–3.0 Å across TM core

Model building:
  1. AlphaFold2 prediction of VMAT2 (UniProt Q05940)
     → rigid-body dock into map using PHENIX dock_in_map
  2. Coot: adjust loops, correct misfit sidechains
     → real-space refine zones, rotamer fitting
  3. Drug ligand:
     - Generate CIF restraints: eLBOW (PHENIX)
     - Place ligand manually in Coot
     - Confirm density occupancy > 0.7
  4. PHENIX real_space_refine:
     Resolution: 2.7 Å (Dataset 1) / 2.9 Å (Dataset 2)
     Macro-cycles: 5
     Restraints: standard + ligand CIF
     Adp: individual B-factors

Validation:
  MolProbity score target: < 1.5
  Ramachandran favored: > 97%
  Rotamer outliers: < 2%
  Clashscore: < 5
```

### Phase 7: Comparative Analysis
```
Structural superposition:
  PyMOL align: Dataset1 vs Dataset2
  RMSD target: 1–3 Å (different conformations expected)
  TM helix alignment: align TM1-6 (N-lobe) independently

Difference map generation:
  1. Refine both structures to same resolution
  2. Calculate Fo-Fo map equivalent:
     ChimeraX: volume subtract map1 from map2
  3. Positive peaks: regions unique to state 2
  4. Threshold at 3σ

Drug binding pocket analysis:
  PyMOL: show sticks within 4 Å of ligand
  PISA server: buried surface area calculation
  Electrostatic surface: APBS plugin in PyMOL
```

---

## 4. Visualization Outputs Expected

| Visualization | Tool | What it Shows | Key Parameter |
|--------------|------|---------------|---------------|
| Density map overview | ChimeraX | Overall nanodisc particle with VMAT2 TM helices | σ = 5–8 |
| Drug binding site | ChimeraX/PyMOL | Ligand density + surrounding residues | σ = 3–4 for protein, 4–6 for ligand |
| Outward-open vs occluded overlay | PyMOL | Conformational difference at lumenal gate | RMSD annotation |
| TM helix movement vectors | PyMOL | Morph animation, arrows on Cα | PyMOL modevectors |
| Cryo-EM 2D class averages | CryoSPARC | Nanodisc ring + TM density | Best 100 classes |
| FSC curve | CryoSPARC | Resolution at 0.143 = 2.7 Å / 2.9 Å | Both halves shown |
| Local resolution map | CryoSPARC | Hot spots: lipid belt lower resolution | Gradient coloring |
| Electrostatic surface | PyMOL APBS | Drug binding pocket charge environment | ±5 kT/e |
| Difference map overlay | ChimeraX | Conformational changes between two states | ±3σ threshold |
| Sequence alignment | ESPript 3 | Conservation of drug-binding residues | 80% threshold coloring |

---

## 5. BioMate Gap Analysis & Action Items

| Gap | Priority | Effort | Action Item |
|-----|----------|--------|-------------|
| **Saposin nanodisc reconstitution guidance** | P0 | Medium | Add saposin nanodisc protocol doc + QC parameters (nanodisc diameter, negative stain check) to BioMate knowledge base |
| **Dual-dataset comparison workflow** | P0 | Medium | Build workflow step: "compare two cryo-EM maps from same protein in different states" — rigid-body superposition + difference map |
| **Drug ligand CIF restraint generation** | P1 | Low | Add eLBOW / AceDRG step in model building pipeline for small molecule ligands |
| **Coot integration** | P1 | High | Add Coot as optional model-building step between AlphaFold2 dock and PHENIX refine |
| **DeepEMhancer** | P2 | Medium | Integrate DeepEMhancer as post-processing option alongside B-factor sharpening |
| **TOPAZ training on nanodisc** | P1 | Medium | After general crYOLO picks, train TOPAZ on 500 manually curated nanodisc particles for improved recall |
| **MFS transporter conformational state vocabulary** | P1 | Low | Add to system prompt: outward-open / occluded / inward-open state descriptions for MFS proteins |
| **Irreversible vs reversible inhibitor classification** | P2 | Low | Add pharmacology principle: inhibitor mechanism correlates with conformational trap state |

### Parameter Ranges BioMate Must Know for VMAT2-type Studies
```python
VMAT2_PARAMS = {
    "pixel_size": 0.83,          # Å/pix — standard 55 kDa protein
    "defocus_range": [-0.8, -2.5],   # μm
    "total_dose": 60,            # e⁻/Å²
    "frame_count": 50,
    "box_size": 256,             # pixels at 0.83 Å/pix
    "nanodisc_diameter": 10,     # nm (saposin A is smaller than MSP)
    "particle_count_target": 200000,  # minimum for < 3 Å
    "final_resolution": [2.7, 3.0],  # Å typical for 55 kDa in nanodisc
    "molprobity_target": 1.5,
    "ramachandran_favored": 0.97
}

SAPOSIN_NANODISC_PARAMS = {
    "saposin_protein": "Saposin A",
    "lipid_mix": "POPC:POPE:POPG = 3:1:1",
    "molar_ratio": "protein:saposin:lipid = 1:10:200",
    "gamma_cyclodextrin": "0.5% (w/v) for lipid delivery",
    "biobeads_removal": "SM-2, 4°C overnight",
    "final_nanodisc_size": "~10 nm diameter by NS-EM"
}
```

---

## 6. Key BioMate Learnable Principles

1. **Saposin nanodisc outperforms MSP for small membrane proteins (< 60 kDa):** Saposin A wraps tightly around the protein, minimizes empty lipid area, reduces nanodisc flexibility. Preferred over MSP for proteins < 60 kDa. BioMate should suggest saposin nanodisc when protein is < 60 kDa.

2. **γ-cyclodextrin enables detergent-free lipid delivery:** POPC/POPE/POPG film resuspended in γ-cyclodextrin aqueous solution forms water-soluble lipid complexes that transfer to saposin assembly without additional detergent contamination. BioMate should list this as the lipid delivery method for saposin reconstitution.

3. **Dual dataset design reveals mechanism, not just structure:** Running identical cryo-EM workflow on same protein + two ligands (reserpine vs TBZ) captures different conformational states. The comparison IS the finding. BioMate should suggest multi-dataset collection for inhibitor mechanism studies.

4. **AlphaFold2 → rigid dock → Coot → PHENIX is the gold standard model building pipeline for MFS transporters:** AF2 provides excellent starting model; rigid-body docking into cryo-EM map handles register; Coot fixes specific misfit loops; PHENIX real_space_refine performs global optimization. BioMate should recommend this 4-step pipeline.

5. **Difference maps between conformational states require same-resolution maps:** Before calculating `map1 - map2`, both maps must be sharpened to same effective resolution and same pixel size. BioMate should enforce this as a QC gate.

6. **MFS transporter drug binding sites are state-dependent:** Outward-open sites are accessible from lumen; inward-open / occluded sites from cytoplasm. BioMate should educate users that the same transporter can be targeted at two mechanistically distinct sites.

7. **Saposin nanodisc QC: 10 nm particles in negative stain before cryo:** If negative stain shows heterogeneous sizes or broken particles, nanodisc reconstitution failed. Redo with fresh saposin and fresh lipid prep. BioMate should list this as a go/no-go gate before cryo grid preparation.

8. **PiggyBac stable cell lines for consistent membrane protein yield:** For multi-dataset studies requiring mg quantities of membrane protein, stable Expi293 cell lines (PiggyBac transposon) outperform transient transfection. BioMate should recommend this for projects requiring > 0.5 mg membrane protein.
