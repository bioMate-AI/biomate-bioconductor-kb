#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_apply_vcog_grade
 * Apply VCOG-CTCAE grading criteria to an adverse event.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.symptom = null
params.severity = null
params.measurement = null

// Main process
process APPLY_VCOG_GRADE {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("apply_vcog_grade_results.json"), emit: results
    path("apply_vcog_grade_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.pharmacology import apply_vcog_grade

# Run the tool
try:
    result = apply_vcog_grade(
    symptom="${params.symptom}",
    severity="${params.severity}",
    measurement="${params.measurement}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("apply_vcog_grade_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("apply_vcog_grade_output.txt", "w") as f:
    f.write("Biomni: Apply Vcog Grade Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("apply_vcog_grade completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHARMACOLOGY_APPLY_VCOG_GRADE {
    take:
    // No file inputs

    main:
    APPLY_VCOG_GRADE()

    emit:
    results = APPLY_VCOG_GRADE.out.results
    output = APPLY_VCOG_GRADE.out.output
}

// Entry workflow
workflow {
    if (!params.symptom) {
        error "Please provide --symptom parameter"
    }
    if (!params.severity) {
        error "Please provide --severity parameter"
    }


    BIOMNI_PHARMACOLOGY_APPLY_VCOG_GRADE()
}
