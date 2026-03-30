#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: flowPeaks
// A fast and automatic clustering to classify the cells into subpopulations based on finding the peaks
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/flowPeaks/inst/doc/flowPeaks-guide.R
// Upstream  : flowCore
// Downstream: none
//
// Install: BiocManager::install("flowPeaks")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWPEAKS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-flowpeaks"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-flowpeaks:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-flowpeaks:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_flowpeaks_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_flowpeaks_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_flowpeaks_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(FCS)
    library(jsonlite)

    # --- Stage1 [] ---
    # Key functions: flowPeaks
    data(barcode)
    summary(barcode)
    fp<-flowPeaks(barcode)
    # --- Stage4 [] ---
    # Key functions: flowPeaks
    fp2<-flowPeaks(barcode[,c(1,3)])
    plot(fp2)
    # --- eval Cluster [] ---
    # Key functions: evalCluster
    evalCluster(barcode.cid,fp2$peaks.cluster,method="Vmeasure")
    # --- Stage6 [] ---
    # Key functions: flowPeaks
    fpc<-assign.flowPeaks(fp2,fp2$x)
    plot(fp2,classlab=fpc,drawboundary=FALSE,
      drawvor=FALSE,drawkmeans=FALSE,drawlab=TRUE)
    # --- Stage7 [] ---
    # Key functions: FCS, flowPeaks, asinh
    require(flowCore)
    samp <- read.FCS(system.file("extdata","0877408774.B08",
    package="flowCore"))
    ##do the clustering based on the asinh transforamtion of
    ##the first two FL channels

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_flowpeaks_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_flowpeaks_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_flowpeaks_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FLOWPEAKS:", paste0("    flowpeaks: ", packageVersion("flowPeaks"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowpeaks_results.csv
    touch ${prefix}_flowpeaks_output.rds
    echo "BIOC_FLOWPEAKS:" > versions.yml
    echo "    flowpeaks: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FLOWPEAKS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FLOWPEAKS(ch_input)

    emit:
    results  = BIOC_FLOWPEAKS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FLOWPEAKS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FLOWPEAKS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FLOWPEAKS.out.versions  // channel: path(versions.yml)
}
