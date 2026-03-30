#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: sesame
// Tools For analyzing Illumina Infinium DNA methylation arrays. SeSAMe provides utilities to support a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/sesame/inst/doc/KYCG.R
// Upstream  : SummarizedExperiment, ggplot2, gprofiler2, knitr, tibble
// Downstream: none
//
// Install: BiocManager::install("sesame")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SESAME {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sesame"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sesame:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sesame:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sesame_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sesame_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sesame_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(KYCG_buildGeneDBs)
    library(KYCG_getDBs)
    library(KYCG_listDBGroups)
    library(KYCG_plotEnrichAll)
    library(KYCG_plotLollipop)
    library(jsonlite)

    # --- Custom ggplot2 visualization [] ---
    # Key functions: sesameDataGet, ggplot, geom_line, labs, theme
    se <- sesameDataGet("MM285.10.SE.tissue")
    library(tibble)
    df_plot <- as.data.frame(t(assay(se)[
    # --- Table formatting and display [] ---
    # Key functions: sesameDataCache, KYCG_getDBs, testEnrichment, KYCG_plotEnrichAll, kable, rowData, KYCG_listDBGroups, KYCG_buildGeneDBs
    df <- rowData(sesameDataGet('MM285.tissueSignature'))
    regs <- sesameData_getTxnGRanges("mm10", merge2gene = TRUE)
    genes <- sesameData_annoProbes(query, regs, platform="MM285", return_ov_features=TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sesame_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sesame_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sesame_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SESAME:", paste0("    sesame: ", packageVersion("sesame"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sesame_results.csv
    touch ${prefix}_sesame_output.rds
    echo "BIOC_SESAME:" > versions.yml
    echo "    sesame: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SESAME_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SESAME(ch_input)

    emit:
    results  = BIOC_SESAME.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SESAME.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SESAME.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SESAME.out.versions  // channel: path(versions.yml)
}
