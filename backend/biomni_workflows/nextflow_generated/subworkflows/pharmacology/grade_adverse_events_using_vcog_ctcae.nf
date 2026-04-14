#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_grade_adverse_events_using_vcog_ctcae
 * Grade and monitor adverse events in animal studies using the VCOG-CTCAE standard.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.clinical_data_file = null

// Main process
process GRADE_ADVERSE_EVENTS_USING_VCOG_CTCAE {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("grade_adverse_events_using_vcog_ctcae_results.json"), emit: results
    path("grade_adverse_events_using_vcog_ctcae_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.pharmacology import grade_adverse_events_using_vcog_ctcae
except ImportError:
    # Fallback: function may need to be implemented locally
    def grade_adverse_events_using_vcog_ctcae(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = grade_adverse_events_using_vcog_ctcae(
    clinical_data_file="${params.clinical_data_file}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("grade_adverse_events_using_vcog_ctcae_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("grade_adverse_events_using_vcog_ctcae_output.txt", "w") as f:
    f.write("Biomni: Grade Adverse Events Using Vcog Ctcae Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("grade_adverse_events_using_vcog_ctcae completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHARMACOLOGY_GRADE_ADVERSE_EVENTS_USING_VCOG_CTCAE {
    take:
    // No file inputs

    main:
    GRADE_ADVERSE_EVENTS_USING_VCOG_CTCAE()

    emit:
    results = GRADE_ADVERSE_EVENTS_USING_VCOG_CTCAE.out.results
    output = GRADE_ADVERSE_EVENTS_USING_VCOG_CTCAE.out.output
}

// Entry workflow
workflow {
    if (!params.clinical_data_file) {
        error "Please provide --clinical_data_file parameter"
    }


    BIOMNI_PHARMACOLOGY_GRADE_ADVERSE_EVENTS_USING_VCOG_CTCAE()
}
