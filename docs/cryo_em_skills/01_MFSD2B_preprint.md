# Skill: MFSD2B S1P Transporter — Lee Lab (bioRxiv 2026)
**Study:** Structure and mechanism of human sphingosine-1-phosphate transporter MFSD2B  
**Authors:** Ahmed S, Huang M, Dai Y, Yang X, Lee CH, Nguyen LN  
**PDB:** 9ZLV / 9ZLW | **EMDB:** 74413 / 74414 | **PMC:** 12871369

---

## 1. Hypothesis → Design → Findings Diagram

```
HYPOTHESIS
  MFSD2B exports S1P from RBCs/platelets, but its mechanism is unknown.
  Is it proton-coupled (like MFSD2A) or a uniporter (like SPNS2)?
       │
       ▼
SCIENTIFIC DESIGN
  ┌─────────────────────────────────────────────────────────────────┐
  │ 1. Solve cryo-EM structure of MFSD2B + S1P at high resolution  │
  │ 2. Identify S1P binding site by density + mutagenesis           │
  │ 3. Trace translocation pathway by MD simulation                 │
  │ 4. Test coupling mechanism with pH/ion gradient assays          │
  │ 5. Rewire coupling using single mutation (G91D) to confirm      │
  └─────────────────────────────────────────────────────────────────┘
       │
       ▼
DATASETS REQUIRED
  Input 1: Cryo-EM movies (.mrc) — ~6.6M particles, 300 kV, K3, 0.649 Å/pix
  Input 2: Protein sequence (FASTA) → for AlphaFold2 initial model
  Input 3: S1P ligand (SMILES/SDF) → for ligand geometry (eLBOW/GRADE)
  Input 4: [³H]-S1P for transport assays (experimental, not computational)
       │
       ▼
WORKFLOW (see Section 3)
       │
       ▼
OUTPUTS
  Primary: Cryo-EM map (3.03 Å), atomic model (PDB 9ZLV), S1P-bound structure
  Secondary: MD trajectories showing TM2/TM11 gate opening, PMF energy profile
  Validation: 40+ mutant transport activities, pH/ion coupling data
       │
       ▼
KEY FINDINGS
  ✓ S1P binds deepest of any MFS lipid transporter (buried in C-domain)
  ✓ TM2/TM11 is the translocation gate (not TM5/TM8)
  ✓ MFSD2B is a uniporter — no proton or ion coupling
  ✓ G91D single mutation converts it to a proton-dependent antiporter
  ✓ Coupling mechanism is controlled by a D91–K423–D95 charge triad
```

---

## 2. Tool & Dataset Inventory

### Tools Used in This Study

| Tool | Version | Step | BioMate Status |
|------|---------|------|----------------|
| Expi293 cell line + PiggyBac | — | Expression | ❌ Not in BioMate (wet lab) |
| DDM/CHS + digitonin | — | Solubilization | ❌ Not in BioMate (wet lab) |
| GFP-nanobody Sepharose | — | Affinity purification | ❌ Not in BioMate (wet lab) |
| γ-cyclodextrin + saposin | — | Nanodisc reconstitution | ❌ Not in BioMate (wet lab) |
| Vitrobot Mark IV | — | Vitrification | ❌ Not in BioMate (wet lab) |
| Titan Krios G3i, 300 kV | — | Data collection | ❌ Not in BioMate (equipment) |
| Gatan K3 detector | — | Data collection | ❌ Not in BioMate (equipment) |
| **cryoSPARC v4** | v4 | Motion correction + all processing | ⚠️ BioMate has cryoSPARC v5 SPA pipeline |
| Blob picker | built-in | Particle picking | ✅ In BioMate SPA pipeline |
| Template picker | built-in | Particle picking | ✅ In BioMate SPA pipeline |
| **TOPAZ** | — | Neural network picking | ⚠️ Listed in BioMate open-source pipeline; not primary in cryoSPARC pipeline |
| **AlphaFold2** | v2.3 | Initial model | ✅ In BioMate |
| **UCSF ChimeraX** | — | Rigid body docking | ❌ Not explicitly in BioMate |
| **Coot** | v0.9.x | Manual rebuilding | ❌ Not in BioMate as automated step |
| **ISOLDE** | — | Real-space validation | ❌ Not in BioMate |
| **PHENIX** | v1.20 | Real-space refinement + validation | ✅ In BioMate |
| **GROMACS** | 2024.3 | MD simulation | ❌ BioMate has GROMACS for drug discovery MD; not integrated with cryo-EM validation |
| MolProbity | via PHENIX | Validation | ✅ In BioMate QC |

### Datasets
| Dataset | Source | Size | BioMate availability |
|---------|--------|------|---------------------|
| Cryo-EM movies | User-provided | ~2 TB (6.6M movies) | EMPIAR deposit (EMPIAR ID not yet assigned) |
| S1P ligand geometry | SMILES → eLBOW | Small | Can be auto-generated |
| MFSD2B FASTA | UniProt Q8N4L1 | Small | ✅ Can fetch from UniProt |
| MFSD2A/SPNS2 comparisons | PDB entries (from Lee Cell 2023) | Small | ✅ Downloadable from PDB |
| POPC/cholesterol force field | CHARMM36m | — | Available in GROMACS install |

---

## 3. Detailed Workflow with Parameters

```
STEP 1: Sample Preparation (WET LAB — BioMate cannot automate)
  ├── Construct: MFSD2BEM (residues 41–504 + MBP + DARPin + mVenus)
  ├── Expression: Stable Expi293 via PiggyBac + puromycin + FACS
  ├── Solubilize: 20 mM DDM + 4 mM CHS, 1.5h, RT
  ├── Affinity: GFP-nanobody Sepharose; elute with 0.05% digitonin buffer
  ├── Cleavage: 3C protease 40:1, 2h → remove mVenus
  ├── Saposin nanodisc: protein:saposin = 1:15, + γ-cyclodextrin, 14h
  ├── SEC: Superose 6 Increase → pool nanodisc peak
  └── Ligand: 10 μM S1P × 1h before grids
  
  BioMate guidance: When user asks about reconstitution, suggest:
  - Saposin nanodiscs for < 100 kDa membrane proteins
  - γ-cyclodextrin method (faster than Bio-Beads)
  - Confirm nanodisc formation by SEC-MALS (expected: ~100–120 kDa peak)

STEP 2: Grid Preparation (WET LAB)
  ├── Grid: UltrAuFoil R1.2/1.3 Au 300 mesh
  ├── Sample: 10 mg/mL + 0.4 mM fluorinated OM + MBP-nanobody (1:1.2)
  ├── Vitrobot: 3.5 μL, blot 1.5s, 10°C (non-standard!), 100% humidity
  └── Cryo: liquid ethane
  
  BioMate guidance: Standard blot = 3–4s at 4°C. This paper uses 1.5s at 10°C.
  If user reports ice too thick → shorten blot time.
  If preferred orientation → add 0.4 mM fluorinated OM (as done here).

STEP 3: Data Collection
  ├── Microscope: Titan Krios 300 kV
  ├── Detector: Gatan K3 (no energy filter mentioned — notable)
  ├── Pixel size: 0.649 Å/pix @ 130,000×    ← SMALLER than typical 0.83 Å/pix
  ├── Defocus: 1.1–2.1 μm (underfocus)      ← Values are POSITIVE in paper
  ├── Total dose: 60 e⁻/Å², 60 frames
  ├── Dose rate: ~1.0 e⁻/Å²/s
  └── Movies: ~6.6M particles starting pool (DDM); ~7.7M (digitonin)
  
  BioMate parameter guidance:
  - 0.649 Å/pix is aggressive — appropriate for <80 kDa targets
  - No energy filter used here (unusual for Lee lab) — may reflect equipment availability
  - Collect TWO datasets (different detergent conditions) to cross-validate S1P density

STEP 4: Data Processing (cryoSPARC4)
  ┌─────────────────────────────────────────────────────────────┐
  │ Motion correction (cryoSPARC integrated)                    │
  │   └── All frames, dose weighting                           │
  │                                                             │
  │ CTF estimation (cryoSPARC integrated)                       │
  │   └── Manual micrograph curation (discard CTF quality < ok) │
  │                                                             │
  │ THREE parallel pickers → merge + deduplicate                │
  │   ├── Blob picker (cryoSPARC)                              │
  │   ├── Template picker (cryoSPARC)                          │
  │   └── TOPAZ neural network picker                          │
  │   └── Total: ~6.6M / 7.7M initial particles               │
  │                                                             │
  │ 2D classification (cryoSPARC)                              │
  │   └── Discard junk; keep classes with secondary structure  │
  │                                                             │
  │ 3D ab initio (cryoSPARC)                                   │
  │   └── 2–3 classes; select best                            │
  │                                                             │
  │ Heterogeneous 3D refinement                                │
  │   └── Multiple rounds; eliminate suboptimal particles      │
  │                                                             │
  │ Non-uniform (NU) refinement                                │
  │                                                             │
  │ Local refinement (soft mask around MFSD2B)                 │
  │   └── Final: 146,629 particles → 3.03 Å (DDM)             │
  │             141,363 particles → 3.08 Å (digitonin)        │
  └─────────────────────────────────────────────────────────────┘
  
  BioMate parameter guidance:
  - Use THREE pickers (critical for saposin nanodisc samples with high background)
  - Particle yield: 6.6M → 146K = 2.2% (normal for nanodisc)
  - Local refinement essential for small particles (MFSD2B core ~58 kDa)
  - Note: cryoSPARC4 used (BioMate has v5 — compatible, slightly different UI)

STEP 5: Model Building
  ├── AlphaFold2 prediction → rigid body dock in ChimeraX into cryo-EM map
  ├── Real-space refinement: Coot + ISOLDE + PHENIX (phenix.real_space_refine)
  ├── S1P ligand: geometry from CCP4 monomer library or GRADE/eLBOW
  └── Validation: MolProbity, PHENIX comprehensive validation

  BioMate parameter guidance:
  - AF2 model is starting point only — requires extensive manual rebuilding in Coot
  - ISOLDE is important for large structural deviations from AF2 model
  - S1P ligand is unusual — needs careful force field parameterization
  - Target MolProbity < 2.0; this paper achieved 0.86 (exceptional)

STEP 6: MD Simulation (GROMACS)
  ├── System: MFSD2B embedded in POPC:cholesterol (3:1) bilayer
  ├── Water: TIP3P, 150 mM NaCl, 310 K, 1 bar
  ├── Force field: CHARMM36m
  ├── S1P exit: 400 ns production MD from cryo-EM bound state
  └── S1P entry (PMF): Umbrella sampling, 60 windows × 30 ns = 1.8 μs total
  
  BioMate guidance: GROMACS already in BioMate (drug_discovery domain).
  Adapt the existing GROMACS workflow for membrane protein validation:
  - Input: PDB + S1P ligand + POPC:chol bilayer (CHARMM-GUI output)
  - Output: trajectory, PMF curve, S1P translocation pathway video

STEP 7: Functional Assays (WET LAB)
  ├── [³H]-S1P export from transfected Expi293 cells (scintillation counting)
  ├── pH gradient assay (pH 5.5–8.5, same NaCl concentration)
  ├── Ion replacement assay (NaCl vs. choline chloride)
  └── Proteoliposome ³H-S1P + NBD-S1P uptake assays
  
  BioMate guidance: Functional assays confirm structural model.
  Always check: if a key residue mutant retains activity → residue is NOT essential.
  Validate every S1P-contacting residue from the structure with mutagenesis.
```

---

## 4. Visualization Outputs Expected

| Visualization | Tool | What it shows |
|---------------|------|---------------|
| Cryo-EM density map (colored by local resolution) | ChimeraX / UCSF Chimera | Overall map quality; resolution at drug site |
| S1P-binding pocket close-up | ChimeraX | Key contacts K88, T192, Q298, Q301, K423 |
| 2D class averages gallery | cryoSPARC | Particle quality; evidence for secondary structure |
| FSC curves (half-map + model vs. map) | cryoSPARC / PHENIX | Resolution at 0.143; overfitting check |
| Angular distribution plot | cryoSPARC | Preferred orientation check |
| Local resolution map (MonoRes/cryoSPARC) | cryoSPARC | Rigid vs. flexible regions |
| MD trajectory S1P exit (top + side view, multiple time points) | VMD / PyMOL | S1P pathway from bound → extracellular |
| PMF energy profile | GROMACS WHAM | Energy barriers during entry; 4 turning points |
| Mutant transport activity bar chart | Matplotlib/R | Structure-function validation |

---

## 5. BioMate Gap Analysis & Action Items

### What BioMate CAN do today (given user-provided cryo-EM movies)
- ✅ Motion correction (MotionCor2 or cryoSPARC integrated)
- ✅ CTF estimation + QC gating
- ✅ Blob + template particle picking
- ✅ 2D classification + 3D ab initio
- ✅ NU-refinement + local refinement (cryoSPARC v5)
- ✅ PHENIX real-space refinement + MolProbity validation
- ✅ AlphaFold2 initial model

### What BioMate CANNOT do today (gaps)
| Gap | Priority | Effort | Action |
|-----|----------|--------|--------|
| TOPAZ picking in cryoSPARC pipeline | HIGH | Low | Add TOPAZ as 3rd picker option in SPA workflow |
| 0.649 Å/pix data collection mode | MED | None (hardware) | Document when to use: target < 80 kDa |
| Saposin nanodisc reconstitution guidance | HIGH | Low | Add to BioMate sample prep knowledge base |
| Coot/ISOLDE model building | HIGH | High | Add Coot + ISOLDE as workflow step post-PHENIX |
| GROMACS + membrane protein | MED | Medium | Adapt existing GROMACS drug_discovery workflow |
| ChimeraX rigid body docking | MED | Low | Add ChimeraX as a visualization/docking tool |
| DeepEMhancer post-processing | LOW | Low | Add as optional post-processing step |

### What BioMate Should Tell Users When They Ask About MFSD2B-like Projects
```
When user says: "I want to study a small membrane transporter by cryo-EM"

BioMate should:
1. Ask: MW? → if < 100 kDa → recommend saposin nanodisc reconstitution
2. Ask: Have you done a FACS-enriched stable cell line? → if no → suggest PiggyBac or Bac-to-Bac Sf9
3. Recommend: Collect TWO datasets (different detergent conditions) to cross-validate ligand density
4. Warn: For <80 kDa target, use 0.649 Å/pix (130,000× magnification) instead of standard 0.83 Å/pix
5. Recommend: Use THREE pickers (blob + template + TOPAZ) for nanodisc samples
6. Recommend: Local refinement with tight mask around the TM core after global refinement
7. After structure: run GROMACS to validate the binding mode and trace translocation pathway
8. For mechanism: design mutagenesis panel targeting every S1P-contacting residue
```

---

## 6. Key BioMate Learnable Principles from This Study

1. **Pixel size scaling rule:** Use 0.649 Å/pix for <80 kDa targets; 0.83 Å/pix for 80–500 kDa
2. **Three-picker strategy:** Blob + Template + TOPAZ always for membrane proteins in nanodiscs
3. **Particle yield benchmark:** 6.6M → 146K (2.2%) is normal for saposin nanodisc
4. **γ-cyclodextrin for nanodisc:** Faster than Bio-Beads for removing digitonin
5. **Mechanistic mutagenesis design:** Test every contacting residue; test alternative residues at each position (D95A, D95E, D95K, D95S, D95Y — systematic alanine scan + rescue)
6. **Dual detergent cross-validation:** Two datasets (DDM + digitonin) confirm S1P density is real
7. **MD for pathway:** 400 ns for exit pathway; 1.8 μs umbrella sampling for entry PMF
8. **Coupling mechanism test:** pH gradient + Na⁺ replacement → definitively distinguish uniporter from antiporter
