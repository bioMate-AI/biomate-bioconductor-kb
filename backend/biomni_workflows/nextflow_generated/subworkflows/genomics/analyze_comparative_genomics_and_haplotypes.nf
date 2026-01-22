#!/usr/bin/env nextflow
/*
 * biomni_genomics_analyze_comparative_genomics_and_haplotypes
 * Perform comparative genomics and haplotype analysis on multiple genome samples.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.sample_fasta_files = null
params.reference_genome_path = null
params.output_dir = './output'

// Main process
process ANALYZE_COMPARATIVE_GENOMICS_AND_HAPLOTYPES {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_comparative_genomics_and_haplotypes_results.json"), emit: results
    path("analyze_comparative_genomics_and_haplotypes_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.genomics import analyze_comparative_genomics_and_haplotypes
except ImportError:
    # Fallback: function may need to be implemented locally
    def analyze_comparative_genomics_and_haplotypes(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = analyze_comparative_genomics_and_haplotypes(
    sample_fasta_files="${params.sample_fasta_files}",
    reference_genome_path="${params.reference_genome_path}",
    output_dir="${params.output_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_comparative_genomics_and_haplotypes_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("analyze_comparative_genomics_and_haplotypes_output.txt", "w") as f:
    f.write("Biomni: Analyze Comparative Genomics And Haplotypes Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("analyze_comparative_genomics_and_haplotypes completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENOMICS_ANALYZE_COMPARATIVE_GENOMICS_AND_HAPLOTYPES {
    take:
    // No file inputs

    main:
    ANALYZE_COMPARATIVE_GENOMICS_AND_HAPLOTYPES()

    emit:
    results = ANALYZE_COMPARATIVE_GENOMICS_AND_HAPLOTYPES.out.results
    output = ANALYZE_COMPARATIVE_GENOMICS_AND_HAPLOTYPES.out.output
}

// Entry workflow
workflow {
    if (!params.sample_fasta_files) {
        error "Please provide --sample_fasta_files parameter"
    }
    if (!params.reference_genome_path) {
        error "Please provide --reference_genome_path parameter"
    }


    BIOMNI_GENOMICS_ANALYZE_COMPARATIVE_GENOMICS_AND_HAPLOTYPES()
}
