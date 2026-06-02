#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DNAfusion
// DNAfusion can identify gene fusions such as EML4-ALK based on paired-end sequencing results. This pa
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DNAfusion/inst/doc/Introduction_to_DNAfusion.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("DNAfusion")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DNAFUSION {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dnafusion"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dnafusion:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dnafusion:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dnafusion_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dnafusion_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dnafusion_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DNAfusion)
    library(ALK_sequence)
    library(EML4_ALK_analysis)
    library(EML4_ALK_detection)
    library(EML4_sequence)
    library(jsonlite)

    # --- Sequence Extraction and Breakpoint Analysis [] ---
    # Key functions: EML4_sequence, ALK_sequence, break_position, break_position_depth
    eml4_seq <- EML4_sequence(H3122_result, genome = "hg38", basepairs = 20)
    alk_seq <- ALK_sequence(H3122_result, genome = "hg38", basepairs = 20)
    bp_eml4 <- break_position(H3122_result, genome = "hg38", gene = "EML4")
    bp_depth <- break_position_depth(H3122_bam, H3122_result, genome = "hg38", gene = "EML4")


    # --- Comprehensive Fusion Analysis [] ---
    # Key functions: EML4_ALK_analysis, introns_ALK_EML4, find_variants
    H3122_results <- EML4_ALK_analysis(file = H3122_bam, genome = "hg38", 
                                        mates = 2, basepairs = 20)
    intron_res <- introns_ALK_EML4(file=H3122_bam, genome="hg38")
    variants <- find_variants(file=H3122_bam, genome="hg38")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dnafusion_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dnafusion_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dnafusion_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DNAFUSION:", paste0("    dnafusion: ", packageVersion("DNAfusion"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dnafusion_results.csv
    touch ${prefix}_dnafusion_output.rds
    echo "BIOC_DNAFUSION:" > versions.yml
    echo "    dnafusion: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DNAFUSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DNAFUSION(ch_input)

    emit:
    results  = BIOC_DNAFUSION.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DNAFUSION.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DNAFUSION.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DNAFUSION.out.versions  // channel: path(versions.yml)
}
