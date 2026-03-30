#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BANDITS
// BANDITS is a Bayesian hierarchical model for detecting differential splicing of genes and transcript
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BANDITS/inst/doc/BANDITS.R
// Upstream  : Biostrings, GenomicFeatures, tximport
// Downstream: none
//
// Install: BiocManager::install("BANDITS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BANDITS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bandits"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bandits:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bandits:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bandits_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bandits_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bandits_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BANDITS)
    library(jsonlite)

    # --- plot precision [] ---
    # Key functions: plot_precision
    plot_precision(precision)
    # --- gene [] ---
    # Key functions: gene
    top_gene = top_genes(results, n = 1)
    gene(results, top_gene$Gene_id)
    # --- top transcript [] ---
    # Key functions: transcript
    top_transcript = top_transcripts(results, n = 1)
    transcript(results, top_transcript$Transcript_id)
    # --- plot proportions [] ---
    # Key functions: plot_proportions
    plot_proportions(results, top_gene$Gene_id, CI = TRUE, CI_level = 0.95)
    # --- top gene 3 groups [] ---
    # Key functions: gene, transcript
    gene(results_3_groups, top_genes(results_3_groups)$Gene_id[1])
    transcript(results_3_groups, top_transcripts(results_3_groups)$Transcript_id[1])
    # --- plot proportions 3 groups [] ---
    # Key functions: plot_proportions
    plot_proportions(results_3_groups, top_genes(results_3_groups)$Gene_id[1], CI = TRUE, CI_level = 0.95)
    # --- top gene 1 group [] ---
    # Key functions: gene, transcript
    gene(results_1_group, top_genes(results_1_group)$Gene_id[1])
    transcript(results_1_group, top_transcripts(results_1_group)$Transcript_id[1])
    # --- plot proportions 1 group [] ---
    # Key functions: plot_proportions
    plot_proportions(results_1_group, top_genes(results)$Gene_id[1], CI = TRUE, CI_level = 0.95)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bandits_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bandits_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bandits_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BANDITS:", paste0("    bandits: ", packageVersion("BANDITS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bandits_results.csv
    touch ${prefix}_bandits_output.rds
    echo "BIOC_BANDITS:" > versions.yml
    echo "    bandits: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BANDITS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BANDITS(ch_input)

    emit:
    results  = BIOC_BANDITS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BANDITS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BANDITS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BANDITS.out.versions  // channel: path(versions.yml)
}
