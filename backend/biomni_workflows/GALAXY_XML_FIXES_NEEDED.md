# Galaxy XML Fixes Needed

Issues found during Nextflow workflow generation that should be fixed in Galaxy XML files.

## Issue 1: Unescaped Double Quotes in Attributes

Many XML files have unescaped double quotes inside attribute values, which breaks XML parsing.

**Example (broken):**
```xml
<param help="... (default: "glv_simulation_results.csv")" />
```

**Should be:**
```xml
<param help="... (default: 'glv_simulation_results.csv')" />
```
or
```xml
<param help="... (default: &quot;glv_simulation_results.csv&quot;)" />
```

**Affected files:**
- microbiology/simulate_generalized_lotka_volterra_dynamics.xml (line 22)
- microbiology/count_bacterial_colonies.xml (line 24)
- microbiology/annotate_bacterial_genome.xml (line 28)
- microbiology/predict_rna_secondary_structure.xml (line 16)
- microbiology/analyze_arsenic_speciation_hplc_icpms.xml (line 19)
- physiology/analyze_fatty_acid_composition_by_gc.xml (line 20)
- physiology/calculate_brain_adc_map.xml (line 21)
- physiology/analyze_hemodynamic_data.xml (line 18)
- physiology/analyze_protein_colocalization.xml (line 21)
- biophysics/analyze_tissue_deformation_flow.xml (line 19)
- biophysics/predict_protein_disorder_regions.xml (line 20)
- pathology/analyze_aortic_diameter_and_geometry.xml (line 16)
- pathology/analyze_intracellular_calcium_with_rhod2.xml (line 20)
- pathology/analyze_thrombus_histology.xml (line 16)
- pathology/analyze_bone_microct_morphometry.xml (line 19)
- pathology/segment_and_quantify_cells_in_multiplexed_images.xml (line 22)
- immunology/analyze_immunohistochemistry_image.xml (line 19)
- immunology/analyze_atac_seq_differential_accessibility.xml (line 27)
- immunology/analyze_cns_lesion_histology.xml (line 19)
- synthetic_biology/analyze_bacterial_growth_rate.xml (line 21)
- synthetic_biology/create_biochemical_network_sbml_model.xml (line 18)
- synthetic_biology/identify_fas_functional_domains.xml (line 19)
- genetics/analyze_protein_phylogeny.xml (line 23)
- genetics/fit_genomic_prediction_model.xml (line 25)
- genetics/simulate_demographic_history.xml (line 45)
- biochemistry/analyze_protein_conservation.xml (line 16)
- biochemistry/analyze_circular_dichroism_spectra.xml (line 24)
- biochemistry/analyze_protease_kinetics.xml (line 25)
- systems_biology/compare_protein_structures.xml (line 26)

## Issue 2: Unescaped Less-Than and Greater-Than Characters

Some XML files have unescaped `<` and `>` characters in attribute values, which breaks XML parsing because `<` is interpreted as starting a new tag.

**Example (broken):**
```xml
<param help="... ('Lin', '<', 100), ('Sca1', '>', 1000) ..." />
```

**Should be:**
```xml
<param help="... ('Lin', '&lt;', 100), ('Sca1', '&gt;', 1000) ..." />
```

**Affected files (FIXED):**
- cell_biology/analyze_flow_cytometry_immunophenotyping.xml (line 20) - Fixed

## Issue 3: Function Names in Wrappers

Some wrapper scripts define the main function inside `main()` or with a different name than expected.

**Affected functions (need wrapper review):**
- Many wrappers where the function is not extractable

## Recommended Fix Script

```bash
# Fix unescaped quotes in help attributes
find biomni_workflows/galaxy/tools/biomni -name "*.xml" -exec sed -i 's/help="\([^"]*\)"\([^"]*\)"/help="\1'"'"'\2'"'"'"/g' {} \;
```

## Impact

- 30+ XML files have parsing issues
- These cannot be converted to Nextflow until fixed
- Galaxy may also have issues loading these tools

## Current Status

The Nextflow generator (`lib/galaxy/ai/generate_nfcore_biomni.py`) now includes automatic fixes for these issues:
- `fix_xml_quotes()` function automatically replaces embedded double quotes with single quotes during generation
- All 237 workflows now generate successfully

However, **the Galaxy XML files themselves should still be fixed** to ensure they work correctly in Galaxy.

## Generator Fixes Applied

The generator (`generate_nfcore_biomni.py`) includes:
1. **Smart dependency extraction** - Only includes helper functions that are actually called by the main function
2. **Quote escaping in parameters** - Properly escapes double quotes in Nextflow parameter exports
3. **JSON/list support** - Auto-converts JSON strings like `'["EcoRI"]'` to Python lists
4. **Type conversion** - Automatically converts string parameters to int/float/bool as needed
