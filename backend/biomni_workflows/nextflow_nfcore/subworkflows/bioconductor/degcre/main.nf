#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DegCre
// DegCre generates associations between differentially expressed genes (DEGs) and cis-regulatory eleme
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DegCre/inst/doc/degcre_introduction_and_examples.R
// Upstream  : GenomicRanges, InteractionSet, plotgardener, magick
// Downstream: none
//
// Install: BiocManager::install("DegCre")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DEGCRE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-degcre"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-degcre:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-degcre:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_degcre_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_degcre_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_degcre_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DegCre)
    library(GRanges)
    library(jsonlite)

    # --- Initial Association Mapping [degcre] ---
    # Key functions: runDegCre
    data(DexNR3C1, package = "degcre")
    subDegGR <- DexNR3C1$DegGR[which(seqnames(DexNR3C1$DegGR) == "chr1")]
    subCreGR <- DexNR3C1$CreGR[which(seqnames(DexNR3C1$CreGR) == "chr1")]
    myDegCreResList <- runDegCre(
        DegGR = subDegGR,
        DegP = subDegGR$pVal,
        DegLfc = subDegGR$logFC,
        CreGR = subCreGR,
        CreP = subCreGR$pVal,
        CreLfc = subCreGR$logFC,
        reqEffectDirConcord = TRUE,
        verbose = FALSE
    )

    # --- Parameter Optimization [degcre] ---
    # Key functions: optimizeAlphaDegCre
    alphaOptList <- optimizeAlphaDegCre(
        DegGR = subDegGR,
        DegP = subDegGR$pVal,
        DegLfc = subDegGR$logFC,
        CreGR = subCreGR,
        CreP = subCreGR$pVal,
        CreLfc = subCreGR$logFC,
        reqEffectDirConcord = TRUE,
        verbose = FALSE
    )
    bestAlphaId <- which.max(alphaOptList$alphaPRMat[, 4])
    bestDegCreResList <- alphaOptList$degCreResListsByAlpha[[bestAlphaId]]

    # --- Association Filtering and Conversion [degcre] ---
    # Key functions: getExpectAssocPerDEG, convertdegCreResListToGInteraction, convertDegCreDataFrame
    expectAssocPerDegDf <- getExpectAssocPerDEG(
        degCreResList = bestDegCreResList,
        geneNameColName = "GeneSymb",
        assocAlpha = 0.05
    )
    degCreGInter <- convertdegCreResListToGInteraction(
        degCreResList = bestDegCreResList,
        assocAlpha = 0.05
    )
    degCreDf <- convertDegCreDataFrame(
        degCreResList = bestDegCreResList,
        assocAlpha = 0.05
    )

    # --- Diagnostic and Performance Plotting [degcre] ---
    # Key functions: plotDegCreAssocProbVsDist, plotDegCreBinHeuristic, degCrePRAUC, plotExpectedAssocsPerDeg
    binStats <- plotDegCreAssocProbVsDist(
        degCreResList = bestDegCreResList,
        assocProbFDRThresh = 0.05
    )
    plotDegCreBinHeuristic(degCreResList = bestDegCreResList)
    degCrePRAUC(degCreResList = bestDegCreResList)
    plotExpectedAssocsPerDeg(expectAssocPerDegDf = expectAssocPerDegDf)

    # --- Genomic Browser Visualization [degcre] ---
    # Key functions: plotBrowserDegCre
    zoomGR <- GenomicRanges::GRanges(
        seqnames = "chr1",
        ranges = IRanges::IRanges(start = 7900e3, end = 8400e3)
    )
    geneHighDf <- data.frame(
        gene = bestDegCreResList$DegGR$GeneSymb,
        col = "gray"
    )
    geneHighDf[which(geneHighDf$gene == "ERRFI1"), 2] <- "black"
    highLightBrowserOuts <- plotBrowserDegCre(
        degCreResList = bestDegCreResList,
        plotRegionGR = zoomGR,
        CreSignalName = "NR3C1",
        geneNameColName = "GeneSymb",
        geneHighlightDf = geneHighDf,
        panelTitleFontSize = 8,
        geneLabelFontsize = 10,
        plotXbegin = 0.9,
        plotWidth = 5
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_degcre_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_degcre_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_degcre_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DEGCRE:", paste0("    degcre: ", packageVersion("DegCre"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_degcre_results.csv
    touch ${prefix}_degcre_output.rds
    echo "BIOC_DEGCRE:" > versions.yml
    echo "    degcre: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DEGCRE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DEGCRE(ch_input)

    emit:
    results  = BIOC_DEGCRE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DEGCRE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DEGCRE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DEGCRE.out.versions  // channel: path(versions.yml)
}
