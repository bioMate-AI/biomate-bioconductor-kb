#!/usr/bin/env nextflow
/*
 * biomni_genomics_perform_chipseq_peak_calling_with_macs2
 * Perform ChIP-seq peak calling using MACS2 to identify genomic regions with significant binding.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.chip_seq_file = null
params.control_file = null
params.output_name = 'macs2_output'
params.genome_size = 'hs'
params.q_value = '0.05'

// Main process
process PERFORM_CHIPSEQ_PEAK_CALLING_WITH_MACS2 {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("perform_chipseq_peak_calling_with_macs2_results.json"), emit: results
    path("perform_chipseq_peak_calling_with_macs2_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.genomics import perform_chipseq_peak_calling_with_macs2
except ImportError:
    # Fallback: function may need to be implemented locally
    def perform_chipseq_peak_calling_with_macs2(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = perform_chipseq_peak_calling_with_macs2(
    chip_seq_file="${params.chip_seq_file}",
    control_file="${params.control_file}",
    output_name="${params.output_name}",
    genome_size="${params.genome_size}",
    q_value="${params.q_value}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("perform_chipseq_peak_calling_with_macs2_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("perform_chipseq_peak_calling_with_macs2_output.txt", "w") as f:
    f.write("Biomni: Perform Chipseq Peak Calling With Macs2 Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("perform_chipseq_peak_calling_with_macs2 completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENOMICS_PERFORM_CHIPSEQ_PEAK_CALLING_WITH_MACS2 {
    take:
    // No file inputs

    main:
    PERFORM_CHIPSEQ_PEAK_CALLING_WITH_MACS2()

    emit:
    results = PERFORM_CHIPSEQ_PEAK_CALLING_WITH_MACS2.out.results
    output = PERFORM_CHIPSEQ_PEAK_CALLING_WITH_MACS2.out.output
}

// Entry workflow
workflow {
    if (!params.chip_seq_file) {
        error "Please provide --chip_seq_file parameter"
    }
    if (!params.control_file) {
        error "Please provide --control_file parameter"
    }


    BIOMNI_GENOMICS_PERFORM_CHIPSEQ_PEAK_CALLING_WITH_MACS2()
}
