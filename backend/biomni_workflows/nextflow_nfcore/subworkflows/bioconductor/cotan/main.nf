#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: COTAN
// Statistical and computational method to analyze the co-expression of gene pairs at single cell level
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/COTAN/inst/doc/Guided_tutorial_v2.R
// Upstream  : ComplexHeatmap, GEOquery, Rtsne, qpdf, rlang
// Downstream: none
//
// Install: BiocManager::install("COTAN")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_COTAN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cotan"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cotan:2.6.3--r44_0' :
        'quay.io/biocontainers/bioconductor-cotan:2.6.3--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cotan_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cotan_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cotan_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(COTAN)
    library(ECDPlot)
    library(GDIPlot)
    library(jsonlite)

    # --- Setlogginglevel [] ---
    # Key functions: setLoggingLevel, setLoggingFile, path, canUseTorch
    ---------------------------------------------------------------------
    outDir <- dataDir
    # Log-level 2 was chosen to showcase better how the package works
    # In normal usage a level of 0 or 1 is more appropriate
    setLoggingLevel(2L)
    # --- Cotan [] ---
    # Key functions: COTAN, initializeMetaDataset, logThis, getMetadataElement, datasetTags
    ---------------------------------------------------------------------
    cond <- "mouse_cortex_E17.5"
    obj <- COTAN(raw = sample.dataset)
    # --- Plot [] ---
    # Key functions: ECDPlot
    ---------------------------------------------------------------------
    plot(ECDPlot(obj))
    # --- Plot [] ---
    # Key functions: cellSizePlot
    ---------------------------------------------------------------------
    plot(cellSizePlot(obj))
    # --- Plot [] ---
    # Key functions: genesSizePlot
    ---------------------------------------------------------------------
    plot(genesSizePlot(obj))
    # --- Plot [] ---
    # Key functions: scatterPlot
    ---------------------------------------------------------------------
    plot(scatterPlot(obj))
    # --- Addelementtometadataset [] ---
    # Key functions: addElementToMetaDataset, getCells, getCellsSize, dropGenesCells, cellSizePlot
    ---------------------------------------------------------------------
    cellsSizeThr <- 6000L
    obj <- addElementToMetaDataset(obj, "Cells size threshold", cellsSizeThr)
    cells_to_rem <- getCells(obj)[getCellsSize(obj) > cellsSizeThr]
    obj <- dropGenesCells(obj, cells = cells_to_rem)
    # --- Addelementtometadataset [] ---
    # Key functions: addElementToMetaDataset, getCells, getNumExpressedGenes, dropGenesCells, genesSizePlot
    ---------------------------------------------------------------------
    genesSizeHighThr <- 3000L
    obj <- addElementToMetaDataset(obj, "Num genes high threshold",
                                   genesSizeHighThr)
    cells_to_rem <- getCells(obj)[getNumExpressedGenes(obj) > genesSizeHighThr]
    # --- Addelementtometadataset [] ---
    # Key functions: addElementToMetaDataset, dropGenesCells, mitochondrialPercentagePlot
    ---------------------------------------------------------------------
    mitPercThr <- 1.0
    obj <- addElementToMetaDataset(obj, "Mitoc. perc. threshold", mitPercThr)
    cells_to_rem <- rownames(mitSizes)[mitSizes[["mit.percentage"]] > mitPercThr]
    obj <- dropGenesCells(obj, cells = cells_to_rem)
    # --- Getgenes [] ---
    # Key functions: getGenes, getCells, getCellsSize, dropGenesCells
    ---------------------------------------------------------------------
    genes_to_rem <- getGenes(obj)[grep("^Mt", getGenes(obj))]
    cells_to_rem <- getCells(obj)[which(getCellsSize(obj) == 0L)]
    obj <- dropGenesCells(obj, genes_to_rem, cells_to_rem)
    # --- Logthis [] ---
    # Key functions: logThis, getNumCells
    ---------------------------------------------------------------------
    logThis(paste("n cells", getNumCells(obj)), logLevel = 1L)
    # --- Addelementtometadataset [] ---
    # Key functions: addElementToMetaDataset, clean, cleanPlots
    ---------------------------------------------------------------------
    obj <- addElementToMetaDataset(obj, "Num drop B group", 0L)
    obj <- clean(obj)
    c(pcaCellsPlot, pcaCellsData, genesPlot,
      UDEPlot, nuPlot, zoomedNuPlot) %<-% cleanPlots(obj)
    # --- Addelementtometadataset [] ---
    # Key functions: addElementToMetaDataset, getCells, getNu, dropGenesCells
    ---------------------------------------------------------------------
    UDELowThr <- 0.30
    obj <- addElementToMetaDataset(obj, "Low UDE cells' threshold", UDELowThr)
    obj <- addElementToMetaDataset(obj, "Num drop B group", 2L)
    cells_to_rem <- getCells(obj)[getNu(obj) < UDELowThr]
    # --- Clean [] ---
    # Key functions: clean, cleanPlots
    ---------------------------------------------------------------------
    obj <- clean(obj)
    c(pcaCellsPlot, pcaCellsData, genesPlot,
      UDEPlot, nuPlot, zoomedNuPlot) %<-% cleanPlots(obj)
    plot(pcaCellsPlot)
    # --- Plot [] ---
    # Key functions: scatterPlot
    ---------------------------------------------------------------------
    plot(scatterPlot(obj))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cotan_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cotan_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cotan_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_COTAN:", paste0("    cotan: ", packageVersion("COTAN"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cotan_results.csv
    touch ${prefix}_cotan_output.rds
    echo "BIOC_COTAN:" > versions.yml
    echo "    cotan: 0.0.0" >> versions.yml
    """
}


workflow BIOC_COTAN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_COTAN(ch_input)

    emit:
    results  = BIOC_COTAN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_COTAN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_COTAN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_COTAN.out.versions  // channel: path(versions.yml)
}
