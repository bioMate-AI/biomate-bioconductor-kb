#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ChIPseeker
// This package implements functions to retrieve the nearest genes around the peak, annotate genomic re
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ChIPseeker/inst/doc/ChIPseeker.html
// Upstream  : GenomicFeatures, GenomicRanges, ReactomePA, clusterProfiler, ggplot2
// Downstream: none
//
// Install: BiocManager::install("ChIPseeker")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHIPSEEKER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-chipseeker"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-chipseeker:1.42.1--r44_0' :
        'quay.io/biocontainers/bioconductor-chipseeker:1.42.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_chipseeker_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_chipseeker_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_chipseeker_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ChIPseeker)
    library(GRanges)
    library(IRanges)
    library(Region)
    library(jsonlite)

    # --- Profile and Heatmap Generation [] ---
    # Key functions: getTagMatrix, tagHeatmap, peakHeatmap
    data("tagMatrixList")
    tagMatrix <- tagMatrixList[[4]]
    tagHeatmap(tagMatrix)


    # --- Genomic Region Profiling [] ---
    # Key functions: plotAvgProf2, plotPeakProf2
    files <- getSampleFiles()
    txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene::TxDb.Hsapiens.UCSC.hg19.knownGene
    plotAvgProf2(
        files[[4]], 
        TxDb=txdb, 
        upstream=3000, 
        downstream=3000,
        xlab="Genomic Region (5'->3')", 
        ylab="Read Count Frequency"
    )


    # --- Peak Annotation [] ---
    # Key functions: annotatePeak, plotAnnoPie, plotAnnoBar, upsetplot
    files <- getSampleFiles()
    txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene::TxDb.Hsapiens.UCSC.hg19.knownGene
    peakAnno <- annotatePeak(
        files[[4]], 
        tssRegion=c(-3000, 3000),
        TxDb=txdb, 
        annoDb="org.Hs.eg.db"
    )
    plotAnnoPie(peakAnno)
    plotAnnoBar(peakAnno)
    upsetplot(peakAnno, vennpie=TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_chipseeker_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_chipseeker_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_chipseeker_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CHIPSEEKER:", paste0("    chipseeker: ", packageVersion("ChIPseeker"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chipseeker_results.csv
    touch ${prefix}_chipseeker_output.rds
    echo "BIOC_CHIPSEEKER:" > versions.yml
    echo "    chipseeker: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CHIPSEEKER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CHIPSEEKER(ch_input)

    emit:
    results  = BIOC_CHIPSEEKER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CHIPSEEKER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CHIPSEEKER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CHIPSEEKER.out.versions  // channel: path(versions.yml)
}
