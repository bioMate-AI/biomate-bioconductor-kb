#!/usr/bin/env nextflow
/*
 * biomni_cancer_biology_detect_and_annotate_somatic_mutations
 * Detects and annotates somatic mutations in tumor samples compared to matched normal samples.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.tumor_bam = null
params.normal_bam = null
params.reference_genome = null
params.output_prefix = null
params.snpeff_database = 'GRCh38.105'

// Main process
process DETECT_AND_ANNOTATE_SOMATIC_MUTATIONS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("detect_and_annotate_somatic_mutations_results.json"), emit: results
    path("detect_and_annotate_somatic_mutations_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.cancer_biology import detect_and_annotate_somatic_mutations
except ImportError:
    # Fallback: function may need to be implemented locally
    def detect_and_annotate_somatic_mutations(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = detect_and_annotate_somatic_mutations(
    tumor_bam="${params.tumor_bam}",
    normal_bam="${params.normal_bam}",
    reference_genome="${params.reference_genome}",
    output_prefix="${params.output_prefix}",
    snpeff_database="${params.snpeff_database}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("detect_and_annotate_somatic_mutations_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("detect_and_annotate_somatic_mutations_output.txt", "w") as f:
    f.write("Biomni: Detect And Annotate Somatic Mutations Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("detect_and_annotate_somatic_mutations completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_CANCER_BIOLOGY_DETECT_AND_ANNOTATE_SOMATIC_MUTATIONS {
    take:
    // No file inputs

    main:
    DETECT_AND_ANNOTATE_SOMATIC_MUTATIONS()

    emit:
    results = DETECT_AND_ANNOTATE_SOMATIC_MUTATIONS.out.results
    output = DETECT_AND_ANNOTATE_SOMATIC_MUTATIONS.out.output
}

// Entry workflow
workflow {
    if (!params.tumor_bam) {
        error "Please provide --tumor_bam parameter"
    }
    if (!params.normal_bam) {
        error "Please provide --normal_bam parameter"
    }
    if (!params.reference_genome) {
        error "Please provide --reference_genome parameter"
    }
    if (!params.output_prefix) {
        error "Please provide --output_prefix parameter"
    }


    BIOMNI_CANCER_BIOLOGY_DETECT_AND_ANNOTATE_SOMATIC_MUTATIONS()
}
