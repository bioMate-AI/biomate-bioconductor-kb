# ANDV Glycoprotein Inhibitor Design Implementation Plan
## BioMate AI x Guo et al. (Cell, Feb 2026)

**Project**: Structure-Based Design of Andes Virus Glycoprotein Inhibitors  
**Timeline**: 4 months (Weeks 1–16)  
**Budget**: $38–50K  
**Owner**: BioMate Computational Chemistry Team  
**Deliverables**: 
- 15–20 novel ANDV GP inhibitors with experimental IC50 + predicted ADMET
- Pre-print (bioRxiv)
- Open-source compound library (GitHub)
- SAR paper + docking visualizations

**BioMate integration**: Pseudocode below is **semantic** (stage intent), not a literal API surface. Map steps to **BioMate workflows** and the drug-development coverage map — `docs/20260417_DRUG_DEVELOPMENT_COVERAGE_ANALYSIS.md` (Stages 0–1: AutoSite, Vina/Glide/DiffDock, ADMET triage; Stages 2–4: ADMET suite, MD/RBFE optional; **DMTA**: `backend/lib/galaxy/ai/drug_discovery/`, `/api/drug-discovery`). Notation and paths: `BIOMATE_CAPABILITY_GAP.md`. For a **computational-only preprint** (no wet-lab claims), see **`research/anti-virus/docs/ANDV_INHIBITOR_INSILICO_PREPRINT_STACK.md`** for Nextflow paths, registry IDs, and PK/PD–safety optional modules. **Operational lessons** (polling `run_id`, Batch HTTP blips, MD scale, epitope profiles): **`research/anti-virus/docs/ANDV_CAMPAIGN_LESSONS_LEARNED.md`**.

---

## PHASE 1: STRUCTURE ANALYSIS & POCKET DISCOVERY (Weeks 1–2)

### 1.1 Input Data Acquisition

**Source**: Guo et al., Cell (Feb 2026); coordinates **public** on PDB/EMDB (see `GUO_ET_AL_CELL2026_READING_NOTES.md`).  
**Primary structures (download from RCSB)**:
- ANDV GP tetramer (~2.35 Å): **PDB 9P3I** (map **EMD-71241**)
- ANDV GP + ADI-65534 Fab: **PDB 9P3Y** (map **EMD-71259**) — epitope / complementarity analysis
- Optional lattice ensemble: dimer-of-tetramers **9P3X / 9P3M / 9P3L** (maps EMD-71258, EMD-71243, EMD-71242)

**Note**: Deposits reflect **ANDV-DM-eVLP** experimental context; align with assay constructs (DM vs WT) when interpreting.

**Local naming (after download)**:
```
9P3I.cif or .pdb              # apo tetramer
9P3Y.cif or .pdb              # Fab complex
9P3X_9P3M_9P3L.cif           # optional conformational ensemble
```

**Reagents (optional, not required for in silico coordinates)**: ADI-65534 protein may require **MTA**; structural work can proceed from **public PDB** alone.

---

### 1.2 Pocket Identification Workflow

#### Step 1.2.1: AutoSite Pocket Detection

**Tool**: BioMate's AutoSite integration (from toolkit)

**Input**: 
```
pdb_file: "Guo_ANDV_GP_tetramer.pdb"
ligand_free: true
burial_cutoff: 2.5  # Å from protein surface
druggability_score: true
```

**Process**:
```python
# Pseudocode for pocket detection
from biomate.structural import AutoSite

# Initialize analysis
pocket_analyzer = AutoSite(
    pdb_file="Guo_ANDV_GP_tetramer.pdb",
    protein_chain=["A", "B", "C", "D"],  # Tetramer chains
    removal_radius=2.5  # Å
)

# Run pocket detection
pockets = pocket_analyzer.identify_pockets(
    min_volume=100,  # Ų (minimum pocket size)
    burial_depth=2.5,  # Å from surface
    calculate_druggability=True
)

# Rank by LPOCV (Ligand Pocket Cavity Volume)
ranked_pockets = sorted(
    pockets,
    key=lambda p: p.lpocv_score,
    reverse=True
)

# Output: Top 5 pockets
for rank, pocket in enumerate(ranked_pockets[:5], 1):
    print(f"{rank}. Volume: {pocket.volume:.1f} Ų")
    print(f"   Druggability: {pocket.lpocv_score:.2f}")
    print(f"   Coordinates: {pocket.centroid}")
    print(f"   Burial: {pocket.burial_depth:.2f} Å")
```

**Output Data Structure**:
```json
{
  "pockets": [
    {
      "id": "pocket_1",
      "centroid_x": 12.34,
      "centroid_y": 56.78,
      "centroid_z": -9.01,
      "volume_angstrom_sq": 350.5,
      "lpocv_score": 0.87,
      "burial_depth_angstrom": 2.3,
      "residues": ["GLY45", "ALA67", "TRP102", ...],
      "chains": ["A", "B"],
      "ligand_atoms_per_residue": 12
    },
    ...
  ]
}
```

**Success Criteria**:
- ✅ Identify 3–5 distinct pockets
- ✅ Each pocket ≥ 200 Ų
- ✅ LPOCV score ≥ 0.7 (druggable)
- ✅ Pockets mapped to tetramer interface regions

---

#### Step 1.2.2: Allosteric Site Screening

**Objective**: Identify pockets that destabilize tetramer assembly

**Analysis**:
```python
# Analyze pocket locations relative to tetramer interface
from biomate.structural import InterfaceAnalyzer

interface = InterfaceAnalyzer(
    pdb_file="Guo_ANDV_GP_tetramer.pdb",
    chain_pairs=[("A", "B"), ("A", "C"), ("A", "D"),  # Interfaces
                 ("B", "C"), ("B", "D"), ("C", "D")]
)

# For each pocket, calculate proximity to interface
for pocket in ranked_pockets:
    # Distance to nearest interface residue
    interface_distance = interface.distance_to_interface(
        pocket.centroid
    )
    
    # If < 8 Å from interface → allosteric candidate
    if interface_distance < 8.0:
        pocket.allosteric_score = 0.9
        pocket.allosteric_type = "interface_destabilizer"
    else:
        pocket.allosteric_score = 0.3
        pocket.allosteric_type = "non_allosteric"
    
    # Store result
    pocket.annotation = {
        "interface_distance_angstrom": interface_distance,
        "allosteric_likelihood": pocket.allosteric_score,
        "mechanism": pocket.allosteric_type
    }
```

**Output**: Ranked pockets by allosteric potential

---

#### Step 1.2.3: Antibody Epitope Overlap Analysis

**Objective**: Identify pockets near ADI-65534 binding site (potential small-molecule complement)

**Process**:
```python
# Extract epitope residues from GP-antibody complex
epitope_analyzer = EpitopeAnalyzer(
    pdb_file="Guo_ANDV_GP_ADI65534_complex.pdb",
    antigen_chain="A",  # ANDV GP
    antibody_chain="H"  # Heavy chain
)

# Residues within 4 Å of antibody
epitope = epitope_analyzer.identify_epitope(distance_cutoff=4.0)

# For each pocket, calculate proximity to epitope
for pocket in ranked_pockets:
    epitope_overlap = epitope_analyzer.overlap_score(
        pocket.centroid,
        epitope.residues,
        distance_cutoff=5.0  # Å
    )
    
    pocket.epitope_proximity = epitope_overlap
    pocket.complementarity_score = 0.8 if epitope_overlap > 0.5 else 0.2
```

**Output**: Epitope-aware pocket ranking

---

#### Step 1.2.4: Final Pocket Ranking & Selection

**Scoring Rubric**:
```python
# Multi-criterion pocket selection
final_score = (
    0.4 * pocket.lpocv_score +           # Druggability
    0.3 * pocket.allosteric_score +      # Allosteric potential
    0.2 * pocket.complementarity_score + # Antibody complement
    0.1 * (1.0 - pocket.burial_depth / 10.0)  # Accessibility
)

# Select top 3–5 pockets
selected_pockets = sorted(
    ranked_pockets,
    key=lambda p: final_score,
    reverse=True
)[:5]
```

**Deliverable**:

```
POCKET_SUMMARY.tsv
─────────────────────────────────────────
ID      | Volume | LPOCV | Allosteric | Epitope_Proximity | Final_Score
pocket_1| 350.5  | 0.87  | 0.9        | 0.6               | 0.82
pocket_2| 280.3  | 0.74  | 0.5        | 0.4               | 0.65
pocket_3| 210.1  | 0.68  | 0.8        | 0.2               | 0.62
...

POCKET_COORDINATES.pdb
─────────────────────────────────────────
(Atom coordinates + REMARK for each pocket)

POCKET_VISUALIZATION.pymol
─────────────────────────────────────────
(PyMOL script for 3D visualization)
```

---

### 1.3 Library Preparation (Week 2)

#### Step 1.3.1: Commercial Library Sourcing

**Source Libraries**:
1. **Enamine REAL database** (50K–500K compounds)
   - Drug-like subset (Ro5 compliant)
   - Focus: 200–400 Da (fits ANDV GP pockets)

2. **ChemDiv library** (alternative)
   - ~1M structures
   - Filtered: 250–450 Da, logP < 5

3. **Internal known antivirals** (SAR reference)
   - Ribavirin (positive control)
   - Remdesivir (broad-spectrum reference)
   - Known hantavirus inhibitors (if public)

**Action**: 
```
Contact Enamine/ChemDiv sales
Request: SDF file (50K–200K) + property CSV
Filters applied: 
  - MW: 250–450 Da
  - logP: 1–5
  - HBA: 2–8
  - HBD: 0–4
  - RotBonds: 0–8
  - TPSA: 20–130 Ų
  - pSA: 0–130 Ų
```

#### Step 1.3.2: Virtual Library Assembly

**Process**:
```python
from biomate.chemoinformatics import LibraryProcessor

# Load vendor libraries
enamine = LibraryProcessor.load_sdf("enamine_50k.sdf")
chemDiv = LibraryProcessor.load_sdf("chemdiv_100k.sdf")
internal = LibraryProcessor.load_smiles("known_antivirals.csv")

# Filter for drug-likeness
filtered = enamine.filter(
    molecular_weight=(250, 450),
    logp=(1.0, 5.0),
    hba=(2, 8),
    hbd=(0, 4),
    rot_bonds=(0, 8),
    tpsa=(20, 130)
)

# Deduplicate across libraries
merged = filtered.merge(chemDiv).deduplicate()

# Add reference compounds
merged = merged.add(internal)

# Property calculation
merged.calculate_properties([
    "TPSA", "logP", "molwt", "hbd", "hba",
    "aromatic_rings", "rot_bonds"
])

# Save for docking
merged.to_sdf("library_for_docking.sdf")
merged.to_csv("library_properties.csv")

print(f"Final library: {len(merged)} compounds")
```

**Output**:
```
library_for_docking.sdf          (SDF format for docking)
library_properties.csv           (Properties matrix)
known_antivirals_references.csv  (Ribavirin, Remdesivir, etc.)
```

---

## PHASE 2: VIRTUAL SCREENING & HIT DISCOVERY (Weeks 3–4)

### 2.1 Structure-Based Docking (High-Throughput)

**Three-Tier Docking Strategy**:

#### Tier 1: AutoDock Vina (Speed, 50K compounds)

```python
from biomate.docking import AutoDockVina

docking_engine = AutoDockVina(
    receptor_pdb="Guo_ANDV_GP_tetramer.pdb",
    exhaustiveness=4,  # Fast mode
    num_modes=1,  # Single best pose
    energy_range=3.0  # kcal/mol
)

# Run docking for each pocket
for pocket in selected_pockets:
    results = docking_engine.dock_library(
        library_sdf="library_for_docking.sdf",
        pocket_center=pocket.centroid,
        pocket_size=25,  # Å box size
        n_jobs=16  # Parallel CPUs
    )
    
    # Save results
    results.to_csv(f"vina_results_{pocket.id}.csv")
    results.sort_by_binding_energy(ascending=True)
    
    print(f"{pocket.id}: {len(results)} docked")
    print(f"Top binding energy: {results[0].binding_energy:.2f} kcal/mol")
```

**Output**: 
```
vina_results_pocket_1.csv
─────────────────────────────────────────
compound_id | binding_energy | rmsd_lb | rmsd_ub | ligand_efficiency
REAL_001    | -8.5          | 0.0     | 1.2     | 0.45
REAL_002    | -8.3          | 0.1     | 1.5     | 0.44
...

vina_poses_pocket_1.pdb  (PDB with docked poses)
```

**Performance Target**: 
- ⏱️ 4–6 hours per pocket (16-core CPU)
- Total: 18–30 hours for all pockets

---

#### Tier 2: Glide Standard (Accuracy, Top 500 Compounds)

```python
from biomate.docking import GlideStandard

# Select top Vina hits across all pockets
top_vina_hits = combine_and_rank_vina_results(
    all_pockets=selected_pockets,
    top_per_pocket=100,  # 500 total across 5 pockets
    min_binding_energy=-7.0
)

# Glide rescoring (more accurate)
glide = GlideStandard(
    receptor_pdb="Guo_ANDV_GP_tetramer.pdb",
    precision="SP"  # Standard Precision
)

glide_results = glide.dock(
    compounds_sdf=top_vina_hits.to_sdf(),
    pocket_center=selected_pockets[0].centroid,
    pocket_size=30  # Å box
)

# Rank by Glide score
glide_results.sort_by_glide_score(ascending=True)

glide_results.to_csv("glide_results_top500.csv")
```

**Expected Output**:
```
Top 500 compounds re-ranked by Glide
Typical Glide score range: -6.0 to -8.5 kcal/mol
```

---

#### Tier 3: DiffDock (Deep Learning, Top 100)

```python
from biomate.docking import DiffDock

# Select top Glide hits
top_glide = glide_results.head(100)

# Deep learning refinement
diffdock = DiffDock(
    model="default",
    gpu=True
)

diffdock_results = diffdock.dock(
    compounds=top_glide.smiles,
    receptor_pdb="Guo_ANDV_GP_tetramer.pdb",
    pocket_center=selected_pockets[0].centroid,
    num_poses=3  # 3 poses per compound
)

# Rank by DiffDock score
diffdock_results.rank_by_confidence()

diffdock_results.to_csv("diffdock_results_top100.csv")
diffdock_results.poses_to_pdb("diffdock_poses/")
```

---

### 2.2 ADMET Triage (Parallel)

**Objective**: Eliminate compounds with poor drug-like properties before synthesis

```python
from biomate.admet import ADMETPredictor

# Load Vina results
hits = pd.read_csv("vina_results_all_pockets_combined.csv")

predictor = ADMETPredictor(
    model_source="biomate_trained"  # Your internal models
)

# Predict ADMET for all hits
admet_predictions = predictor.predict_batch(
    smiles_list=hits['smiles'],
    properties=[
        "lipinski_ro5",
        "tpsa",
        "herg_risk",
        "cyp_inhibition_panel",
        "plasma_protein_binding",
        "aqueous_solubility",
        "metabolic_stability"
    ]
)

# Triage: Remove failures
failures = admet_predictions[
    (admet_predictions['lipinski_violation'] > 1) |
    (admet_predictions['herg_risk'] == "high") |
    (admet_predictions['solubility'] < -5)  # logS
]

passed = admet_predictions[
    ~admet_predictions.index.isin(failures.index)
]

print(f"Passed ADMET triage: {len(passed)}/{len(hits)} ({100*len(passed)/len(hits):.1f}%)")
```

**Scoring Rubric**:
```
PASS (Advance to synthesis consideration):
  ✅ Ro5 violations: 0–1 (at most 1 violation)
  ✅ hERG risk: Low or Medium
  ✅ CYP inhibition: <50% at 10 µM for major isoforms
  ✅ Solubility: logS > -6
  ✅ TPSA: 20–130 Ų

FAIL (Eliminate):
  ❌ Ro5 violations: ≥2
  ❌ hERG risk: High
  ❌ CYP inhibition: >80% (major DDI risk)
  ❌ Solubility: logS < -7
```

---

### 2.3 Hit Selection & Ranking

**Final Hit List**:
```python
# Combine docking + ADMET scores
hit_ranking = pd.DataFrame({
    'compound_id': passed.index,
    'vina_score': passed['binding_energy'],
    'glide_score': passed['glide_score'],
    'admet_pass': True,
    'herg_risk': passed['herg_risk'],
    'solubility': passed['solubility'],
    'caco2': passed['caco2_permeability']
})

# Multi-criterion ranking
hit_ranking['composite_score'] = (
    0.4 * normalize(hit_ranking['vina_score'], reverse=True) +
    0.3 * normalize(hit_ranking['glide_score'], reverse=True) +
    0.2 * normalize(hit_ranking['caco2'], reverse=True) +
    0.1 * (hit_ranking['herg_risk'] == "low").astype(int)
)

hits_top50 = hit_ranking.nlargest(50, 'composite_score')

# Save top 50 for SAR analysis
hits_top50.to_csv("hit_list_top50.csv")
```

**Deliverable**:
```
HIT_LIST_TOP50.csv
─────────────────────────────────────────────────────
compound_id | SMILES | Vina_Score | Glide_Score | hERG | Solubility | Composite_Score
REAL_0001   | CC... | -8.5       | -7.8        | Low  | -4.2       | 0.87
REAL_0045   | CC... | -8.2       | -7.5        | Med  | -4.5       | 0.81
...

HIT_DOCKING_VISUALIZATION.pymol
─────────────────────────────────────────────────────
(PyMOL script showing top 20 docked poses)
```

---

## PHASE 3: HIT-TO-LEAD DMTA LOOP (Weeks 5–15)

### 3.1 Bayesian Optimization Framework

**Objective**: Iteratively propose chemical analogs with improved ADMET while maintaining binding

```python
from biomate.optimization import BayesianOptimizer
from biomate.chemoinformatics import AnalogGenerator

# Initialize Bayesian optimizer
optimizer = BayesianOptimizer(
    objective_metrics=[
        "binding_energy",      # docking score (minimize)
        "admet_composite",     # ADMET score (maximize)
        "selectivity_gini",    # kinase selectivity (maximize)
        "synthesizability"     # Syncraft score (maximize)
    ],
    constraints={
        "mw": (250, 450),
        "logp": (1.0, 5.0),
        "herg_risk": ["low", "medium"]
    },
    method="gaussian_process",  # GP surrogate model
    acquisition="expected_improvement"
)

# Round 1: Train on initial hits
initial_compounds = hits_top50.copy()
initial_data = {
    'smiles': initial_compounds['SMILES'],
    'binding_energy': initial_compounds['vina_score'],
    'admet_score': initial_compounds['admet_composite'],
    'synthesizability': initial_compounds['syncraft_score']
}

optimizer.fit(initial_data)

# Generate analogs
analog_generator = AnalogGenerator(
    library_model="libinvent",  # Generative model
    constraint_filter=True
)

# Propose 20 new compounds
proposed_round1 = optimizer.suggest_batch(
    n_compounds=20,
    strategy="expected_improvement"
)

# Validate proposed compounds
validated_smiles = [smi for smi in proposed_round1['smiles'] 
                   if validate_chemistry(smi)]

print(f"Valid proposed compounds: {len(validated_smiles)}/{len(proposed_round1)}")
```

**Data Structure**:
```json
{
  "round": 1,
  "proposed_compounds": [
    {
      "id": "bo_001",
      "smiles": "CC(=O)Nc1ccc(cc1)c2ccc(cc2)C(=O)O",
      "predicted_binding_energy": -8.7,
      "predicted_admet_score": 0.92,
      "predicted_selectivity": 0.85,
      "predicted_syncraft": 0.7,
      "rationale": "Reduced MW while maintaining H-bond acceptors"
    },
    ...
  ]
}
```

---

### 3.2 Round-by-Round Execution

#### **ROUND 1: Synthesis & Bioassays (Weeks 5–9)**

**CRO Order**:
```
TO: Enamine (or WuXi Express)
──────────────────────────────────
Compounds to synthesize: 6 (from top proposed)
Delivery timeline: 2–3 weeks
Purity required: >95% (HPLC)
Quantities: 10 mg each (for bioassays)
Cost: $15–25K

Compound List:
BO_001, BO_002, BO_003, BO_004, BO_005, BO_006
```

**Bioassay Panel**:

**[Assay 1.1] Viral Pseudotype Entry Inhibition**
```
Protocol:
  • Lentiviral particles pseudotyped with ANDV GP
  • Target cells: HEK293 or Huh7
  • Readout: Luciferase activity (48h post-infection)
  • Positive control: ADI-65534 (neutralizing antibody)
  • Negative control: Ribavirin (known weak inhibitor)
  • Test range: 0.1–100 µM
  • Replicates: 3
  
Expected output:
  IC50_pseudotype_µM: [e.g., 2.3, 1.8, 3.1, ...]
  EC50_estimate: [based on dose-response fit]
  
Cost per compound: $200–300
Timeline: 3 weeks
```

**[Assay 1.2] Target Engagement (SPR)**
```
Protocol:
  • Immobilize ANDV GP tetramer on SPR chip
  • Inject compounds at 5 µM
  • Measure: Kd (dissociation constant), kon, koff
  • Positive control: ADI-65534 antibody
  • Reference: Ribavirin
  
Expected output:
  Kd_µM: [affinity]
  kon_M-1s-1: [association rate]
  koff_s-1: [dissociation rate]
  
Cost per compound: $150–200
Timeline: 2 weeks
```

**[Assay 1.3] Selectivity Panel**
```
Protocol:
  • hERG: PatchClamp equivalent (HERGLite)
    Target: IC50 > 30 µM (safety margin)
  
  • Microsomal stability:
    Liver microsomes + NADPH
    Measure: Half-life (min), CLint (µL/min/mg protein)
    Target: t½ > 20 min (low clearance compounds preferred)
  
Cost per compound: $100–150
Timeline: 2 weeks
```

**Data Collection Template**:
```csv
compound_id, assay, ic50_µm, ec50_µm, potency_fold_vs_ribavirin, 
selectivity_kinase_index, herg_ic50_µm, microsomal_t_half_min
BO_001, pseudotype, 2.3, 1.8, 12.8, 0.95, 45, 25
BO_002, pseudotype, 1.9, 1.5, 15.2, 0.87, 52, 31
...
```

---

#### **Round 1 Data Integration (Week 10)**

```python
# Load experimental results
expt_data = pd.read_csv("round1_bioassays.csv")

# Update Bayesian model
optimizer.update(
    smiles=expt_data['compound_id'].map(lambda x: smiles_map[x]),
    y_binding=expt_data['ic50_µm'],
    y_admet=-log10(expt_data['microsomal_t_half_min']),  # Proxy for clearance
    y_selectivity=expt_data['selectivity_kinase_index']
)

# Generate next round (10 compounds)
proposed_round2 = optimizer.suggest_batch(
    n_compounds=10,
    strategy="expected_improvement",
    diversity_penalty=0.2
)

print("Round 1 Results:")
print(expt_data[['compound_id', 'ic50_µm', 'herg_ic50_µm', 'microsomal_t_half_min']].to_string())

# Calculate predictive accuracy
print("\nPredicted vs. Measured IC50 Correlation:")
correlation = calculate_pearson_r(
    expt_data['predicted_ic50'],
    expt_data['ic50_µm']
)
print(f"r = {correlation:.3f}")
```

---

#### **ROUND 2: Synthesis & Bioassays (Weeks 11–15)**

**Same CRO panel**, now targeting top 10 compounds from Bayesian optimization

**Expected Improvements**:
- IC50 more potent (target: < 1 µM)
- hERG IC50 maintained or improved (target: > 30 µM)
- Microsomal half-life improved (target: > 25 min)
- Selectivity index improved (target: > 0.9)

---

### 3.3 Data Integration & SAR Analysis

**Once Round 2 data available (Week 16)**:

```python
# Compile all compounds (Round 1 + Round 2)
all_data = pd.concat([round1_data, round2_data])

# SAR Landscape
sar_analysis = SARAnalyzer(
    compounds=all_data,
    features=['binding_energy', 'mw', 'logp', 'tpsa', 'hba', 'hbd'],
    targets=['ic50_pseudotype', 'microsomal_clint', 'herg_ic50']
)

# Generate SAR heatmap
sar_analysis.plot_activity_landscape(
    x_feature='mw',
    y_feature='logp',
    color_by='ic50_pseudotype',
    output='sar_landscape.png'
)

# Key SAR insights:
# Example: "Compounds with MW 300–350 and logP 2.5–3.5 show best potency"

insights = sar_analysis.extract_rules()
for rule in insights:
    print(f"SAR Rule {rule.confidence:.2%}: {rule.description}")
```

---

## PHASE 4: PUBLICATION & RELEASE (Weeks 17–20)

### 4.1 Manuscript Preparation

**Title**: "Structure-Based Design of Andes Virus Glycoprotein Inhibitors using AI-Guided Drug Discovery: From Virtual Screening to In Vitro Validation"

**Sections**:

1. **Methods**
   - Pocket identification (AutoSite)
   - Virtual screening (Vina/Glide/DiffDock)
   - ADMET prediction
   - Bayesian optimization
   - Bioassay protocols

2. **Results**
   - Pocket analysis (figures + table)
   - Hit discovery statistics (% ADMET pass-through)
   - Round 1 & 2 bioassay results
   - SAR analysis + mechanistic insights
   - Predicted vs. measured IC50 correlation

3. **Discussion**
   - Comparison to ribavirin + known antivirals
   - DMPK profile assessment
   - Next steps for in vivo validation
   - Therapeutic potential

4. **Data Availability**
   - GitHub repository link
   - Compound library (SDF + CSV)
   - PDB coordinates + docking poses

---

### 4.2 Figure & Data Package

**Figures**:
```
Figure 1: ANDV GP structure & pocket identification
  Panel A: Guo's cryo-EM structure (tetramer)
  Panel B: Top 5 pockets colored by druggability
  Panel C: Allosteric site mapping
  Panel D: Epitope alignment with ADI-65534

Figure 2: Virtual screening pipeline
  Panel A: Docking funnel (50K → 500 → 100 compounds)
  Panel B: Vina vs. Glide score distribution
  Panel C: ADMET pass-through rates by compound class
  Panel D: Top 50 hits ranked by composite score

Figure 3: Bayesian optimization & DMTA loop
  Panel A: Round 1 proposed compounds (chemical structures)
  Panel B: Predicted vs. measured IC50 (scatter plot)
  Panel C: SAR landscape (MW vs. logP vs. IC50)
  Panel D: Lead series scaffolds

Figure 4: Structure-activity relationships
  Panel A: Docking poses of top 5 compounds
  Panel B: Key H-bonds & interactions
  Panel C: ADMET property profiles vs. ribavirin
  Panel D: Microsomal stability + hERG selectivity

Table 1: Hit Summary (16 compounds, Round 1 + 2)
  Columns: Compound ID, SMILES, MW, logP, IC50, hERG IC50, t½, Selectivity Index

Table 2: SAR Rules extracted from Bayesian model
  Columns: Rule, Confidence, Description, Example Compounds

Supplementary Table S1: Full compound library (SDF download link)
Supplementary Figure S1: Full docking poses (PDB files)
```

---

### 4.3 GitHub Release

**Repository Structure**:
```
biomate-andv-inhibitors/
│
├── README.md
│   └─ Project overview, citation, usage
│
├── data/
│   ├─ compound_library.sdf       (All 16 compounds + 50 hits)
│   ├─ compound_library.csv       (SMILES + ADMET properties)
│   ├─ bioassay_results.csv       (IC50, selectivity, stability)
│   ├─ docking_poses.tar.gz       (PDB for all poses)
│   └─ selected_pockets.pdb       (Top 5 ANDV GP pockets)
│
├── code/
│   ├─ 01_pocket_identification.py
│   ├─ 02_virtual_screening.py
│   ├─ 03_admet_filtering.py
│   ├─ 04_bayesian_optimization.py
│   └─ 05_sar_analysis.py
│
├── notebooks/
│   ├─ docking_visualization.ipynb
│   ├─ sar_analysis.ipynb
│   └─ bioassay_correlation.ipynb
│
├── figures/
│   ├─ pocket_identification.png
│   ├─ docking_funnel.png
│   ├─ sar_landscape.png
│   └─ dose_response_curves.png
│
└── LICENSE (CC-BY 4.0)
```

**README Example**:
```markdown
# ANDV Glycoprotein Inhibitor Library

## Overview
This repository contains a curated library of 16 novel Andes virus (ANDV) 
glycoprotein inhibitors designed using AI-guided drug discovery.

## Citation
[Preprint DOI or Author et al., bioRxiv 2026]

## Quick Start
```python
from rdkit import Chem
import pandas as pd

# Load compound library
compounds = pd.read_csv("data/compound_library.csv")
print(f"Library size: {len(compounds)} compounds")

# View top compounds by IC50
top = compounds.nsmallest(5, 'ic50_pseudotype_µm')
print(top[['compound_id', 'ic50_pseudotype_µm', 'herg_ic50_µm']])

# Load SDF for visualization
mols = Chem.SDMolSupplier("data/compound_library.sdf")
```

## Data Description

### Compound Properties
- **compound_id**: Unique identifier
- **smiles**: SMILES string
- **mw**: Molecular weight (Da)
- **logp**: Partition coefficient
- **ic50_pseudotype_µm**: Viral pseudotype entry inhibition (µM)
- **herg_ic50_µm**: hERG channel activity (µM, higher = safer)
- **microsomal_t_half_min**: Liver microsomal half-life (min)
- **selectivity_kinase_gini**: Off-target selectivity (0–1, higher = better)

## Key Findings
- **Most potent**: Compound BO_015 (IC50 = 0.8 µM, selectivity = 0.93)
- **Best ADMET**: Compound BO_012 (t½ = 35 min, hERG IC50 = 65 µM)
- **SAR insight**: MW 300–350 Da + logP 2.5–3.5 optimal for binding + ADMET
```

---

### 4.4 Pre-print Submission

**Timeline**: Week 17–18

**Target Venue**: bioRxiv (rapid dissemination)

**Submission Checklist**:
- ✅ Manuscript (Methods, Results, Discussion, References)
- ✅ Figures (4 main + Supplementary)
- ✅ Tables (2 main + Supplementary S1, S2)
- ✅ Data availability statement
- ✅ Conflict of interest
- ✅ GitHub DOI badge (Zenodo)

**Link**: `https://www.biorxiv.org/content/XXXX.XXXX`

---

## DELIVERABLES CHECKLIST

### By Week 16 (Data Complete):
- [ ] 16 novel ANDV GP inhibitors with IC50 + ADMET
- [ ] Compound library (SDF + CSV)
- [ ] Bioassay results (pseudotype, SPR, selectivity)
- [ ] SAR analysis & mechanistic insights
- [ ] Docking visualizations (PyMOL/Chimera)

### By Week 18 (Pre-print):
- [ ] bioRxiv pre-print submitted
- [ ] Manuscript with figures & tables
- [ ] GitHub repository live + DOI

### By Week 20 (Full Release):
- [ ] Pre-print live + promoted on social media
- [ ] GitHub fully populated
- [ ] Blog post on BioMate website
- [ ] Discussion thread on relevant forums (virology, drug discovery)

---

## BUDGET BREAKDOWN

| Item | Cost | Timeline |
|------|------|----------|
| **CRO Synthesis Round 1** (6 compounds) | $15–20K | Weeks 5–6 |
| **Pseudotype Assay** (6 compounds) | $1.2–1.8K | Weeks 6–9 |
| **SPR Target Engagement** (6 compounds) | $0.9–1.2K | Weeks 7–8 |
| **Selectivity Panel** (6 compounds) | $0.6–0.9K | Weeks 7–9 |
| **CRO Synthesis Round 2** (10 compounds) | $20–25K | Weeks 11–12 |
| **Bioassays Round 2** (10 compounds) | $3–4K | Weeks 12–15 |
| **Computational Labor** (BioMate internal) | $0 (sunk) | Ongoing |
| **Writing + Figure Design** | $3–5K | Weeks 16–18 |
| **Submission Fees** | $0 (bioRxiv) | Week 17 |
| **TOTAL** | **$44–57K** | **4 months** |

---

## SUCCESS METRICS

### Inhibitor Track Success = ALL of:
- ✅ ≥ 15 novel compounds identified
- ✅ ≥ 1 compound with IC50 < 1 µM (5–10x better than ribavirin)
- ✅ ≥ 10 compounds with hERG IC50 > 30 µM
- ✅ ≥ 8 compounds with microsomal t½ > 20 min
- ✅ Predicted vs. measured IC50 correlation r > 0.70
- ✅ Pre-print published on bioRxiv
- ✅ GitHub repository with open-source data
- ✅ One academic collaboration offer (in vivo validation)

---

## NEXT STEPS (Post-Campaign)

1. **In Vivo Validation**: Partner with virology lab for mouse efficacy studies
2. **Lead Optimization**: Select top 2 candidates for preclinical PK/Tox
3. **Patent Filing**: File composition-of-matter + method patents
4. **IND Enabling**: ADME/Tox + CMC for FDA IND application

---

**Document Version**: 1.0 (April 2026)  
**Author**: BioMate AI  
**Status**: Ready for Implementation via Claude Code
