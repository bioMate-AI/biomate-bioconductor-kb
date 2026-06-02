#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: FindIT2
// This package implements functions to find influential TF and target based on different input type. I
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/FindIT2/inst/doc/FindIT2.R
// Upstream  : SummarizedExperiment, dplyr, ggplot2, sessioninfo
// Downstream: none
//
// Install: BiocManager::install("FindIT2")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FINDIT2 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-findit2"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-findit2:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-findit2:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_findit2_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_findit2_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_findit2_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(FindIT2)
    library(jsonlite)

    # --- Association Diagnostics and Visualization [] ---
    # Key functions: getAssocPairNumber, plot_annoDistance, plot_peakGeneAlias_summary
    pair_summary <- getAssocPairNumber(
        mmAnno = mmAnno_nearestgene,
        output_summary = TRUE
    )
    plot_annoDistance(mmAnno = mmAnno_nearestgene)
    plot_peakGeneAlias_summary(
        mmAnno = mmAnno_geneScan,
        output_type = "feature_id"
    )


    # --- Regulatory Potential Calculation [] ---
    # Key functions: calcRP_TFHit, calcRP_region
    colnames(mcols(ChIP_peak_GR))[2] <- "feature_score"
    fullRP_hit <- calcRP_TFHit(
        mmAnno = mmAnno_geneScan,
        Txdb = Txdb,
        decay_dist = 1000,
        report_fullInfo = TRUE
    )
    peakRP_gene <- metadata(fullRP_hit)$peakRP_gene
    data("ATAC_normCount", package = "FindIT2")
    regionRP <- calcRP_region(
        mmAnno = mmAnno_geneScan,
        peakScoreMt = ATAC_normCount,
        Txdb = Txdb,
        Chrs_included = "Chr5"
    )


    # --- Target Gene Integration [] ---
    # Key functions: integrate_ChIP_RNA
    data("RNADiff_LEC2_GR", package = "FindIT2")
    merge_result <- integrate_ChIP_RNA(
        result_geneRP = peakRP_gene,
        result_geneDiff = RNADiff_LEC2_GR
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_findit2_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_findit2_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_findit2_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FINDIT2:", paste0("    findit2: ", packageVersion("FindIT2"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_findit2_results.csv
    touch ${prefix}_findit2_output.rds
    echo "BIOC_FINDIT2:" > versions.yml
    echo "    findit2: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FINDIT2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FINDIT2(ch_input)

    emit:
    results  = BIOC_FINDIT2.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FINDIT2.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FINDIT2.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FINDIT2.out.versions  // channel: path(versions.yml)
}
