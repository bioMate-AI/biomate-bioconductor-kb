#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CytoMDS
// This package implements a low dimensional visualization of a set of cytometry samples, in order to v
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CytoMDS/inst/doc/CytoMDS.R
// Upstream  : HDCytoData, ggplot2, patchwork
// Downstream: none
//
// Install: BiocManager::install("CytoMDS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CYTOMDS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cytomds"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cytomds:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cytomds:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cytomds_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cytomds_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cytomds_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CytoMDS)
    library(Bodenmiller_BCR_XL_flowSet)
    library(SnowParam)
    library(jsonlite)

    # --- Multidimensional Scaling [] ---
    # Key functions: computeMetricMDS
    mdsObj <- computeMetricMDS(pwDist, seed = 0)
    mdsObj2 <- computeMetricMDS(pwDist, seed = 0, nDim = 2)
    mdsObj3 <- computeMetricMDS(
        pwDist, seed = 0, targetPseudoRSq = 0.99
    )


    # --- MDS Visualisation [] ---
    # Key functions: ggplotSampleMDS, ggplotSampleMDSShepard
    p12 <- ggplotSampleMDS(
        mdsObj, pData = phenoData, projectionAxes = c(1, 2),
        pDataForColour = "group_id", pDataForLabel = "patient_id"
    )
    pShepard <- ggplotSampleMDSShepard(mdsObj)


    # --- Biplot and Summary Statistics [] ---
    # Key functions: channelSummaryStats, ggplotSampleMDSWrapBiplots, ggplotMarginalDensities
    medians <- channelSummaryStats(
        BCRXL_fs_trans, channels = chLabels, statFUNs = median
    )
    pBiplot <- ggplotSampleMDS(
        mdsObj, pData = phenoData, pDataForColour = "group_id",
        biplot = TRUE, extVariables = medians
    )
    pDens <- ggplotMarginalDensities(
        BCRXL_fs_trans, channels = chLabels,
        pDataForColour = "group_id", pDataForGroup = "sample_id"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cytomds_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cytomds_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cytomds_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CYTOMDS:", paste0("    cytomds: ", packageVersion("CytoMDS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cytomds_results.csv
    touch ${prefix}_cytomds_output.rds
    echo "BIOC_CYTOMDS:" > versions.yml
    echo "    cytomds: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CYTOMDS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CYTOMDS(ch_input)

    emit:
    results  = BIOC_CYTOMDS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CYTOMDS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CYTOMDS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CYTOMDS.out.versions  // channel: path(versions.yml)
}
