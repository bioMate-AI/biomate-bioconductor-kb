#!/usr/bin/env nextflow
/*
 * biomni_cancer_biology_detect_and_characterize_structural_variations
 * Detects and characterizes structural variations (SVs) in genomic sequencing data.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.bam_file_path = null
params.reference_genome_path = null
params.output_dir = null
params.cosmic_db_path = null
params.clinvar_db_path = null

// Main process
process DETECT_AND_CHARACTERIZE_STRUCTURAL_VARIATIONS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("detect_and_characterize_structural_variations_results.json"), emit: results
    path("detect_and_characterize_structural_variations_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.cancer_biology import detect_and_characterize_structural_variations

# Run the tool
try:
    result = detect_and_characterize_structural_variations(
    bam_file_path="${params.bam_file_path}",
    reference_genome_path="${params.reference_genome_path}",
    output_dir="${params.output_dir}",
    cosmic_db_path="${params.cosmic_db_path}",
    clinvar_db_path="${params.clinvar_db_path}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("detect_and_characterize_structural_variations_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("detect_and_characterize_structural_variations_output.txt", "w") as f:
    f.write("Biomni: Detect And Characterize Structural Variations Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("detect_and_characterize_structural_variations completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_CANCER_BIOLOGY_DETECT_AND_CHARACTERIZE_STRUCTURAL_VARIATIONS {
    take:
    // No file inputs

    main:
    DETECT_AND_CHARACTERIZE_STRUCTURAL_VARIATIONS()

    emit:
    results = DETECT_AND_CHARACTERIZE_STRUCTURAL_VARIATIONS.out.results
    output = DETECT_AND_CHARACTERIZE_STRUCTURAL_VARIATIONS.out.output
}

// Entry workflow
workflow {
    if (!params.bam_file_path) {
        error "Please provide --bam_file_path parameter"
    }
    if (!params.reference_genome_path) {
        error "Please provide --reference_genome_path parameter"
    }
    if (!params.output_dir) {
        error "Please provide --output_dir parameter"
    }


    BIOMNI_CANCER_BIOLOGY_DETECT_AND_CHARACTERIZE_STRUCTURAL_VARIATIONS()
}
