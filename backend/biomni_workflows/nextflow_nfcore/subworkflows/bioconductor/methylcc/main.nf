#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: methylCC
// A tool to estimate the cell composition of DNA methylation whole blood sample measured on any platfo
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/methylCC/inst/doc/methylCC.R
// Upstream  : dplyr, ggplot2, minfi, tidyr
// Downstream: none
//
// Install: BiocManager::install("methylCC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METHYLCC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-methylcc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-methylcc:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-methylcc:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_methylcc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_methylcc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_methylcc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(methylCC)
    library(jsonlite)

    # --- p Data [] ---
    # Key functions: pData
    head(pData(FlowSorted.Blood.450k))
    pData(FlowSorted.Blood.450k)$CellTypeLong %in% "Whole blood"]
    # --- estimatecc [] ---
    # Key functions: estimatecc
    set.seed(12345)
    est <- estimatecc(object = rgset)
    # --- sample Names [] ---
    # Key functions: sampleNames, estimateCellCounts
    sampleNames(rgset) <- paste0("Sample", 1:6)
    est_minfi <- minfi::estimateCellCounts(rgset)
    # --- Custom ggplot2 visualization [] ---
    # Key functions: cell_counts, full_join, ggplot, geom_point, geom_abline


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_methylcc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_methylcc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_methylcc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METHYLCC:", paste0("    methylcc: ", packageVersion("methylCC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methylcc_results.csv
    touch ${prefix}_methylcc_output.rds
    echo "BIOC_METHYLCC:" > versions.yml
    echo "    methylcc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METHYLCC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METHYLCC(ch_input)

    emit:
    results  = BIOC_METHYLCC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METHYLCC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METHYLCC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METHYLCC.out.versions  // channel: path(versions.yml)
}
