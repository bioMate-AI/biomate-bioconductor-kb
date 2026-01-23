#!/usr/bin/env nextflow
/*
 * biomni_genomics_annotate_celltype_with_panhumanpy
 * Perform hierarchical cell type annotation using panhumanpy and Azimuth Neural Network.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.adata_path = null
params.feature_names_col = null
params.refine = 'True'
params.umap = 'True'
params.output_dir = './output'

// Main process
process ANNOTATE_CELLTYPE_WITH_PANHUMANPY {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("annotate_celltype_with_panhumanpy_results.json"), emit: results
    path("annotate_celltype_with_panhumanpy_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.genomics import annotate_celltype_with_panhumanpy

# Run the tool
try:
    result = annotate_celltype_with_panhumanpy(
    adata_path="${params.adata_path}",
    feature_names_col="${params.feature_names_col}",
    refine="${params.refine}",
    umap="${params.umap}",
    output_dir="${params.output_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("annotate_celltype_with_panhumanpy_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("annotate_celltype_with_panhumanpy_output.txt", "w") as f:
    f.write("Biomni: Annotate Celltype With Panhumanpy Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("annotate_celltype_with_panhumanpy completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENOMICS_ANNOTATE_CELLTYPE_WITH_PANHUMANPY {
    take:
    // No file inputs

    main:
    ANNOTATE_CELLTYPE_WITH_PANHUMANPY()

    emit:
    results = ANNOTATE_CELLTYPE_WITH_PANHUMANPY.out.results
    output = ANNOTATE_CELLTYPE_WITH_PANHUMANPY.out.output
}

// Entry workflow
workflow {
    if (!params.adata_path) {
        error "Please provide --adata_path parameter"
    }


    BIOMNI_GENOMICS_ANNOTATE_CELLTYPE_WITH_PANHUMANPY()
}
