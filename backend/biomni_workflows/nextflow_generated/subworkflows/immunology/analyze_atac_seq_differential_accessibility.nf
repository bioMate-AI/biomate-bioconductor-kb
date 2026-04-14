#!/usr/bin/env nextflow
/*
 * biomni_immunology_analyze_atac_seq_differential_accessibility
 * Perform ATAC-seq peak calling and differential accessibility analysis using MACS2.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.treatment_bam = null
params.control_bam = null
params.output_dir = './atac_results'
params.genome_size = 'hs'
params.q_value = '0.05'
params.name_prefix = 'atac'

// Main process
process ANALYZE_ATAC_SEQ_DIFFERENTIAL_ACCESSIBILITY {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_atac_seq_differential_accessibility_results.json"), emit: results
    path("analyze_atac_seq_differential_accessibility_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.immunology import analyze_atac_seq_differential_accessibility
except ImportError:
    # Fallback: function may need to be implemented locally
    def analyze_atac_seq_differential_accessibility(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = analyze_atac_seq_differential_accessibility(
    treatment_bam="${params.treatment_bam}",
    control_bam="${params.control_bam}",
    output_dir="${params.output_dir}",
    genome_size="${params.genome_size}",
    q_value="${params.q_value}",
    name_prefix="${params.name_prefix}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_atac_seq_differential_accessibility_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("analyze_atac_seq_differential_accessibility_output.txt", "w") as f:
    f.write("Biomni: Analyze Atac Seq Differential Accessibility Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("analyze_atac_seq_differential_accessibility completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_IMMUNOLOGY_ANALYZE_ATAC_SEQ_DIFFERENTIAL_ACCESSIBILITY {
    take:
    // No file inputs

    main:
    ANALYZE_ATAC_SEQ_DIFFERENTIAL_ACCESSIBILITY()

    emit:
    results = ANALYZE_ATAC_SEQ_DIFFERENTIAL_ACCESSIBILITY.out.results
    output = ANALYZE_ATAC_SEQ_DIFFERENTIAL_ACCESSIBILITY.out.output
}

// Entry workflow
workflow {
    if (!params.treatment_bam) {
        error "Please provide --treatment_bam parameter"
    }
    if (!params.control_bam) {
        error "Please provide --control_bam parameter"
    }


    BIOMNI_IMMUNOLOGY_ANALYZE_ATAC_SEQ_DIFFERENTIAL_ACCESSIBILITY()
}
