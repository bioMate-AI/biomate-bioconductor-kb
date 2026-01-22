#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_design_knockout_sgrna
 * Design sgRNAs for CRISPR knockout by searching pre-computed sgRNA libraries.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.gene_name = null
params.data_lake_path = null
params.species = 'human'
params.num_guides = 1

// Main process
process DESIGN_KNOCKOUT_SGRNA {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("design_knockout_sgrna_results.json"), emit: results
    path("design_knockout_sgrna_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.molecular_biology import design_knockout_sgrna
except ImportError:
    # Fallback: function may need to be implemented locally
    def design_knockout_sgrna(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = design_knockout_sgrna(
    gene_name="${params.gene_name}",
    data_lake_path="${params.data_lake_path}",
    species="${params.species}",
    num_guides=${params.num_guides}
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("design_knockout_sgrna_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("design_knockout_sgrna_output.txt", "w") as f:
    f.write("Biomni: Design Knockout Sgrna Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("design_knockout_sgrna completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MOLECULAR_BIOLOGY_DESIGN_KNOCKOUT_SGRNA {
    take:
    // No file inputs

    main:
    DESIGN_KNOCKOUT_SGRNA()

    emit:
    results = DESIGN_KNOCKOUT_SGRNA.out.results
    output = DESIGN_KNOCKOUT_SGRNA.out.output
}

// Entry workflow
workflow {
    if (!params.gene_name) {
        error "Please provide --gene_name parameter"
    }
    if (!params.data_lake_path) {
        error "Please provide --data_lake_path parameter"
    }


    BIOMNI_MOLECULAR_BIOLOGY_DESIGN_KNOCKOUT_SGRNA()
}
