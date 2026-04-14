#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_design_verification_primers
 * Design Sanger sequencing primers to verify a specific region in a plasmid.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.plasmid_sequence = null
params.target_region = null
params.existing_primers = null
params.is_circular = false
params.coverage_length = 800
params.primer_length = 20
params.min_gc = 0.4
params.max_gc = 0.6
params.min_tm = 55.0
params.max_tm = 65.0

// Main process
process DESIGN_VERIFICATION_PRIMERS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("design_verification_primers_results.json"), emit: results
    path("design_verification_primers_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.molecular_biology import design_verification_primers

# Run the tool
try:
    result = design_verification_primers(
    plasmid_sequence="${params.plasmid_sequence}",
    target_region="${params.target_region}",
    existing_primers="${params.existing_primers}",
    is_circular=${params.is_circular ? "True" : "False"},
    coverage_length=${params.coverage_length},
    primer_length=${params.primer_length},
    min_gc=${params.min_gc},
    max_gc=${params.max_gc},
    min_tm=${params.min_tm},
    max_tm=${params.max_tm}
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("design_verification_primers_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("design_verification_primers_output.txt", "w") as f:
    f.write("Biomni: Design Verification Primers Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("design_verification_primers completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MOLECULAR_BIOLOGY_DESIGN_VERIFICATION_PRIMERS {
    take:
    // No file inputs

    main:
    DESIGN_VERIFICATION_PRIMERS()

    emit:
    results = DESIGN_VERIFICATION_PRIMERS.out.results
    output = DESIGN_VERIFICATION_PRIMERS.out.output
}

// Entry workflow
workflow {
    if (!params.plasmid_sequence) {
        error "Please provide --plasmid_sequence parameter"
    }
    if (!params.target_region) {
        error "Please provide --target_region parameter"
    }


    BIOMNI_MOLECULAR_BIOLOGY_DESIGN_VERIFICATION_PRIMERS()
}
