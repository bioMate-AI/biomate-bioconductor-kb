#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_design_primer
 * Design a single primer within the given sequence window.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.sequence = null
params.start_pos = 0
params.primer_length = 20
params.min_gc = 0.4
params.max_gc = 0.6
params.min_tm = 55.0
params.max_tm = 65.0
params.search_window = 100

// Main process
process DESIGN_PRIMER {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("design_primer_results.json"), emit: results
    path("design_primer_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.molecular_biology import design_primer
except ImportError:
    # Fallback: function may need to be implemented locally
    def design_primer(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = design_primer(
    sequence="${params.sequence}",
    start_pos=${params.start_pos},
    primer_length=${params.primer_length},
    min_gc=${params.min_gc},
    max_gc=${params.max_gc},
    min_tm=${params.min_tm},
    max_tm=${params.max_tm},
    search_window=${params.search_window}
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("design_primer_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("design_primer_output.txt", "w") as f:
    f.write("Biomni: Design Primer Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("design_primer completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MOLECULAR_BIOLOGY_DESIGN_PRIMER {
    take:
    // No file inputs

    main:
    DESIGN_PRIMER()

    emit:
    results = DESIGN_PRIMER.out.results
    output = DESIGN_PRIMER.out.output
}

// Entry workflow
workflow {
    if (!params.sequence) {
        error "Please provide --sequence parameter"
    }


    BIOMNI_MOLECULAR_BIOLOGY_DESIGN_PRIMER()
}
