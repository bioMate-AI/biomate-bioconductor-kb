# Biomni Tool Value Analysis

**Date:** 2026-01-16
**Purpose:** Analyze what unique value Biomni tools provide vs Galaxy

## Summary

Biomni provides **172 unique analysis tools** that are NOT available in standard Galaxy toolshed.

## Tool Categories

| Category | Count | Galaxy Alternative? |
|----------|-------|---------------------|
| Data Source (query) | 48 | ✅ Use `biomate_ds_api_*` instead |
| Computational chemistry | 23 | ⚠️ Partial (AutoDock, drug-likeness) |
| Single Cell | 19 | ⚠️ Partial (Scanpy exists) |
| Sequence Analysis | 18 | ⚠️ Partial |
| Imaging | 17 | ❌ Unique |
| Metagenomics | 12 | ⚠️ Partial |
| Physiology | 11 | ❌ Unique |
| Immunology | 10 | ❌ Unique |
| Population Genetics | 9 | ⚠️ Partial |
| Synthetic Biology | 8 | ❌ Unique |
| Utilities | 8 | ⚠️ Partial |
| Bioengineering | 7 | ❌ Unique |
| Systems Biology | 7 | ❌ Unique |
| Biochemistry | 6 | ❌ Unique |
| Cancer Biology | 6 | ⚠️ Partial |
| Cell Biology | 5 | ❌ Unique |
| Biophysics | 3 | ❌ Unique |
| Glycoengineering | 3 | ❌ Unique |

## Unique Biomni Tools (No Galaxy Equivalent)

### Molecular Biology
- `find_restriction_sites` - Find restriction enzyme cut sites
- `design_primer` - Design PCR primers
- `find_restriction_enzymes` - Find compatible enzymes
- `digest_sequence` - Virtual restriction digest
- `golden_gate_assembly` - Golden Gate cloning simulation
- `design_verification_primers` - Colony PCR primers

### Biochemistry
- `analyze_enzyme_kinetics_assay` - Michaelis-Menten kinetics
- `analyze_circular_dichroism_spectra` - CD spectroscopy analysis
- `analyze_protease_kinetics` - Protease activity analysis
- `analyze_protein_conservation` - Conservation scoring

### Glycoengineering
- `find_n_glycosylation_motifs` - N-linked glycosylation sites
- `predict_o_glycosylation_hotspots` - O-linked glycosylation
- `list_glycoengineering_resources` - Database resources

### Microbiology
- `predict_rna_secondary_structure` - RNA folding (ViennaRNA)
- `simulate_microbial_population_dynamics` - Population modeling
- `model_bacterial_growth_dynamics` - Growth curves
- `enumerate_bacterial_cfu_by_serial_dilution` - CFU counting

### Biophysics
- `predict_protein_disorder_regions` - IUPred disorder prediction

### Pharmacology
- `calculate_physicochemical_properties` - RDKit properties
- `predict_admet_properties` - DeepPurpose ADMET
- `check_drug_combination_safety` - Drug interactions
- `docking_autodock_vina` - Molecular docking
- `run_diffdock_with_smiles` - DiffDock AI docking

### Synthetic Biology
- `analyze_bacterial_growth_rate` - Growth rate analysis
- `optimize_codons_for_heterologous_expression` - Codon optimization
- `simulate_gene_circuit_with_growth_feedback` - Circuit simulation

## Tools to REMOVE from Biomni (Duplicates)

All `query_*` functions - Use Galaxy `biomate_ds_api_*` tools instead:
- ✅ DONE: Removed from `database.py`
- ✅ DONE: Removed from `literature.py`

## Recommendation

**Keep Biomni for unique analysis tools:**
- Molecular biology (primers, restriction sites, cloning)
- Biochemistry (kinetics, CD spectra)
- Glycoengineering
- Microbiology (RNA structure, growth modeling)
- Pharmacology (ADMET, docking)
- Synthetic biology

**Use Galaxy for:**
- Database queries (UniProt, PDB, KEGG, etc.)
- Standard NGS pipelines
- Visualization

## Test Results

```
✅ glycoengineering.find_n_glycosylation_motifs - Working
✅ molecular_biology.find_restriction_sites - Working
✅ microbiology.predict_rna_secondary_structure - Working (needs ViennaRNA)
⚠️ pharmacology.calculate_physicochemical_properties - Returns string not dict
```
