# DIA-NN Pre-computed Spectral Library - Detailed Explanation

**Date**: 2025-12-05 16:09

---

## What is a Spectral Library?

A **spectral library** is a database that contains:

```
For each peptide:
├── Peptide sequence (e.g., "PEPTIDEK")
├── Charge state (e.g., 2+, 3+)
├── Precursor m/z (mass-to-charge ratio)
├── Retention time (when it elutes from LC column)
├── Ion mobility (if applicable)
└── Fragment ions (MS2 spectrum)
    ├── b-ions: b1, b2, b3...
    ├── y-ions: y1, y2, y3...
    └── Relative intensities
```

### Visual Example

```
Peptide: PEPTIDEK (charge 2+)

MS2 Spectrum (fragmentation pattern):
Intensity
    │
100%│    ▓
    │    ▓                   ▓
 75%│    ▓          ▓        ▓
    │    ▓    ▓     ▓        ▓     ▓
 50%│    ▓    ▓     ▓   ▓    ▓     ▓
    │    ▓    ▓     ▓   ▓    ▓     ▓
 25%│ ▓  ▓    ▓  ▓  ▓   ▓    ▓  ▓  ▓
    │ ▓  ▓    ▓  ▓  ▓   ▓    ▓  ▓  ▓
    └────────────────────────────────────→ m/z
      y1 b2  y2 b3 y3  b4   y4 b5 y5

Retention Time: 25.3 minutes
Ion Mobility: 0.95 1/K0
```

---

## Why Does DIA-NN Need a Spectral Library?

### DIA (Data-Independent Acquisition) Problem

In DIA mass spectrometry:
1. All peptides in a mass window are fragmented together
2. The resulting spectrum is a **mixture** of many peptides
3. You need to **deconvolute** this mixture to identify individual peptides

```
DIA Spectrum (mixed):
    │  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  ← Many peptides overlapping!
    └────────────────────────────────────→ m/z

Spectral Library tells you:
- "Peptide A should have peaks at m/z 200, 350, 500"
- "Peptide B should have peaks at m/z 210, 400, 550"
- DIA-NN matches the mixed spectrum against known patterns
```

### How DIA-NN Uses the Library

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           DIA-NN WORKFLOW                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   Raw DIA Data                    Spectral Library                          │
│   ────────────                    ────────────────                          │
│   Mixed spectra         +         Known peptide patterns                    │
│   from instrument                 (predicted or experimental)               │
│                                                                             │
│                    ↓                                                        │
│                                                                             │
│              ┌─────────────────────────────────────────┐                    │
│              │      DIA-NN Matching Algorithm          │                    │
│              │                                         │                    │
│              │  For each peptide in library:           │                    │
│              │  1. Find expected RT window             │                    │
│              │  2. Extract fragment ion signals        │                    │
│              │  3. Score match against library         │                    │
│              │  4. Apply neural network scoring        │                    │
│              └─────────────────────────────────────────┘                    │
│                                                                             │
│                    ↓                                                        │
│                                                                             │
│   Output: Identified & Quantified Proteins                                  │
│   ────────────────────────────────────────                                  │
│   Protein A: 1000 copies                                                    │
│   Protein B: 500 copies                                                     │
│   Protein C: 2500 copies                                                    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## The Bottleneck: In-Silico Library Generation

### Current Workflow (SLOW)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     CURRENT: GENERATE LIBRARY EVERY TIME                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  INPUT: UniProt FASTA (Human)                                               │
│  ─────────────────────────────                                              │
│  >sp|P04637|P53_HUMAN Cellular tumor antigen p53                            │
│  MEEPQSDPSVEPPLSQETFSDLWKLLPENNVLSPLPSQAMDDLMLSPDDIEQWFTEDPGP...            │
│  >sp|P38398|BRCA1_HUMAN Breast cancer type 1 susceptibility protein         │
│  MDLSALRVEEVQNVINAMQKILECPICLELIKEPVSTKCDHIFCKFCMLKLLNQKKGPSQC...            │
│  ... (20,000+ proteins)                                                     │
│                                                                             │
│                    ↓ Step 1: In-silico digestion (fast, ~10 min)            │
│                                                                             │
│  PEPTIDES (millions)                                                        │
│  ───────────────────                                                        │
│  MEEPQSDPSVEPPLSQETFSDK  (tryptic peptide from P53)                         │
│  LLPENNVLSPLPSQAMDDLMLSPDDIEQWFTEDPGPK  (too long, filtered)                │
│  ... (2-5 million peptides)                                                 │
│                                                                             │
│                    ↓ Step 2: Deep learning prediction (SLOW! 24-48 hours)   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    NEURAL NETWORK PREDICTIONS                        │   │
│  │                                                                      │   │
│  │  For EACH of 2-5 million peptides, predict:                          │   │
│  │                                                                      │   │
│  │  1. Retention Time (RT)                                              │   │
│  │     - When will this peptide elute?                                  │   │
│  │     - Deep learning model trained on millions of examples            │   │
│  │                                                                      │   │
│  │  2. Fragment Ion Intensities                                         │   │
│  │     - Which fragment ions will be most intense?                      │   │
│  │     - Requires understanding of peptide chemistry                    │   │
│  │     - ~20-50 fragment ions per peptide                               │   │
│  │                                                                      │   │
│  │  3. Ion Mobility (optional)                                          │   │
│  │     - Shape-dependent drift time                                     │   │
│  │                                                                      │   │
│  │  Total predictions: 2M peptides × 50 fragments = 100M predictions    │   │
│  │  Time: 24-48 HOURS on CPU                                            │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│                    ↓                                                        │
│                                                                             │
│  OUTPUT: .predicted.speclib file (~2-5 GB)                                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Why It Takes So Long

| Step | Time | Why |
|------|------|-----|
| FASTA parsing | 1 min | Simple text processing |
| In-silico digestion | 10 min | Generate all tryptic peptides |
| **Deep learning prediction** | **24-48 hours** | **Neural network inference on millions of peptides** |
| File writing | 30 min | Write large .speclib file |

The deep learning step is CPU-bound and processes peptides sequentially.

---

## The Solution: Pre-computed Library

### Concept

**Instead of generating the library every time, generate it ONCE and reuse it.**

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     PRE-COMPUTED LIBRARY APPROACH                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ONE-TIME GENERATION (done by us, stored in cloud)                          │
│  ─────────────────────────────────────────────────                          │
│                                                                             │
│  UniProt Human FASTA → DIA-NN → uniprot_human_2024.speclib                  │
│  UniProt Mouse FASTA → DIA-NN → uniprot_mouse_2024.speclib                  │
│  UniProt Yeast FASTA → DIA-NN → uniprot_yeast_2024.speclib                  │
│  Contaminants FASTA  → DIA-NN → contaminants.speclib                        │
│                                                                             │
│  (Takes 2 days once, but only needs to be done once per UniProt release)    │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  USER WORKFLOW (fast every time)                                            │
│  ───────────────────────────────                                            │
│                                                                             │
│  1. User starts DIA-NN analysis                                             │
│  2. BioMate checks: "Human proteome? We have that library!"                 │
│  3. Download pre-computed library (~2-5 GB, 5-10 min)                       │
│  4. Skip 48-hour generation step entirely!                                  │
│  5. Run DIA-NN analysis (~2-4 hours)                                        │
│                                                                             │
│  Total time: 2-4 hours instead of 2+ days                                   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Library Repository Structure

```
biomate-spectral-libraries/
├── human/
│   ├── uniprot_human_2024_01.speclib         # Full UniProt (20,000 proteins)
│   ├── uniprot_human_reviewed.speclib        # SwissProt only (curated)
│   ├── uniprot_human_phospho.speclib         # With phosphorylation
│   └── metadata.json
│       {
│         "organism": "Homo sapiens",
│         "taxonomy_id": 9606,
│         "uniprot_version": "2024_01",
│         "proteins": 20385,
│         "peptides": 2847293,
│         "enzyme": "trypsin",
│         "missed_cleavages": 1,
│         "fixed_mods": ["Carbamidomethyl (C)"],
│         "variable_mods": ["Oxidation (M)"],
│         "file_size_gb": 2.8,
│         "diann_version": "1.8.1",
│         "generated_date": "2024-01-15"
│       }
│
├── mouse/
│   ├── uniprot_mouse_2024_01.speclib
│   └── metadata.json
│
├── yeast/
│   └── ...
│
├── ecoli/
│   └── ...
│
└── contaminants/
    └── crap_contaminants.speclib             # Common contaminants
```

### When Pre-computed Works vs. When It Doesn't

| Scenario | Pre-computed Works? | Notes |
|----------|---------------------|-------|
| Standard human proteome | ✅ YES | Most common case |
| Standard mouse proteome | ✅ YES | Common model organism |
| Custom FASTA (mutations) | ❌ NO | Need to generate new library |
| Unusual modifications | ❌ NO | Need specific modification library |
| Non-model organism | ⚠️ MAYBE | We can add common organisms |

---

## Implementation in BioMate

### User Experience

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  🔬 Run DIA-NN Analysis                                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Organism: [Human (Homo sapiens)     ▼]                                     │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  ✅ Pre-computed library available!                                  │   │
│  │                                                                      │   │
│  │  UniProt Human 2024_01                                               │   │
│  │  • 20,385 proteins                                                   │   │
│  │  • 2.8 GB download                                                   │   │
│  │  • Estimated time: 5-10 minutes to download                          │   │
│  │                                                                      │   │
│  │  ○ Use pre-computed library (recommended)                            │   │
│  │  ○ Generate new library from FASTA (24-48 hours)                     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  [Upload Raw Files]  [Start Analysis]                                       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Workflow Modification

```nextflow
// In nf-core/quantms DIA workflow

workflow DIA_PROTEOMICS_ANALYSIS {
    take:
    ch_input
    ch_fasta

    main:

    // NEW: Check for pre-computed library
    if (params.precomputed_speclib) {
        // User provided pre-computed library path
        ch_speclib = Channel.fromPath(params.precomputed_speclib)
    } else if (params.organism && PRECOMPUTED_AVAILABLE[params.organism]) {
        // Auto-download for common organisms
        DOWNLOAD_PRECOMPUTED_LIBRARY(params.organism)
        ch_speclib = DOWNLOAD_PRECOMPUTED_LIBRARY.out.speclib
    } else {
        // Fall back to generation (slow)
        DIANN_INSILICOLIBRARYGENERATION(ch_fasta)
        ch_speclib = DIANN_INSILICOLIBRARYGENERATION.out.predict_speclib
    }

    // Rest of workflow uses ch_speclib...
    DIANN_PRELIMINARYANALYSIS(ch_input, ch_speclib)
    // ...
}
```

---

## Cost-Benefit Analysis

### Time Savings

| Scenario | Without Pre-computed | With Pre-computed | Savings |
|----------|---------------------|-------------------|---------|
| First analysis (human) | 48 hours | 4 hours | 44 hours |
| Repeat analysis (same FASTA) | 48 hours | 2 hours | 46 hours |
| 10 samples (human) | 48 + 10×2 = 68 hours | 0.5 + 10×2 = 20.5 hours | 47.5 hours |

### Storage Costs

| Organism | Library Size | Cloud Storage/Month |
|----------|--------------|---------------------|
| Human | 2.8 GB | $0.07 |
| Mouse | 2.5 GB | $0.06 |
| Yeast | 0.8 GB | $0.02 |
| All common organisms | ~15 GB | $0.35 |

**Cost is negligible compared to compute time saved.**

---

## Summary

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          PRE-COMPUTED LIBRARY SUMMARY                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  WHAT: A spectral library containing predicted MS2 spectra for all         │
│        peptides in a proteome (e.g., human UniProt)                         │
│                                                                             │
│  WHY: DIA-NN needs this library to identify proteins from DIA data          │
│       Generating it takes 24-48 hours due to deep learning predictions      │
│                                                                             │
│  HOW: Generate once, store in cloud, download when needed                   │
│       Skip the 48-hour generation step for common organisms                 │
│                                                                             │
│  RESULT: 2 days → 2-4 hours (10-20x faster)                                 │
│                                                                             │
│  LIMITATION: Only works for standard proteomes with standard modifications  │
│              Custom FASTAs still need library generation                    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```
