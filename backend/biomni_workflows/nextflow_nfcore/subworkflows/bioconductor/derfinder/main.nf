#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: derfinder
// This package provides functions for annotation-agnostic differential expression analysis of RNA-seq 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/derfinder/inst/doc/derfinder-quickstart.R
// Upstream  : DESeq2, GenomicRanges, IRanges, RefManageR, bumphunter
// Downstream: none
//
// Install: BiocManager::install("derfinder")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DERFINDER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-derfinder"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-derfinder:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-derfinder:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_derfinder_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_derfinder_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_derfinder_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DESeq)
    library(DESeqDataSetFromMatrix)
    library(PrintBibliography)
    library(jsonlite)

    # --- 'installDer' [] ---
    # Key functions: valid

    # --- 'ultraQuick' [] ---
    # Key functions: rawFiles, fullCoverage, regionMatrix, DESeqDataSetFromMatrix
    library("derfinder")
    library("derfinderData")
    library("GenomicRanges")
    # --- 'locateAMYfiles' [] ---
    # Key functions: rawFiles

    # --- Load Raw Files [] ---
    # Key functions: fullCoverage

    # --- Load Data Windows [] ---
    # Key functions: foo

    # --- 'regionMatrix' [] ---
    # Key functions: regionMatrix
    Get the region matrix of Expressed Regions (ERs)
    regionMat <- regionMatrix(fullCov, cutoff = 30, L = 76, verbose = FALSE)
    # --- Identify DERs using DESeq2 [] ---
    # Key functions: DESeqDataSetFromMatrix, DESeq, mcols, results
    library("DESeq2")
    counts <- round(regionMat$chr21$coverageMatrix)
    dse <- DESeqDataSetFromMatrix(counts, pheno, ~ group + gender)
    # --- 'vennRegions' [] ---
    # Key functions: annotateRegions, vennRegions
    annoRegs <- annotateRegions(ers, genomicState$fullGenome, verbose = FALSE)
    library("derfinderPlot")
    # --- 'nearestGene' [] ---
    # Key functions: keepSeqlevels, annotateTranscripts, matchGenes, restoreSeqlevels
    library("TxDb.Hsapiens.UCSC.hg19.knownGene")
    txdb <- keepSeqlevels(TxDb.Hsapiens.UCSC.hg19.knownGene, "chr21")
    library("bumphunter")
    # --- 'firstfive' [] ---
    # Key functions: plotRegionCoverage

    # --- knit [] ---
    # Key functions: knit
    library("rmarkdown")
    system.time(render("derfinder-quickstart.Rmd", "BiocStyle::html_document"))
    library("knitr")
    # --- diff [] ---
    # Key functions: diff
    totalTime <- diff(c(startTime, Sys.time()))
    round(totalTime, digits = 3)
    # --- session_info [] ---
    # Key functions: session_info
    library("sessioninfo")
    options(width = 120)
    session_info()
    # --- Print Bibliography [] ---
    # Key functions: PrintBibliography
    PrintBibliography(bib, .opts = list(hyperlink = "to.doc", style = "html"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_derfinder_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_derfinder_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_derfinder_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DERFINDER:", paste0("    derfinder: ", packageVersion("derfinder"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_derfinder_results.csv
    touch ${prefix}_derfinder_output.rds
    echo "BIOC_DERFINDER:" > versions.yml
    echo "    derfinder: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DERFINDER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DERFINDER(ch_input)

    emit:
    results  = BIOC_DERFINDER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DERFINDER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DERFINDER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DERFINDER.out.versions  // channel: path(versions.yml)
}
