#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: FeatSeekR
// FeatSeekR performs unsupervised feature selection using replicated measurements. It iteratively sele
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/FeatSeekR/inst/doc/FeatSeekR-vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("FeatSeekR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FEATSEEKR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-featseekr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-featseekr:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-featseekr:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_featseekr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_featseekr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_featseekr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(FeatSeek)
    library(jsonlite)

    # --- Plot hierarchical clustering heatmap [] ---
    # Key functions: simData, pheatmap
    set.seed(111)
    # --- FeatSeek analysis [] ---
    # Key functions: FeatSeek, plotSelectedFeatures, aperm, dimnames, plotVarianceExplained
    data("subSampleForStabilitySelection", package="DmelSGI")
    data <- aperm(data, c(1, 3, 2))
    dimnames(data)[[2]] <- subSampleForStabilitySelection$phenotype

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_featseekr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_featseekr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_featseekr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FEATSEEKR:", paste0("    featseekr: ", packageVersion("FeatSeekR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_featseekr_results.csv
    touch ${prefix}_featseekr_output.rds
    echo "BIOC_FEATSEEKR:" > versions.yml
    echo "    featseekr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FEATSEEKR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FEATSEEKR(ch_input)

    emit:
    results  = BIOC_FEATSEEKR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FEATSEEKR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FEATSEEKR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FEATSEEKR.out.versions  // channel: path(versions.yml)
}
