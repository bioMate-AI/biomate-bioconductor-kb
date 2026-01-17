# Biomni Docker Tool Test Results

**Date:** 2026-01-16
**Purpose:** Verify Biomni tools work in Docker and identify unique value

## Summary

Biomni Docker container (`biomate/biomni-tools:latest`) successfully executes unique analysis tools that are NOT available in standard Galaxy toolshed.

## Test Results

### Passed Tests (Unique Biomni Tools)

| Tool | Module | Test | Result |
|------|--------|------|--------|
| `find_restriction_sites` | molecular_biology | Find EcoRI, HindIII, BamHI sites | ✅ PASS |
| `find_n_glycosylation_motifs` | glycoengineering | Find N-X-[S/T] sequons | ✅ PASS |
| `analyze_enzyme_kinetics_assay` | biochemistry | Michaelis-Menten kinetics | ✅ PASS |
| `design_primer` | molecular_biology | Design PCR primers | ✅ PASS |
| `model_bacterial_growth_dynamics` | microbiology | Population dynamics ODE | ✅ PASS |

### Tool Categories Available

```json
{
  "molecular_biology": [
    "align_sequences",
    "annotate_open_reading_frames",
    "annotate_plasmid",
    "design_golden_gate_oligos",
    "design_knockout_sgrna",
    "design_primer",
    "design_verification_primers",
    "digest_sequence",
    "find_restriction_enzymes",
    "find_restriction_sites",
    "find_sequence_mutations",
    "get_bacterial_transformation_protocol",
    "get_gene_coding_sequence",
    "get_golden_gate_assembly_protocol",
    "get_oligo_annealing_protocol",
    "get_plasmid_sequence",
    "golden_gate_assembly",
    "pcr_simple"
  ],
  "biochemistry": [
    "analyze_circular_dichroism_spectra",
    "analyze_enzyme_kinetics_assay",
    "analyze_itc_binding_thermodynamics",
    "analyze_protease_kinetics",
    "analyze_protein_conservation",
    "analyze_rna_secondary_structure_features"
  ],
  "microbiology": [
    "analyze_arsenic_speciation_hplc_icpms",
    "annotate_bacterial_genome",
    "count_bacterial_colonies",
    "enumerate_bacterial_cfu_by_serial_dilution",
    "model_bacterial_growth_dynamics",
    "optimize_anaerobic_digestion_process",
    "predict_rna_secondary_structure",
    "quantify_biofilm_biomass_crystal_violet",
    "segment_and_analyze_microbial_cells",
    "segment_cells_with_deep_learning",
    "simulate_generalized_lotka_volterra_dynamics",
    "simulate_microbial_population_dynamics"
  ],
  "genetics": [
    "analyze_cas9_mutation_outcomes",
    "analyze_crispr_genome_editing",
    "analyze_protein_phylogeny",
    "bayesian_finemapping_with_deep_vi",
    "fit_genomic_prediction_model",
    "identify_transcription_factor_binding_sites",
    "liftover_coordinates",
    "perform_pcr_and_gel_electrophoresis",
    "simulate_demographic_history"
  ],
  "synthetic_biology": [
    "analyze_bacterial_growth_rate",
    "analyze_barcode_sequencing_data",
    "analyze_bifurcation_diagram",
    "create_biochemical_network_sbml_model",
    "engineer_bacterial_genome_for_therapeutic_delivery",
    "identify_fas_functional_domains",
    "optimize_codons_for_heterologous_expression",
    "simulate_gene_circuit_with_growth_feedback"
  ],
  "glycoengineering": [
    "find_n_glycosylation_motifs",
    "list_glycoengineering_resources",
    "predict_o_glycosylation_hotspots"
  ]
}
```

## Docker Image Status

### Current Image
- **Image:** `biomate/biomni-tools:latest`
- **Size:** 6.52GB
- **Status:** Contains old code with query functions

### Action Required
The Docker image needs to be rebuilt to sync with cleaned Biomni code:
- Remove query_* functions (now handled by Galaxy biomate_ds_api_* tools)
- Remove LLM-dependent functions (advanced_web_search_claude, etc.)

## Galaxy Tool Wrapper Integration

Galaxy tool wrappers exist at:
```
Biomni/biomni_galaxy/tools/biomni/
├── biochemistry/
├── bioengineering/
├── bioimaging/
├── biophysics/
├── cancer_biology/
├── cell_biology/
├── database/           # Should be removed or use biomate_ds_api_* instead
├── genetics/
├── glycoengineering/
├── microbiology/
├── molecular_biology/
├── pharmacology/
└── synthetic_biology/
```

### Example Tool Wrapper

```xml
<tool id="biomni_molecular_biology_find_restriction_sites"
      name="Biomni: Find Restriction Sites" version="1.0.0">
    <requirements>
        <container type="docker">biomate/biomni-tools:latest</container>
    </requirements>
    <command>
python -c "
from biomni.tool.molecular_biology import find_restriction_sites
result = find_restriction_sites(**args)
..."
    </command>
</tool>
```

## Indexed Workflows

275 Biomni workflows indexed as Galaxy `.ga` files:
```
backend/biomni_workflows/galaxy/subworkflows/
├── database/           # 25 workflows (use biomate_ds_api_* instead)
├── genomics/           # 30 workflows
├── molecular_biology/  # 26 workflows
├── pharmacology/       # 10+ workflows
└── ...
```

## Why We Need Biomni

### Unique Value (Keep)
1. **Molecular Biology** - Primers, restriction sites, cloning protocols
2. **Biochemistry** - Enzyme kinetics, CD spectra analysis
3. **Glycoengineering** - N/O-glycosylation prediction
4. **Microbiology** - Growth modeling, population dynamics
5. **Synthetic Biology** - Gene circuit simulation, codon optimization
6. **Genetics** - CRISPR analysis, phylogenetics

### Deprecated (Use Galaxy Instead)
1. **Database Queries** - Use `biomate_ds_api_*` Galaxy tools
2. **Literature Search** - Use PubMed Galaxy tool
3. **Web Search** - Removed (LLM-dependent)

## Recommendations

1. **Rebuild Docker Image** - Sync with cleaned Biomni code
2. **Remove database/*.xml wrappers** - Use biomate_ds_api_* tools instead
3. **Keep unique analysis tools** - These provide value not available in Galaxy toolshed
4. **Test workflows end-to-end** - Verify indexed workflows execute correctly

## Test Commands

```bash
# Test restriction site analysis
docker run --rm biomate/biomni-tools:latest python -c "
from biomni.tool.molecular_biology import find_restriction_sites
result = find_restriction_sites('GAATTCAAGCTTGAATTC', ['EcoRI', 'HindIII'], is_circular=False)
print(result)
"

# Test glycosylation prediction
docker run --rm biomate/biomni-tools:latest python -c "
from biomni.tool.glycoengineering import find_n_glycosylation_motifs
result = find_n_glycosylation_motifs('MNFTHGLSPAAGTSTLNQTALQ')
print(result)
"

# Test enzyme kinetics
docker run --rm biomate/biomni-tools:latest python -c "
from biomni.tool.biochemistry import analyze_enzyme_kinetics_assay
result = analyze_enzyme_kinetics_assay('Lysozyme', [0.1,0.5,1,2,5,10], 50.0)
print(result)
"
```
