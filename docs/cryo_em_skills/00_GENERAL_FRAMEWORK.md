# General Cryo-EM Protocol Design Framework
**Purpose:** Teach BioMate to GENERATE protocols from first principles — not just recall memorized steps.  
**Derived from:** 6 master-lab skill documents + general cryo-EM literature  
**Updated:** 2026-04-02

---

## Core Insight

Every cryo-EM project can be described by 5 independent input variables. Each variable makes a series of protocol decisions deterministic. BioMate should ask for these variables (or infer them from context) and then generate a tailored protocol.

```
INPUT VARIABLES
───────────────
V1: Sample class          → purification branch
V2: Molecular weight      → data collection parameters
V3: Scientific question   → dataset design
V4: Expected heterogeneity → classification depth
V5: Target resolution     → particle count, CTF strategy
```

---

## Decision Tree: V1 — Sample Class

```
What kind of sample is it?
│
├─► MEMBRANE PROTEIN (single subunit, no partner)
│     │
│     ├─► < 60 kDa?
│     │     → Saposin nanodisc (wraps tightly, less background)
│     │     → 0.649 Å/pix (small particle needs higher sampling)
│     │     → 3-picker strategy: blob + template + TOPAZ
│     │     → Example: MFSD2B (21 kDa TM core), VMAT2 (55 kDa)
│     │
│     └─► > 60 kDa?
│           → MSP1D1 nanodisc OR detergent (GDN, DDM, LMNG)
│           → 0.83 Å/pix
│           → crYOLO general model often sufficient
│           → Example: CaV1.2 in GDN (400 kDa total complex)
│
├─► GPCR + G PROTEIN COMPLEX
│     → MSP1D1ΔH5 nanodisc (smallest disc, least background)
│     → Required: scFv16 (Gi) or Nb35/scFv16 (Gs)
│     → Required: apyrase nucleotide removal
│     → 0.83 Å/pix, −0.8 to −2.0 μm (tight defocus)
│     → Two-mask local refinement (TM core + G protein)
│     → Example: μOR-Gi, D1R-Gs
│
├─► PORE-FORMING PROTEIN (in membrane)
│     → FUNCTIONAL VALIDATION FIRST (lysis assay, > 50%)
│     → Liposome composition: match target membrane
│       OMM → DOPC:DOPE:CL (4:3:1)
│       PM → DOPC:DOPE:Chol (2:1:1)
│       ER → POPC:POPE (7:3)
│     → Two EM approaches:
│       (a) SPA: DDM extract pore → standard pipeline
│       (b) Cryo-ET: direct on liposomes (lower res, more native)
│     → Arc/asymmetric shapes: TOPAZ training mandatory
│     → Example: BAX (octameric arc)
│
├─► LARGE RNA-PROTEIN COMPLEX (> 500 kDa)
│     → Endogenous purification (not recombinant)
│     → Native affinity tag on endogenous locus
│     → No nanodisc — soluble complex
│     → 1.08–1.30 Å/pix (low magnification for large particle)
│     → −1.0 to −3.0 μm defocus (deeper for large)
│     → 3D classification critical — many assembly states
│     → 3D multi-body refinement for flexible modules
│     → Example: spliceosome (700 kDa–1.5 MDa)
│
├─► SYMMETRIC ASSEMBLY (virus, ring ATPase, proteasome)
│     → Symmetry MUST be determined before refinement
│     → CryoSPARC: use symmetry (C2, D7, T, O, I) in refine
│     → Symmetry expansion for asymmetric features
│     → Very high particle counts achievable (1M+)
│     → Example: viral capsid (T=7 icosahedral), AAA+ ATPase (D6)
│
├─► LARGE RNA-PROTEIN COMPLEX (spliceosome, ribosome, > 500 kDa)
│     → Endogenous purification preferred (not recombinant)
│       HeLa nuclear extract → glycerol gradient (10–30%) sedimentation
│       Density fractions: 40S, 60S peaks → identify by Western blot
│       No affinity tag → antibody bead capture or biotin-streptavidin
│     → Multi-state biology: single dataset → multiple conformations
│       Use 3DVA or heterogeneous refinement: 6–10 classes
│       Each class = one assembly intermediate
│       Resolution per class: 3–5 Å (conformational averaging limits it)
│     → 3D multi-body refinement: divide into 3–6 independent modules
│       (e.g., U1, U2, U4/U6, U5 snRNPs for spliceosome)
│     → 1.06–1.30 Å/pix, −1.5 to −3.0 μm, 45 e⁻/Å²
│     → Example: Shi lab spliceosome (700 kDa–1.5 MDa)
│
├─► SYMMETRIC ASSEMBLY (virus T=4/T=7, ring ATPase D6, proteasome)
│     → Symmetry detection from 2D classes first (C1 ab initio first)
│     → Apply icosahedral (I1), dihedral (D6), cyclic (C7) in CryoSPARC
│     → Effective particle count = actual_count × symmetry_order
│       (T=4 capsid, 240 subunits → each particle gives 240× symmetry)
│     → Asymmetric features (internal DNA, portal):
│       Step 1: Symmetry-imposed refinement for capsid shell (high res)
│       Step 2: Signal subtraction → subtract capsid shell signal
│       Step 3: Focused 3D classification on asymmetric internal signal
│     → Native cell isolation (vs E. coli recombinant):
│       → Captures PTMs, lipid cargo, host factors
│       → But: more heterogeneity, requires additional 3D sorting
│     → 0.83 Å/pix, 50–60 e⁻/Å² (higher dose OK for stable capsids)
│     → Example: HBV capsid (T=4), AAV (T=1 icosahedral)
│
├─► ENDOGENOUS MEMBRANE PROTEIN (no overexpression, no tag)
│     → Vesicle-based method (Liu/Dang PNAS 2025):
│       Pressure homogenize cells/organelles → membrane vesicles
│       Sucrose density gradient → enrich target organelle membranes
│       Cryo-EM directly on vesicle fraction (no detergent!)
│     → Challenge: mixture of many membrane proteins
│       Target identified post-hoc by 2D class shape or 3D sort
│       Need: know approximate appearance of target from prior structure
│     → Resolution ceiling: ~3.5–4 Å (vesicle background limits)
│     → Best for: abundant endogenous proteins (ATP synthase, Complex III)
│     → Example: pig heart F-ATPase, endogenous ERAD complexes
│
├─► IN-CELL CRYO-ET (no purification — native cellular context)
│     → Completely different from all SPA approaches
│     → Sample prep: cryo-FIB milling (cryo-PFIB or FIB-SEM)
│       Vitrify cells on EM grid → FIB mill to 100–200 nm lamella
│       → electron-transparent without any biochemistry
│     → Data: tilt series −60° to +60°, ~3° increments (not single images)
│       Total dose: 100–150 e⁻/Å² split across ~41 tilts
│     → Reconstruction: weighted back-projection → 3D tomogram
│     → Particle picking: done in 3D tomogram volume (not 2D micrograph)
│     → Subtomogram averaging: align + average in 3D
│       Resolution ceiling: ~10–20 Å in situ (missing wedge limits)
│     → Template: use SPA structure (purified) as 3D search template
│     → Applications: ribosome, ATP synthase, microtubule, clathrin in native context
│     → Example: Kelley et al. Mol Cell 2026 (C. reinhardtii, 1,829 tomograms)
│     → BioMate gap: et_full_pipeline EXISTS (AreTomo2 + WBP + STA, 5 steps)
│       MISSING: cryo-FIB milling sample prep guidance, in-cell context knowledge
│
└─► SOLUBLE PROTEIN (< 100 kDa, no membrane)
      → Most challenging for cryo-EM
      → Consider: is X-ray crystallography or NMR better?
      → If cryo-EM: 0.649 Å/pix mandatory
      → Needs: high concentration (5–10 mg/mL), fresh prep
      → Consider: Fab or nanobody decoration to increase MW
      → TOPAZ training mandatory (hard to pick)
      → Target: 500K+ particles for 3 Å
      → Example: 50–80 kDa enzymes
```

---

## Decision Table: V2 — Molecular Weight → Data Collection Parameters

| MW (kDa) | Pixel size (Å/pix) | Defocus range (μm) | Box size (px) | Min particles for 3 Å | Typical resolution |
|----------|-------------------|-------------------|---------------|----------------------|-------------------|
| < 50 | 0.649 | −0.8 to −2.0 | 320 | 500K | 2.5–3.5 Å |
| 50–100 | 0.649–0.83 | −0.8 to −2.0 | 256–320 | 200K | 2.5–3.5 Å |
| 100–300 | 0.83 | −0.8 to −2.5 | 256–320 | 100K | 2.5–3.5 Å |
| 300–600 | 0.83 | −1.0 to −2.5 | 320–400 | 50K | 2.5–4.0 Å |
| 600–1500 | 1.06–1.08 | −1.5 to −3.0 | 400–512 | 20K | 3.0–5.0 Å |
| > 1500 | 1.30+ | −2.0 to −4.0 | 512+ | 10K | 3.5–6.0 Å |

**Box size rule:** box_px = (particle_diameter_Å × 1.5) / pixel_size  
**Particle diameter estimation:** diameter_Å ≈ 13.3 × MW_kDa^(1/3)

```python
def estimate_box_size(mw_kda, pixel_size_angstrom, safety_factor=1.5):
    diameter_A = 13.3 * (mw_kda ** (1/3))
    box_px = (diameter_A * safety_factor) / pixel_size_angstrom
    # Round up to nearest power of 2
    import math
    return 2 ** math.ceil(math.log2(box_px))
```

---

## Decision Table: V3 — Scientific Question → Dataset Design

| Question | Min datasets | Conditions | Key additional step |
|----------|-------------|------------|---------------------|
| Single structure (apo) | 1 | None | Standard pipeline |
| Drug binding mechanism | 2 (apo + drug) | Match drug Kd × 10–50 | Difference map pipeline |
| Conformational states | 2–4 | Apo + activator/inhibitor/mutant | 3DVA or multi-dataset comparison |
| Multi-drug atlas | N+1 (N drugs + 1 apo) | All at same concentration | Difference map × N |
| Allosteric cooperativity | ≥4 (apo, PAM1, PAM2, dual) | Functional EC50 validation first | Multi-ligand model building |
| Mechanism (time-resolved) | 3–5 time points | Mixing times: ms to min | Special grid preparation (spray/mixing) |
| Biased agonism | 2+ agonists + functional | Same Emax concentration | TM6 displacement + Gα5 angle measurement |

**Key rule:** Never collect a dataset without a reference condition. Even for a single drug study, collect apo first. The reference makes the finding interpretable.

---

## Decision Table: V4 — Heterogeneity → Classification Strategy

```
Is the sample heterogeneous?

Ask: How many conformational states are biologically expected?
  - Ion channel: closed / open / inactivated (3 states)
  - Transporter: outward-open / occluded / inward-open (3 states)
  - Pore: monomer / dimer / oligomer / pore (4+ states)
  - GPCR complex: stable (1 state if well-assembled)
  - RNA-protein: multiple assembly intermediates (5–10 states)

Heterogeneity → 3D classification depth:
│
├─► LOW (1–2 states expected, well-folded protein)
│     CryoSPARC: 2–4 classes in hetero-refine
│     RELION: 3D classification 4 classes
│     Time: ~6 hr on GPU cluster
│
├─► MEDIUM (3–5 states, flexible complex)
│     CryoSPARC: 6–8 classes, multiple rounds
│     Consider: 3D variability analysis (3DVA)
│       → PCA-like decomposition of particle images
│       → First 3 components capture major motions
│     Time: ~24 hr
│
└─► HIGH (many states, large flexible complex)
      RELION 3D multi-body refinement:
        → Define N rigid bodies (empirical: 3–6)
        → Bodies = independently folded domains
        → Allow ±5–10° rotation between bodies
        → Resolution improves per-body by 0.2–0.5 Å
      Time: 48–72 hr
      
      Or: focused classification with signal subtraction
        → Subtract everything except region of interest
        → 3D classify on residual signal
```

---

## Decision Table: V5 — Target Resolution → Particle Strategy

| Target | Min particles | CTF refinement | Polish/refine | Key bottleneck |
|--------|--------------|----------------|---------------|----------------|
| < 2.5 Å | > 1M | Full (per-particle + beam tilt + trefoil) | RELION Polish mandatory | Beam coherence, sample prep |
| 2.5–3.0 Å | 200K–1M | Per-particle defocus + beam tilt | Recommended | Particle quality |
| 3.0–3.5 Å | 50K–200K | Per-particle defocus | Optional | Particle count |
| 3.5–4.5 Å | 20K–50K | Minimal | Not needed | Heterogeneity |
| > 4.5 Å | < 20K | None | None | Sample quality (fix sample!) |

**Sub-2.5 Å checklist:**
- [ ] Microscope alignment: < 1 nm beam tilt, Zemlin tableau
- [ ] CTF fit quality: FOM > 0.15 for all used micrographs
- [ ] Particle polish: RELION Bayesian polish (frame-by-frame weighting)
- [ ] Beam tilt correction: per-particle, per-optics group
- [ ] Anisotropic magnification: calibrate monthly
- [ ] Map interpretation: use phenix.mtriage to check FSC-model

---

## Universal QC Gate Table

Every cryo-EM project must pass these gates in order. Failing a gate = STOP, fix, do not proceed.

| Gate | Checkpoint | Pass criterion | Action if fail |
|------|-----------|----------------|----------------|
| **G1** | Protein purity | > 90% by SDS-PAGE, single SEC peak | Re-purify; add SEC polishing step |
| **G2** | Protein concentration | Within target range (3–5 mg/mL typical) | Concentrate or dilute |
| **G3** | Negative stain EM | Monodisperse particles, correct size | Fix sample; wrong buffer/detergent |
| **G4** | Functional assay (if applicable) | > 50% activity (pore lysis, BRET, etc.) | Reassemble complex; check ligands |
| **G5** | Ice quality | Thin vitreous ice, few contaminants | Re-grid; adjust blot time |
| **G6** | Motion correction | < 50 Å total drift | Check stage, increase blot time |
| **G7** | CTF quality | FOM > 0.1, resolution < 4.5 Å, defocus in target range | Discard micrographs |
| **G8** | 2D classification | Clear secondary structure in top classes | Repick; adjust box; change protein |
| **G9** | Ab initio 3D | Recognizable 3D structure at 15 Å | More particles; fix heterogeneity |
| **G10** | Gold-standard FSC | 0.143 crossing visible (not just asymptote) | More particles; improve CTF |
| **G11** | Local resolution | < 1 Å gradient across protein core | OK if gradient is at flexible termini |
| **G12** | Model-map fit | CC > 0.8 in core; all helices in density | Rebuild problem regions |
| **G13** | MolProbity | < 2.0 (< 1.5 excellent) | Real-space refine more cycles |
| **G14** | Ramachandran | > 97% favored | Fix outlier regions in Coot |

---

## Protocol Generation Algorithm

When a user describes a cryo-EM project, BioMate should:

```
STEP 1: Extract input variables
  Ask (or infer):
  - "What protein? What is the MW?"
  - "Is it a membrane protein? Which reconstitution?"
  - "What is the scientific question? Drug binding? Mechanism?"
  - "Do you expect conformational heterogeneity?"
  - "What resolution are you aiming for?"

STEP 2: Map to protocol branch
  Use V1 (sample class) → select purification + reconstitution branch
  Use V2 (MW) → set pixel size, box size, defocus, dose
  Use V3 (question) → set dataset count and conditions
  Use V4 (heterogeneity) → set classification depth
  Use V5 (resolution) → set CTF strategy, particle count target

STEP 3: Generate parameter block
  Output as structured protocol with:
  - Grid preparation (grid type, plasma, blot conditions)
  - Data collection (microscope settings, EPU parameters)
  - Pre-processing (MotionCor2, CTFFIND4, thresholds)
  - Picking strategy (tool, box size, expected yield)
  - 2D/3D strategy (class count, iterations)
  - Refinement (symmetry, masking, CTF refine depth)
  - Model building (template source, building tool, validation)
  - Analysis (comparison strategy, validation assays)

STEP 4: Flag missing information
  Before generating protocol, check:
  - Is the reconstitution strategy specified?
  - Has functional validation been planned?
  - Is there a reference/apo dataset?
  - Are drug/ligand concentrations specified?
  Warn user about any missing inputs.

STEP 5: Output QC gate checklist
  For each project, generate a customized QC checklist
  derived from the universal gate table, with values
  specific to the protein's MW, sample type, and resolution goal.
```

---

## Key Invariant Principles (Never Violate)

These hold across ALL sample types — no exceptions:

1. **Gold-standard FSC at 0.143:** Always report. Never use 0.5 as primary resolution criterion.

2. **MolProbity < 2.0:** A structure deposited with MolProbity > 2.0 will not pass PDB validation without explanation.

3. **Negative stain BEFORE cryo-EM:** Confirms complex assembly, correct particle size, absence of aggregation. Non-negotiable for multi-component systems.

4. **Functional validation before structural study for active/assembled systems:** Pores (lysis assay), GPCR complexes (BRET/cAMP), enzymes (activity assay). Structure of an inactive/unassembled complex is uninformative.

5. **Reference dataset is mandatory for comparative studies:** Drug-bound without apo, or two agonists without shared reference, cannot be compared.

6. **CTF correction limits resolution:** No matter how many particles, if CTF FOM < 0.1, those micrographs cap resolution at ~4 Å. Discard ruthlessly.

7. **Ligand density at < 4σ is unreliable:** Drug/ligand placement only in density peaks at ≥ 4σ in sharpened map. Anything below = uncertain, annotate accordingly.

8. **Never symmetrize without experimental evidence:** Applying C2/D2/I symmetry speeds refinement but can mask asymmetric features. Start C1, verify symmetry from 2D classes.

---

## Sample-Type-Specific Parameter Cheatsheet

```
SAMPLE TYPE          PIXEL   DEFOCUS        DOSE    RECONSTITUTION      STABILIZER
─────────────────────────────────────────────────────────────────────────────────────
Saposin nanodisc     0.649   -0.8 to -2.0   60      Saposin A + γ-CD    —
  (< 60 kDa TM)      (0.83)  
MSP nanodisc GPCR    0.83    -0.8 to -2.0   50      MSP1D1ΔH5           scFv16/Nb35
Detergent (large)    0.83    -1.0 to -2.5   50      GDN 0.02% or DDM    —
Liposome pore        0.83    -1.0 to -2.5   50      DOPC:DOPE:CL 4:3:1  None (native)
Soluble < 100 kDa    0.649   -0.8 to -2.0   40-50   None                Fab/Nb decoration
Soluble 100-500 kDa  0.83    -0.8 to -2.5   50      None                —
Large complex > 500  1.06    -1.5 to -3.0   45      None (endogenous)   —
Symmetric assembly   0.83    -1.0 to -2.0   50-60   Depends             Apply symmetry
Cryo-ET liposome     1.37    per-tilt ~3    100-120 Direct vitrification Per-tilt dose
```

---

## Model Building Decision Tree

```
Starting point for model building:

Is there a high-identity (> 40%) crystal structure in PDB?
  ├─► YES: Use as template
  │     → PHENIX dock_in_map (rigid body)
  │     → Coot: fix misfit loops, sidechains
  │     → PHENIX real_space_refine
  │
  └─► NO: Use AlphaFold2 prediction
        Quality of AF2 model:
        ├─► pLDDT > 70 for all TM helices?
        │     → Proceed: rigid-body dock → Coot → PHENIX
        │
        └─► pLDDT < 70 in critical regions?
              → Rebuild those regions in Coot from scratch
              → Use Rosetta or ISOLDE for difficult segments
              → Consider: is resolution sufficient (< 3.5 Å)?
              → Below 3.5 Å: sidechain assignment unreliable

Drug/ligand placement:
  1. Generate CIF restraints: phenix.elbow --smiles "..."
  2. Identify density in difference map (drug vs apo)
  3. Place ligand in Coot (fit by hand)
  4. PHENIX real_space_refine with ligand CIF
  5. Check: occupancy > 0.7, CC > 0.8 in ligand region
  6. Final: PISA analysis of binding site

Multi-chain complexes (> 4 chains):
  → Apply NCS restraints during refinement
  → Release NCS in final 2–3 macrocycles
  → Use ISOLDE for high-clashscore regions
  → PISA: calculate buried interface per chain pair
```

---

## Common Failure Modes and Fixes

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Resolution stuck at 5–6 Å | Sample heterogeneity | More 3D classification; 3DVA |
| Good 2D, bad 3D | Wrong ab initio reference | Try 6–8 ab initio classes; use known low-res reference |
| Disk-like particles (membrane view = ring) | Preferred orientation | Add 0.05% OG to grid sample; tilt stage 30° |
| Resolution asymmetry (one face blurry) | Preferred orientation + flexibility | Local refinement of blurry region; tilt collection |
| Drug density absent | Drug fell off during grid prep | Add drug fresh to grid sample; keep on ice |
| MolProbity > 3.0 | Incorrect sequence register | Check register with Coot density markers |
| FSC drops sharply (no plateau) | Map overfitting or masking artifact | Use softer mask (5 Å cosine edge); check mask |
| Gold-standard FSC != half-map FSC | Particle leakage between half-sets | Re-split datasets; don't use non-random split |

---

## BioMate Protocol Generation Template

When user says: "I want to solve the cryo-EM structure of [protein]"

BioMate's response should follow this template:

```
1. PROTEIN ASSESSMENT
   - MW: [calculated or estimated]
   - Sample type: [membrane/soluble/complex]
   - Recommended reconstitution: [nanodisc/detergent/none]
   - Expected resolution: [based on MW and sample type]

2. SAMPLE PREPARATION CHECKLIST
   - Expression system: [Expi293/Sf9/E. coli — depends on protein]
   - Purification: [affinity → SEC → reconstitution]
   - QC gates: [purity, concentration, NS-EM, functional assay]

3. DATA COLLECTION PARAMETERS
   - Pixel size: [from MW table]
   - Defocus range: [from MW table]
   - Total dose: [standard or adjusted]
   - Expected micrographs: [based on particle density, min particle target]

4. PROCESSING STRATEGY
   - Picking: [crYOLO / TOPAZ / template — from sample type]
   - 2D/3D: [class count from heterogeneity estimate]
   - Refinement: [symmetry, masking strategy]
   - CTF refinement: [depth from resolution target]

5. MODEL BUILDING
   - Template: [PDB homolog or AF2 prediction]
   - Building: [Coot → PHENIX pipeline]
   - Ligands: [eLBOW CIF if drug present]
   - Validation: [MolProbity, Ramachandran, clashscore]

6. ANALYSIS (if comparative study)
   - Reference dataset: [confirm present]
   - Difference map: [drug/conformation comparison]
   - Functional validation: [assay type for this protein]
```
