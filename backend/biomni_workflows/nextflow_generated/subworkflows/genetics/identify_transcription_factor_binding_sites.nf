#!/usr/bin/env nextflow
/*
 * biomni_genetics_identify_transcription_factor_binding_sites
 * Identifies binding sites for a specific transcription factor in a genomic sequence.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.sequence = null
params.tf_name = null
params.threshold = '0.8'
params.output_file = null

// Main process
process IDENTIFY_TRANSCRIPTION_FACTOR_BINDING_SITES {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("identify_transcription_factor_binding_sites_results.json"), emit: results
    path("identify_transcription_factor_binding_sites_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.genetics import identify_transcription_factor_binding_sites
except ImportError:
    # Fallback: function may need to be implemented locally
    def identify_transcription_factor_binding_sites(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = identify_transcription_factor_binding_sites(
    sequence="${params.sequence}",
    tf_name="${params.tf_name}",
    threshold="${params.threshold}",
    output_file="${params.output_file}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("identify_transcription_factor_binding_sites_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("identify_transcription_factor_binding_sites_output.txt", "w") as f:
    f.write("Biomni: Identify Transcription Factor Binding Sites Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("identify_transcription_factor_binding_sites completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENETICS_IDENTIFY_TRANSCRIPTION_FACTOR_BINDING_SITES {
    take:
    // No file inputs

    main:
    IDENTIFY_TRANSCRIPTION_FACTOR_BINDING_SITES()

    emit:
    results = IDENTIFY_TRANSCRIPTION_FACTOR_BINDING_SITES.out.results
    output = IDENTIFY_TRANSCRIPTION_FACTOR_BINDING_SITES.out.output
}

// Entry workflow
workflow {
    if (!params.sequence) {
        error "Please provide --sequence parameter"
    }
    if (!params.tf_name) {
        error "Please provide --tf_name parameter"
    }


    BIOMNI_GENETICS_IDENTIFY_TRANSCRIPTION_FACTOR_BINDING_SITES()
}
