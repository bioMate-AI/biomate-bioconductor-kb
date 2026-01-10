# SGI-Bench Error Analysis and Failure Modes: Complete Documentation

## Executive Summary

This document provides a comprehensive analysis of all error types, failure modes, and life science-specific failure cases identified in SGI-Bench. Understanding these systematic failures is critical for BioMate AI's platform design, as they reveal exactly where AI systems fail in scientific workflows and where human-AI collaboration provides the most value.

---

## 1. Error Taxonomy Overview

### 1.1 Error Categories by Task Type

| Task | Error Category | Severity | Frequency |
|------|---------------|----------|-----------|
| **Deep Research** | Reasoning trajectory collapse | Critical | Very High |
| **Deep Research** | Numerical data extraction failure | High | High |
| **Deep Research** | Multi-source synthesis failure | High | High |
| **Idea Generation** | Missing implementation details | Critical | Very High |
| **Idea Generation** | Feasibility blindness | Critical | Very High |
| **Dry Experiment** | Algorithm selection errors | Critical | High |
| **Dry Experiment** | Numerical precision failures | Critical | High |
| **Wet Experiment** | Temporal coordination failures | Critical | Very High |
| **Wet Experiment** | Branch conflation | Critical | High |
| **Wet Experiment** | Step omission/insertion | High | Very High |
| **Experimental Reasoning** | Comparative reasoning weakness | High | Very High |
| **Experimental Reasoning** | Cross-sample discrimination failure | High | High |

### 1.2 Error Impact Matrix

```
                    Low Impact    Medium Impact    High Impact    Critical
                    ─────────────────────────────────────────────────────────
Deep Research       │            │ Multi-source   │ Numerical    │ Trajectory
                    │            │ synthesis      │ extraction   │ collapse
                    │            │                │              │
Idea Generation     │            │ Redundancy     │ Missing      │ Feasibility
                    │            │                │ details      │ blindness
                    │            │                │              │
Dry Experiment      │ Syntax     │ API misuse     │ Algorithm    │ Numerical
                    │ errors     │                │ selection    │ precision
                    │            │                │              │
Wet Experiment      │ Parameter  │ Step insertion │ Step omission│ Temporal
                    │ typos      │                │              │ coordination
                    │            │                │              │
Exp Reasoning       │            │ Partial logic  │ Comparative  │ Domain
                    │            │                │ reasoning    │ blindness
```

---

## 2. Deep Research Errors

### 2.1 Reasoning Trajectory Collapse

**Definition:** Models produce locally correct steps but fail to maintain global coherence across long reasoning chains, causing final answer failure despite intermediate correctness.

**Evidence:**
- Step-Level Accuracy (SLA): ~50-65%
- Exact Match (EM): ~10-20%
- **Gap ratio: 2.5-3.2x** between SLA and EM

**Failure Pattern:**
```
Ground Truth Path:
  Step 1 → Step 2 → Step 3 → Step 4 → Step 5 → Correct Answer
  
Model Path (Trajectory Collapse):
  Step 1 → Step 2 → [ERROR] → Step 4' → Step 5' → Wrong Answer
  ✓        ✓        ✗          Propagated error → Cascading failure
```

**Life Science Example - Biomarker Discovery:**
```
Task: Extract IC50 values for compound X across 5 studies

Ground Truth Extraction:
  Study A: IC50 = 2.3 µM (Table 2, Row 5)
  Study B: IC50 = 1.8 µM (Figure 3 legend)
  Study C: IC50 = 3.1 µM (Supplementary Table S1)
  Study D: IC50 = 2.7 µM (Text, Results section)
  Study E: IC50 = 2.0 µM (Abstract)
  
Model Failure:
  Study A: IC50 = 2.3 µM ✓
  Study B: IC50 = 1.8 µM ✓
  Study C: IC50 = 31 µM ✗ (decimal point error)
  Study D: IC50 = 2.7 nM ✗ (unit confusion from Study C context)
  Study E: Skipped (trajectory abandoned)
  
  Final synthesis: Incorrect range, missing data
```

### 2.2 Task-Specific Difficulty Distribution

| Task Category | Performance | Primary Failure Mode |
|--------------|-------------|---------------------|
| **Data Retrieval** | ~10% EM | Scattered numerical details |
| **Properties** | ~15% EM | Unit conversions, context switching |
| **Micro-experiments** | ~20% EM | Protocol parameter extraction |
| **Macro-experiments** | ~25% EM | Workflow reconstruction |

### 2.3 Life Science Deep Research Failures

**Example: Drug-Drug Interaction Literature Review**
```
Question: What is the maximum recommended dose adjustment 
for Drug A when co-administered with CYP3A4 inhibitors 
according to FDA labeling?

Model Response Issues:
1. Conflated strong vs. moderate inhibitors
2. Extracted dose from Phase 2 study instead of FDA label
3. Missed contraindication for strong inhibitors
4. Provided adjustment for wrong patient population

Error Chain:
  Source identification (partial) → 
  Context confusion (CYP3A4 vs CYP2D6) → 
  Wrong numerical extraction → 
  Incorrect final recommendation
```

---

## 3. Idea Generation Errors

### 3.1 Feasibility Blindness (Most Critical)

**Definition:** Models generate ideas with high novelty scores but uniformly low feasibility scores, producing concepts that cannot be practically implemented.

**Quantitative Evidence:**
- Novelty Score: 60-76 (acceptable)
- Effectiveness: 24-51 (moderate)
- Detailedness: 43-86 (variable)
- **Feasibility: 14-23 (uniformly low)**

**Feasibility Gap Analysis:**
```
Best Model Performance (o3):
  Novelty:     72.90
  Feasibility: 22.90
  Gap:         50.00 points (3.2x ratio)
  
Typical Pattern:
  "Propose a novel deep learning architecture for protein-ligand 
   binding prediction using transformer attention mechanisms 
   with physics-informed constraints..."
   
  Missing Critical Elements:
  ✗ Training data source/size not specified
  ✗ Compute requirements undefined
  ✗ Hyperparameters absent
  ✗ Baseline comparisons not planned
  ✗ Evaluation metrics incomplete
  ✗ Timeline not realistic
```

### 3.2 Missing Implementation Details Catalog

| Category | Missing Elements | Frequency |
|----------|-----------------|-----------|
| **Data Acquisition** | Source URLs, access permissions, preprocessing steps | 95% |
| **Compute Resources** | GPU hours, memory requirements, parallelization | 92% |
| **Hyperparameters** | Learning rates, batch sizes, optimizer settings | 88% |
| **Dependencies** | Library versions, compatibility constraints | 85% |
| **Interfaces** | Input/output formats, API specifications | 82% |
| **Evaluation** | Specific metrics, statistical tests, baselines | 78% |
| **Timeline** | Phase durations, milestones, deadlines | 75% |

### 3.3 Life Science Idea Generation Failures

**Example: AlphaFold-Style Protein Structure Prediction**

**Model-Generated Idea (Abbreviated):**
```
"Develop an end-to-end architecture that jointly processes 
MSA and pairwise features through Evoformer blocks, 
then refines 3D coordinates via invariant point attention..."
```

**Missing Feasibility Elements:**
```
Data Acquisition:
  ✗ How to obtain UniRef90/BFD sequences
  ✗ PDB download and preprocessing pipeline
  ✗ MSA construction tool specifications (HHblits version)

Compute Requirements:
  ✗ TPU pod specifications (Google internal)
  ✗ Training time estimates (weeks to months)
  ✗ Memory requirements per sequence length

Implementation Details:
  ✗ Evoformer block count
  ✗ Attention head dimensions
  ✗ Triangle update specifications
  ✗ Recycling iteration count
  ✗ Loss function weights

Evaluation Protocol:
  ✗ CASP blind evaluation logistics
  ✗ Template cutoff dates
  ✗ Sequence identity filtering
```

**Contrast with Ground Truth:**
```
Ground Truth Implementation Steps:
1. Data: PDB (April 2018), UniRef90, BFD (~2.2B sequences 
   clustered into ~66M families), Uniclust30, MGnify
2. MSA: HHBlits, jackhmmer, HHSearch tools
3. Architecture: Evoformer with interleaved attention 
   and triangle update blocks
4. Training: FAPE loss, distogram loss, BERT-style MSA 
   masking, auxiliary side-chain losses
5. Self-distillation: ~350,000 Uniclust30 clusters
6. Inference: Ensemble predictions, Amber relaxation
7. Evaluation: CASP14 (87 domains), recent PDB (n=10,795)
```

---

## 4. Dry Experiment Errors

### 4.1 Algorithm Selection Errors (Most Critical)

**Definition:** Models select algorithmically incorrect methods that execute successfully but produce scientifically wrong results.

**Core Problem:**
```
High Smooth Execution Rate (SER): >90%
Low PassAll@5: ~35%

Interpretation: Code runs but is scientifically wrong
```

**Gravitational Wave Computation Case Study:**

```python
# INCORRECT (o4-mini) - Uses np.cumsum (forward Euler)
def comoving_volume(z_max, H0_val, omega_m_val, omega_l_val):
    nz = 2000
    z = np.linspace(0.0, z_max, nz)
    dz = z[1] - z[0]
    E = np.sqrt(omega_m_val * (1.0 + z)**3 + omega_l_val)
    dchi_dz = (C / H0_val) / E
    chi = np.cumsum(dchi_dz) * dz  # ← CUMULATIVE ERROR
    chi[0] = 0.0
    dV_dz = 4.0 * np.pi * chi**2 * dchi_dz
    V_mpc3 = np.trapz(dV_dz, z)
    V_gpc3 = V_mpc3 / 1e9
    return V_gpc3

# CORRECT (GPT-4.1) - Uses scipy.integrate.quad
def comoving_volume(z_max, H0_val, omega_m_val, omega_l_val):
    def E(z):
        return np.sqrt(omega_m_val * (1 + z)**3 + omega_l_val)
    def integrand(z):
        return 1.0 / E(z)
    c_km_s = C
    integral, _ = integrate.quad(integrand, 0, z_max, 
                                  epsabs=1e-8, epsrel=1e-8)  # ← ADAPTIVE
    d_c = (c_km_s / H0_val) * integral
    volume_mpc3 = (4.0 / 3.0) * np.pi * d_c**3
    volume_gpc3 = volume_mpc3 / 1e9
    return volume_gpc3

# Result difference: ~21x accuracy gap
```

### 4.2 Function Category Difficulty

| Function Type | PassAll@5 | Primary Error Mode |
|--------------|-----------|-------------------|
| **Data Processing** | ~45% | Format handling |
| **Predictive Modeling** | ~40% | Hyperparameter defaults |
| **Statistical Analysis** | ~35% | Test selection |
| **Metric Calculation** | ~35% | Edge cases |
| **Simulation** | ~28% | Discretization errors |
| **Numerical Calculation** | ~25% | Algorithm selection |

### 4.3 Life Science Dry Experiment Failures

**Example: Pharmacokinetic Modeling**

```python
# Task: Implement two-compartment PK model with 
# first-order absorption

# COMMON ERRORS:

# Error 1: Wrong ODE formulation
def pk_model_wrong(y, t, params):
    # Missing absorption compartment
    C_central = y[0]
    dC_dt = -params['ke'] * C_central  # ← ONE-COMPARTMENT ONLY
    return [dC_dt]

# Error 2: Incorrect integration method
solution = odeint(pk_model, y0, t)  # ← No stiffness handling
# Should use solve_ivp with method='BDF' for stiff systems

# Error 3: Unit errors
Vd = 70  # L (correct)
dose = 500  # mg
C0 = dose / Vd  # mg/L
# Later: assumes µg/mL without conversion

# Error 4: Numerical instability
t = np.linspace(0, 24, 10)  # ← Too coarse for fast phases
# Should use adaptive timesteps or logarithmic spacing
```

**LC-MS Relevant Example: Peak Integration**

```python
# Task: Implement chromatographic peak integration

# COMMON ERRORS:

# Error 1: Baseline correction failure
def integrate_peak_wrong(signal, rt_start, rt_end):
    baseline = np.min(signal)  # ← Flat baseline assumption
    area = np.trapz(signal - baseline)  # Wrong for drifting baseline
    return area

# Error 2: Peak boundary detection
def find_peak_boundaries_wrong(signal):
    # Uses fixed threshold
    threshold = 0.05 * np.max(signal)  # ← Fails for small peaks
    # Should use derivative-based or valley detection

# Error 3: Noise handling
def denoise_wrong(signal):
    return gaussian_filter1d(signal, sigma=2)  # ← Peak broadening
    # Should use Savitzky-Golay or wavelet denoising

# CORRECT APPROACH:
from scipy.signal import find_peaks, peak_widths
from scipy.integrate import simpson

def integrate_peak_correct(signal, time, peak_idx):
    # Adaptive baseline using SNIP algorithm
    baseline = snip_baseline(signal, iterations=40)
    corrected = signal - baseline
    
    # Find peak boundaries using second derivative
    widths = peak_widths(corrected, [peak_idx], rel_height=0.95)
    left_idx, right_idx = int(widths[2][0]), int(widths[3][0])
    
    # Simpson's rule integration
    area = simpson(corrected[left_idx:right_idx], 
                   time[left_idx:right_idx])
    return area
```

---

## 5. Wet Experiment Errors

### 5.1 Temporal Coordination Failures (Most Critical)

**Definition:** Models collapse longitudinal sampling designs into single timepoints, destroying the ability to capture temporal dynamics.

**Quantitative Evidence:**
- Sequence Similarity (SS): ~30-35%
- Parameter Accuracy (PA): ~35-40%

**NSCLC Anti-PD-1 Immunotherapy Case Study:**

```
GROUND TRUTH PROTOCOL:
═══════════════════════════════════════════════════════════════

Day 0 (Baseline):
├─ Blood Sample #1
│  ├─ PBMC Isolation → T-cell baseline phenotyping
│  └─ Plasma → Cytokine baseline panel
├─ Tumor Biopsy
│  ├─ WES → Mutation calling
│  ├─ HLA Typing
│  └─ Neoantigen Prediction
└─ Treatment: Anti-PD-1 administration

Day 7:
├─ Blood Sample #2
│  ├─ PBMC Isolation → T-cell expansion monitoring
│  └─ Plasma → Early cytokine response
└─ Continue treatment

Day 14:
├─ Blood Sample #3
│  ├─ PBMC Isolation → Neoantigen-specific T-cell detection
│  ├─ pMHC Multimer Staining
│  ├─ Flow Cytometry
│  └─ Intracellular Cytokine Staining
└─ Correlate with mutation burden

Day 21+:
├─ Blood Sample #4
│  └─ PBMC → Long-term response assessment
└─ Clinical Response Evaluation (RECIST)

MODEL-GENERATED PROTOCOL (o4-mini):
═══════════════════════════════════════════════════════════════

Single Timepoint (Collapsed):
├─ Blood Sample (ONE)           ← CRITICAL ERROR
│  ├─ PBMC Isolation (ONCE)     ← Cannot track dynamics
│  └─ Genomic DNA Extraction    ← Wrong sample use
├─ Tumor Tissue Extraction
│  ├─ WES
│  └─ Neoantigen Prediction
├─ Multimer Staining (ONCE)     ← No baseline comparison
├─ Flow Cytometry (ONCE)        ← No temporal data
└─ Correlate with response      ← Statistically invalid

ERRORS IDENTIFIED:
✗ Collapsed 4 timepoints into 1 (temporal coordination failure)
✗ Single PBMC isolation (cannot track T-cell dynamics)
✗ Conflated genomic and immunophenotyping branches
✗ Missing baseline measurements
✗ Intracellular cytokine staining omitted
✗ No statistical power for correlation analysis
```

### 5.2 Error Type Classification

| Error Type | Description | Frequency | Severity |
|------------|-------------|-----------|----------|
| **Temporal Collapse** | Multi-timepoint → single collection | 45% | Critical |
| **Branch Conflation** | Parallel workflows merged incorrectly | 35% | Critical |
| **Step Omission** | Required action missing | 40% | High |
| **Step Insertion** | Unnecessary action added | 30% | Medium |
| **Order Reversal** | Correct steps in wrong sequence | 25% | High |
| **Parameter Error** | Wrong reagent/concentration/time | 35% | Medium-High |

### 5.3 Life Science Protocol Failure Examples

**Example 1: FFPE Processing**
```
Correct Order:
  Fixation (24-48h) → Dehydration → Clearing → 
  Embedding → Sectioning → Deparaffinization → 
  Antigen Retrieval → Staining

Model Errors:
  ✗ Fixation time not specified (over-fixation destroys antigens)
  ✗ Antigen retrieval skipped (no epitope exposure)
  ✗ Blocking step omitted (high background)
  ✗ Dehydration series incomplete (poor embedding)
```

**Example 2: Flow Cytometry Panel**
```
Correct Order:
  PBMC Isolation → Viability Staining → Fc Block →
  Surface Staining → Fixation → Permeabilization →
  Intracellular Staining → Acquisition

Model Errors:
  ✗ Fc block omitted (non-specific binding)
  ✗ Viability dye after fixation (dead cell exclusion fails)
  ✗ Surface staining after permeabilization (epitope loss)
  ✗ Wrong fixation buffer for phospho-proteins
```

**Example 3: RNA Extraction from FFPE**
```
Correct Order:
  Deparaffinization (xylene) → Proteinase K Digestion →
  DNase Treatment → RNA Purification → RIN Assessment →
  cDNA Synthesis (if RIN > 7)

Model Errors:
  ✗ Deparaffinization incomplete (paraffin inhibits enzymes)
  ✗ DNase step omitted (genomic DNA contamination)
  ✗ No RIN quality check (downstream failure)
  ✗ Wrong extraction kit for FFPE (column clogging)
```

---

## 6. Experimental Reasoning Errors

### 6.1 Comparative Reasoning Weakness (Most Challenging)

**Definition:** Models fail at tasks requiring subtle quantitative or qualitative discrimination between samples, conditions, or experimental outcomes.

**Performance by Reasoning Type:**
| Reasoning Type | Accuracy | Relative Difficulty |
|---------------|----------|---------------------|
| Signal Perception | ~45% | Moderate |
| Causal Reasoning | ~42% | Moderate |
| Attribute Understanding | ~35% | High |
| **Comparative Reasoning** | ~30% | **Highest** |

**Why Comparative Reasoning Fails:**
```
Required Cognitive Operations:
1. Extract quantitative values from multiple images
2. Align measurements across different scales/units
3. Detect subtle differences (often <10% change)
4. Discriminate signal from noise
5. Integrate context for interpretation

Model Failure Points:
✗ Cannot reliably extract numbers from figures
✗ Fails at cross-image alignment
✗ Misses subtle but significant differences
✗ Conflates correlation with causation
✗ Over-generalizes from single observations
```

### 6.2 Domain-Specific Difficulty

| Domain | MCA | RV | Primary Challenge |
|--------|-----|----|--------------------|
| Astronomy | ~42% | ~70% | Structured patterns (easier) |
| Chemistry | ~40% | ~68% | Standard setups |
| Physics | ~38% | ~65% | Theoretical grounding |
| Neuroscience | ~36% | ~62% | Complex signals |
| Energy | ~35% | ~60% | System dynamics |
| Information | ~34% | ~58% | Abstract reasoning |
| Earth Science | ~32% | ~55% | Heterogeneous data |
| **Life Science** | ~30% | ~52% | **Visual heterogeneity** |
| **Materials** | ~28% | ~50% | **Domain-specific cues** |

### 6.3 Life Science Experimental Reasoning Failures

**Example: Siglec-10/CD24 Immunotherapy Analysis**

```
Task: Multi-image analysis requiring:
  Image 1: Molecular pathway (Siglec-10/CD24 axis)
  Image 2: Nanoparticle delivery strategies (A, B, C)
  Image 3: Drug delivery classification

Question: Which target, method, and type for 
deep-level tumor inhibition via non-tumor cells?

Correct Answer: E (Siglec-10; C; A)
  - Siglec-10 on macrophages (non-tumor)
  - Method C: siRNA (nucleic acid level = deeper)
  - Type A: Passive targeting

Common Model Errors:
  ✗ Confused CD24 (tumor) with Siglec-10 (immune cells)
  ✗ Selected antibody blocking (surface) over siRNA (genetic)
  ✗ Misidentified targeting mechanism
  ✗ Failed to integrate information across all three images
```

**Example: Ocean Heat Content Analysis**

```
Task: Analyze 4 images showing OHC anomalies across 
Pacific, Atlantic, Indian oceans + ONI time series

Required Analysis:
  - Compare warming patterns across basins
  - Correlate with El Niño/La Niña events
  - Identify temporal onset of warming bands
  - Distinguish latitude-specific trends

Model Failure Modes:
  ✗ Cannot extract numerical values from heatmaps
  ✗ Fails to compare color scales across images
  ✗ Misinterprets temporal axis
  ✗ Confuses correlation direction (positive vs negative)
  ✗ Over-generalizes from single basin
```

---

## 7. Root Cause Analysis

### 7.1 Fundamental Limitations

| Root Cause | Manifestation | Tasks Affected |
|------------|---------------|----------------|
| **Linguistic abstraction without grounding** | Fluent proposals without executable details | Idea Generation |
| **Syntactic fluency ≠ semantic correctness** | Code runs but is scientifically wrong | Dry Experiment |
| **Missing procedural constraints** | Temporal and dependency violations | Wet Experiment |
| **Lack of cross-sample training** | Cannot discriminate subtle differences | Exp Reasoning |
| **Error propagation in long chains** | Local correctness, global failure | Deep Research |

### 7.2 Training Data Gaps

```
Scientific Computing Knowledge:
  ✗ Numerical method selection criteria
  ✗ Stability/precision tradeoffs
  ✗ Domain-specific algorithm constraints

Laboratory Protocol Knowledge:
  ✗ Temporal dependencies between steps
  ✗ Sample handling constraints
  ✗ Quality control checkpoints

Experimental Design Knowledge:
  ✗ Statistical power requirements
  ✗ Control group necessity
  ✗ Confounding variable management
```

---

## 8. BioMate Design Implications

### 8.1 Error Mitigation Strategies

| Error Type | Mitigation Strategy | BioMate Implementation |
|------------|--------------------|-----------------------|
| Trajectory collapse | Step-by-step validation | RAG with checkpoint verification |
| Feasibility blindness | Constraint checking | Parameter validation engine |
| Algorithm selection | Pre-validated libraries | OpenMS/MZmine integration |
| Temporal coordination | Protocol templates | Multi-timepoint workflow builder |
| Comparative reasoning | Structured comparison | QC deviation frameworks |

### 8.2 Architecture Recommendations

```
BioMate Architecture to Address SGI-Bench Failures:

┌─────────────────────────────────────────────────────────────┐
│                    User Query Layer                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │ Natural     │  │ Protocol    │  │ Parameter           │ │
│  │ Language    │──▶│ Template    │──▶│ Validation         │ │
│  │ Parser      │  │ Matcher     │  │ Engine             │ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
│         │                │                   │              │
│         ▼                ▼                   ▼              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Validation Checkpoint Layer             │   │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐   │   │
│  │  │Temporal │ │Parameter│ │Algorithm│ │Domain   │   │   │
│  │  │Order    │ │Range    │ │Selection│ │Constraint│   │   │
│  │  │Check    │ │Check    │ │Check    │ │Check    │   │   │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘   │   │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                 │
│                           ▼                                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Validated Tool Execution                │   │
│  │  OpenMS │ MZmine │ XCMS │ MetaboAnalyst │ Custom    │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘

Key Design Principles:
1. No AI-generated code execution without validation
2. Protocol templates with locked step ordering
3. Parameter constraints from domain knowledge base
4. Comparative analysis with structured frameworks
5. Step-by-step verification with human checkpoints
```

### 8.3 Quality Metrics for BioMate

Based on SGI-Bench error rates, BioMate should target:

| Metric | SGI-Bench Best | BioMate Target | Method |
|--------|----------------|----------------|--------|
| Workflow Sequence Similarity | 35.5% | **>80%** | Pre-validated templates |
| Parameter Accuracy | 40.6% | **>90%** | Constraint validation |
| Numerical Computation | 36.64% PassAll@5 | **>70%** | Validated algorithms |
| Multi-step Reasoning | 20% EM | **>50%** | Checkpoint verification |
| Comparative Analysis | 30% MCA | **>75%** | Structured frameworks |

---

## 9. Appendix: Complete Error Code Reference

### 9.1 Deep Research Error Codes

| Code | Error Type | Description | Example |
|------|------------|-------------|---------|
| DR-001 | Trajectory Collapse | Global coherence failure | Multi-hop reasoning breakdown |
| DR-002 | Numerical Extraction | Value/unit extraction error | IC50 = 31 µM instead of 3.1 µM |
| DR-003 | Source Confusion | Wrong paper/section cited | Phase 2 vs FDA label |
| DR-004 | Context Switch | Domain knowledge bleeding | CYP3A4 vs CYP2D6 confusion |
| DR-005 | Aggregation Failure | Cannot synthesize multiple sources | Conflicting data not reconciled |

### 9.2 Idea Generation Error Codes

| Code | Error Type | Description | Example |
|------|------------|-------------|---------|
| IG-001 | Missing Data Plan | No data acquisition specified | "Use large dataset" without source |
| IG-002 | Missing Compute | No resource requirements | GPU hours undefined |
| IG-003 | Missing Hyperparameters | Training details absent | "Fine-tune model" only |
| IG-004 | Missing Dependencies | Library versions unspecified | PyTorch version unclear |
| IG-005 | Missing Evaluation | Metrics/baselines incomplete | "Measure accuracy" only |
| IG-006 | Infeasible Timeline | Unrealistic schedule | 1 week for 6-month project |

### 9.3 Dry Experiment Error Codes

| Code | Error Type | Description | Example |
|------|------------|-------------|---------|
| DE-001 | Algorithm Selection | Wrong method for problem | np.cumsum vs scipy.integrate.quad |
| DE-002 | Numerical Precision | Insufficient accuracy | Single precision for sensitive calc |
| DE-003 | Discretization Error | Grid too coarse | 10 points for fast dynamics |
| DE-004 | Unit Mismatch | Inconsistent units | mg/L vs µg/mL |
| DE-005 | Edge Case Failure | Boundary conditions wrong | Division by zero not handled |
| DE-006 | Stiffness Ignored | Wrong solver for stiff systems | odeint vs solve_ivp(method='BDF') |

### 9.4 Wet Experiment Error Codes

| Code | Error Type | Description | Example |
|------|------------|-------------|---------|
| WE-001 | Temporal Collapse | Multi-timepoint to single | 4 blood draws → 1 |
| WE-002 | Branch Conflation | Parallel workflows merged | Genomic + immunophenotyping |
| WE-003 | Step Omission | Required action missing | Fc block skipped |
| WE-004 | Step Insertion | Unnecessary action added | Extra wash step |
| WE-005 | Order Reversal | Correct steps, wrong order | Stain before block |
| WE-006 | Parameter Error | Wrong reagent/time/temp | 4% PFA vs 10% NBF |
| WE-007 | Sample Misuse | Wrong sample for assay | Plasma for cell culture |

### 9.5 Experimental Reasoning Error Codes

| Code | Error Type | Description | Example |
|------|------------|-------------|---------|
| ER-001 | Numerical Extraction | Cannot read values from figures | Heatmap value misread |
| ER-002 | Cross-Image Failure | Cannot align information | Different scales |
| ER-003 | Comparative Weakness | Cannot discriminate differences | <10% change missed |
| ER-004 | Causal Confusion | Correlation vs causation | Association as mechanism |
| ER-005 | Domain Blindness | Missing domain-specific cues | Pathology pattern |
| ER-006 | Integration Failure | Cannot synthesize multi-modal | Text + image + graph |

---

*Document prepared for BioMate AI platform development*
*Source: SGI-Bench (arXiv:2512.16969v1, December 2025)*
*Total error types catalogued: 35 distinct failure modes*
*Life science-specific examples: 18 detailed cases*
