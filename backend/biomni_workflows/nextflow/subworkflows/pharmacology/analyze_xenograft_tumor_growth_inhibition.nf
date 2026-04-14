#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_analyze_xenograft_tumor_growth_inhibition
 * Analyze tumor growth inhibition in xenograft models across different treatment groups.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.data_path = null
params.time_column = null
params.volume_column = null
params.group_column = null
params.subject_column = null
params.output_dir = './results'

// Main process
process ANALYZE_XENOGRAFT_TUMOR_GROWTH_INHIBITION {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_xenograft_tumor_growth_inhibition_results.json"), emit: results
    path("analyze_xenograft_tumor_growth_inhibition_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.pharmacology import analyze_xenograft_tumor_growth_inhibition

# Run the tool
try:
    result = analyze_xenograft_tumor_growth_inhibition(
    data_path="${params.data_path}",
    time_column="${params.time_column}",
    volume_column="${params.volume_column}",
    group_column="${params.group_column}",
    subject_column="${params.subject_column}",
    output_dir="${params.output_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_xenograft_tumor_growth_inhibition_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("analyze_xenograft_tumor_growth_inhibition_output.txt", "w") as f:
    f.write("Biomni: Analyze Xenograft Tumor Growth Inhibition Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("analyze_xenograft_tumor_growth_inhibition completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHARMACOLOGY_ANALYZE_XENOGRAFT_TUMOR_GROWTH_INHIBITION {
    take:
    // No file inputs

    main:
    ANALYZE_XENOGRAFT_TUMOR_GROWTH_INHIBITION()

    emit:
    results = ANALYZE_XENOGRAFT_TUMOR_GROWTH_INHIBITION.out.results
    output = ANALYZE_XENOGRAFT_TUMOR_GROWTH_INHIBITION.out.output
}

// Entry workflow
workflow {
    if (!params.data_path) {
        error "Please provide --data_path parameter"
    }
    if (!params.time_column) {
        error "Please provide --time_column parameter"
    }
    if (!params.volume_column) {
        error "Please provide --volume_column parameter"
    }
    if (!params.group_column) {
        error "Please provide --group_column parameter"
    }
    if (!params.subject_column) {
        error "Please provide --subject_column parameter"
    }


    BIOMNI_PHARMACOLOGY_ANALYZE_XENOGRAFT_TUMOR_GROWTH_INHIBITION()
}
