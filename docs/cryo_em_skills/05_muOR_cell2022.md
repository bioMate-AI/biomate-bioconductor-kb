# Skill: μ-Opioid Receptor Gs Complex — Xu Lab (Cell 2022)

**Paper:** "Structures of the μ-opioid receptor–Gi protein complex with morphine and fentanyl"  
**Lab:** H. Eric Xu (iHuman Institute, ShanghaiTech / Van Andel Institute)  
**Journal:** Cell, 2022  
**DOI:** 10.1016/j.cell.2022.06.017  
**Why it matters for BioMate:** Gold-standard GPCR-G protein complex cryo-EM workflow; nanobody/scFv stabilization strategy; biased agonism structural basis; nanodisc reconstitution of GPCR complexes; most clinically relevant drug target in opioid crisis research.

---

## 1. Hypothesis → Design → Findings Diagram

```
HYPOTHESIS
──────────
Morphine and fentanyl both activate the μ-opioid receptor (μOR) and
recruit Gi protein, but differ dramatically in:
  - Analgesic efficacy (fentanyl 100× more potent)
  - Respiratory depression and addiction liability
This suggests different molecular contacts → "biased agonism"
→ Question: How do morphine vs fentanyl structurally activate μOR-Gi complex?

                    ┌──────────────────────────────────────────────────────┐
                    │                 EXPERIMENTAL DESIGN                   │
                    └──────────────────────────────────────────────────────┘
                                             │
         ┌──────────────────────────────────┬┴───────────────────────────────┐
         ▼                                  ▼                                ▼
  GPCR COMPLEX ASSEMBLY             STABILIZATION STRATEGY          TWO DRUG CONDITIONS
  ────────────────────              ─────────────────────           ──────────────────
  μOR (human, full-length)          scFv16 nanobody                 Dataset 1: + morphine
  Gαi1 protein                      → binds β-γ G protein           Dataset 2: + fentanyl
  Gβ1γ2 complex                      interface (NANOBODY             Same complex, same
  Expi293 co-expression              = stabilizes complex)           cryo-EM conditions
  Nanodisc: MSP1D1ΔH5               Thermostabilization:            Compare orthosteric
  (POPC:POPG:POPE = 3:1:1)          agonist + GDP→GTPγS→            site geometry
                                     apyrase to remove
                                     nucleotide → stable complex

         │                                  │                                │
         └──────────────────────────────────┼────────────────────────────────┘
                                            ▼
                             CRYO-EM DATA COLLECTION
                             ─────────────────────────
                             Titan Krios, 300 kV, K3
                             0.83 Å/pix
                             −0.8 to −2.0 μm
                             50 e⁻/Å²
                             ~5,000 movies per dataset

                                            │
                              ┌─────────────┴──────────────┐
                              ▼                            ▼
                     MORPHINE DATASET               FENTANYL DATASET
                     2.9 Å global                  2.7 Å global
                     TM bundle + Gi                TM bundle + Gi
                     Orthosteric pocket:           Orthosteric pocket:
                     morphine = compact            fentanyl = elongated
                                                   reaches deeper

                                            │
                              ┌─────────────┴──────────────┐
                              ▼                            ▼
                      MODEL BUILDING                COMPARATIVE ANALYSIS
                      ─────────────                ──────────────────────
                      μOR: PDB 6DDE                Drug pocket geometry
                      Gi complex: PDB 6CMO         IC50 pocket volumes
                      Coot + PHENIX                TM5/TM6 opening angle
                      Drug ligand: eLBOW           Extracellular loop 2
                                                   differences

                                            ▼
                                      KEY FINDINGS
                                      ────────────
                                      Morphine: occupies upper binding pocket
                                      Fentanyl: extends deeper into TM cleft
                                      (piperidine + phenethyl reach TM3/TM7)
                                      TM6 outward displacement: larger in fentanyl
                                      → more complete "active" conformation
                                      ECL2: morphine contacts = weaker
                                      → explains different signaling kinetics
                                      Both recruit Gi-α5 helix identically
                                      → efficacy divergence is at receptor, not G protein
```

---

## 2. Tool & Dataset Inventory

| Tool | Version | Step | BioMate Status | Notes |
|------|---------|------|----------------|-------|
| **MotionCor2** | 1.4 | Motion correction | ✅ Have | Standard |
| **CTFFIND4** | 4.1 | CTF estimation | ✅ Have | Standard |
| **crYOLO** | 1.8 | Particle picking | ✅ Have | For nanodisc particles |
| **TOPAZ** | 0.2.5 | Neural network picking | ⚠️ General only | Train on GPCR-Gi nanodisc |
| **CryoSPARC** | v4 | Full SPA pipeline | ✅ Have | 2D/3D/refine/CTF refine |
| **RELION** | 4.0 | 3D classification, polishing | ✅ Have | Post-cryoSPARC |
| **AlphaFold2-Multimer** | 2.3 | μOR-Gi complex initial model | ✅ Have | Per-subunit or multimer |
| **Coot** | 0.9 | Manual model building | ⚠️ Not in pipeline | Required for ECL2 loops |
| **PHENIX** | 1.20 | Real-space refine | ✅ Have | Standard |
| **eLBOW** | (PHENIX) | Morphine/fentanyl CIF restraints | ✅ Have (PHENIX) | Opiate ligand CIF |
| **BRET assay** | — | Gi activation in cells | ❌ Outside scope | Functional validation |
| **cAMP assay** | — | Gs/Gi signaling (HTRF) | ❌ Outside scope | Complementary assay |
| **ChimeraX** | 1.5 | Visualization, morphine vs fentanyl overlay | ✅ Have | Standard |
| **PyMOL** | 2.5 | Drug binding site analysis | ✅ Have | Standard |
| **scFv16 nanobody** | — | Complex stabilization reagent | ❌ Not in BioMate | User must obtain separately |
| **Apyrase** | — | Nucleotide removal (GDP removal) | ❌ Not in BioMate | User protocol |
| **MSP1D1ΔH5** | — | Nanodisc scaffold protein | ❌ Not in BioMate | User must express |

### Datasets Used
| Dataset | Source | Size | Purpose |
|---------|--------|------|---------|
| μOR + morphine micrographs | In-house Titan Krios | ~5,000 movies | Dataset 1 |
| μOR + fentanyl micrographs | In-house Titan Krios | ~5,000 movies | Dataset 2 |
| μOR crystal structure | PDB 6DDE | 1 structure | Initial TM model |
| Gi protein structure | PDB 6CMO | 1 structure | Gi complex template |
| scFv16 nanobody | PDB 6CMO | — | Stabilizer chain |
| Morphine / fentanyl SMILES | PubChem | 2 molecules | Ligand CIF generation |
| μOR sequence | UniProt P35372 | — | AF2 prediction |

---

## 3. Detailed Workflow with Parameters

### Phase 0: GPCR-Gi Complex Assembly
```
CRITICAL — most challenging sample preparation in cryo-EM

Step 1: μOR expression
  Cell: Expi293 (not stable — transient for GPCR overload)
  Vector: pcDNA3.1, N-terminal FLAG, C-terminal His10
  Ligand during expression: 10 μM naloxone (antagonist) or
    direct agonist (10 μM morphine / fentanyl)
  Harvest: 48 hr post-transfection
  Membrane prep: 100,000×g ultracentrifugation

Step 2: Gi protein preparation
  - Gαi1 + Gβ1 + Gγ2 — co-express in Sf9 (insect cells, baculovirus)
  - Or: obtain commercially (Signal Chem or NovaBiochem)
  - SEC: Superose 6, verify heterotrimer peak

Step 3: scFv16 nanobody preparation
  - Express scFv16 in E. coli (Origami2 strain)
  - Periplasmic extraction → Ni-NTA → SEC
  - Or obtain from AddGene plasmid #114469

Step 4: Complex assembly (CRITICAL PROTOCOL)
  a. Reconstitute μOR into MSP1D1ΔH5 nanodisc:
     - Solubilize with DDM + CHS
     - Mix with MSP1D1ΔH5 + POPC:POPG:POPE (3:1:1)
     - Detergent removal: SM-2 Bio-Beads, 4°C overnight
     - SEC: collect nanodisc-μOR fraction (~80 kDa)
  
  b. Agonist addition:
     - Add morphine (or fentanyl): 10–50 μM
     - Incubate 30 min, 4°C
     - Confirms receptor in active conformation
  
  c. Gi coupling:
     - Add Gi heterotrimer (5× molar excess)
     - Add apyrase (0.02 U/mL) → removes GDP from Gα
     - Incubate 2 hr, 25°C → forms stable agonist-μOR-Gi complex
  
  d. scFv16 addition:
     - Add scFv16 (1.5× molar excess vs Gi)
     - Incubate 1 hr, 4°C → stabilizes Gi β-γ subunit orientation
  
  e. Final purification:
     - Anti-FLAG M2 affinity (capture via μOR FLAG tag)
     - Elute with FLAG peptide
     - SEC: Superose 6 → collect ternary complex peak
     - QC: negative stain EM → uniform particles ~12 nm
  
  Timeline: 3–5 days from cell harvest to cryo-EM grid

Complex QC checkpoints:
  1. Negative stain EM: particles ~12 nm, round
  2. SDS-PAGE: 4 bands (μOR + Gαi1 + Gβ1 + scFv16)
  3. SEC: single symmetrical peak
  4. Native PAGE: shift vs apo μOR (confirms complex)
```

### Phase 1: Cryo-EM Grid Preparation
```
Grid: Quantifoil R1.2/1.3 Au 300 mesh
Plasma: Solarus II, 3 s (gentler for GPCR-lipid complex)
Sample: 3–4 mg/mL ternary complex
Vitrobot: 4°C, 100% RH, 3 s blot, force 4
Addition note: add agonist fresh (10 μM final) to grid sample
Plunge: liquid ethane
Check ice thickness: ideally ~30–40 nm (thin vitreous ice)
```

### Phase 2: Data Collection
```
Microscope: Titan Krios G3i or G4
Detector: K3 (counting mode)
Energy filter: 20 eV slit
Magnification: 105,000× → 0.83 Å/pix
Defocus: −0.8 to −2.0 μm (finer range — small particles)
Dose: 50 e⁻/Å²
Frames: 50
Exposure: 2.0 s
Movies per dataset: ~5,000
EPU: yes, automated
```

### Phase 3: Pre-processing (Standard)
```
MotionCor2: 5×5 patches, gain reference
CTFFIND4: 30–5 Å, FOM > 0.1
QC thresholds:
  Defocus: −0.8 to −2.0 μm
  Resolution: < 4.5 Å
  Motion: < 50 Å total
Typical pass rate: ~85%
```

### Phase 4: Particle Processing — GPCR-Specific Considerations
```
Particle size estimation:
  μOR-Gi-nanodisc-scFv16: ~120 kDa complex + nanodisc lipid belt
  Effective diameter: ~120–140 Å
  Box size: 320 px at 0.83 Å/pix

Picking:
  Round 1: crYOLO general model
  Round 2: TOPAZ trained on manually picked nanodisc-GPCR particles
  (GPCR in nanodisc looks like MFSD2B — see skill 01)

2D classification:
  Classes: 200
  Select: classes showing TM helices + ECD of scFv16 + Gi domains
  Reject: nanodisc alone (no protein), free Gi, broken complex
  Challenge: GPCR-Gi complex is flexible at Gα-receptor interface
    → expect multiple "fuzzy" 2D classes; still usable

3D classification:
  Ab initio: 6 classes (multiple assemblies possible)
  3D hetero refine: select class showing all 4 components
  
  KEY: CryoSPARC CTF refinement is critical for GPCR:
    - Per-particle defocus: major improvement
    - Beam tilt: must correct for Krios G4
    - Anisotropic magnification: correct if needed

Local refinement:
  Mask 1: μOR TM core + drug binding site → 2.7–2.9 Å
  Mask 2: Gi Gα ras domain → often lower resolution (flexible)
  Report: both resolutions separately in paper
```

### Phase 5: Drug Binding Analysis
```
Orthosteric pocket analysis:
  After refining morphine and fentanyl datasets independently:
  
  1. Superimpose both structures (align TM2-7 helices)
  2. Calculate pocket volume:
     - POVME3 or fpocket
     - Output: volume in Å³ per drug condition
  
  3. Drug density analysis:
     - Threshold map at 3σ in drug region
     - Check all heavy atoms inside density
     - Measure: largest gap between drug atom and density edge
     
  4. Identify drug-specific contacts:
     - Morphine contacts: Asp147, Tyr326, His297 (see paper)
     - Fentanyl additional contacts: TM2/TM3 deeper residues
     - Difference: piperidine-phenethyl extends 3–4 Å deeper
  
  5. Calculate binding pocket RMSD:
     - TM5/TM6 opening angle (helix axis vectors)
     - Larger in fentanyl → more "active-like" receptor
```

### Phase 6: Biased Agonism Analysis
```
Compare TM6 outward displacement:
  Reference: inactive μOR (PDB 4DKL)
  Measurement: Cα distance TM3-TM6 intracellular ends
  Morphine dataset: ~10 Å outward movement
  Fentanyl dataset: ~12 Å outward movement
  → More complete activation with fentanyl

G protein interface analysis:
  PISA: calculate buried surface area Gα5 helix ↔ μOR cavity
  Rotation angle of α5 helix (Gαi1):
  → Both similar → Gi coupling is not the differentiator
  → Biased signaling originates at receptor, not G protein

Comparison with β-arrestin bias studies:
  Previous: morphine poorly recruits β-arrestin
  Structural explanation: ECL2 conformation (morphine = looser)
  Looser ECL2 → weaker GRK phosphorylation → less β-arrestin
```

---

## 4. Visualization Outputs Expected

| Visualization | Tool | What it Shows | Parameters |
|--------------|------|---------------|------------|
| Full complex overview | ChimeraX | μOR + Gi + scFv16 + nanodisc | σ = 5–8, ribbon |
| Drug binding pocket (morphine) | ChimeraX/PyMOL | Orthosteric site, drug density | σ = 4–6 for density |
| Drug binding pocket (fentanyl) | ChimeraX/PyMOL | Deeper penetration visible | σ = 4–6 |
| Morphine vs fentanyl overlay | PyMOL | Two drugs superimposed | Align on TM backbone |
| TM6 displacement comparison | PyMOL | Inactive vs morphine vs fentanyl | Measure Cα distances |
| Gi α5 helix engagement | ChimeraX | Gα5 in μOR intracellular cavity | σ = 5–8 |
| ECL2 conformation | PyMOL | Extracellular loop 2, both agonists | Stick representation |
| 2D class averages | CryoSPARC | GPCR-Gi complex orientations | Best 100 classes |
| FSC curves (×2) | CryoSPARC | 2.7 Å (fentanyl) / 2.9 Å (morphine) | 0.143 criterion |
| BRET signaling data | matplotlib | Gi/β-arr bias ratios per drug | ΔΔlog(Emax/EC50) |

---

## 5. BioMate Gap Analysis & Action Items

| Gap | Priority | Effort | Action Item |
|-----|----------|--------|-------------|
| **GPCR-Gi complex assembly protocol** | P0 | High | Add step-by-step: μOR expression → Gi prep → nanodisc reconstitution → complex coupling → scFv16 addition → SEC → QC |
| **scFv16 nanobody sourcing** | P0 | Low | Document: obtain from AddGene #114469; express in E. coli Origami2; purify from periplasm |
| **Apyrase nucleotide removal** | P1 | Low | Add to complex assembly: 0.02 U/mL apyrase removes GDP → required for stable ternary complex |
| **MSP1D1ΔH5 nanodisc for GPCR** | P0 | Medium | Document: MSP1D1ΔH5 (smaller disc) preferred over MSP1D1 for GPCRs; POPC:POPG:POPE composition |
| **Local refinement masking strategy** | P1 | Medium | Add: mask on TM core separately from G protein; report both resolutions |
| **Biased agonism structural analysis** | P1 | Medium | Add workflow: measure TM6 displacement, ECL2 conformation, Gα5 engagement for two-agonist comparison |
| **GPCR functional assay templates** | P1 | Low | Add: BRET Gi sensor assay, cAMP HTRF assay protocols as companion validation |
| **GPCR knowledge base** | P2 | Low | Add to system prompt: Ballesteros-Weinstein GPCR numbering, inactive/active state criteria, biased agonism definition |

### Critical Parameters for GPCR-Gi Studies
```python
MUOR_GI_PARAMS = {
    # Sample
    "complex_mw": 120,                    # kDa approximate
    "nanodisc": "MSP1D1ΔH5",             # smaller = less background
    "lipid_ratio": "POPC:POPG:POPE = 3:1:1",
    "scfv16_excess": 1.5,                 # molar vs Gi
    "apyrase": 0.02,                      # U/mL
    "agonist_conc": [10, 50],            # μM
    
    # Cryo-EM
    "pixel_size": 0.83,                  # Å/pix
    "defocus_range": [-0.8, -2.0],       # μm (tighter range)
    "total_dose": 50,                    # e⁻/Å²
    "frame_count": 50,
    "box_size_pixels": 320,              # at 0.83 Å/pix
    
    # Processing
    "target_resolution_tm": 2.7,        # Å after local refine TM core
    "target_resolution_gi": 3.5,        # Å for Gi ras domain
    "ctf_refine": True,                  # CRITICAL for GPCR
    "local_refine_masks": 2,            # TM core + G protein
    
    # Analysis
    "tm6_displacement_inactive_ref": "4DKL",  # PDB for inactive μOR
    "contact_distance": 4.0,            # Å for binding site residues
}

GPCR_COMPLEX_ASSEMBLY = {
    "key_steps": [
        "Nanodisc reconstitution first",
        "Agonist addition → confirm active",
        "Gi coupling + apyrase (remove GDP)",
        "scFv16 addition",
        "SEC purification",
        "Negative stain QC",
    ],
    "time_to_grid": "3-5 days",
    "critical_go_nogo": "Negative stain shows round ~12 nm particles"
}
```

---

## 6. Key BioMate Learnable Principles

1. **GPCR-G protein complex requires stepwise assembly with nucleotide manipulation:** The complex only forms stably when: (1) receptor is in agonist-bound active state, (2) Gα is nucleotide-free (apyrase removes GDP), (3) scFv16 locks β-γ in the correct orientation. Omitting any step gives low yield. BioMate must present this as a sequential protocol, not parallel.

2. **scFv16 nanobody is the key stabilizer for Gi-coupled GPCRs:** scFv16 binds the Gβ-Gγ interface and prevents dissociation during cryo-EM vitrification. Without it, complex yield drops 10-fold. BioMate should suggest scFv16 by default for any Gi-coupled GPCR cryo-EM project.

3. **MSP1D1ΔH5 nanodisc (not MSP1D1) for GPCRs:** The shorter MSP1D1ΔH5 scaffold produces ~9 nm nanodiscs vs 12 nm with MSP1D1. For GPCRs (~7 TM helices = 4–5 nm diameter), the smaller disc reduces lipid flexibility and improves particle alignment. BioMate should specify ΔH5 for all GPCR nanodisc projects.

4. **Local refinement with two masks reveals differential resolution:** In GPCR-G protein complexes, the TM core is always better resolved than the G protein ras domain (more flexible). Using two separate masks for local refinement and reporting both resolutions is the standard practice. BioMate should automatically suggest dual-mask local refinement for complexes with flexible domains.

5. **Biased agonism is measurable from TM6 displacement angle:** More potent/efficacious agonists cause larger TM6 outward displacement (measured as Cα distance TM3-TM6 intracellular ends). BioMate should quantify this metric when comparing agonist structures: distance < 10 Å = partial agonist, > 12 Å = full agonist.

6. **Ballesteros-Weinstein numbering enables cross-GPCR comparison:** All GPCR residues are annotated by TM helix number + position within helix (e.g., Asp3.32 = TM3, position 32). BioMate should use B-W numbering in all GPCR structural discussions to enable cross-receptor comparison.

7. **Negative stain EM is mandatory QC before cryo-EM for GPCR complexes:** For expensive cryo-EM sessions, a 2-hr negative stain preparation on a benchtop TEM (FEI Morgagni or Talos) confirms: particle size, complex assembly, absence of aggregation. BioMate should treat negative stain as a hard prerequisite for all multi-component GPCR projects.

8. **Functional assays (BRET, cAMP) must accompany structural studies:** Structures without functional validation of biased agonism are incomplete. BRET (Gi sensor: CAMYEL, or NanoBiT Gi) and cAMP HTRF assays take 1 day and directly validate that the drug concentrations used in cryo-EM produce the expected signaling. BioMate should list these as companion experiments for any GPCR agonist study.
