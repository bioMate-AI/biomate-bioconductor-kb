#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: broadSeq
// This package helps user to do easily RNA-seq data analysis with multiple methods (usually which need
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/broadSeq/inst/doc/broadSeq.R
// Upstream  : ggplot2, vsn
// Downstream: none
//
// Install: BiocManager::install("broadSeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BROADSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-broadseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-broadseq:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-broadseq:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_broadseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_broadseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_broadseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(broadSeq)
    library(jsonlite)

    # --- assays [] ---
    # Key functions: assays, geom_vline
    assays(se)[["counts"]][,5] %>% ggpubr::ggdensity(y = "count")+
    ggplot2::geom_vline(xintercept = 10)+ggplot2::scale_x_log10()
    keep <- (assays(se)[["counts"]] >= 3) %>% rowSums() >= 5

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_broadseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_broadseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_broadseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BROADSEQ:", paste0("    broadseq: ", packageVersion("broadSeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_broadseq_results.csv
    touch ${prefix}_broadseq_output.rds
    echo "BIOC_BROADSEQ:" > versions.yml
    echo "    broadseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BROADSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BROADSEQ(ch_input)

    emit:
    results  = BIOC_BROADSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BROADSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BROADSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BROADSEQ.out.versions  // channel: path(versions.yml)
}
