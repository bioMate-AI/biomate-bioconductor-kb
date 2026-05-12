# ANDV Broad-Spectrum Vaccine Design: PLAN B (mRNA-LNP)
## Implementation Plan — Ready for Claude Code

**Project**: mRNA-LNP Vaccine Platform for Pandemic-Ready Hantavirus Protection  
**Timeline**: 4 months (Weeks 1–20, parallel with Inhibitor Track)  
**Budget**: $50–68K  
**Approach**: mRNA sequence design + LNP formulation optimization + stability validation  
**Owner**: BioMate Synthetic Biology & Immunology Team  
**Deliverables**:
- 3 optimized mRNA-LNP candidates (ANDV/SNV/PUUV epitope variants)
- Proof-of-concept neutralizing antibodies in mice
- Manufacturing stability data (4°C, RT, −20°C, −80°C)
- GMP-grade mRNA synthesis pathway
- Pre-print + open-source vaccine platform

**Key Differentiator**: Pandemic-ready vaccine deployable in 6 months post-pathogen identification

**BioMate in silico routing (this repository)**: Pseudocode blocks below are **intent**, not `import biomate.*` APIs. Map phases to indexed Nextflow workflows and `POST /api/nextflow/execute` (see `BIOMATE_CAPABILITY_GAP.md`, `docs/20260419_WORKFLOW_REGISTRY.csv`): **codon / expression** → `nextflow_nfcore/subworkflows/synthetic_biology/optimize_codons_for_heterologous_expression/main.nf` (id **10813**); **RNA secondary structure** → `nextflow_nfcore/subworkflows/microbiology/predict_rna_secondary_structure/main.nf` (id **10721**, ViennaRNA); **mRNA construct QC (CAI, RNAfold, ORF)** → `nextflow_nfcore/subworkflows/drug_discovery/p0_mrna_validation/main.nf` (id **12819**); **LNP formulation sweep** → `nextflow_nfcore/subworkflows/drug_discovery/lnp_formulation_optimization/main.nf` (id **12869**); **NP PK / biodistribution** → `nextflow_nfcore/subworkflows/pharmacology/nanoparticle_pk_biodistribution/main.nf` (id **12867**). Epitope / MHC steps overlap Plan A: **nf-core/epitopeprediction** (id **12700**). Run on **AWS Batch** when inputs or `outdir` use `s3://` (BioMate default).

**Plan B phase → BioMate Nextflow paths (ids above only; Plan B codon/LNP smoke helper omits epitope / Plan A overlap):**

| Plan B (this document) | Indexed workflow (same `nextflow_path` strings as routing paragraph) |
|------------------------|------------------------------------------------------------------------|
| Phase 1 — epitope / immunogen (Weeks 1–6) | Plan A only; not duplicated in Plan B in silico helpers here. |
| Phase 2.1 — codon optimization | **10813** — `nextflow_nfcore/subworkflows/synthetic_biology/optimize_codons_for_heterologous_expression/main.nf` |
| Phase 2.2 — 5′/3′ UTR design | No separate id among **10813 / 10721 / 12819 / 12869 / 12867**; full-construct QC overlaps **12819** where UTRs are embedded in the validation pipeline. |
| Phase 2.3 — structural stability (RNA) | **10721** — `nextflow_nfcore/subworkflows/microbiology/predict_rna_secondary_structure/main.nf`; mRNA-level CAI / ORF / MFE checks overlap **12819**. |
| Phase 2 — integrated mRNA validation (optional single check) | **12819** — `nextflow_nfcore/subworkflows/drug_discovery/p0_mrna_validation/main.nf` |
| Phase 3 — LNP formulation (ionizable lipid, sweep, predicted EE / size) | **12869** — `nextflow_nfcore/subworkflows/drug_discovery/lnp_formulation_optimization/main.nf` |
| Phase 3.2 — particle / encapsulation predictions | Same as Phase 3 (**12869**); cold-chain and long-horizon stability remain empirical (CRO / lab). |
| Phase 4–5 — GMP synthesis, encapsulation, real-time stability | Wet lab / CRO; outside the five indexed subworkflows. |
| Phase 6–7 — immunogenicity, comparative integration | Wet lab; **12867** — `nextflow_nfcore/subworkflows/pharmacology/nanoparticle_pk_biodistribution/main.nf` for NP PK / biodistribution modeling aligned with non-clinical / translation narratives. |
| Phase 8 — publication / release | N/A for execution routing. |

Copy/paste smoke examples (demo parameters only): `research/anti-virus/scripts/run_plan_b_codon_lnp_smoke.sh`.

---

## PHASE 1: EPITOPE DISCOVERY & IMMUNOGEN DESIGN (Weeks 1–6)

*Identical to Plan A (Weeks 1–6)*

**Reference**: See PLAN A sections 1.1–3.3 for:
- Epitope extraction from Guo's structures
- Cross-species conservation analysis
- CD8+ T-cell epitope prediction
- MHC binding analysis
- Immunogen construct design (Mosaic, Chimeric, Consensus)

**Output**: Three epitope-optimized sequences ready for mRNA encoding

---

## PHASE 2: mRNA SEQUENCE DESIGN & OPTIMIZATION (Weeks 2–5)

### 2.1 Codon Optimization

**Objective**: Maximize mRNA translation efficiency in human cells

```python
from biomate.synthetic_biology import CodonOptimizer, TranslationPredictor

# Input: Three epitope sequences from Phase 1
constructs = {
    "A_mosaic": "FKTFATGTVLLAVGGSTGTVLLSVGSLLAVGLCIL...",
    "B_chimeric": "MKTILLIVFLVISPPQ...TGTVLLSVGL...LLAVGLCIL...",
    "C_consensus": "MKTILLIVFLVISPPQ...LLAVGLCIL..."
}

optimizer = CodonOptimizer(
    target_organism="Homo_sapiens",
    optimization_level="high"  # Maximum translation
)

optimized_sequences = {}

for construct_name, protein_seq in constructs.items():
    # Optimize codons for human expression
    optimized_dna = optimizer.optimize(
        protein_sequence=protein_seq,
        gc_content_target=50,  # Optimal for mRNA stability
        cai_threshold=0.8,     # Codon Adaptation Index
        avoid_regulatory_sequences=True
    )
    
    # Calculate translation efficiency
    translator = TranslationPredictor(model="ribosomeprofiling")
    translation_score = translator.predict_efficiency(optimized_dna)
    
    # Verify no problematic sequences
    validator = mRNAValidator()
    issues = validator.check_secondary_structure(optimized_dna)
    issues += validator.check_homopolymer_runs(optimized_dna)
    issues += validator.check_cis_acting_elements(optimized_dna)
    
    optimized_sequences[construct_name] = {
        "dna_sequence": optimized_dna,
        "protein_sequence": protein_seq,
        "codon_optimized": True,
        "translation_score": translation_score,
        "gc_content": compute_gc(optimized_dna),
        "validation_issues": issues,
        "original_vs_optimized_difference": compute_diff_score(protein_seq, optimized_dna)
    }
    
    print(f"\n{construct_name}:")
    print(f"  Translation efficiency score: {translation_score:.3f}")
    print(f"  GC content: {optimized_sequences[construct_name]['gc_content']:.1%}")
    print(f"  Validation issues: {len(issues)}")
    if issues:
        print(f"    Issues: {issues}")

# Save codon-optimized sequences
for name, data in optimized_sequences.items():
    with open(f"{name}_codon_optimized.fasta", "w") as f:
        f.write(f">{name}_optimized\n")
        f.write(data['dna_sequence'] + "\n")
```

**Output**:
```
construct_A_codon_optimized.fasta
construct_B_codon_optimized.fasta
construct_C_codon_optimized.fasta

codon_optimization_report.json
─────────────────────────────────────────────────
{
  "construct_A": {
    "translation_score": 0.92,
    "gc_content": 0.502,
    "validation_passed": true,
    "optimization_improvement": "15% higher predicted expression"
  },
  ...
}
```

---

### 2.2 5' & 3' UTR Design

**Objective**: Maximize mRNA stability, translation, and avoid innate immunity

```python
from biomate.synthetic_biology import UTRDesigner, InnateImmunityChecker

# Select UTRs
utr_designer = UTRDesigner(target_cells="dendritic_cells")

# 5' UTR: Kozak consensus + secondary structure optimization
five_prime_utr = utr_designer.design_five_prime(
    strategy="kozhikoff_optimized",  # Best for mRNA vaccines
    length=100,
    secondary_structure_target="minimal"  # Low secondary structure = better translation
)

# 3' UTR: Polyadenylation + stability elements
three_prime_utr = utr_designer.design_three_prime(
    length=200,
    include_bgh_poly_a=True,  # Bovine growth hormone polyA (strong)
    include_stability_elements=True  # AU-rich elements for adjuvant effect
)

# Check for innate immune triggers (TLR3, TLR8, dsRNA patterns)
immune_checker = InnateImmunityChecker()

for construct_name in optimized_sequences.keys():
    coding_seq = optimized_sequences[construct_name]['dna_sequence']
    
    # Assemble full mRNA: 5' cap - 5'UTR - CDS - 3'UTR - polyA
    full_mrna = (
        "GGCCGCGACCCGCCCGCGACGC" +  # 5' cap mimic
        five_prime_utr +
        coding_seq +
        three_prime_utr +
        "A" * 120  # Poly(A) tail
    )
    
    # Check for immunogenicity
    immune_signals = immune_checker.predict_immunogenicity(full_mrna)
    
    # Try to reduce TLR activation (optional: use pseudouridine substitution)
    if immune_signals['tlr_risk'] == "high":
        # Option 1: Replace U with pseudouridine (Ψ)
        pseudouridine_version = full_mrna.replace("U", "Ψ")
        immune_signals_psi = immune_checker.predict_immunogenicity(pseudouridine_version)
        
        if immune_signals_psi['tlr_risk'] == "low":
            full_mrna = pseudouridine_version
            print(f"✓ Pseudouridine modification reduced TLR risk for {construct_name}")
    
    # Save design
    with open(f"{construct_name}_full_mrna_design.fasta", "w") as f:
        f.write(f">{construct_name}_full_mRNA\n")
        f.write(full_mrna + "\n")
    
    print(f"\n{construct_name} mRNA Design:")
    print(f"  Total length: {len(full_mrna)} nt")
    print(f"  5' UTR length: {len(five_prime_utr)}")
    print(f"  CDS length: {len(coding_seq)}")
    print(f"  3' UTR length: {len(three_prime_utr)}")
    print(f"  Poly(A) tail: 120 nt")
    print(f"  TLR risk: {immune_signals['tlr_risk']}")
    print(f"  Predicted translation level: {immune_signals['translation_score']:.2f}")
```

**Output**: Full mRNA sequences with optimized UTRs

---

### 2.3 Structural Stability Analysis

**Objective**: Predict mRNA secondary structure that could destabilize or enhance delivery

```python
from biomate.synthetic_biology import SecondaryStructurePredictor, MFECalculator

for construct_name, data in optimized_sequences.items():
    mrna_file = f"{construct_name}_full_mrna_design.fasta"
    
    # Predict secondary structure
    structure_predictor = SecondaryStructurePredictor(
        algorithm="RNAfold",
        include_pseudoknots=False
    )
    
    structure = structure_predictor.predict(mrna_file)
    
    # Calculate minimum free energy (MFE)
    mfe_calculator = MFECalculator()
    mfe = mfe_calculator.calculate(mrna_file)
    
    # Assess if structure is problematic
    # Highly stable secondary structure = slow translation
    # Very unstable = degradation risk
    
    stability_score = classify_stability(mfe)
    
    print(f"{construct_name}:")
    print(f"  MFE: {mfe:.1f} kcal/mol")
    print(f"  Stability classification: {stability_score}")
    print(f"  Recommendation: {'Add destabilizing elements' if mfe < -1000 else 'Acceptable'}")
    
    # Visualize structure (for top construct)
    if construct_name == "A_mosaic":
        structure_predictor.visualize(
            output="construct_A_secondary_structure.png"
        )
```

---

## PHASE 3: LNP FORMULATION DESIGN (Weeks 3–6)

### 3.1 Ionizable Lipid Selection & pKa Optimization

**Objective**: Design optimal ionizable lipid formulation for endosomal escape

```python
from biomate.biochemistry import LipidLibrary, LNPSimulator

# Available ionizable lipids
lipid_library = LipidLibrary()

ionizable_lipids = [
    "SM-102",           # Moderna's approved lipid
    "Proprietary_pKa7.5",  # Custom pKa
    "Proprietary_pKa8.0",
    "Proprietary_pKa8.5"
]

# For each lipid, model endosomal escape
simulator = LNPSimulator()

formulation_designs = []

for lipid in ionizable_lipids:
    # Test multiple formulations with this lipid
    formulations = generate_formulation_matrix(
        ionizable_lipid=lipid,
        peg_lipid_ratios=[0.5, 1.0, 2.0, 5.0],  # %
        cholesterol_ratios=[30, 40, 50],  # %
        dspc_ratios=[5, 10, 15]  # %
    )
    
    for formulation in formulations:
        # Predict performance
        predictions = simulator.predict(
            formulation=formulation,
            mrna_size=2500,  # nucleotides
            target_cells="dendritic_cells",
            readout_metrics=[
                "encapsulation_efficiency",  # % mRNA encapsulated
                "particle_size",             # nm
                "zeta_potential",            # mV
                "cellular_uptake_rate",      # % cells transfected
                "endosomal_escape_efficiency",  # % cytoplasmic delivery
                "transfection_efficiency"    # % protein expression
            ]
        )
        
        # Score formulations
        score = (
            0.25 * normalize(predictions['encapsulation_efficiency']) +
            0.25 * normalize(predictions['cellular_uptake_rate']) +
            0.25 * normalize(predictions['endosomal_escape_efficiency']) +
            0.15 * normalize(predictions['transfection_efficiency']) +
            0.10 * (1.0 - normalize(predictions['particle_size']))  # Smaller is better
        )
        
        formulation_designs.append({
            "ionizable_lipid": lipid,
            "peg_ratio": formulation['peg_percent'],
            "cholesterol_ratio": formulation['chol_percent'],
            "dspc_ratio": formulation['dspc_percent'],
            "predicted_ee": predictions['encapsulation_efficiency'],
            "predicted_uptake": predictions['cellular_uptake_rate'],
            "predicted_escape": predictions['endosomal_escape_efficiency'],
            "predicted_expression": predictions['transfection_efficiency'],
            "composite_score": score
        })

# Select top 3 formulations
top_formulations = sorted(
    formulation_designs,
    key=lambda x: x['composite_score'],
    reverse=True
)[:3]

print("Top 3 LNP Formulations:")
for rank, form in enumerate(top_formulations, 1):
    print(f"\n{rank}. {form['ionizable_lipid']}")
    print(f"   PEG ratio: {form['peg_ratio']:.1f}%")
    print(f"   Cholesterol: {form['cholesterol_ratio']:.0f}%")
    print(f"   DSPC: {form['dspc_ratio']:.0f}%")
    print(f"   Predicted EE: {form['predicted_ee']:.1%}")
    print(f"   Predicted transfection: {form['predicted_expression']:.1%}")

# Save LNP design specifications
import json
with open("top_3_lnp_formulations.json", "w") as f:
    json.dump([dict(f) for f in top_formulations], f, indent=2)
```

**Output**:
```
top_3_lnp_formulations.json
─────────────────────────────────────────────────
[
  {
    "ionizable_lipid": "SM-102",
    "peg_ratio": 1.5,
    "cholesterol_ratio": 40,
    "dspc_ratio": 10,
    "predicted_ee": 0.92,
    "predicted_transfection": 0.85,
    "composite_score": 0.88
  },
  ...
]
```

---

### 3.2 Particle Size & Stability Prediction

**Objective**: Predict LNP physical properties relevant to manufacturing

```python
from biomate.biochemistry import LNPCharacterizer

characterizer = LNPCharacterizer()

for construct_name in optimized_sequences.keys():
    for formulation in top_formulations:
        # Predict particle properties
        properties = characterizer.predict_properties(
            mrna_length=len(optimized_sequences[construct_name]['dna_sequence']),
            formulation=formulation,
            temperature=25,  # °C
            ph=7.4,          # physiological pH
            ionic_strength=150  # mM (PBS)
        )
        
        # Stability timeline
        stability = characterizer.predict_stability(
            properties=properties,
            storage_conditions=[
                {"temp": 4, "humidity": None, "description": "Refrigerated"},
                {"temp": 25, "humidity": 40, "description": "Room temperature"},
                {"temp": -20, "humidity": None, "description": "Frozen"},
                {"temp": -80, "humidity": None, "description": "Ultra-frozen"}
            ],
            timepoints=[1, 4, 12, 24, 52]  # weeks
        )
        
        print(f"\n{construct_name} + {formulation['ionizable_lipid']}:")
        print(f"  Particle size: {properties['diameter_nm']:.0f} ± {properties['pdI_nm']:.0f} nm")
        print(f"  Zeta potential: {properties['zeta_potential_mv']:.1f} mV")
        print(f"  Encapsulation efficiency: {properties['ee_percent']:.1f}%")
        print(f"\n  Shelf life:")
        for condition, stability_data in stability.items():
            print(f"    {condition}:")
            for week, retention in stability_data.items():
                print(f"      Week {week}: {retention:.0%} potency retention")
```

**Expected Output**:
```
Predicted LNP Properties
─────────────────────────────────────────────────
Particle size: 100–120 nm (LNP optimal range)
Zeta potential: −20 to −30 mV (stable, not aggregating)
EE: 85–95% (excellent mRNA loading)

Shelf Life Predictions:
  4°C: 52 weeks (1 year at refrigerator)
  −20°C: 156 weeks (3 years at standard freezer)
  −80°C: >1 year (stable long-term storage)
```

---

## PHASE 4: mRNA-LNP MANUFACTURING & PRODUCTION (Weeks 7–12)

### 4.1 GMP-Grade mRNA Synthesis

**CRO Order: mRNA Synthesis**

```
TO: [GMP-certified mRNA manufacturer: Ology, Synthego, or Aldevron]
─────────────────────────────────────────────────────────────────────

For each of 3 constructs:

Specification:
  • mRNA sequence: [Full 2,500 nt sequences with optimized UTRs]
  • Quantity: 500 mg (GMP-grade) for mouse studies
  • Purity: >98% (verified by HPLC)
  • Endotoxin: <1 EU/mg
  • dsRNA content: <0.2% (avoid TLR3 activation)
  • Capping: 7-methylguanosine cap (m7G)
  • Poly(A): 120 A residues
  • Format: Lyophilized or liquid (−20°C storage)

Quality Specifications:
  ✓ Identity: Confirmed by mass spectrometry
  ✓ Purity: HPLC profile
  ✓ Endotoxin: LAL test
  ✓ Sterility: Gram stain + culture
  ✓ Stability: Real-time at 4°C for 12 weeks

Timeline: 4–6 weeks
Cost per construct: $8–10K
Total: $24–30K (3 constructs)
```

---

### 4.2 LNP Encapsulation & Formulation

**CRO Order: LNP Manufacture**

```
TO: [LNP formulation CRO: Evonik, Acuitas, or academic partner]
──────────────────────────────────────────────────────────────────

For each of 3 mRNA × 3 formulations = 9 LNP batches

Specification:
  • mRNA input: 500 mg (GMP-quality)
  • Formulation: [SM-102 or optimized lipid blend]
  • Lipid ratios: [As specified in top_3_lnp_formulations.json]
  • Manufacturing method: Microfluidic mixing (highest quality)
  • Batch size: 50 mL (sufficient for mouse studies + analytics)
  • Final concentration: 10 mg/mL total lipids
  • Encapsulation efficiency: ≥85%

Quality Control:
  ✓ Particle size (DLS): 100–150 nm
  ✓ Polydispersity index (PDI): <0.3
  ✓ Zeta potential: −20 to −30 mV
  ✓ Encapsulation efficiency: HPLC quantification
  ✓ Endotoxin: <1 EU/mL
  ✓ Sterility: Gram stain + culture
  ✓ Osmolality: 280–300 mOsm/kg

Stability Testing (Real-Time):
  • 4°C storage: Measure at weeks 1, 4, 8, 12, 24
  • −20°C storage: Measure at weeks 1, 12, 24, 52
  • Room temperature (25°C): Measure at days 1, 3, 7, 14
  • Readouts: Particle size, zeta potential, mRNA integrity, endotoxin

Delivery: Batches in sterile glass vials, temperature-controlled shipment

Timeline: 6–8 weeks
Cost per batch: $3–4K
Total (9 batches): $27–36K
```

**Timeline Integration**:
- Week 7: CRO order placed (mRNA synthesis)
- Week 11: mRNA delivered
- Week 12: LNP formulation begins
- Week 16: LNP delivery complete + stability initiation
- Week 24–52: Real-time stability data collection (continues post-campaign)

---

### 4.3 Regulatory-Grade Documentation

**Prepare for future IND submission**:

```
Regulatory Documentation Package:
├─ CMC (Chemistry, Manufacturing, Controls):
│  ├─ mRNA synthesis procedure (detailed description)
│  ├─ LNP manufacturing SOP (microfluidic protocol)
│  ├─ Analytical methods (purity, particle size, encapsulation)
│  ├─ Lot release specifications
│  └─ Stability protocol & real-time data
│
├─ Non-Clinical:
│  ├─ In vitro transfection (HEK293, dendritic cells)
│  ├─ Mouse immunogenicity (Study report)
│  ├─ Toxicology (if required)
│  └─ PK/PD modeling
│
└─ Clinical:
   ├─ Clinical trial design (Phase 1 proposal)
   ├─ Regulatory interaction summaries
   └─ Risk assessment
```

---

## PHASE 5: STABILITY TESTING & MANUFACTURING VALIDATION (Weeks 8–20)

### 5.1 Real-Time Stability (Accelerated + Real-Time)

**Storage Condition Testing**:

```python
from biomate.biochemistry import StabilityTester, RetentionAnalyzer

stability_tester = StabilityTester(
    lnp_batches=9,  # All formulations
    storage_conditions=[
        {"temp": 4, "humidity": "N/A", "label": "Refrigerated"},
        {"temp": 25, "humidity": 40, "label": "Room Temperature (ICH)"},
        {"temp": -20, "humidity": "N/A", "label": "Frozen"},
        {"temp": -80, "humidity": "N/A", "label": "Ultra-Frozen"}
    ]
)

# Sampling timeline
timepoints_weeks = [1, 2, 4, 8, 12, 24, 52]

results = {}

for condition in stability_tester.storage_conditions:
    potency_data = []
    
    for week in timepoints_weeks:
        # Measure at each timepoint
        measurements = stability_tester.measure(
            condition=condition,
            week=week,
            metrics=[
                "particle_size_nm",        # DLS
                "polydispersity_index",    # PDI
                "zeta_potential_mv",       # Zeta potential
                "encapsulation_efficiency", # qNMR or HPLC
                "mrna_integrity_percent",  # Capillary electrophoresis
                "endotoxin_eu_ml",         # LAL test
                "moisture_content_percent" # Karl Fischer
            ]
        )
        
        # Calculate potency retention
        # (relative to week 0 baseline)
        potency_retention = calculate_potency_retention(
            measurements,
            baseline_week0=results.get('baseline', {})
        )
        
        potency_data.append({
            "week": week,
            "potency_retention_percent": potency_retention,
            "measurements": measurements
        })
    
    results[condition['label']] = potency_data

# Analyze retention kinetics
retention_analyzer = RetentionAnalyzer()

for condition, data in results.items():
    # Fit degradation curve (exponential decay)
    t_90 = retention_analyzer.calculate_t90(
        timepoint_weeks=[d['week'] for d in data],
        retention_percent=[d['potency_retention_percent'] for d in data]
    )
    
    print(f"\n{condition}:")
    print(f"  Weeks for 90% retention (t90): {t_90:.1f} weeks")
    
    if t_90 >= 52:
        print(f"  ✓ Acceptable 1-year shelf life")
    elif t_90 >= 12:
        print(f"  ⚠ Acceptable 3-month shelf life")
    else:
        print(f"  ✗ Poor stability (reformulation needed)")

# Save stability data
import pandas as pd
stability_df = pd.DataFrame(results).T
stability_df.to_csv("lnp_stability_data.csv")
```

**Expected Output**:
```
LNP Stability Profile (Real-Time Data)
─────────────────────────────────────────────────────
Storage Condition    | t90 (weeks) | Shelf Life | Recommendation
4°C (Refrigerated)   | 52+         | 1 year ✓   | Standard cold chain
−20°C (Freezer)      | 156+        | 3 years ✓  | Long-term storage
−80°C (Ultra)        | >156        | Indefinite | Archival
25°C (Room Temp)     | 1–2 weeks   | <1 month   | Shipping only

Key Finding: SM-102 formulation achieves 12-month stability at 4°C,
enabling deployment with standard cold chain infrastructure (not −80°C).
```

---

### 5.2 Manufacturing Scale-Up Path

**Process Outline**:

```
Current Scale (mouse studies):  50 mL batches
↓
Phase 1 Clinical Scale:         500 mL – 1 L batches
↓
Phase 2 Clinical Scale:         5 L batches
↓
Phase 3 GMP Manufacturing:      20–50 L scale
↓
Commercial Scale:               Parallelizable reactors (2–5 L each)

Key Advantage: mRNA manufacturing is inherently scalable.
  • Same microfluidic equipment for 50 mL or 500 mL
  • Parallel synthesis (multiply number of reactors, not complexity)
  • Timeline: 6 months (target) from pathogen ID → human trial
```

---

## PHASE 6: IMMUNOGENICITY VALIDATION (Weeks 9–18, Parallel with Manufacturing)

*Similar to Plan A, with modifications for mRNA-LNP*

### 6.1 Mouse Immunization (mRNA-LNP)

**Experimental Design**:

```python
from biomate.immunology import MouseImmunizationProtocol

protocol = MouseImmunizationProtocol(
    animal_model="C57BL/6 mice",
    age="6–8 weeks",
    sex="female",
    n_per_group=5,
    replicates=2
)

# Define groups
groups = {
    "Group 1": {
        "vaccine": "mRNA-LNP_A_mosaic",
        "mrna_construct": "A_mosaic",
        "lnp_formulation": "SM-102_optimized",
        "dose": 10,  # µg mRNA
        "route": "intramuscular"  # IM injection
    },
    "Group 2": {
        "vaccine": "mRNA-LNP_B_chimeric",
        "mrna_construct": "B_chimeric",
        "lnp_formulation": "SM-102_optimized",
        "dose": 10,
        "route": "intramuscular"
    },
    "Group 3": {
        "vaccine": "mRNA-LNP_C_consensus",
        "mrna_construct": "C_consensus",
        "lnp_formulation": "SM-102_optimized",
        "dose": 10,
        "route": "intramuscular"
    },
    "Group 4": {
        "vaccine": "ANDV_wt_GP_mRNA-LNP",  # Wild-type control
        "mrna_construct": "ANDV_WT_GP",
        "lnp_formulation": "SM-102_optimized",
        "dose": 10,
        "route": "intramuscular"
    },
    "Group 5": {
        "vaccine": "PBS_saline",  # Negative control
        "dose": 0.1,  # mL saline
        "route": "intramuscular"
    }
}

# Immunization schedule: mRNA vaccines typically require fewer boosts
schedule = {
    "Week 0": "Prime (10 µg mRNA-LNP)",
    "Week 2": "Boost 1 (10 µg mRNA-LNP)",  # Second dose enhances breadth
    "Week 4": "Final bleed (terminal harvest)"
}

print("mRNA-LNP Mouse Immunization Protocol:")
for timepoint, action in schedule.items():
    print(f"  {timepoint}: {action}")

# Note: Shorter timeline than protein immunization (4 vs. 8 weeks)
print(f"\nTotal study duration: 4 weeks (vs. 8 weeks for protein/VLP)")
```

**Key Difference from Plan A**: 
- Fewer immunizations needed (2 vs. 3)
- Faster kinetics (peak response at week 4 vs. week 6)
- Potentially stronger CD8+ response (intrinsic immunogenicity of mRNA)

---

### 6.2 Immunogenicity Readouts (mRNA-LNP)

**[Assay 1] Antibody Titer (ELISA)**
```
Same as Plan A: IgG, IgG1, IgG2a against ANDV/SNV/PUUV GP

Expected enhancement with mRNA:
  • Higher IgG titers (mRNA is more immunogenic than protein)
  • Stronger Th1 response (higher IgG2a; cellular immunity)
```

**[Assay 2] Neutralization (Pseudotype)**
```
Same as Plan A: Pseudotype entry inhibition

Expected profile:
  • mRNA vaccines often generate broader responses
  • Cross-species neutralization likely stronger than protein VLP
```

**[Assay 3] CD8+ T-Cell Response (ELISPOT + Flow)**
```
Same as Plan A: IFN-γ ELISPOT + flow cytometry phenotyping

Expected advantage of mRNA:
  • Stronger CD8+ response (mRNA activates TLR3/TLR8)
  • Higher polyfunctionality (IFN-γ+ TNF-α+ IL-2+)
  • Faster response kinetics
```

**[Additional Assay 4] Innate Immune Response (mRNA-specific)**
```
Protocol:
  Measure: Serum cytokines at 24h post-vaccination (prime)
  Readout: IL-6, TNF-α, IFN-β, IL-12p40
  
Timeline: 1 week
Cost: $600–1,000

Expected: Brief innate activation (desired for adjuvanticity)
```

---

## PHASE 7: COMPARATIVE DATA INTEGRATION (Weeks 19–20)

### 7.1 Plan A vs. Plan B Comparison

**If both vaccines tested in parallel mice**:

```python
import pandas as pd
from scipy.stats import ttest_ind

# Load data from both approaches
plan_a_data = pd.read_csv("plan_a_mouse_results.csv")
plan_b_data = pd.read_csv("plan_b_mouse_results.csv")

# Metrics comparison
comparison_metrics = {
    "Antibody Titer": {
        "plan_a": plan_a_data['igg_titer_andv'].mean(),
        "plan_b": plan_b_data['igg_titer_andv'].mean()
    },
    "Neutralization Breadth": {
        "plan_a": (plan_a_data['andv_neutralized'] & 
                   plan_a_data['snv_neutralized']).sum() / len(plan_a_data),
        "plan_b": (plan_b_data['andv_neutralized'] & 
                   plan_b_data['snv_neutralized']).sum() / len(plan_b_data)
    },
    "CD8+ Magnitude (SFU/million)": {
        "plan_a": plan_a_data['elispot_sfu'].mean(),
        "plan_b": plan_b_data['elispot_sfu'].mean()
    },
    "Manufacturing Cost": {
        "plan_a": 46000,  # Budget
        "plan_b": 50000
    },
    "Shelf Life at 4°C": {
        "plan_a": "?",  # Requires empirical testing
        "plan_b": "52+ weeks"  # Predicted
    }
}

print("Plan A (Protein/VLP) vs. Plan B (mRNA-LNP) Comparison:")
print("=" * 70)

for metric, values in comparison_metrics.items():
    plan_a = values.get('plan_a', 'N/A')
    plan_b = values.get('plan_b', 'N/A')
    print(f"\n{metric}:")
    print(f"  Plan A (Protein): {plan_a}")
    print(f"  Plan B (mRNA-LNP): {plan_b}")
    
    # Statistical comparison (if numerical)
    if isinstance(plan_a, (int, float)) and isinstance(plan_b, (int, float)):
        improvement = ((plan_b - plan_a) / plan_a) * 100
        direction = "better" if improvement > 0 else "worse"
        print(f"  → Plan B is {abs(improvement):.0f}% {direction}")
```

**Expected Comparative Outcome**:

| Metric | Plan A (Protein/VLP) | Plan B (mRNA-LNP) | Winner |
|--------|----------------------|-------------------|--------|
| **Antibody Titer** | High (10K–100K) | Very High (100K–1M) | Plan B ✓ |
| **CD8+ Response** | Moderate | Strong | Plan B ✓ |
| **Breadth (# species neutralized)** | 2–3 | 2–3 | Tie |
| **Manufacturing Time** | 12–16 weeks | 6–8 weeks | Plan B ✓ |
| **Shelf Life at 4°C** | Unknown (3–6 months?) | 52+ weeks | Plan B ✓ |
| **Pandemic Deployment Speed** | 9–12 months | 6 months | Plan B ✓ |
| **Regulatory Precedent** | Limited | Strong (COVID vaccines) | Plan B ✓ |
| **Cost per Dose** | $20–50 | $2–5 | Plan B ✓ |

**Recommendation**: Plan B (mRNA-LNP) superior for pandemic readiness; Plan A (Protein) valuable as backup.

---

## PHASE 8: PUBLICATION & RELEASE (Weeks 19–20)

### 8.1 Manuscript Preparation

**Title**: "Rapid mRNA-LNP Vaccine Development for Pandemic-Ready Hantavirus Protection: From Rational Design to Clinical-Grade Manufacturing"

**Unique Elements vs. Plan A**:
- mRNA sequence optimization strategies
- LNP formulation design rationale
- Stability data at multiple temperatures
- Manufacturing scalability pathway
- Comparison to protein-based approach

**Key Figures**:

```
Figure 1: mRNA Design & Optimization
  Panel A: Codon optimization strategy
  Panel B: UTR design rationale
  Panel C: GC content optimization
  Panel D: Secondary structure prediction

Figure 2: LNP Formulation Design
  Panel A: Ionizable lipid library screened
  Panel B: Predicted vs. measured transfection efficiency
  Panel C: Particle size distribution (optimized formulation)
  Panel D: Zeta potential measurements

Figure 3: Manufacturing & Stability
  Panel A: GMP mRNA synthesis workflow
  Panel B: Microfluidic LNP encapsulation setup
  Panel C: Stability curves (4°C, −20°C, −80°C storage)
  Panel D: Manufacturing scale-up pathway

Figure 4: Mouse Immunogenicity
  Panel A: Antibody kinetics (IgG, IgG1, IgG2a)
  Panel B: Neutralization breadth (ANDV/SNV/PUUV pseudotypes)
  Panel C: CD8+ T-cell response (ELISPOT)
  Panel D: Comparison to Plan A (protein/VLP)

Figure 5: Pandemic Deployment Readiness
  Panel A: Timeline from pathogen ID → human trial (6 months)
  Panel B: Manufacturing capacity (scale-up potential)
  Panel C: Cold chain requirements (4°C compatible)
  Panel D: Cost per dose analysis
```

---

### 8.2 GitHub Release

```
biomate-andv-vaccine-plan-b/
│
├── README.md
│   └─ Overview, methods, pandemic deployment rationale
│
├── mrna_design/
│   ├─ construct_A_codon_optimized.fasta
│   ├─ construct_B_codon_optimized.fasta
│   ├─ construct_C_codon_optimized.fasta
│   ├─ full_mrna_designs_with_UTRs.fasta
│   └─ codon_optimization_report.json
│
├── lnp_formulation/
│   ├─ top_3_lnp_formulations.json
│   ├─ lipid_component_specifications.csv
│   ├─ microfluidic_manufacturing_sop.pdf
│   └─ predicted_lnp_properties.xlsx
│
├── manufacturing/
│   ├─ gmp_mrna_synthesis_spec.pdf
│   ├─ lnp_encapsulation_sop.pdf
│   ├─ analytical_methods_compendium.pdf
│   ├─ cmc_regulatory_package.pdf
│   └─ stability_protocol.pdf
│
├── data/
│   ├─ mrna_immunogenicity_mouse.csv
│   ├─ lnp_stability_realtime.csv
│   ├─ pseudotype_neutralization_titers.csv
│   ├─ cd8_elispot_results.csv
│   ├─ mrna_innate_immune_response.csv
│   └─ plan_a_vs_plan_b_comparison.xlsx
│
├── code/
│   ├─ 01_mrna_sequence_optimization.py
│   ├─ 02_utr_design.py
│   ├─ 03_lnp_formulation_optimization.py
│   ├─ 04_stability_prediction.py
│   ├─ 05_manufacturing_scale_up.py
│   └─ 06_immunogenicity_analysis.py
│
├── figures/
│   ├─ mrna_design_strategy.png
│   ├─ lnp_formulation_landscape.png
│   ├─ stability_curves.png
│   ├─ neutralization_breadth.png
│   ├─ pandemic_deployment_timeline.png
│   └─ plan_a_vs_b_comparison.png
│
├── supplementary/
│   ├─ gmp_cmc_complete_documentation.zip
│   ├─ microfluidic_parameters.json
│   ├─ stability_data_long_term.xlsx (weeks 0–52)
│   └─ regulatory_readiness_checklist.pdf
│
└── LICENSE (CC-BY 4.0)
```

---

### 8.3 Key GitHub Assets

**For immediate implementation/adoption**:

```
1. mRNA Sequence Files (FASTA)
   → Direct use for synthesis orders
   → Copy-paste into GMP-CRO ordering system

2. LNP Formulation Specifications (JSON)
   → Exact molar ratios for microfluidic synthesis
   → Lipid sourcing contacts

3. Manufacturing SOPs (PDF)
   → Step-by-step protocols
   → Quality control checkpoints
   → Regulatory-compliant documentation

4. Stability Data & Predictions
   → Shelf-life estimates at different temperatures
   → Real-time data from 52-week study (ongoing)

5. Regulatory Documentation
   → CMC (Chemistry, Manufacturing, Controls)
   → Non-clinical & clinical sections pre-drafted
   → IND-ready package (with real data)
```

---

## PLAN B: SUCCESS METRICS

### ✅ Plan B (mRNA-LNP) Success = ALL of:
- ✅ 3 optimized mRNA sequences with stable secondary structure
- ✅ 3 LNP formulations with predicted/measured EE > 85%
- ✅ Stability data: ≥ 52 weeks at 4°C (1-year shelf life)
- ✅ GMP-grade mRNA manufactured (500 mg per construct)
- ✅ Mouse sera neutralize ≥ 2/3 hantavirus species
- ✅ CD8+ T-cell response: IFN-γ+ > 200 SFU/million (strong)
- ✅ Predicted mRNA/LNP correlation with immunogenicity r > 0.6
- ✅ Pre-print published + regulatory CMC package complete
- ✅ GitHub repository with manufacturing-ready specifications
- ✅ Clear 6-month deployment pathway from pathogen ID → Phase 1

---

## PLAN B BUDGET BREAKDOWN

| Item | Cost | Timeline |
|------|------|----------|
| **mRNA Sequence Design** (BioMate internal) | $0 | Weeks 2–5 |
| **GMP mRNA Synthesis (3 constructs)** | $24–30K | Weeks 7–11 |
| **LNP Formulation (9 batches)** | $27–36K | Weeks 12–16 |
| **Stability Testing (Real-time + Accelerated)** | $5–8K | Weeks 8–20 |
| **Mouse Facility & Vivarium** | $5–8K | Weeks 9–16 |
| **Mouse Immunization + Assays** | $12–15K | Weeks 9–18 |
| **Regulatory Documentation** | $3–5K | Weeks 18–20 |
| **Manuscript Writing + Figures** | $3–5K | Weeks 19–20 |
| **TOTAL** | **$79–107K** | **4 months** |

**Note**: Plan B slightly higher cost due to GMP mRNA synthesis + extended stability testing, but justified by pandemic deployment advantage.

---

## PLAN B: MANUFACTURING READINESS

### Post-Campaign (Weeks 21+): Path to IND

```
Week 21–26: Finalize Stability Data
  ├─ Complete 24-week real-time stability (data in hand)
  ├─ File CMC module with FDA
  └─ Prepare for manufacturing inspections

Week 27–39: Clinical Manufacturing
  ├─ Scale-up from 50 mL → 1 L batches (GMP)
  ├─ Phase 1 clinical-grade LNP-mRNA (500 doses)
  ├─ Clinical supply manufacturing validation
  └─ Inspection-ready facility

Week 40–52: Regulatory Submission
  ├─ IND submission (CMC + non-clinical complete)
  ├─ FDA review (30 days)
  ├─ IND approval
  └─ Phase 1 initiation

Month 13: First-in-Human Administration
```

**Total Time: 13 months from manuscript publication → Phase 1 initiation**

---

## COMPARATIVE DEPLOYMENT SCENARIO

**If hantavirus pandemic emerges in Year 2**:

```
Scenario: Novel hantavirus species isolated (Week 0 of emergency)

Plan A (Protein/VLP):
  └─ Week 0: Obtain sequence
     Week 1–4: Design immunogens + epitope prediction
     Week 5–12: Express/fold proteins + characterization
     Week 13–20: Mouse immunogenicity studies
     Week 21: First human vaccine administration
     → 21-week deployment timeline

Plan B (mRNA-LNP):
  └─ Week 0: Obtain sequence
     Week 1–2: mRNA optimization + formulation (pre-validated)
     Week 3–4: GMP mRNA synthesis
     Week 5–6: LNP encapsulation (using pre-validated formulation)
     Week 7: Clinical-grade manufacturing complete
     Week 8–13: Expedited IND (with Plan A mouse data as precedent)
     Week 14: First human vaccine administration
     → 14-week deployment timeline

Advantage: Plan B saves ~7 weeks (33% faster) in pandemic scenario.
```

---

## FINAL COMPARISON: Plan A vs Plan B

| Dimension | Plan A (Protein/VLP) | Plan B (mRNA-LNP) | Winner |
|-----------|----------------------|-------------------|--------|
| **Scientific Rigor** | ✓✓ Robust protein folding data | ✓✓ GMP manufacturing precedent | Tie |
| **Timeline (mouse → Phase 1)** | 21 weeks | 14 weeks | Plan B (7 week savings) |
| **Immunogenicity (breadth)** | ✓ Strong (2–3 species) | ✓✓ Very Strong (likely 3/3) | Plan B |
| **CD8+ Response** | ✓ Moderate | ✓✓ Strong (TLR activation) | Plan B |
| **Stability at 4°C** | ⚠ Requires testing | ✓ 52+ weeks predicted | Plan B |
| **Shelf Life at 25°C** | ✗ Poor (days) | ⚠ 1–2 weeks | Neither ideal |
| **Manufacturing Complexity** | ✓ Standard protein production | ✓✓ Microfluidic (simple, scalable) | Plan B |
| **Vaccine Cost/Dose** | $20–50 | $2–5 | Plan B |
| **Regulatory Precedent** | ⚠ Unique vaccine format | ✓✓ COVID mRNA vaccines approved | Plan B |
| **Cold Chain Requirement** | Standard (2–8°C or −20°C) | Refrigerated (4°C) preferred | Plan B |

---

## RECOMMENDATION FOR YAOYUN

**If choosing ONE plan**: **Plan B (mRNA-LNP)**

**Rationale**:
1. **Pandemic readiness**: 6-month deployment timeline aligns with WHO pandemic preparedness goals
2. **Manufacturing**: Microfluidic LNP synthesis is scalable (unlike protein folding bottlenecks)
3. **Regulatory**: COVID mRNA vaccine precedent accelerates FDA review
4. **Commercial**: Much lower COGS ($2–5/dose vs. $20–50/dose) enables global access
5. **IP**: BioMate can own the epitope design + LNP formulation strategy

**If doing BOTH (optimal)**: 
- Use Plan A mouse data to support Plan B IND filing
- Plan A serves as backup if mRNA manufacturing encounters issues
- Combined investment: ~$120K total budget
- Combined timeline: 4 months for both proof-of-concepts

---

**Document Version**: 1.0 (April 2026)  
**Approach**: mRNA-LNP platform for scalable, pandemic-ready vaccines  
**Status**: Ready for Implementation via Claude Code

**BioMate note**: mRNA/LNP sections use **semantic pseudocode**. Map **LNP formulation**, **NP PK**, and related steps to the **Nucleic Acid / LNP** track in **`docs/20260417_DRUG_DEVELOPMENT_COVERAGE_ANALYSIS.md`**; CRO and stability data remain external boundaries per that doc. See `BIOMATE_CAPABILITY_GAP.md`.
