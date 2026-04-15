# Skill: Symmetric Assembly Cryo-EM — Viral Capsid (Structure 2026 / Sci Adv 2025)

**Papers:**  
- "Cryo-EM structures of HBV capsids from human cells at near-atomic resolution" — Structure 2026 (PMID: 41314213)  
- "Cryo-EM resolves the structure of the archaeal dsDNA virus HFTV1 from head to tail" — Science Advances 2025 (PMID: 41042861)  
**Why it matters for BioMate:** Symmetry imposition changes processing fundamentally; native cell-isolated capsids vs recombinant; internal asymmetric cargo requires symmetry expansion.

---

## 1. Key Paradigm Difference: Symmetry Exploitation

```
ASYMMETRIC SPA (standard)               SYMMETRIC ASSEMBLY
────────────────────────                ──────────────────────────────
C1 symmetry throughout                  Apply icosahedral (I1) or dihedral (D6)
Each particle = 1 unique view           Each particle = multiple unique views
1M particles → 1M images               1M particles × 60 (ico) = 60M effective images
Box = particle dimensions               Box = full assembly (capsid + some interior)
Resolution driven by particle count     Resolution driven by structural heterogeneity
Model = one chain + multimer            Model = asymmetric unit only (1/60 of capsid)
```

**Why symmetry matters numerically:**
- HBV T=4 capsid: 240 copies of core protein per capsid
- Each particle image generates 240 symmetry-related views after I1 imposition
- 5,000 particles → effectively 1.2M views for refinement
- This is why near-atomic resolution is achievable with very few particles

---

## 2. Protocol Divergences for Symmetric Assemblies

### Sample Sources
```
Recombinant capsid (benchmark):
  - Express core protein in E. coli
  - Capsid assembles spontaneously (for HBV: 100 mM NaCl, 37°C)
  - Purify: ultracentrifugation → sucrose cushion → gel filtration
  - Advantage: homogeneous, high yield (mg quantities)
  - Disadvantage: no PTMs, no lipid cargo, no RNA, not physiological

Native cell-isolated capsid:
  - HEK293T transfection with HBV genome or capsid plasmid
  - Or: infected cell line (hepatocytes)
  - Lyse cells: freeze-thaw × 3, low-speed spin (3,000×g)
  - Supernatant → ultracentrifugation (100,000×g, 2 hr)
  - Pelleted capsids → resuspend → sucrose gradient fractionation
  - Advantage: captures PTMs (phosphorylation), lipid cargo, RNA content
  - Disadvantage: heterogeneous (mature/immature capsids mixed), lower yield
  - QC: DLS → monodisperse ~32 nm (T=4), cryo-EM screen next day
```

### Data Collection
```
Grid: Quantifoil R1.2/1.3, 300 mesh
Plasma clean: standard (5 s)
Concentration: 0.5–1.0 mg/mL (lower than membrane proteins — large particles)
Vitrobot: 3 s blot, 4°C, 100% RH
IMPORTANT: Ice must be thin relative to capsid diameter (~32 nm for HBV T=4)
Microscope: Titan Krios, 300 kV, K3
Pixel size: 0.83 Å/pix (sufficient for capsid ~32 nm)
  → Can use 1.06 Å/pix for initial characterization if large (> 100 nm)
Defocus: −0.5 to −2.0 μm (can use shallower defocus for large particles)
Dose: 50–60 e⁻/Å² (stable assemblies tolerate higher dose)
Movies: 2,000–5,000 (fewer needed due to symmetry amplification)
```

### Symmetry-Imposed Refinement Workflow
```
Step 1: C1 ab initio (ALWAYS start symmetric assemblies in C1)
  - Verify: do 2D class averages show icosahedral projections?
    (5-fold, 3-fold, 2-fold views should all be present)
  - If 2D classes are polar: preferred orientation problem
    Add 0.1% OG or tilt stage 30° during collection

Step 2: Determine correct symmetry
  CryoSPARC symmetry detection job (if unsure)
  OR: compare FSC with C1 vs I1 applied
  Correct symmetry: FSC improves dramatically (> 0.5 Å gain)
  Wrong symmetry: FSC gets worse or structure looks distorted

Step 3: Apply symmetry in refinement
  CryoSPARC homogeneous refine: --symmetry I1 (icosahedral)
  Or: --symmetry C7 for D7 ring ATPase
  Resolution gain vs C1: typically 1–2 Å for well-ordered capsid

Step 4: Per-particle CTF refinement
  Same as standard: per-particle defocus, beam tilt
  Critical: large particles have significant defocus gradient across diameter
  → Use optics group refinement for field-dependent CTF

Step 5: Final resolution (HBV T=4 in cells): ~3.0–3.5 Å for shell
```

### Asymmetric Internal Cargo (Portal, DNA, RNA)
```
Problem: Symmetry imposition averages out any asymmetric internal features

Solution: Symmetry expansion + signal subtraction

Step 1: Symmetry expansion
  CryoSPARC: symmetry expand with I1 → generates 60 copies of each particle
  Each expanded particle covers one symmetry unit

Step 2: Signal subtraction
  Create mask: exclude capsid shell → keep only interior region
  Subtract symmetrized shell signal from each expanded particle
  Residual: only asymmetric internal signal (portal, packaged DNA/RNA)

Step 3: Focused 3D classification
  3D classify on subtracted particles: 6–10 classes
  Select: class with clear density at portal vertex
  → Portal: often 1 of 12 pentamers (T=4 capsid)

Step 4: Reconstruct asymmetric feature
  Refine portal class: C1, focused mask
  Resolution: typically 5–10 Å (limited by per-particle alignment error)

Application: HBV RNA packaging, HFTV1 dsDNA organization (10 concentric layers)
```

### Model Building for Capsids
```
Asymmetric unit (ASU) = 1/60 of icosahedral capsid = 4 subunits (T=4)

Step 1: Fit one copy of core protein into ASU density
  PHENIX dock_in_map: 1 copy
  Or AlphaFold2 prediction → dock

Step 2: Expand by symmetry to build full capsid model
  phenix.apply_ncs:
    pdb=monomer.pdb
    ncs_spec=I1_symmetry.ncs_spec

Step 3: Refine ASU only (not full capsid — too large for PHENIX)
  Mask: ASU + one layer of neighbors
  Apply NCS restraints for neighboring subunits

Step 4: Validate ASU
  MolProbity: target < 2.0
  CC in ASU density: > 0.8

Lipid/cargo identification:
  - Difference maps within hydrophobic pockets
  - HBV: stearic acid + palmitic acid in intradimer pocket
  - Confirmed by companion GC-MS of isolated capsids
```

---

## 3. BioMate Gaps for Symmetric Assemblies

| Gap | Priority | Action |
|-----|----------|--------|
| Symmetry detection workflow | P1 | Add: C1 first → symmetry detection → apply correct point group |
| Symmetry expansion + signal subtraction | P1 | Document: CryoSPARC symex → signal subtract → focused classify |
| ASU-based model building | P1 | Document: dock into ASU → apply NCS expand → refine ASU only |
| Native cell capsid isolation | P2 | Add: ultracentrifugation capsid isolation from transfected cells |
| Lipid density identification in capsid | P2 | Add: difference map for lipid in hydrophobic pockets + GC-MS validation |

---

## 4. Key Principles for BioMate

1. **Always start C1, verify symmetry from 2D classes before imposing:** Incorrectly applied symmetry (C2 on C1 structure, or I1 on non-icosahedral particle) produces artifactual maps that look fine at low resolution. BioMate must check 2D class averages for hallmark views of the proposed symmetry.

2. **Symmetry amplification makes capsids resolution-efficient:** T=4 icosahedral capsid with 1,000 particles → 60,000 effective views after I1 imposition. Users don't need millions of particles for capsid structures. BioMate should communicate expected particle count requirements based on symmetry order.

3. **Asymmetric features require symmetry expansion + signal subtraction:** Viral genomes, portals, and non-equivalent subunits are destroyed by symmetry averaging. BioMate must warn users: "Your capsid structure shows the shell, but internal asymmetric cargo (DNA/RNA packaging) requires a separate focused analysis with symmetry expansion."

4. **Native-source capsids are more biologically authentic but harder:** Cell-isolated HBV capsids showed lipid cargo and RNA not present in recombinant versions. For PTM-dependent questions (phosphorylation regulating assembly), native isolation is required. For drug-binding to the shell, recombinant is sufficient. BioMate should ask which question the user is answering.

5. **Preferred orientation is the #1 failure mode for spherical capsids:** Round capsids with C5 symmetry on grids adsorb in preferred orientations (showing one face). If > 60% particles show same 2D class, preferred orientation problem — add detergent (OG), tilt stage, or collect on graphene oxide grids.
