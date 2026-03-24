#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: smoothclust
// Method for segmentation of spatial domains and spatially-aware clustering in spatial transcriptomics
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/smoothclust/inst/doc/smoothclust.R
// Upstream  : STexampleData, ggspavis, scater, scran, scuttle
// Downstream: none
//
// Install: BiocManager::install("smoothclust")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SMOOTHCLUST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-smoothclust"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-smoothclust:1.2.2--r44_0' :
        'quay.io/biocontainers/bioconductor-smoothclust:1.2.2--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_smoothclust_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_smoothclust_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_smoothclust_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Visium_humanDLPFC)
    library(jsonlite)

    # --- Visium Humandlpfc [] ---
    # Key functions: Visium_humanDLPFC, colData, assayNames
    ---------------------------------------------------------------------
    # load data
    spe <- Visium_humanDLPFC()
    # keep spots over tissue
    spe <- spe[, colData(spe)$in_tissue == 1]
    # --- Assaynames [] ---
    # Key functions: assayNames
    ---------------------------------------------------------------------
    # check output object
    assayNames(spe)
    # --- Lognormcounts [] ---
    # Key functions: logNormCounts, assayNames
    ---------------------------------------------------------------------
    # calculate logcounts
    spe <- logNormCounts(spe, assay.type = "counts_smooth")
    assayNames(spe)
    # --- Grepl [] ---
    # Key functions: rowData, genes, modelGeneVar, getTopHVGs
    ---------------------------------------------------------------------
    # preprocessing steps for clustering
    # remove mitochondrial genes
    is_mito <- grepl("(^mt-)", rowData(spe)$gene_name, ignore.case = TRUE)
    table(is_mito)
    # --- Unname [] ---
    # Key functions: unname, colors, plotSpots
    ---------------------------------------------------------------------
    # color palettes
    pal8 <- "libd_layer_colors"
    pal36 <- unname(palette.colors(36, "Polychrome 36"))
    # plot clusters / spatial domains
    # --- Plotspots [] ---
    # Key functions: plotSpots
    ---------------------------------------------------------------------
    # plot reference labels
    plotSpots(spe, annotate = "ground_truth", pal = pal8)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_smoothclust_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_smoothclust_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_smoothclust_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SMOOTHCLUST:", paste0("    smoothclust: ", packageVersion("smoothclust"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_smoothclust_results.csv
    touch ${prefix}_smoothclust_output.rds
    echo "BIOC_SMOOTHCLUST:" > versions.yml
    echo "    smoothclust: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SMOOTHCLUST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_SMOOTHCLUST(ch_input)

    emit:
    results  = BIOC_SMOOTHCLUST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SMOOTHCLUST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SMOOTHCLUST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SMOOTHCLUST.out.versions  // channel: path(versions.yml)
}
