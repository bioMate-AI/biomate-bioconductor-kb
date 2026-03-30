#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cghMCR
// This package provides functions to identify genomic regions of interests based on segmented copy num
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cghMCR/inst/doc/findMCR.R
// Upstream  : limma
// Downstream: none
//
// Install: BiocManager::install("cghMCR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CGHMCR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cghmcr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cghmcr:1.64.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cghmcr:1.64.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cghmcr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cghmcr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cghmcr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CNSeg)
    library(MCR)
    library(SGOL)
    library(jsonlite)

    # --- Files [] ---
    # Key functions: files
    require("limma")
    arrayFiles  <- list.files(system.file("sampleData", package = "cghMCR"),
         full.names = TRUE, pattern = "TCGA")
    arrayFiles
    # --- Maimages [] ---
    # Key functions: maimages
    rawData <- read.maimages(arrayFiles, source = "agilent", columns =
        list(R = "rMedianSignal", G = "gMedianSignal", Rb = "rBGMedianSignal",
        Gb = "gBGMedianSignal"), annotation = c("Row", "Col", "ControlType",
        "ProbeName", "GeneName", "SystematicName", "PositionX", "PositionY",
        "gIsFeatNonUnifOL", "rIsFeatNonUnifOL", "gIsBGNonUnifOL", "rIsBGNonUnifOL",
    # --- Normalizewithinarrays [] ---
    # Key functions: normalizeWithinArrays, backgroundCorrect
    ma <- normalizeWithinArrays(backgroundCorrect(rawData, method = "minimum"), method = "loess")
    # --- Gsub [] ---
    # Key functions: chr
    chrom <- gsub("chr([0-9XY]+):.*", "\\1", ma$genes[, "SystematicName"])
    dropMe <- c(which(!chrom %in% c(1:22, "X", "Y")), which(ma$genes[, "ControlType"] != 0))
    # --- Data [] ---
    # Key functions: data
    require(CNTools, quietly = TRUE)
    data("sampleData", package = "CNTools")
    head(sampleData)
    # --- Data [] ---
    # Key functions: getRS, CNSeg, element, sample
    data(geneInfo)
    data(sampleData, package = "CNTools")
    set.seed(1234)
    convertedData <- getRS(CNSeg(sampleData[which(is.element(sampleData[, "ID"], sample(unique(sampleData[, "ID"]), 20))), ]), by = "gene", imput = FALSE,
    XY = FALSE, geneMap = geneInfo, what = "median")
    # --- Sgol [] ---
    # Key functions: SGOL
    require(cghMCR, quietly = TRUE)
    SGOLScores <- SGOL(convertedData, threshold = c(-0.2, 0.2), method = sum)
    plot(SGOLScores)
    # --- Which [] ---
    # Key functions: unlist, gol
    GOIGains <- SGOLScores[which(as.numeric(unlist(gol(SGOLScores[, "gains"]))) >
         20), "gains"]
    GOILosses <- SGOLScores[which(as.numeric(unlist(gol(SGOLScores[, "losses"]))) <
         -20), "losses"]
    head(gol(GOIGains))
    # --- Cghmcr [] ---
    # Key functions: cghMCR, MCR
    cghmcr <- cghMCR(segData, gapAllowed = 500, alteredLow = 0.9,
     alteredHigh = 0.9, recurrence = 100)
    mcrs <- MCR(cghmcr)
    # --- Head [] ---
    # Key functions: cbind
    head(cbind(mcrs[, c("chromosome", "status", "mcr.start", "mcr.end",
                         "samples")]))
    # --- Mergemcrprobes [] ---
    # Key functions: mergeMCRProbes, frame
    mcrs <- mergeMCRProbes(mcrs[mcrs[, "chromosome"] == "7", ], as.data.frame(segData[["data"]]))
    head(cbind(mcrs[, c("chromosome", "status", "mcr.start", "mcr.end",
                         "probes")]))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cghmcr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cghmcr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cghmcr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CGHMCR:", paste0("    cghmcr: ", packageVersion("cghMCR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cghmcr_results.csv
    touch ${prefix}_cghmcr_output.rds
    echo "BIOC_CGHMCR:" > versions.yml
    echo "    cghmcr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CGHMCR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CGHMCR(ch_input)

    emit:
    results  = BIOC_CGHMCR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CGHMCR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CGHMCR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CGHMCR.out.versions  // channel: path(versions.yml)
}
