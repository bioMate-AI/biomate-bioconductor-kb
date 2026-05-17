# ANDV Broad-Spectrum Vaccine Design: PLAN A (Protein/VLP)
## Implementation Plan — Ready for Claude Code

**Project**: Rational Immunogen Design for Broad-Spectrum Hantavirus Protection  
**Timeline**: 4 months (Weeks 1–20, parallel with Inhibitor Track)  
**Budget**: $38–53K  
**Approach**: Protein-based VLP immunogens + CD8+ T-cell epitopes  
**Owner**: BioMate Structural Biology & Immunology Team  
**Deliverables**:
- 3 novel immunogen constructs (mosaic, chimeric, consensus)
- Proof-of-concept neutralizing antibodies in mice
- Cross-species breadth validation (ANDV/SNV/PUUV)
- Pre-print + open-source vaccine design framework

**BioMate / nf-core dev note (epitopeprediction, id 12700):** If `POST /api/nextflow/execute` with `nfcore/epitopeprediction/main.nf` fails with missing `conf/base.config`, the nested clone under `backend/nf-core-workflows/epitopeprediction` may have **git sparse-checkout** excluding directories. Run **`bash research/anti-virus/scripts/ensure_nfcore_epitopeprediction_worktree.sh`** once, then re-submit. Full biocontainer runs on **ARM64** may still need **AWS Batch** or an **x86** host.

**AWS Batch (linux/amd64) — scripted path:** Use **`python3 research/anti-virus/scripts/run_plan_a_epitopeprediction_batch.py`** with **`profile: docker`**, **`compute_config.executor: awsbatch`**, and an S3 samplesheet whose `filename` column uses absolute **`s3://…`** paths. Checked-in sheet template: **`research/anti-virus/runs/plan_a_epitope_samplesheet_template/samplesheet_s3_batch.csv`**. Details and defaults (including `nextflow_path`) are in the script docstring and `research/anti-virus/runs/plan_a_exec_20260512T184220Z/EXECUTION_REPORT.md`.

**Plan A — in silico publication checklist (no wet lab):** `research/anti-virus/docs/PLAN_A_VACCINE_INSILICO_PUBLICATION_CHECKLIST.md`

---

## PHASE 1: EPITOPE DISCOVERY & MAPPING (Weeks 1–4)

### 1.1 Epitope Extraction from Guo's Structure

**Input Data**:
- ANDV GP tetramer (2.35 Å, Guo et al.)
- ANDV GP + ADI-65534 antibody complex (high-res)

**Workflow**:

```python
from biomate.structural import EpitopeAnalyzer
from biomate.immunology import MHCPredictor

# Initialize epitope analysis
epitope_analyzer = EpitopeAnalyzer(
    pdb_file="Guo_ANDV_GP_ADI65534_complex.pdb",
    antigen_chain="A",      # ANDV GP
    antibody_chains={"H": "heavy", "L": "light"}
)

# Extract epitope residues (within 4 Å of antibody)
epitope_residues = epitope_analyzer.identify_epitope(
    distance_cutoff=4.0  # Å from any antibody atom
)

# Define linear epitope sequence
linear_epitope_sequence = epitope_analyzer.extract_sequence(
    residue_indices=epitope_residues,
    padding=3  # Add 3 residues on each side for context
)

print(f"Epitope length: {len(linear_epitope_sequence)} residues")
print(f"Epitope sequence: {linear_epitope_sequence}")

# Output: Epitope definition
epitope_data = {
    "name": "ADI-65534_epitope_ANDV",
    "sequence": linear_epitope_sequence,
    "residue_indices": epitope_residues,
    "antibody_interface_residues": epitope_analyzer.get_interface_atoms(),
    "conformational_epitope": True,  # 3D structure important
    "buried_residues": epitope_analyzer.identify_buried_residues(),
    "exposed_residues": epitope_analyzer.identify_exposed_residues()
}

import json
with open("epitope_definition_ANDV.json", "w") as f:
    json.dump(epitope_data, f, indent=2)
```

**Output**:
```
epitope_definition_ANDV.json
─────────────────────────────────────────
{
  "name": "ADI-65534_epitope_ANDV",
  "sequence": "FKTFATGTVLLAVGLC...",
  "length": 28,
  "residue_indices": [45, 46, 48, 50, ...],
  "conformational_epitope": true,
  "pdb_contact_atoms": 127
}
```

---

### 1.2 Cross-Species Sequence Alignment

**Objective**: Identify which epitope regions are conserved across hantavirus species

**Species Target**:
1. **ANDV** (Andes virus) — primary target
2. **SNV** (Sin Nombre virus) — North American spillover risk
3. **PUUV** (Puumala virus) — European threat

**Workflow**:

```python
from biomate.bioinformatics import SequenceAligner, ConservationAnalyzer

# Fetch sequences from UniProt
sequences = {
    "ANDV": "MKTILLIVFLVISPPQ...",  # GP2 sequence (UniProt P29525)
    "SNV": "MKTILLTVSLVVSFPQ...",   # GP2 sequence (UniProt P30833)
    "PUUV": "MKKILLIVFLVISPPQ...",  # GP2 sequence (UniProt P14397)
}

# Multiple sequence alignment
aligner = SequenceAligner(method="muscle")
msa = aligner.align(sequences)

# Extract epitope regions from alignment
epitope_aligned = msa.extract_region(
    residue_indices=epitope_data["residue_indices"],
    padding=3
)

print("Aligned epitope sequences:")
for species, seq in epitope_aligned.items():
    print(f"{species}: {seq}")

# Conservation analysis
conserv_analyzer = ConservationAnalyzer(
    msa=msa,
    method="shannon_entropy"
)

# Calculate entropy at each position
entropy_scores = conserv_analyzer.positional_entropy()

# Identify highly conserved positions (entropy < 0.5 bits = <50% variability)
conserved_positions = [i for i, e in enumerate(entropy_scores) if e < 0.5]

print(f"Conserved epitope positions: {len(conserved_positions)}/{len(entropy_scores)}")

# Output: Conservation heatmap
conserv_analyzer.plot_entropy(
    output="epitope_conservation_heatmap.png"
)

# Save alignment for visualization
msa.to_clustalw("epitope_alignment_ANDV_SNV_PUUV.aln")
```

**Output Data Structure**:
```
epitope_alignment_ANDV_SNV_PUUV.aln
──────────────────────────────────────────
ANDV          FKTFATGTVLLAVGLCILVSSQRFVT...
SNV           FKTFATGTVLLSVGLCILVSSQRFVT...
PUUV          FKTFATGSVLLSVGLCILVGSQRFVT...
              **** **.** *** ***** * *** 

Conservation: Position 1 = 100%, Position 5 = 95%, ...

conservation_scores.json
──────────────────────────────────────────
{
  "position": [1, 2, 3, ...],
  "residue_ANDV": ["F", "K", "T", ...],
  "residue_SNV": ["F", "K", "T", ...],
  "residue_PUUV": ["F", "K", "S", ...],
  "entropy_bits": [0.0, 0.0, 0.52, ...],
  "conservation_percent": [100, 100, 95, ...],
  "consensus": ["F", "K", "T", ...]
}
```

---

### 1.3 Discontinuous Epitope Prediction

**Objective**: Identify *additional* neutralizing epitopes beyond ADI-65534 site

**Tools**:
- **ProTools**: Epitope prediction from structure
- **EPSVR**: Machine learning epitope scoring
- **DiscoTope**: Discontinuous epitope finder

```python
from biomate.immunology import EpitopePredictor

predictor = EpitopePredictor(
    pdb_file="Guo_ANDV_GP_tetramer.pdb",
    chain="A"
)

# Predict additional surface-exposed epitopes
predicted_epitopes = predictor.predict_epitopes(
    method="discotope2",
    confidence_threshold=0.5
)

print(f"Predicted epitopes: {len(predicted_epitopes)}")

# Rank by immunogenicity potential
ranked = sorted(
    predicted_epitopes,
    key=lambda e: e.immunogenicity_score,
    reverse=True
)

# Select top 3–5 candidates
candidate_epitopes = ranked[:5]

for rank, epitope in enumerate(candidate_epitopes, 1):
    print(f"{rank}. Residues {epitope.residue_range}")
    print(f"   Score: {epitope.immunogenicity_score:.3f}")
    print(f"   Surface exposure: {epitope.surface_accessibility:.1%}")
```

**Output**: 3–5 predicted epitope regions for immunogen incorporation

---

## PHASE 2: MHC BINDING & CD8+ T-CELL EPITOPE PREDICTION (Weeks 2–4)

### 2.1 MHC-Peptide Binding Prediction

**Objective**: Identify which peptides from ANDV GP epitopes bind common human HLA molecules

**Target HLA Types** (population coverage):
- HLA-A*02:01 (50% worldwide)
- HLA-A*01:01 (25%)
- HLA-B*07:02 (15%)
- HLA-C*07:02 (10%)

**Workflow**:

```python
from biomate.immunology import MHCPredictor, PeptideGenerator

# Generate 8–12 mer peptides from each epitope
peptide_gen = PeptideGenerator()

all_peptides = []
for epitope in candidate_epitopes:
    peptides = peptide_gen.generate_kmers(
        sequence=epitope.sequence,
        k_min=8,
        k_max=12,
        overlap=1  # Generate overlapping peptides
    )
    all_peptides.extend(peptides)

print(f"Total peptides generated: {len(all_peptides)}")

# Predict MHC binding affinity
mhc_predictor = MHCPredictor(
    algorithm="netmhc4.1",  # NetMHC 4.1
    hla_alleles=[
        "HLA-A*02:01",
        "HLA-A*01:01", 
        "HLA-B*07:02",
        "HLA-C*07:02"
    ]
)

# Batch predict for all peptides
predictions = mhc_predictor.predict_batch(
    peptides=all_peptides,
    affinity_threshold=500  # nM (strong binders < 500 nM)
)

# Filter for strong binders
strong_binders = predictions[
    predictions['affinity_nM'] < 500
].sort_values('affinity_nM')

print(f"Strong MHC binders: {len(strong_binders)}/{len(predictions)}")
print(strong_binders[['peptide', 'hla_allele', 'affinity_nM']].head(10))

# Additional predictions
additional_pred = mhc_predictor.predict_batch(
    peptides=all_peptides,
    additional_properties=[
        "proteasomal_cleavage",  # NetChop
        "tap_transport",          # TAPPred
        "immunogenicity"          # IEDB MHC-IG
    ]
)

# Integrate all predictions
integrated = strong_binders.merge(
    additional_pred[['peptide', 'cleavage_score', 'tap_score', 'immunogenicity_score']],
    on='peptide'
)

# CD8+ T-cell epitope score
integrated['cd8_epitope_score'] = (
    0.4 * (1 - integrated['affinity_nM']/1000) +  # MHC binding strength
    0.3 * integrated['cleavage_score'] +          # Proteasomal cleavage
    0.2 * integrated['tap_score'] +               # TAP transport
    0.1 * integrated['immunogenicity_score']      # Immunogenicity
)

# Top CD8+ epitopes (target: 5–10)
top_cd8 = integrated.nlargest(10, 'cd8_epitope_score')

print("\nTop CD8+ T-cell Epitopes:")
print(top_cd8[['peptide', 'hla_allele', 'affinity_nM', 'cd8_epitope_score']])

# Save results
top_cd8.to_csv("cd8_epitopes_top10.csv")
```

**Output**:
```
cd8_epitopes_top10.csv
──────────────────────────────────────────────────────────────
peptide | hla_allele | affinity_nM | cleavage | tap_score | cd8_score
FKTFATGTV | HLA-A*02:01 | 245 | 0.92 | 0.88 | 0.85
TGTVLLAVG | HLA-B*07:02 | 380 | 0.85 | 0.91 | 0.82
KTFATGTV | HLA-A*01:01 | 420 | 0.88 | 0.85 | 0.80
...
```

---

### 2.2 Population Coverage Analysis

**Objective**: Estimate % of global population that can mount CD8+ response

```python
from biomate.immunology import PopulationCoverage

# HLA frequency database
hla_frequencies = {
    "HLA-A*02:01": 0.50,
    "HLA-A*01:01": 0.25,
    "HLA-B*07:02": 0.15,
    "HLA-C*07:02": 0.10,
    # Add more alleles for accuracy
}

coverage = PopulationCoverage(
    epitopes=top_cd8['peptide'].tolist(),
    hla_frequencies=hla_frequencies
)

# Calculate coverage
global_coverage = coverage.calculate(
    method="within_allele_breadth"  # Each allele counts once
)

print(f"Estimated global population coverage: {global_coverage:.1%}")

# Coverage by region
regional_coverage = coverage.calculate_by_region(
    regions=["North America", "Europe", "Asia", "Africa"]
)

for region, pct in regional_coverage.items():
    print(f"{region}: {pct:.1%}")
```

---

## PHASE 3: IMMUNOGEN CONSTRUCT DESIGN (Weeks 4–6)

### 3.1 Construct A: Mosaic Epitope

**Design Strategy**: Chain conserved epitopes from ANDV/SNV/PUUV with spacer

```python
from biomate.immunology import ImmunoigenDesigner

# Extract conserved epitope sequences (from cross-species alignment)
conserved_epitopes = {
    "ANDV_region_1": "FKTFATGTVLLAV",
    "SNV_region_1": "FKTFATGTVLLSV",
    "PUUV_region_1": "FKTFATGSV",  # Shortest due to alignment
}

# Use consensus sequence (most common residue at each position)
consensus_epitope = "FKTFATGTV"  # 100% conserved core

designer = ImmunoigenDesigner()

# Design mosaic construct
construct_A = designer.design_mosaic(
    epitope_segments=[
        conserved_epitope,  # ANDV core epitope
        "TGTVLLAVG",       # SNV-specific
        "LLAVGLCIL",       # PUUV-specific
    ],
    spacer="GS" * 3,  # Glycine-serine linker (9 aa)
    order="sequential"
)

construct_A_sequence = construct_A['sequence']
construct_A_length = len(construct_A_sequence)

print(f"Construct A (Mosaic):")
print(f"Sequence: {construct_A_sequence}")
print(f"Length: {construct_A_length} aa")
print(f"Epitope coverage: ANDV (✓), SNV (✓), PUUV (✓)")

# Save construct
with open("construct_A_mosaic.fasta", "w") as f:
    f.write(">Construct_A_Mosaic_ANDV_SNV_PUUV\n")
    f.write(construct_A_sequence + "\n")
```

**Construct A Output**:
```
>Construct_A_Mosaic_ANDV_SNV_PUUV
FKTFATGTVLLAVGGSTGTVLLSVGSLLAVGLCILGGSGSGSGSGSGSGSPPPPPPPPP
Length: 61 aa
Molecular Weight: 6,800 Da
```

---

### 3.2 Construct B: Chimeric VLP

**Design Strategy**: ANDV GP backbone with SNV/PUUV epitope grafts

```python
# Load ANDV GP structure (from Guo)
andv_gp = PDB("Guo_ANDV_GP_monomer.pdb")

# Identify loop regions suitable for epitope insertion
loops = andv_gp.identify_loops(min_length=8, max_length=20)

print(f"Identified {len(loops)} potential graft sites")

# Select 2 best loops for epitope insertion
best_loops = sorted(
    loops,
    key=lambda l: l.surface_exposure,
    reverse=True
)[:2]

# Design chimeric construct
construct_B = designer.design_chimeric_vip(
    backbone="ANDV_GP",
    graft_sites=[
        {
            "loop": best_loops[0],
            "epitope": "TGTVLLSVGL",  # SNV epitope
            "flanking": 3  # Keep 3 flank residues
        },
        {
            "loop": best_loops[1],
            "epitope": "LLAVGLCIL",   # PUUV epitope
            "flanking": 3
        }
    ]
)

construct_B_sequence = construct_B['sequence']

print(f"Construct B (Chimeric VLP):")
print(f"Backbone: ANDV GP (gp120)")
print(f"Graft 1: SNV epitope at position {best_loops[0].start}")
print(f"Graft 2: PUUV epitope at position {best_loops[1].start}")
print(f"Total length: {len(construct_B_sequence)} aa")

# Structural validation: fold prediction
structure_validator = StructureValidator()
predicted_structure = structure_validator.predict_fold(
    sequence=construct_B_sequence,
    model="esmfold"  # Fast structure prediction
)

print(f"Predicted pLDDT confidence: {predicted_structure.plddt_mean:.2f}")
if predicted_structure.plddt_mean > 70:
    print("✓ Structural integrity preserved (pLDDT > 70)")
else:
    print("✗ Warning: Low confidence in predicted structure")
```

---

### 3.3 Construct C: Consensus Sequence

**Design Strategy**: Derive consensus ANDV/SNV/PUUV GP sequence

```python
# Generate consensus from cross-species MSA
consensus_seq = msa.consensus(
    method="majority_vote"  # Most common residue at each position
)

# Construct C = full consensus GP ectodomain
construct_C_sequence = consensus_seq

print(f"Construct C (Consensus):")
print(f"Sequence length: {len(construct_C_sequence)} aa")
print(f"Expected expression system: Mammalian (HEK293) or insect (Sf9)")
print(f"Expected refolding: 12–24 hours with oxidation")

# Validate consensus doesn't have stop codons or frameshifts
validator = SequenceValidator()
validation_result = validator.validate(construct_C_sequence)

if validation_result.is_valid:
    print("✓ Consensus sequence is valid (no stops, frameshifts)")
else:
    print("✗ Validation issues found:", validation_result.issues)
```

**Output: Three Construct Designs**
```
construct_A_mosaic.fasta      (61 aa, recombinant protein)
construct_B_chimeric_vip.fasta (120 aa, VLP-displayable)
construct_C_consensus.fasta    (420 aa, full ectodomain)
```

---

## PHASE 4: VLP PRESENTATION MODELING (Weeks 5–7)

### 4.1 Structure Prediction & Presentation

**Objective**: Model how epitopes will be displayed on VLP surface

```python
from biomate.structural import ChaiMultimer, BoltzMultimer

# For each construct, predict 3D structure
constructs = {
    "A_mosaic": construct_A_sequence,
    "B_chimeric": construct_B_sequence,
    "C_consensus": construct_C_sequence
}

for name, sequence in constructs.items():
    # Use Chai-1 for rapid prediction
    predictor = ChaiMultimer(
        model="chai1",
        multimer_state=4  # Predict tetramer (mimics VLP lattice)
    )
    
    structure = predictor.predict(
        sequences=[sequence, sequence, sequence, sequence],
        num_recycles=3
    )
    
    # Extract pLDDT (confidence per residue)
    plddt = structure.plddt
    
    # Identify epitope regions in predicted structure
    epitope_indices = [i for i, res in enumerate(sequence) 
                      if res in "FKTG"]  # Example epitope residues
    epitope_confidence = [plddt[i] for i in epitope_indices]
    
    print(f"\n{name}:")
    print(f"  Overall pLDDT: {plddt.mean():.1f}")
    print(f"  Epitope pLDDT: {np.mean(epitope_confidence):.1f}")
    print(f"  Predicted stability: {'✓ Stable' if plddt.mean() > 75 else '✗ Unstable'}")
    
    # Save predicted structure
    structure.to_pdb(f"construct_{name}_predicted.pdb")
```

**Output**: 
```
construct_A_mosaic_predicted.pdb
construct_B_chimeric_predicted.pdb
construct_C_consensus_predicted.pdb
```

---

### 4.2 Epitope Accessibility Analysis

**Objective**: Calculate which epitopes are "facing out" on VLP surface

```python
from biomate.structural import SurfaceAccessibility

for construct_name in constructs.keys():
    pdb_file = f"construct_{construct_name}_predicted.pdb"
    
    analyzer = SurfaceAccessibility(
        pdb_file=pdb_file
    )
    
    # Calculate RASA (Relative Accessible Surface Area) for each residue
    rasa_scores = analyzer.calculate_rasa()
    
    # Epitope accessibility = average RASA of epitope residues
    epitope_rasa = np.mean([rasa_scores[i] for i in epitope_indices])
    
    # Plot surface color-coded by epitope
    analyzer.plot_surface(
        color_by="epitope_residues",
        output=f"construct_{construct_name}_surface.png"
    )
    
    print(f"{construct_name}: Epitope accessibility = {epitope_rasa:.2f} RASA")
    if epitope_rasa > 0.7:
        print("  ✓ Epitope well-exposed")
    else:
        print("  ⚠ Epitope partially buried")
```

---

## PHASE 5: PROTEIN EXPRESSION & VALIDATION (Weeks 8–14)

### 5.1 Expression System Selection

**For each construct, select best expression system**:

```python
from biomate.expression import ExpressionOptimizer

expression_plans = {}

for construct_name, sequence in constructs.items():
    optimizer = ExpressionOptimizer(
        sequence=sequence,
        criteria=["yield", "folding", "post_translational_modifications"]
    )
    
    recommendations = optimizer.recommend_system()
    
    # Typical outcomes:
    # A_mosaic (61 aa): Bacterial (E. coli) or yeast
    # B_chimeric (120 aa): Mammalian (HEK293)
    # C_consensus (420 aa): Mammalian (HEK293) or insect (Sf9)
    
    expression_plans[construct_name] = {
        "system": recommendations['primary_system'],
        "yield_estimate": recommendations['predicted_yield'],
        "timeline": recommendations['production_timeline'],
        "cost_estimate": recommendations['cost_kg']
    }

print("Expression Plans:")
for construct, plan in expression_plans.items():
    print(f"\n{construct}:")
    print(f"  System: {plan['system']}")
    print(f"  Estimated yield: {plan['yield_estimate']} mg/L")
    print(f"  Timeline: {plan['timeline']} weeks")
```

**CRO Order**:
```
TO: [Select CRO: Genscript, Sino Biologics, or academic collaborator]
────────────────────────────────────────────────────────────────

Construct A (Mosaic):
  Expression system: Mammalian HEK293
  Quantity: 100 mg (purified, >95% purity)
  Post-translational modifications: None required
  Delivery timeline: 4 weeks
  Cost: $5–8K

Construct B (Chimeric):
  Expression system: Mammalian HEK293
  Quantity: 100 mg
  Folding validation: Required
  Delivery timeline: 5 weeks
  Cost: $6–10K

Construct C (Consensus):
  Expression system: Insect (Sf9)
  Quantity: 100 mg
  Refolding required: Yes (oxidation, 16h)
  Delivery timeline: 6 weeks
  Cost: $8–12K

TOTAL PROTEIN EXPRESSION: $19–30K
```

---

### 5.2 Protein Characterization

**Upon CRO delivery (Weeks 9–12)**:

```python
# Characterization protocols:

# [Test 1] SDS-PAGE + mass spec
# → Verify molecular weight matches prediction
# → Monomer vs. aggregates?

# [Test 2] Dynamic Light Scattering (DLS)
# → Particle size distribution
# → Polydispersity index (target: <0.3, monodisperse)

# [Test 3] Size Exclusion Chromatography (SEC)
# → Hydrodynamic radius
# → Oligomeric state

# [Test 4] Thermal Stability (DSF)
# → Melting temperature (Tm)
# → Protein folding stability
# → Target: Tm > 50°C for thermal stability

# [Test 5] Circular Dichroism (CD)
# → Secondary structure confirmation
# → Alpha-helix / beta-sheet content

print("Protein QC Summary:")
print("✓ Monomer MW matches prediction")
print("✓ Monodisperse (PDI < 0.3)")
print("✓ Tm > 50°C")
print("→ Proteins ready for immunization")
```

---

## PHASE 6: IMMUNOGENICITY VALIDATION (Weeks 9–18, Parallel)

### 6.1 Mouse Immunization Design

**Experimental Setup**:

```python
from biomate.immunology import MouseImmunizationProtocol

protocol = MouseImmunizationProtocol(
    animal_model="C57BL/6 mice",
    age="6–8 weeks",
    sex="female",
    n_per_group=5,
    replicates=2  # 10 mice per group
)

# Define groups
groups = {
    "Group 1": {"construct": "A_mosaic", "dose": 10, "adjuvant": "Alum"},
    "Group 2": {"construct": "B_chimeric", "dose": 10, "adjuvant": "Alum"},
    "Group 3": {"construct": "C_consensus", "dose": 10, "adjuvant": "Alum"},
    "Group 4": {"construct": "ANDV_wt_GP", "dose": 10, "adjuvant": "Alum"},  # Control
    "Group 5": {"antigen": None, "adjuvant": "Alum"}  # Negative control
}

# Immunization schedule
schedule = protocol.create_schedule(
    primary_dose_week=0,
    boost_dose_week=2,
    final_boost_week=4,
    final_bleed_week=6
)

print("Immunization Timeline:")
for timepoint, action in schedule.items():
    print(f"Week {timepoint}: {action}")

# Output: Institutional protocol document
protocol.to_iacuc_form("mouse_immunization_protocol.pdf")
```

**Timeline**: 8 weeks (Weeks 9–16)

---

### 6.2 Humoral Immunity Assays (Weeks 11–18)

#### **[Assay 1] Antibody Titer (ELISA)**

```
Protocol:
  Measure: IgG, IgG1, IgG2a antibodies
  Antigen: Coating protein (immunogen + control ANDV/SNV/PUUV GPs)
  Readout: Optical density (OD450)
  Timeline: 2 weeks post-final boost
  
Expected Output:
  Construct A: High titer vs. ANDV + SNV + PUUV (broad)
  Construct B: High titer vs. ANDV + SNV (cross-reactive)
  Construct C: High titer vs. all species (consensus coverage)
```

**Data Collection**:
```csv
group, week, igg_titer_andv, igg_titer_snv, igg_titer_puuv, 
andv_igg1_ratio, andv_igg2a_ratio

Group_A, 6, 64000, 32000, 8000, 0.8, 0.2
Group_B, 6, 128000, 64000, 2000, 0.75, 0.25
...
```

---

#### **[Assay 2] Neutralization Breadth (Pseudotype)**

```
Protocol:
  Virus: Lentiviral pseudotypes bearing:
    • ANDV GP (self target)
    • SNV GP (cross-reactivity test)
    • PUUV GP (cross-reactivity test)
  
  Cells: HEK293 or Huh7
  Readout: Luciferase activity
  EC50 calculation: Dose-response fitting
  
Timeline: 3 weeks
Cost per serum: $1,500–2,000

Expected Output:
  Construct A (Mosaic): 
    EC50_ANDV = 1:200, EC50_SNV = 1:100, EC50_PUUV = 1:50
    (Breadth score: 3/3 species neutralized)
  
  Construct B (Chimeric):
    EC50_ANDV = 1:400, EC50_SNV = 1:200, EC50_PUUV = <1:20
    (Breadth score: 2/3 species neutralized)
  
  Construct C (Consensus):
    EC50_ANDV = 1:100, EC50_SNV = 1:50, EC50_PUUV = 1:100
    (Breadth score: 3/3 species neutralized)
```

---

### 6.3 Cellular Immunity Assays (Weeks 12–18)

#### **[Assay 3] CD8+ T-Cell Response (IFN-γ ELISPOT)**

```
Protocol:
  Stimulation: Splenocytes + predicted CD8 epitope peptides
  Readout: IFN-γ-secreting cells (spot-forming units, SFU)
  
Timeline: 2 weeks
Cost: $800–1,200 per group

Expected Output:
  Responder frequency: 100–1,000 SFU/million splenocytes
  Epitope specificity: Response to predicted MHC-bound peptides
```

#### **[Assay 4] Flow Cytometry (CD8+ T-Cell Phenotyping)**

```
Protocol:
  Markers: CD3, CD8, CD44, CD62L, IFN-γ, TNF-α
  Cells: Splenocytes ± epitope peptide stimulation
  
Timeline: 2 weeks
Cost: $600–1,000 per group

Expected Output:
  CD44+ CD62L− = activated memory T cells (desired)
  IFN-γ+ TNF-α+ = polyfunctional CD8+ T cells (desired)
  Frequency: 1–5% of CD8+ T cells
```

---

## PHASE 7: IMMUNOLOGY DATA INTEGRATION (Weeks 19–20)

### 7.1 Prediction vs. Experimental Correlation

```python
import pandas as pd
from scipy.stats import pearsonr

# Load data
predictions = pd.read_csv("cd8_epitopes_top10.csv")
experimental = pd.read_csv("mouse_elispot_results.csv")

# Compare predicted epitope rankings to measured responses
correlation = pearsonr(
    predictions['cd8_epitope_score'],
    experimental['sfu_per_million']
)

print(f"Predicted CD8 score vs. Measured ELISPOT response:")
print(f"r = {correlation.statistic:.3f}, p = {correlation.pvalue:.2e}")

# If r > 0.7: Predictions are excellent
# If r > 0.5: Predictions are good
# If r < 0.5: Need to refine prediction models

# Construct ranking by breadth
construct_breadth = experimental.groupby('construct').agg({
    'species_neutralized': 'first',
    'neutralization_breadth_score': 'first',
    'cd8_magnitude': 'mean',
    'cd8_polyfunctionality': 'mean'
}).sort_values('neutralization_breadth_score', ascending=False)

print("\nConstruct Ranking by Immunogenicity:")
print(construct_breadth)

# Expected winner: Construct C (Consensus) or Construct A (Mosaic)
```

---

## PHASE 8: PUBLICATION & RELEASE (Weeks 19–20)

### 8.1 Manuscript Preparation

**Title**: "Rational Immunogen Design for Broad-Spectrum Hantavirus Protection: Structure-Based Epitope Discovery and Preclinical Validation"

**Figures**:

```
Figure 1: Epitope Discovery & Cross-Species Analysis
  Panel A: Guo's ANDV GP structure + ADI-65534 complex
  Panel B: Linear epitope sequence + conserved residues
  Panel C: Multi-species alignment (ANDV/SNV/PUUV)
  Panel D: Conservation heatmap

Figure 2: Immunogen Design
  Panel A: Schematic of Constructs A, B, C (ribbon diagrams)
  Panel B: Sequence comparison (alignment view)
  Panel C: Predicted 3D structures (Chai-1 output)
  Panel D: Surface accessibility (RASA scores)

Figure 3: CD8+ T-Cell Epitope Prediction
  Panel A: MHC binding prediction heatmap
  Panel B: Top epitopes ranked by CD8 score
  Panel C: Population coverage (% global population)
  Panel D: Proteasomal cleavage + TAP transport

Figure 4: Mouse Immunogenicity
  Panel A: Antibody titers (ELISA, by group)
  Panel B: Neutralization curves (pseudotype, 3 species)
  Panel C: Neutralization breadth (bar chart)
  Panel D: CD8+ T-cell response (ELISPOT magnitude)

Figure 5: Cross-Validation & Mechanistic Insights
  Panel A: Predicted vs. measured EC50 (scatter plot)
  Panel B: Breadth vs. CD8 magnitude (correlation)
  Panel C: Consensus vs. chimeric (SAR analysis)
  Panel D: Proposed mechanism of broad neutralization
```

**Tables**:

```
Table 1: Immunogen Constructs (Design Specifications)
  Columns: Construct, Epitope Source, Length (aa), MW (kDa), 
           Expression System, Predicted Tm (°C), Folding Confidence

Table 2: Top CD8+ T-Cell Epitopes
  Columns: Peptide, HLA Allele, Kd (nM), CD8 Score, 
           Cross-Reactivity (ANDV/SNV/PUUV)

Table 3: Mouse Immunization Results
  Columns: Group, Construct, ANDV EC50, SNV EC50, PUUV EC50, 
           Breadth Score, CD8 Magnitude, IFN-γ+ Frequency
```

---

### 8.2 GitHub Release

```
biomate-andv-vaccine-plan-a/
│
├── README.md
│   └─ Project overview, methods, results summary
│
├── data/
│   ├─ epitope_predictions.csv
│   ├─ mhc_binding_predictions.csv
│   ├─ mouse_immunogenicity_raw.csv
│   ├─ neutralization_titers.csv
│   └─ cd8_elispot_results.csv
│
├── constructs/
│   ├─ construct_A_mosaic.fasta
│   ├─ construct_B_chimeric.fasta
│   ├─ construct_C_consensus.fasta
│   ├─ construct_A_predicted_structure.pdb
│   ├─ construct_B_predicted_structure.pdb
│   └─ construct_C_predicted_structure.pdb
│
├── code/
│   ├─ 01_epitope_discovery.py
│   ├─ 02_cross_species_alignment.py
│   ├─ 03_mhc_prediction.py
│   ├─ 04_construct_design.py
│   ├─ 05_structure_prediction.py
│   └─ 06_immunogenicity_analysis.py
│
├── figures/
│   ├─ epitope_conservation_heatmap.png
│   ├─ construct_designs.png
│   ├─ neutralization_curves.png
│   ├─ cd8_response.png
│   └─ breadth_analysis.png
│
├── supplementary/
│   ├─ multi_sequence_alignment.aln
│   ├─ docking_poses_epitope_antibody.pdb
│   └─ population_coverage_analysis.xlsx
│
└── LICENSE (CC-BY 4.0)
```

---

## PLAN A: SUCCESS METRICS

### ✅ Vaccine Design Track (Plan A) Success = ALL of:
- ✅ 3 novel immunogen constructs designed & validated
- ✅ ≥ 8 predicted CD8+ T-cell epitopes identified
- ✅ Mouse sera neutralize ≥ 2/3 hantavirus species (ANDV + SNV, or ANDV + PUUV)
- ✅ CD8+ T-cell response detected (IFN-γ+ > 100 SFU/million)
- ✅ Predicted MHC binding correlated with experimental immunogenicity (r > 0.6)
- ✅ Pre-print published (bioRxiv)
- ✅ GitHub repository with open-source vaccine designs
- ✅ One academic collaboration offer for in vivo efficacy

---

## BUDGET BREAKDOWN (Plan A)

| Item | Cost | Timeline |
|------|------|----------|
| **Protein Expression (3 constructs)** | $19–30K | Weeks 8–12 |
| **Protein Characterization** | $2–3K | Weeks 9–12 |
| **Mouse Facility & Vivarium** | $5–8K | Weeks 9–16 |
| **Mouse Immunization + Bleeds** | $3–5K | Weeks 9–16 |
| **ELISA Titering** | $2–3K | Week 17 |
| **Pseudotype Neutralization** | $9–12K | Weeks 12–18 |
| **ELISPOT + Flow Cytometry** | $3–5K | Weeks 12–18 |
| **Manuscript + Figures** | $3–5K | Weeks 19–20 |
| **TOTAL** | **$46–71K** | **4 months** |

---

**Document Version**: 1.0 (April 2026)  
**Approach**: Protein/VLP-based immunogens + CD8+ T-cell optimization  
**Status**: Ready for Implementation via Claude Code

**BioMate note**: Epitope/MHC blocks are **semantic**. Align with **`docs/20260417_DRUG_DEVELOPMENT_COVERAGE_ANALYSIS.md`** (nf-core/epitopeprediction / workflow **id=12700** reference there) and standard alignment tools; see `BIOMATE_CAPABILITY_GAP.md`.
