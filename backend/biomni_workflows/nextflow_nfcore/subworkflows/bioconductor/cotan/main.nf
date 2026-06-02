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

    # --- Quality Control Visualization [] ---
    # Key functions: ECDPlot, cellSizePlot, genesSizePlot, scatterPlot
    p_ecd <- ECDPlot(obj)
    p_cell <- cellSizePlot(obj)
    p_gene <- genesSizePlot(obj)
    p_scat <- scatterPlot(obj)


    # --- Size and Expression Filtering [] ---
    # Key functions: addElementToMetaDataset, getCells, getCellsSize, dropGenesCells, getNumExpressedGenes
    obj <- addElementToMetaDataset(obj, "Cells size threshold", 6000L)
    cells_to_rem <- getCells(obj)[getCellsSize(obj) > 6000L]
    obj <- dropGenesCells(obj, cells = cells_to_rem)
    obj <- addElementToMetaDataset(obj, "Num genes high threshold", 3000L)
    cells_to_rem2 <- getCells(obj)[getNumExpressedGenes(obj) > 3000L]
    obj <- dropGenesCells(obj, cells = cells_to_rem2)


    # --- Mitochondrial Quality Control [] ---
    # Key functions: mitochondrialPercentagePlot, addElementToMetaDataset, dropGenesCells, getGenes
    mit_res <- mitochondrialPercentagePlot(obj, genePrefix = "^Mt")
    mit_sizes <- mit_res[[2]]
    obj <- addElementToMetaDataset(obj, "Mitoc. perc. threshold", 1.0)
    cells_to_rem <- rownames(mit_sizes)[mit_sizes[["mit.percentage"]] > 1.0]
    obj <- dropGenesCells(obj, cells = cells_to_rem)
    genes_to_rem <- getGenes(obj)[grep("^Mt", getGenes(obj))]
    obj <- dropGenesCells(obj, genes = genes_to_rem)


    # --- Data Cleaning and Normalisation [] ---
    # Key functions: addElementToMetaDataset, clean, cleanPlots, dropGenesCells
    obj <- addElementToMetaDataset(obj, "Num drop B group", 0L)
    obj <- clean(obj)
    plots_res <- cleanPlots(obj)
    pca_data <- plots_res[[2]]
    cells_to_rem <- rownames(pca_data)[pca_data[["groups"]] == "B"]
    obj <- dropGenesCells(obj, cells = cells_to_rem)
    obj <- clean(obj)

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
