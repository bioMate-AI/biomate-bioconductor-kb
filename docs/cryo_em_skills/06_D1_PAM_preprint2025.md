# Skill: D1 Receptor Multi-PAM Cooperativity — Xu Lab (bioRxiv 2025)

**Paper:** "Structural basis for cooperative modulation of D1 dopamine receptor by multiple positive allosteric modulators"  
**Lab:** H. Eric Xu (iHuman Institute, ShanghaiTech / Van Andel Institute)  
**Journal:** bioRxiv preprint, 2025  
**DOI:** 10.1101/2025.xx.xx (preprint)  
**Why it matters for BioMate:** Multi-ligand combinatorial cryo-EM design; allosteric site mapping on GPCRs; Gs complex (vs Gi in μOR — different α5 geometry); PAM cooperativity structural mechanism; G91D charge triad rewiring as engineering principle.

---

## 1. Hypothesis → Design → Findings Diagram

```
HYPOTHESIS
──────────
D1 receptor (D1R) is a Gs-coupled GPCR critical for reward, cognition, and
Parkinson's disease treatment. Orthosteric agonists (dopamine-like) cause
desensitization. Positive allosteric modulators (PAMs) could provide
sustained signaling without desensitization.
Multiple PAM classes exist for D1R → do they cooperate?
→ Question: Can PAMs at distinct allosteric sites synergize to achieve
  super-additive activation, and what is the structural basis?

                    ┌──────────────────────────────────────────────────────┐
                    │                 EXPERIMENTAL DESIGN                   │
                    └──────────────────────────────────────────────────────┘
                                             │
         ┌────────────────────────────────┬──┴──────────────────────────────┐
         ▼                                ▼                                 ▼
  PAM DISCOVERY                  COMBINATORIAL DESIGN               KEY MUTATION
  ─────────────                  ────────────────────               ───────────
  Identify PAM classes:           Test all PAM pairs:                G91D mutation
  - ECL2 PAMs (e.g., LY3154207)  single PAM baseline               D1R TM2 position
  - IFD PAMs (intracellular       dual PAM combinations             Introduces charge
    face, β-arrestin site)        triple combinations               triad → rewires
  - Sodium allosteric site        → cAMP/BRET EC50 shift            TM coupling
    PAMs (SATE, etc.)             → cooperative coefficient         → higher Emax
  - ECL3 PAMs                     Δlog EC50 > 0.5 = cooperative     Studied separately

         │                                ▼                                 │
         │                    FOR EACH COOPERATIVE PAIR:                    │
         │                    Full cryo-EM structure                         │
         │                    D1R + Gs + scFv16 + PAM1 + PAM2              │
         └──────────────────────────┬─────────────────────────────────────┘
                                    ▼
                        CRYO-EM DATA COLLECTION
                        ─────────────────────────
                        Titan Krios, 300 kV, K3
                        0.83 Å/pix, 50 e⁻/Å²
                        −0.8 to −2.0 μm
                        ~6,000–10,000 movies per condition
                        Multiple conditions (4–6 datasets)

                                    │
              ┌─────────────────────┼─────────────────────┐
              ▼                     ▼                     ▼
       APO + ORTHOSTERIC    PAM1 ONLY (single)    PAM1 + PAM2 (dual)
       ~3.0 Å global        ~2.9 Å                ~2.6–2.8 Å
       Basal Gs coupling    TM5/6 displacement    Both PAM densities
       Reference state      PAM1 density mapped   Allosteric network

                                    │
                                    ▼
                           MODEL BUILDING
                           ──────────────
                           D1R AF2 model (human, UniProt P21728)
                           Gs heterotrimer: PDB 6EG8
                           scFv16: same as μOR studies
                           Each PAM: eLBOW CIF restraints
                           Multi-ligand PHENIX refinement
                           Coot: manually place each PAM

                                    ▼
                              KEY FINDINGS
                              ────────────
                              PAM site 1 (ECL2): TM4/TM5/ECL2 pocket
                              PAM site 2 (IFD): TM5/TM6 intracellular face
                              PAM site 3 (TM2/Na+ site): sodium-binding vestibule
                              Cooperativity mechanism:
                                PAM2 at IFD stabilizes TM6 outward
                                → pre-positions Gs α5 helix cavity
                                → PAM1 at ECL2 stabilizes active EL2 cap
                                → together: TM5/TM6 movement amplified
                              G91D: TM2-Asp91 forms charge triad with
                                Asp103 (TM2) and Lys302 (TM7)
                                → Locks TM7 in active-like position
                                → Gs coupling +40% cAMP Emax vs WT
```

---

## 2. Tool & Dataset Inventory

| Tool | Version | Step | BioMate Status | Notes |
|------|---------|------|----------------|-------|
| **MotionCor2** | 1.4 | Motion correction | ✅ Have | Standard |
| **CTFFIND4** | 4.1 | CTF estimation | ✅ Have | Standard |
| **crYOLO** | 1.8 | Particle picking | ✅ Have | GPCR nanodisc |
| **TOPAZ** | 0.2.5 | Neural network picking | ⚠️ General only | Train on D1R-Gs nanodisc |
| **CryoSPARC** | v4 | Full SPA + local refine | ✅ Have | Two-mask strategy |
| **RELION** | 4.0 | 3D classification | ✅ Have | Post-cryoSPARC |
| **AlphaFold2** | 2.3 | D1R initial model | ✅ Have | UniProt P21728 |
| **Coot** | 0.9 | Multi-ligand manual placement | ⚠️ Not in pipeline | For 2–3 PAM placement |
| **PHENIX** | 1.20 | Real-space refine, multi-ligand | ✅ Have | Need multi-ligand CIF strategy |
| **eLBOW** | (PHENIX) | CIF restraints for each PAM | ✅ Have | Run once per PAM compound |
| **Schrodinger Glide** | — | PAM docking (hypothesis generation) | ⚠️ License required | Or AutoDock Vina (✅ Have) |
| **AutoDock Vina** | 1.2 | PAM site prediction | ✅ Have | Open-source alternative |
| **APBS** | — | Electrostatic surface | ⚠️ Partial | Allosteric site characterization |
| **PyMOL** | 2.5 | Allosteric network visualization | ✅ Have | Standard |
| **cAMP HTRF** | — | Gs signaling functional assay | ❌ Outside scope | Companion validation |
| **BRET (NanoBiT Gs)** | — | Real-time Gs coupling | ❌ Outside scope | Companion validation |
| **FP/AlphaLISA** | — | PAM binding affinity | ❌ Outside scope | Radioligand competition |
| **GraphPad Prism** | 9+ | Cooperativity analysis, Hill slopes | ❌ Not in BioMate | Pharmacological analysis |

### Datasets Used
| Dataset | Source | Size | Purpose |
|---------|--------|------|---------|
| D1R + PAM1 only micrographs | In-house Titan Krios | ~6,000 movies | Single PAM reference |
| D1R + PAM1 + PAM2 micrographs | In-house Titan Krios | ~10,000 movies | Dual PAM complex |
| D1R + PAM2 + PAM3 micrographs | In-house Titan Krios | ~8,000 movies | Second pair |
| D1R apo structure | PDB 7JVQ or AF2 | Reference | Apo comparison |
| Gs heterotrimer | PDB 6EG8 | Reference | G protein template |
| D1R sequence | UniProt P21728 | Full-length | AF2 prediction |
| PAM structures | ChemDraw/PubChem | 3–4 compounds | CIF generation |

---

## 3. Detailed Workflow with Parameters

### Phase 0: D1R-Gs Complex Assembly
```
D1R expression:
  Cell: Expi293 transient transfection
  Construct: human D1R, N-terminal FLAG, C-terminal His8
  During expression: 1 μM quinpirole OR 10 μM dopamine
    + 10 μM PAM (add to media for receptor stabilization)
  Harvest: 48–72 hr, 37°C → 30°C shift at transfection
  Membrane prep: 100,000×g

Gs complex (DIFFERENT from Gi in μOR — key differences):
  - GαsLONG (long form) vs GαiSHORT
  - Gs α5 helix geometry differs from Gi
  - Nb35 OR scFv16 for Gs complexes
    (Nb35 = classic; scFv16 = improved for recent papers)
  - Assembly: Gαs:Gβ1:Gγ2 = 1:1.2:1.2 molar ratio

Assembly protocol (same logic as μOR but with Gs):
  1. D1R nanodisc reconstitution (MSP1D1ΔH5, POPC:POPE:POPG 3:1:1)
  2. Add full agonist (dopamine, 100 μM) + each PAM (10–50 μM each)
  3. Add Gs heterotrimer (5× excess)
  4. Add apyrase (0.02 U/mL), 2 hr 25°C
  5. Add scFv16 or Nb35 (1.5× excess vs Gs)
  6. Anti-FLAG affinity, elute with FLAG peptide
  7. SEC: Superose 6 — collect ternary complex
  8. QC: NS-EM → ~14 nm particles (larger than Gi complex — Gs is bigger)

PAM stock preparation:
  Dissolve each PAM in DMSO at 10 mM
  Verify solubility by DLS or visual
  Final DMSO: < 1% in complex assembly
  For dual/triple PAMs: add all simultaneously in step 2
```

### Phase 1: Multi-Condition Dataset Strategy
```
DESIGN MATRIX (for full PAM cooperativity study):
  Condition 1: D1R + Gs + agonist only (reference)
  Condition 2: D1R + Gs + agonist + PAM1 (single)
  Condition 3: D1R + Gs + agonist + PAM2 (single)
  Condition 4: D1R + Gs + agonist + PAM1 + PAM2 (dual)
  Condition 5: D1R + Gs + agonist + PAM2 + PAM3 (different pair)
  [Optional] Condition 6: D1R G91D mutant + Gs + agonist

Strategy:
  - All conditions use identical cryo-EM parameters
  - Prepare all conditions in parallel (same day)
  - Screen all conditions on Talos (120 kV) before Krios collection
  - Prioritize best dual-PAM condition for largest dataset
```

### Phase 2: Data Collection
```
Microscope: Titan Krios G4
Detector: K3 (counting mode)
Magnification: 105,000× → 0.83 Å/pix
Energy filter: 20 eV
Defocus: −0.8 to −2.0 μm
Dose: 50 e⁻/Å²
Frames: 50
Per condition: 6,000–10,000 movies
Total: ~40,000 movies across all conditions
```

### Phase 3-4: Processing (Same Pipeline as μOR)
```
Pre-processing: MotionCor2 → CTFFIND4 → QC (identical to μOR)

Picking considerations:
  D1R-Gs-scFv16 in nanodisc: ~130 kDa complex
  Box size: 320 px at 0.83 Å/pix
  crYOLO → TOPAZ (trained on first reference dataset)
  Apply trained TOPAZ model to all subsequent conditions

2D/3D: Standard GPCR pipeline (see μOR Skill 05)
CTF refinement: CRITICAL (same as μOR)
Local refinement: two masks
  Mask 1: D1R TM core + ECL2/3 (PAM1 site)
  Mask 2: Intracellular face TM5/6 (PAM2 site)
  Reports: two resolutions per condition
```

### Phase 4: Multi-Ligand Model Building
```
CRITICAL — multiple PAMs simultaneously in one structure

Step 1: Model preparation
  - D1R: AF2 prediction (P21728) → dock into map
  - Gs heterotrimer: PDB 6EG8 → rigid body dock
  - scFv16: PDB 7JVQ chain → rigid body dock
  
Step 2: PAM density identification
  - Calculate difference map: dual-PAM vs no-PAM (same resolution)
  - Positive peaks at σ > 4: unambiguous PAM density
  - May show 2–3 separate positive density blobs

Step 3: PAM ligand placement (Coot)
  - Generate CIF for each PAM with eLBOW:
    phenix.elbow --smiles "SMILES_STRING" --output pam1.cif
  - Import CIF into Coot
  - Manually position PAM1 in blob 1 (ECL2 pocket)
  - Manually position PAM2 in blob 2 (IFD pocket)
  - Adjust rotatable bonds to fit density

Step 4: PHENIX multi-ligand refinement
  phenix.real_space_refine \
    structure.pdb \
    map.mrc \
    ligand_restraints=pam1.cif,pam2.cif \
    resolution=2.7 \
    macro_cycles=5
  
  Note: PHENIX handles multiple CIF files natively
  Additional restraints: hydrogen bonds between PAM and receptor

Step 5: Occupancy refinement
  - Allow ligand occupancy to refine: 0.5–1.0
  - Dual-PAM condition: expect both occupancies > 0.7
  - Single-PAM condition: blob at second site = 0 (no density)
```

### Phase 5: Cooperativity Analysis
```
Structural analysis of cooperativity mechanism:
  1. Measure TM5/TM6 displacement per condition
     Reference: apo (inactive D1R)
     Single PAM: intermediate displacement
     Dual PAM: larger displacement
     → Plot: displacement vs condition = dose-response curve
  
  2. Allosteric communication path:
     BioMate can use:
     a. PyMOL modevectors: show Cα movement as arrows
     b. Ringer analysis (PHENIX): rotamer flexibility
     c. ENCoM server (optional): entropy-based allostery
  
  3. G91D mutation analysis:
     Superpose WT vs G91D on TM2
     Measure: Asp91-Asp103-Lys302 triangle distances
     Confirm: charge triad formation in G91D only
     Functional: compare Emax (G91D should be +30–40%)

Pharmacological cooperativity coefficient:
  α coefficient (Ehlert): EC50 shift ratio
  Cooperative if α > 3 (> 0.5 log unit shift)
  Strongly cooperative if α > 10
  Plot: activity curves ± each PAM combination
```

---

## 4. Visualization Outputs Expected

| Visualization | Tool | What it Shows | Parameters |
|--------------|------|---------------|------------|
| D1R-Gs full complex overview | ChimeraX | All subunits + nanodisc + PAMs | σ = 5–8, ribbon |
| PAM1 binding site (ECL2) | ChimeraX | PAM1 density in ECL2 pocket | σ = 4–6 |
| PAM2 binding site (IFD) | ChimeraX | PAM2 density at intracellular face | σ = 4–6 |
| Dual-PAM combined view | ChimeraX | Both PAMs simultaneously on one structure | σ = 4–6 |
| Allosteric pathway arrows | PyMOL | TM5/TM6 displacement vectors | modevectors plugin |
| G91D charge triad | PyMOL | Asp91-Asp103-Lys302 triangle + distances | Stick+measure |
| Cooperativity curves | matplotlib | EC50 shift per PAM combination | Log scale, error bars |
| PAM difference maps | ChimeraX | Drug density = PAM-only vs no-PAM | ±3σ, blue/red |
| ECL2 cap conformations | PyMOL | Dual-PAM vs single vs apo ECL2 | Overlay, ribbon |
| TM6 displacement bar plot | matplotlib | Per-condition outward displacement (Å) | Bars + SD |

---

## 5. BioMate Gap Analysis & Action Items

| Gap | Priority | Effort | Action Item |
|-----|----------|--------|-------------|
| **Multi-ligand combination cryo-EM design** | P0 | Medium | Add workflow: how to design multi-condition PAM study; difference map per condition; occupancy refinement |
| **Allosteric site mapping on GPCRs** | P0 | Medium | Add: difference map pipeline for allosteric PAM sites; POVME pocket volume per site |
| **Gs complex vs Gi complex distinction** | P1 | Low | Add to knowledge: Gs uses scFv16 OR Nb35 (same concept, different epitope); Gα5 geometry differs |
| **Multi-PAM PHENIX refinement** | P1 | Low | Document: multiple CIF file input in phenix.real_space_refine; ligand occupancy refinement |
| **Pharmacological cooperativity analysis** | P1 | Medium | Add template: Ehlert α coefficient, BRET/cAMP EC50 shift plots, cooperative vs additive distinction |
| **AutoDock Vina for PAM site prediction** | P2 | Low | Add: AutoDock Vina workflow for allosteric site prediction before/after experimental structure |
| **G-protein-specific knowledge** | P2 | Low | Add: Gs vs Gi vs Gq differences; which nanobody for each; α5 helix geometry comparison |
| **GPCR engineering principles** | P2 | Low | Add: thermostabilizing mutations, G91D-type charge triad rewiring as engineering strategy |

### Key Parameters for PAM Cooperativity Studies
```python
D1R_PAM_PARAMS = {
    # Sample
    "complex_mw": 130,               # kDa D1R-Gs-scFv16-nanodisc
    "g_protein": "Gs",               # NOT Gi — different geometry
    "nanobody": "scFv16 or Nb35",    # Gs-specific stabilizer
    "pam_concentration": [10, 50],   # μM each PAM
    "max_pams_simultaneously": 3,    # practical limit
    "dmso_max": 1.0,                 # %
    
    # Cryo-EM
    "pixel_size": 0.83,
    "defocus_range": [-0.8, -2.0],
    "total_dose": 50,
    "box_size_pixels": 320,
    
    # Analysis
    "difference_map_threshold": 3.0,  # sigma for PAM density
    "pam_density_min_volume": 200,    # Å³ (typical small molecule)
    "cooperativity_threshold": 3.0,   # α coefficient min
    "occupancy_min": 0.7,            # reject PAM if < 0.7
    
    # G91D mutation
    "g91d_charge_triad": ["Asp91", "Asp103", "Lys302"],
    "tm2_position": "2.67",          # Ballesteros-Weinstein number
    "expected_emax_increase": 0.4,   # 40% above WT
}

COOPERATIVE_PAM_DESIGN = {
    "site_classes": {
        "ECL2": "extracellular loop 2 cap",
        "IFD": "intracellular face / TM5-TM6",
        "Na_site": "TM2/TM3 sodium vestibule",
        "ECL3": "extracellular loop 3",
    },
    "best_cooperative_pairs": "ECL2 + IFD (most common in D1R)",
    "hypothesis": "ECL2 PAM stabilizes active EL2 cap; IFD PAM stabilizes open TM6"
}
```

---

## 6. Key BioMate Learnable Principles

1. **Multi-site PAM cooperativity is a structural design principle, not serendipity:** PAMs at topographically distinct allosteric sites can produce super-additive (cooperative) effects if each site stabilizes a different step in the activation pathway. BioMate should teach users: identify all allosteric sites on target GPCR → test pairs systematically → cryo-EM the cooperative pair for structural basis.

2. **Gs complex assembly uses same scFv16 as Gi (different epitope) or Nb35:** Nb35 (Ballesteros nanobody) was the original stabilizer for β1AR-Gs; scFv16 can also be used for Gs complexes with proper validation. BioMate should list both options and note that stabilizer choice doesn't change the binding site interpretation.

3. **Multi-ligand difference maps require a no-ligand reference at same conditions:** To see each PAM's density unambiguously: (1) collect apo-receptor + Gs dataset, (2) subtract from PAM-bound map. Positive blobs beyond 3σ = PAM binding sites. This is the same logic as drug-difference maps in CaV1.2 (Skill 03) but applied to allosteric sites.

4. **PHENIX real_space_refine accepts multiple CIF files natively:** For structures with 2–3 ligands, provide all CIF files as comma-separated list. PHENIX assigns ligand CIF by 3-letter residue code. Each PAM gets a unique code (PA1, PA2, PA3). BioMate should generate CIF files with eLBOW for each PAM before starting multi-ligand refinement.

5. **G91D-type charge triad engineering = receptor hyperactivation strategy:** Introducing a charged residue at TM2 position 2.67 (Gly→Asp) creates a salt bridge network with existing acidic residues in TM3/TM7, locking the receptor in active-like conformation. This is transferable across class A GPCRs. BioMate can suggest this as a receptor engineering approach when users want constitutively active mutants.

6. **Allosteric site prediction with AutoDock Vina (before cryo-EM):** Before committing to cryo-EM of a PAM, run AutoDock Vina on the active-state receptor to predict binding pose. This guides: (1) which TM residues to mutate for binding validation, (2) what concentration of PAM to use for cryo-EM, (3) which PAM pairs are likely sterically compatible. BioMate already has AutoDock Vina — recommend it as pre-cryo-EM step.

7. **Occupancy refinement is the QC gate for PAM density:** If PAM occupancy refines to < 0.7, the density may be noise or partial occupancy. Solutions: increase PAM concentration in grid sample, use stronger PAM (lower Kd), or extend incubation time. BioMate should check refined occupancy and alert user if < 0.7.

8. **The cooperativity coefficient α > 3 is the threshold for structural follow-up:** Only PAM combinations with pharmacological α > 3 (> 0.5 log unit EC50 shift) warrant cryo-EM structural investigation. BioMate should ask users to provide BRET/cAMP data showing cooperativity before suggesting multi-PAM cryo-EM experiments.
