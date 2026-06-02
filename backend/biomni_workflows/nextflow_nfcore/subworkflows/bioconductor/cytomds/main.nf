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
    library(Bodenmiller_BCR_XL_flowSet)
    library(SnowParam)
    library(jsonlite)

    # --- Bodenmiller_ B C R_ X L_flow Set [] ---
    # Key functions: Bodenmiller_BCR_XL_flowSet
    BCRXL_fs <- HDCytoData::Bodenmiller_BCR_XL_flowSet()
    # --- p Data [] ---
    # Key functions: pData, keyword
    phenoData <- flowCore::pData(BCRXL_fs)
    keyword(BCRXL_fs[[1]], "EXPERIMENT_INFO")$EXPERIMENT_INFO
    phenoData <- cbind(phenoData, additionalPhenoData)
    # --- keyword [] ---
    # Key functions: keyword
    markerInfo <- keyword(BCRXL_fs[[1]], "MARKER_INFO")$MARKER_INFO
    table(chClass)
    (chMarkers <- markerInfo$marker_name[chClass != "none"])
    # --- arcsinh Transform [] ---
    # Key functions: arcsinhTransform, transform, transformList
    trans <- arcsinhTransform(
    BCRXL_fs_trans <- transform(
    transformList(chLabels, trans))
    # --- pairwise E M D Dist [] ---
    # Key functions: pairwiseEMDDist
    pwDist <- pairwiseEMDDist(
    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, geom_histogram, theme_bw
    distVec <- pwDist[upper.tri(pwDist)]
    distVecDF <- data.frame(dist = distVec)
    pHist <- ggplot(distVecDF, mapping = aes(x=dist)) +
    # --- compute Metric M D S [] ---
    # Key functions: computeMetricMDS, show
    mdsObj <- computeMetricMDS(pwDist, seed = 0)
    show(mdsObj)
    # --- plotMDS1 simplest [] ---
    # Key functions: ggplotSampleMDS
    ggplotSampleMDS(mdsObj)
    # --- plotMDS colours shapes 1 2 [] ---
    # Key functions: ggplotSampleMDS
    p12 <- ggplotSampleMDS(
    projectionAxes = c(1,2),
    # --- plotMDS colours shapes 2 3 4 [] ---
    # Key functions: ggplotSampleMDS
    p23 <- ggplotSampleMDS(
    projectionAxes = c(2,3),
    p34 <- ggplotSampleMDS(
    # --- ggplot Sample M D S Shepard [] ---
    # Key functions: ggplotSampleMDSShepard
    ggplotSampleMDSShepard(mdsObj)
    # --- compute Metric M D S [] ---
    # Key functions: computeMetricMDS, ggplotSampleMDS
    mdsObj2 <- CytoMDS::computeMetricMDS(pwDist, seed = 0, nDim = 2)
    ggplotSampleMDS(mdsObj2,
    projectionAxes = c(1,2),
    # --- ggplot Sample M D S Shepard [] ---
    # Key functions: ggplotSampleMDSShepard
    ggplotSampleMDSShepard(mdsObj3)
    # --- plotMDS medians [] ---
    # Key functions: channelSummaryStats
    medians <- channelSummaryStats(BCRXL_fs_trans,
    # --- plotMDS biplot [] ---
    # Key functions: ggplotSampleMDS
    ggplotSampleMDS(mdsObj,

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
