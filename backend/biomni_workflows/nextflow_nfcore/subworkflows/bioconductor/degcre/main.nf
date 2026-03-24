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
    library(GRanges)
    library(jsonlite)

    # --- demo DegCre default [] ---
    # Key functions: runDegCre
    subDegGR <- DexNR3C1$DegGR[which(seqnames(DexNR3C1$DegGR)=="chr1")]
    subCreGR <- DexNR3C1$CreGR[which(seqnames(DexNR3C1$CreGR)=="chr1")]
    myDegCreResList <- runDegCre(DegGR=subDegGR,
    # --- demo Alpha opt [] ---
    # Key functions: optimizeAlphaDegCre
    alphaOptList <- optimizeAlphaDegCre(DegGR=subDegGR,
    bestAlphaId <- which.max(alphaOptList$alphaPRMat[,4])
    # --- demo assoc dist plot [] ---
    # Key functions: plotDegCreAssocProbVsDist
    par(mai=c(0.8,1.6,0.4,0.1))
    par(mgp=c(1.7,0.5,0))
    par(cex.axis=1)
    # --- demo plot bin algorithm [] ---
    # Key functions: plotDegCreBinHeuristic
    par(mai=c(0.8,0.6,0.4,0.1))
    par(mgp=c(1.7,0.5,0))
    par(cex.axis=1)
    # --- demo plot PR curve [] ---
    # Key functions: degCrePRAUC
    par(mai=c(0.8,0.6,0.4,0.1))
    par(mgp=c(1.7,0.5,0))
    par(cex.axis=1)
    # --- demo expect associations [] ---
    # Key functions: getExpectAssocPerDEG
    expectAssocPerDegDf <- getExpectAssocPerDEG(degCreResList=bestDegCreResList,
    # --- demo plot expect hist [] ---
    # Key functions: plotExpectedAssocsPerDeg
    par(mai=c(0.8,0.6,0.4,0.1))
    par(mgp=c(1.7,0.5,0))
    par(cex.axis=1)
    # --- plot Browser Deg Cre [] ---
    # Key functions: plotBrowserDegCre
    browserOuts <- plotBrowserDegCre(degCreResList=bestDegCreResList,
    # --- demo zoom browser [] ---
    # Key functions: GRanges
    zoomGR <- GRanges(seqnames="chr1",
    ranges=IRanges(start=7900e3,end=8400e3))
    # --- plot browser2 [] ---
    # Key functions: plotBrowserDegCre
    zoomBrowserOuts <- plotBrowserDegCre(degCreResList=bestDegCreResList,
    # --- plot browser3 [] ---
    # Key functions: plotBrowserDegCre
    highLightBrowserOuts <- plotBrowserDegCre(degCreResList=bestDegCreResList,
    # --- demo convert to DataFrame [] ---
    # Key functions: convertDegCreDataFrame
    degCreDf <- convertDegCreDataFrame(degCreResList=bestDegCreResList,
    head(degCreDf)
    sessionInfo()

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
