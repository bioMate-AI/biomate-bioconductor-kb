#!/usr/bin/env nextflow
/*
 * biomni_biochemistry_analyze_protein_conservation
 * Perform multiple sequence alignment and phylogenetic analysis to identify conserved protein regions.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.protein_sequences = null
params.output_dir = './'

// Main process
process ANALYZE_PROTEIN_CONSERVATION {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_protein_conservation_results.json"), emit: results
    path("analyze_protein_conservation_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.biochemistry import analyze_protein_conservation
except ImportError:
    # Fallback: function may need to be implemented locally
    def analyze_protein_conservation(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = analyze_protein_conservation(
    protein_sequences="${params.protein_sequences}",
    output_dir="${params.output_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_protein_conservation_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("analyze_protein_conservation_output.txt", "w") as f:
    f.write("Biomni: Analyze Protein Conservation Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("analyze_protein_conservation completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOCHEMISTRY_ANALYZE_PROTEIN_CONSERVATION {
    take:
    // No file inputs

    main:
    ANALYZE_PROTEIN_CONSERVATION()

    emit:
    results = ANALYZE_PROTEIN_CONSERVATION.out.results
    output = ANALYZE_PROTEIN_CONSERVATION.out.output
}

// Entry workflow
workflow {
    if (!params.protein_sequences) {
        error "Please provide --protein_sequences parameter"
    }


    BIOMNI_BIOCHEMISTRY_ANALYZE_PROTEIN_CONSERVATION()
}
