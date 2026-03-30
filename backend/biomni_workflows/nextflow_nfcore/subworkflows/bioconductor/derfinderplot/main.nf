#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: derfinderPlot
// This package provides plotting functions for results from the derfinder package. This helps separate
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/derfinderPlot/inst/doc/derfinderPlot.R
// Upstream  : RefManageR, bumphunter, derfinder, derfinderData, knitr
// Downstream: none
//
// Install: BiocManager::install("derfinderPlot")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DERFINDERPLOT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-derfinderplot"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-derfinderplot:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-derfinderplot:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_derfinderplot_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_derfinderplot_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_derfinderplot_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PrintBibliography)
    library(jsonlite)

    # --- 'installDer' [] ---
    # Key functions: valid
    if (!requireNamespace("BiocManager", quietly = TRUE)) {
    install.packages("BiocManager")
    BiocManager::install("derfinderPlot")
    # --- 'phenoData' [] ---
    # Key functions: kable
    library("knitr")
    pheno <- subset(brainspanPheno, structure_acronym == "A1C")
    p <- pheno[, -which(colnames(pheno) %in% c(
    # --- 'getData' [] ---
    # Key functions: rawFiles
    files <- rawFiles(system.file("extdata", "A1C", package = "derfinderData"),
    names(files) <- gsub(".bw", "", names(files))
    system.time(fullCov <- fullCoverage(files = files, chrs = "chr21"))
    # --- 'getDataWindows' [] ---
    # Key functions: foo
    foo <- function() {
    load(system.file("extdata", "fullCov", "fullCovA1C.RData",
    return(fullCovA1C)
    # --- 'models' [] ---
    # Key functions: sampleDepth, makeModels
    sampleDepths <- sampleDepth(collapseFullCoverage(fullCov), 1)
    models <- makeModels(sampleDepths,
    adjustvars = pheno[, c("gender")]
    # --- 'plotOverview' [] ---
    # Key functions: plotOverview
    plotOverview(regions = regions, annotation = results$annotation, type = "qval")
    # --- 'regionData' [] ---
    # Key functions: annotateRegions, getRegionCoverage
    annoRegs <- annotateRegions(regions, genomicState$fullGenome)
    regionCov <- getRegionCoverage(fullCov, regions)
    # --- 'vennRegions' [] ---
    # Key functions: vennRegions
    venn <- vennRegions(annoRegs)
    # --- knit [] ---
    # Key functions: knit
    library("rmarkdown")
    system.time(render("derfinderPlot.Rmd", "BiocStyle::html_document"))
    library("knitr")
    # --- unlink [] ---
    # Key functions: unlink
    unlink("chr21", recursive = TRUE)
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
        write.csv(results_df, "${prefix}_derfinderplot_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_derfinderplot_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_derfinderplot_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DERFINDERPLOT:", paste0("    derfinderplot: ", packageVersion("derfinderPlot"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_derfinderplot_results.csv
    touch ${prefix}_derfinderplot_output.rds
    echo "BIOC_DERFINDERPLOT:" > versions.yml
    echo "    derfinderplot: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DERFINDERPLOT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DERFINDERPLOT(ch_input)

    emit:
    results  = BIOC_DERFINDERPLOT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DERFINDERPLOT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DERFINDERPLOT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DERFINDERPLOT.out.versions  // channel: path(versions.yml)
}
