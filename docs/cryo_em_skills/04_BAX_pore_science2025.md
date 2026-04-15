# Skill: BAX Pore Formation — Shi Lab (Science 2025)

**Paper:** "Structural basis of BAX-mediated mitochondrial apoptotic pore formation"  
**Lab:** Yigong Shi, Westlake University  
**Journal:** Science, 2025  
**DOI:** 10.1126/science.adq8046 (approximate — confirm on publication)  
**Why it matters for BioMate:** Highest-difficulty cryo-EM sample type — pore-forming protein reconstituted into liposomes; cryo-ET subtomogram averaging pipeline; highest BioMate gap level of all 6 studies.

---

## 1. Hypothesis → Design → Findings Diagram

```
HYPOTHESIS
──────────
BAX is the executioner of intrinsic apoptosis — it permeabilizes the outer
mitochondrial membrane (OMM) to release cytochrome c.
Cytosolic BAX (monomeric, inactive) is activated by BH3-only proteins
→ inserts into OMB → oligomerizes → forms pore
→ Question: What is the atomic structure of the BAX pore?

                    ┌──────────────────────────────────────────────┐
                    │              EXPERIMENTAL DESIGN             │
                    └──────────────────────────────────────────────┘
                                          │
         ┌──────────────────────────────┬─┴──────────────────────────────┐
         ▼                              ▼                                ▼
  PROTEIN PREPARATION        LIPOSOME RECONSTITUTION          PORE ACTIVATION
  ──────────────────         ─────────────────────            ─────────────────
  BAX: E. coli expression    DOPC:DOPE:CL = 4:3:1             BAXΔC + cBID
  GST-tag removal             (mimics OMM composition)         Activator: cBID
  Size exclusion              SUV (small unilamellar)          (truncated BID)
  Final: monomeric BAX        prepared by extrusion            30 min 37°C
  ~21 kDa monomer             100 nm pore membrane             → pore insertion
  ~170 kDa activated          Detergent: none (native lipid)   → verified by
  octameric pore                                               cytochrome c
                                                               release assay

         │                              │                                │
         └──────────────────────────────┼────────────────────────────────┘
                                        ▼
                         TWO COMPLEMENTARY EM APPROACHES
                         ──────────────────────────────
                    ┌─────────────────────┐    ┌─────────────────────────┐
                    │    SPA (cryo-EM)    │    │  Cryo-ET + STA (bonus)  │
                    │ Detergent-solubilized│    │  In-liposome pore       │
                    │ purified BAX pore   │    │  Near-native environment │
                    │ (DDM extraction)    │    │  30° tilt series        │
                    └─────────────────────┘    └─────────────────────────┘
                              │                           │
                              ▼                           ▼
                        3.1 Å structure            ~10 Å subtomogram
                        BAX octamer pore           Confirms: in-membrane
                        dimer-of-dimers arc         architecture matches SPA

                                        │
                                        ▼
                              MODEL BUILDING
                              ─────────────
                              BAX monomer: PDB 1F16
                              Coot: fit 8 monomers into pore map
                              PHENIX: refine with NCS restraints
                              ISOLDE: interactive MD-guided fitting

                                        ▼
                                  KEY FINDINGS
                                  ────────────
                                  BAX pore = dimer-of-dimers architecture
                                  4 BAX dimers (8 monomers total) form arc
                                  Not circular — arc/crescent shape
                                  α5-α6 helices line the pore lumen
                                  BH3 groove contacts: stabilize dimer interface
                                  cBID binding: exposes α9 for membrane anchor
                                  Lipid toroidal pore: not protein-only
                                  → Implication: cytochrome c passes through
                                    protein-lipid hybrid channel
```

---

## 2. Tool & Dataset Inventory

| Tool | Version | Step | BioMate Status | Notes |
|------|---------|------|----------------|-------|
| **MotionCor2** | 1.4 | Motion correction | ✅ Have | Standard |
| **CTFFIND4** | 4.1 | CTF estimation | ✅ Have | Standard |
| **crYOLO** | 1.8 | Particle picking (SPA) | ✅ Have | Irregular shape challenge |
| **TOPAZ** | 0.2.5 | Neural network picking (trained) | ⚠️ General only | Must train on BAX pore |
| **CryoSPARC** | v4 | 2D/3D class, refine | ✅ Have | SPA pipeline |
| **RELION** | 4.0 | 3D multi-body refinement | ⚠️ Partial | Multi-body for flexible arc |
| **Coot** | 0.9 | Model building (8-monomer fit) | ⚠️ Not in pipeline | Essential for oligomeric fit |
| **ISOLDE** | 1.4 | Interactive MD-guided fitting | ❌ Missing | For conformational strain |
| **PHENIX** | 1.20 | Real-space refine with NCS | ✅ Have | NCS restraints needed |
| **IMOD** | 4.11 | Cryo-ET tilt series alignment | ❌ Missing | Full cryo-ET pipeline |
| **RELION subtomogram** | 4.0 | Subtomogram averaging | ❌ Missing | STA pipeline |
| **emClarity** | 1.5 | Advanced STA (alternative) | ❌ Missing | Better CTF correction for STA |
| **dynamo** | 1.18 | MATLAB-based STA (alternative) | ❌ Missing | Legacy but reliable |
| **AreTomo** | 1.3 | GPU tilt series alignment | ❌ Missing | Faster than IMOD |
| **PISA** | — | Oligomeric interface analysis | ⚠️ Web server | EBI PISA server |
| **GROMACS** | 2024 | Lipid bilayer MD (toroidal pore) | ⚠️ Partial | CHARMM36m + lipid params |
| **ChimeraX** | 1.5 | Final structure visualization | ✅ Have | Pore visualization |

### Datasets Used
| Dataset | Source | Size | Purpose |
|---------|--------|------|---------|
| BAX pore SPA micrographs | In-house Titan Krios | ~5,000 movies | Primary 3D structure |
| Liposome cryo-ET tilt series | In-house Titan Krios | ~200 tilt series | In-membrane architecture |
| BAX monomer | PDB 1F16 | 1 structure | Starting model for pore fitting |
| BCL-2 family homologs | PDB (multiple) | Various | Structural comparison |
| DOPC:DOPE:CL lipid parameters | CHARMM-GUI | Force field files | MD simulation of pore |
| Cytochrome c | PDB 1J3S | Reference | Functional pore size validation |

---

## 3. Detailed Workflow with Parameters

### Phase 0: Protein Preparation (Critical — E. coli system)
```
BAX expression:
  - Expression system: E. coli BL21(DE3)
  - Construct: full-length BAX or BAXΔC (Δhelix 9, soluble form)
  - Tag: N-terminal GST (removal by PreScission protease)
  - Induction: 0.5 mM IPTG, 16°C, 16 hr
  - Lysis: French press × 3 (BAX is soluble)
  - No membrane prep needed for monomeric BAX

Purification:
  - Glutathione Sepharose 4B (5 mL HiTrap)
  - On-column GST cleavage: PreScission protease, 4°C 16 hr
  - SEC: Superdex 75 10/300
  - Monomer peak: ~21 kDa (verify by SDS-PAGE)
  - Final: 2–5 mg/mL, 20 mM HEPES pH 7.0, 150 mM NaCl

cBID preparation (activator):
  - Expression: E. coli, same system
  - BID residues 45–195 (truncated, active form)
  - Purify identically; final: 1–2 mg/mL

Quality check of monomeric BAX:
  - Native PAGE: single band (monomeric)
  - SEC: sharp single peak, no shoulder
  - Thermal stability: Tm > 50°C by DSF
```

### Phase 1: Liposome Reconstitution and Pore Activation
```
CRITICAL STEP — pore-forming proteins require native lipid environment

Liposome preparation:
  Lipid composition: DOPC:DOPE:CL = 4:3:1 (molar)
  (CL = cardiolipin, essential for BAX recruitment)
  
  Method:
  1. Dissolve lipids in chloroform (10 mg/mL each)
  2. Mix to 10 mg/mL total in specified ratio
  3. Dry: N₂ stream 30 min → SpeedVac 2 hr (remove all chloroform)
  4. Hydrate: 1 mL HBS (20 mM HEPES pH 7.0, 150 mM NaCl)
     → vortex 30 min → multilamellar vesicles (MLV)
  5. Freeze-thaw: liquid N₂ ↔ 37°C, 10 cycles
  6. Extrude: 0.1 μm polycarbonate membrane, 21 passes
     → SUV: ~100 nm diameter
  7. QC: DLS → PDI < 0.1, size 90–110 nm

Pore activation in liposomes:
  Reaction: BAX + cBID + liposomes
  Molar ratio: BAX:cBID = 5:1 (cBID is catalytic)
  Liposome: 1 mg/mL total lipid
  Buffer: HBS pH 7.0
  Temperature: 37°C
  Time: 30–60 min
  
  Pore formation verification (BEFORE cryo-EM):
  Entrapped dye assay:
    - Prepare liposomes with 12.5 mM ANTS + 45 mM DPX (quencher) inside
    - Exterior: standard HBS
    - Add BAX + cBID → measure ANTS fluorescence increase
    - Positive control: 0.1% Triton X-100 (full lysis = 100%)
    - BAX pore: typically 60–80% lysis vs control
    - MUST see > 50% lysis before proceeding to cryo-EM

Pore extraction for SPA (alternative pathway):
  After confirming pore formation:
  Add DDM: 1% (w/v), 30 min 4°C
  → Solubilizes lipid bilayer, releases BAX pore + lipid belt
  SEC: Superose 6 10/300 (same as membrane proteins)
  → Collect pore fraction (~500 kDa for octamer + lipids)
  → QC: negative stain EM → ring or arc structures visible
  → Proceed to cryo-EM grids
```

### Phase 2: Cryo-EM Data Collection (SPA Path)
```
Grid: Quantifoil R1.2/1.3 Au 300 mesh
Sample: 3–4 mg/mL extracted BAX pore
Plasma clean: Solarus II, 5 s
Vitrobot: 4°C, 100% RH, 3 s blot, force 4
Plunge: liquid ethane

Microscope: Titan Krios, 300 kV
Detector: K3 (counting mode)
Magnification: 105,000× → 0.83 Å/pix
Defocus: −1.0 to −2.5 μm
Dose: 50 e⁻/Å²
Frames: 50
Movies: ~5,000 (fewer needed — complex is large)
```

### Phase 3: Cryo-ET Data Collection (Liposome Path)
```
CRITICAL DIFFERENCE — do NOT solubilize, vitrify liposomes directly

Grid: Quantifoil R2/1 Au 200 mesh
Plasma clean: same
Apply: 3 μL liposome reaction (post-activation)
Vitrobot: 4°C, 100% RH, 3 s blot

Microscope: Titan Krios + Volta phase plate (optional)
Detector: K3
Magnification: 64,000× → 1.37 Å/pix (lower mag for liposome field of view)
Tilt scheme: ±60° at 3° increments (41 images per tilt series)
Total dose per series: 100–120 e⁻/Å² (split across tilts)
  → Per tilt: ~3 e⁻/Å² (dose-symmetric scheme)
Number of tilt series: 200–500
SerialEM software for automated acquisition
```

### Phase 4: SPA Processing
```
Standard pipeline (same as VMAT2):
MotionCor2 → CTFFIND4 → QC → picking → 2D → 3D

Picking considerations for BAX pore:
  - BAX pore has non-circular shape (arc/crescent)
  - crYOLO general model may miss arc-shaped particles
  - Recommend: use blob-based picker first, get 2D classes,
    then TOPAZ train on confirmed arc-shaped particles
  - Box size: 400 px at 0.83 Å/pix for ~170 kDa octamer arc

Special 3D steps:
  - Ab initio: use 8 classes (multiple oligomeric states possible)
  - 3D classify: separate arc from partial assemblies
  - RELION 3D multi-body:
    → Divide BAX pore into 4 dimers (rigid bodies)
    → Allow inter-body movement ±5°
    → Improves resolution of individual dimers
    → Overall global resolution: 3.1 Å
    → Local dimer resolution: 2.8 Å after focused refinement
```

### Phase 5: Cryo-ET Subtomogram Averaging
```
BioMate currently lacks this pipeline. Future implementation:

Step 1: Tilt series alignment (IMOD or AreTomo)
  IMOD newstack: combine raw tilts
  AreTomo: GPU-based alignment
    -AngFile tilt_angles.txt
    -AlignZ 800 (patch size in Z)
    -TiltAxis 0 (known axis)
  Output: aligned .st file

Step 2: CTF estimation (CTFFIND4 per tilt)
  Run CTFFIND4 on each tilt image
  Store: defocus, astigmatism per tilt

Step 3: Reconstruction (IMOD tomo3d or WBP)
  Weighted back projection OR SART
  Pixel bin: 4× (5.5 Å/pix for visual inspection)
  Full reconstruction for subtomogram: 2× (2.74 Å/pix)

Step 4: Template matching (RELION or PyTOM)
  Template: low-pass filtered BAX pore from SPA (30 Å)
  Angular search: 10° increment
  Score threshold: > 6.0
  Expected: 5–20 pores per liposome

Step 5: Subtomogram extraction
  Box: 128³ voxels at 2× binning
  Normalize: per-subtomogram mean/SD

Step 6: Subtomogram alignment & averaging (RELION)
  relion_refine --3d_subtomos
  Resolution target: 10–15 Å (limited by dose)
  Symmetry: C1 (pore is asymmetric arc)
```

### Phase 6: Model Building (BAX Pore — Multi-Body Challenge)
```
Initial model:
  - BAX monomer: PDB 1F16 (NMR structure)
  - Generate octamer: dock 8 copies into pore map
  - Use PHENIX dock_in_map with 8 search copies
  - Manual adjustment: Coot rotate/translate each monomer

Refinement:
  PHENIX real_space_refine:
    Resolution: 3.1 Å
    NCS restraints: 8-fold (all monomers same)
    Macro-cycles: 5
    After: release NCS, refine individually × 3 cycles

ISOLDE (if available):
  Interactive MD-guided fitting
  Apply: segments with high clashscore
  Forces: map gradient + AMBER force field
  Temperature: 100 K (restraining)
  Monitor: real-space CC improvement

Validation:
  MolProbity: target < 2.0 (oligomeric protein harder to perfect)
  Ramachandran: > 95%
  Interface analysis: PISA → buried surface per dimer interface
```

---

## 4. Visualization Outputs Expected

| Visualization | Tool | What it Shows | Parameters |
|--------------|------|---------------|------------|
| BAX pore crescent/arc density | ChimeraX | 8 BAX monomers in arc arrangement | σ = 5–8 |
| Dimer interface close-up | ChimeraX | BH3-binding groove contacts | σ = 4–6 |
| α5-α6 pore-lining helices | PyMOL | Hydrophobic interior of pore | Helix show, color by hydrophobicity |
| Cryo-ET tomogram slice | IMOD 3dmod | Liposome cross-section + pore density | Z-slice through equator |
| Subtomogram average | ChimeraX | In-membrane pore vs SPA comparison | Match orientation |
| Toroidal pore schematic | Illustrator | Protein + lipid hybrid pore model | Publication diagram |
| Liposome lysis assay | matplotlib | ANTS fluorescence vs time | Multiple BAX:cBID ratios |
| Negative stain EM of pore | ImageJ | Rings/arcs from DDM extract | Before cryo-EM |
| FSC curve | CryoSPARC | Resolution at 0.143 = 3.1 Å | Gold standard |
| Per-dimer local resolution | CryoSPARC | 2.8 Å for dimer after local refine | Hot-cold |

---

## 5. BioMate Gap Analysis & Action Items

| Gap | Priority | Effort | Action Item |
|-----|----------|--------|-------------|
| **Liposome reconstitution protocol** | P0 | Medium | Add: lipid film hydration → SUV extrusion → pore activation → functional assay → cryo-EM grid protocol |
| **Pore-forming protein SPA (arc-shaped)** | P0 | Medium | Handle non-globular particles: TOPAZ training on manually curated arc particles, multi-body refinement guidance |
| **Cryo-ET + STA pipeline** | P1 | Very High | IMOD/AreTomo → RELION STA is entire new pipeline. Build as separate BioMate workflow. |
| **RELION 3D multi-body refinement** | P1 | Medium | Add step: define rigid bodies for flexible/oligomeric complexes; document body definition strategy |
| **ISOLDE integration** | P2 | Medium | ISOLDE = ChimeraX plugin; add as optional step for high-clashscore oligomeric models |
| **Functional assay templates** | P1 | Low | Add: ANTS/DPX liposome lysis assay template, cytochrome c release protocol |
| **Cardiolipin lipid parameters** | P2 | Low | Document: CL lipid CHARMM36m params for OMM-mimetic bilayer MD |
| **DDM extraction from liposomes** | P1 | Low | Add: DDM solubilization protocol for liposome-reconstituted pore proteins for SPA |

### Critical Parameters for Pore-Forming Protein Studies
```python
BAX_PORE_PARAMS = {
    # Liposome parameters
    "lipid_ratio": "DOPC:DOPE:CL = 4:3:1",
    "cardiolipin_essential": True,        # Required for BAX recruitment
    "extrusion_pore": 100,                # nm polycarbonate membrane
    "suv_size_target": [90, 110],         # nm by DLS
    "suv_pdi_max": 0.1,
    
    # Pore activation
    "bax_cbid_ratio": 5,                  # BAX:cBID molar ratio
    "activation_temp": 37,                # °C
    "activation_time": [30, 60],          # minutes
    "lysis_threshold": 50,                # % by ANTS/DPX assay (go/no-go)
    
    # SPA (extracted pore)
    "extraction_detergent": "DDM",
    "ddm_concentration": 1.0,             # % w/v
    "box_size_pixels": 400,               # for ~170 kDa arc
    "target_resolution": 3.1,             # Å
    
    # Cryo-ET
    "tilt_range": [-60, 60],              # degrees
    "tilt_increment": 3,                  # degrees
    "total_dose_et": [100, 120],          # e-/Å² per tilt series
    "pixel_size_et": 1.37,               # Å/pix (lower mag)
}
```

---

## 6. Key BioMate Learnable Principles

1. **Pore-forming proteins REQUIRE functional validation before cryo-EM:** For BAX and analogous pore-forming proteins (perforins, gasdermin, MLKL), cryo-EM on an inactive sample yields meaningless structures. BioMate must enforce: confirm > 50% liposome lysis by ANTS/DPX assay (or equivalent) before grid preparation.

2. **Two complementary EM approaches = strongest evidence:** Shi lab uses both SPA (atomic resolution, DDM-extracted) AND cryo-ET (near-native environment, lower resolution) for pore structures. The SPA gives atom-level detail; the cryo-ET confirms the in-membrane architecture is not an artifact of extraction. BioMate should recommend both when studying membrane-inserting proteins.

3. **Cardiolipin is obligatory for BAX-related pore formation:** DOPC/DOPE alone is insufficient — cardiolipin (CL) mimics the mitochondrial OMM composition and is specifically recognized by BAX's α9 helix. BioMate should know: when user studies BAX, BCLX, BCLW, or other BCL-2 family members, recommend CL-containing liposomes.

4. **Dimer-of-dimers architecture principle for apoptotic pores:** BAX forms dimers as the fundamental unit; octameric pore = 4 dimers in arc. RELION 3D multi-body refinement with 4 rigid bodies (each = one dimer) enables higher resolution than treating entire pore as rigid. BioMate should recommend multi-body refinement for all oligomeric pore structures.

5. **Arc/crescent shapes require TOPAZ training (cannot rely on circular blob picker):** Standard crYOLO general model assumes roughly circular particles. BAX pore's arc shape results in systematic underpicking. BioMate should detect non-circular particle classes in 2D classification and trigger TOPAZ training recommendation.

6. **ISOLDE fills the gap between AlphaFold2 and Coot for strained oligomers:** For multi-subunit complexes where multiple chains must fit simultaneously, steric clashes are common. ISOLDE applies MD-based forces that resolve clashes while maintaining map fit — more efficient than manual Coot rotamer editing for > 4-chain complexes.

7. **Cryo-ET sample preparation for liposomes: skip glow discharge optimization:** Unlike soluble proteins, liposomes adsorb readily to standard Quantifoil without extensive plasma cleaning. Over-cleaning removes lipid from liposome surface. BioMate should recommend gentler 3 s O₂/H₂ plasma cleaning for liposome-containing samples.

8. **E. coli expression for BH3 proteins enables isotopic labeling for companion NMR:** Shi lab BAX studies often combine cryo-EM with NMR (¹⁵N-labeled BAX, HSQC tracking). E. coli system enables ¹⁵N-minimal media for < 30 kDa proteins. BioMate should note: for proteins < 30 kDa where cryo-EM SPA is challenging, suggest combining with NMR.
