#!/usr/bin/env nextflow
/*
 * biomni_cancer_biology_analyze_copy_number_purity_ploidy_and_focal_events
 * CNVkit-based copy number workflow: CNV segmentation, purity/ploidy & HRD approximation, focal events.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.tumor_bam = null
params.reference_genome = null
params.normal_bam = null
params.output_dir = 'cn_analysis_results'
params.targets_bed = null
params.antitargets_bed = null
params.gene_bed = null
params.focal_genes = null
params.log2_amp_threshold = '1.0'
params.log2_del_threshold = null

// Main process
process ANALYZE_COPY_NUMBER_PURITY_PLOIDY_AND_FOCAL_EVENTS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_copy_number_purity_ploidy_and_focal_events_results.json"), emit: results
    path("analyze_copy_number_purity_ploidy_and_focal_events_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.cancer_biology import analyze_copy_number_purity_ploidy_and_focal_events

# Run the tool
try:
    result = analyze_copy_number_purity_ploidy_and_focal_events(
    tumor_bam="${params.tumor_bam}",
    reference_genome="${params.reference_genome}",
    normal_bam="${params.normal_bam}",
    output_dir="${params.output_dir}",
    targets_bed="${params.targets_bed}",
    antitargets_bed="${params.antitargets_bed}",
    gene_bed="${params.gene_bed}",
    focal_genes="${params.focal_genes}",
    log2_amp_threshold="${params.log2_amp_threshold}",
    log2_del_threshold="${params.log2_del_threshold}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_copy_number_purity_ploidy_and_focal_events_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("analyze_copy_number_purity_ploidy_and_focal_events_output.txt", "w") as f:
    f.write("Biomni: Analyze Copy Number Purity Ploidy And Focal Events Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("analyze_copy_number_purity_ploidy_and_focal_events completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_CANCER_BIOLOGY_ANALYZE_COPY_NUMBER_PURITY_PLOIDY_AND_FOCAL_EVENTS {
    take:
    // No file inputs

    main:
    ANALYZE_COPY_NUMBER_PURITY_PLOIDY_AND_FOCAL_EVENTS()

    emit:
    results = ANALYZE_COPY_NUMBER_PURITY_PLOIDY_AND_FOCAL_EVENTS.out.results
    output = ANALYZE_COPY_NUMBER_PURITY_PLOIDY_AND_FOCAL_EVENTS.out.output
}

// Entry workflow
workflow {
    if (!params.tumor_bam) {
        error "Please provide --tumor_bam parameter"
    }
    if (!params.reference_genome) {
        error "Please provide --reference_genome parameter"
    }


    BIOMNI_CANCER_BIOLOGY_ANALYZE_COPY_NUMBER_PURITY_PLOIDY_AND_FOCAL_EVENTS()
}
