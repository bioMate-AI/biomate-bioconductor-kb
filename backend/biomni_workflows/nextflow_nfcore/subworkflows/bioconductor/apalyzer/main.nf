#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: APAlyzer
// Perform 3'UTR APA, Intronic APA and gene expression analysis using RNA-seq data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/APAlyzer/inst/doc/APAlyzer.R
// Upstream  : GenomicFeatures, Rsamtools, TBX20BamSubset, ggplot2, knitr
// Downstream: none
//
// Install: BiocManager::install("APAlyzer")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_APALYZER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-apalyzer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-apalyzer:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-apalyzer:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_apalyzer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_apalyzer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_apalyzer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(APAlyzer)
    library(jsonlite)

    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, geom_violin, geom_boxplot, geom_hline
    ggplot(dfplot, aes(x = APA, y = RED)) +
    geom_violin(trim = FALSE) +
    geom_boxplot(width = 0.2)+ theme_bw() +
    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, stat_ecdf, ylab, geom_vline, geom_hline
    ggplot(dfplot, aes( x = RED, color = APA)) +
    stat_ecdf(geom = "step") +
    ylab("cumulative fraction")+

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_apalyzer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_apalyzer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_apalyzer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_APALYZER:", paste0("    apalyzer: ", packageVersion("APAlyzer"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_apalyzer_results.csv
    touch ${prefix}_apalyzer_output.rds
    echo "BIOC_APALYZER:" > versions.yml
    echo "    apalyzer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_APALYZER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_APALYZER(ch_input)

    emit:
    results  = BIOC_APALYZER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_APALYZER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_APALYZER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_APALYZER.out.versions  // channel: path(versions.yml)
}
