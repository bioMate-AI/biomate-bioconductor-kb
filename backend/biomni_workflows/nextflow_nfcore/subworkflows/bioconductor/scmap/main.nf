#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scmap
// Single-cell RNA-seq (scRNA-seq) is widely used to investigate the composition of complex tissues sin
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scmap/inst/doc/scmap.R
// Upstream  : SingleCellExperiment, googleVis
// Downstream: none
//
// Install: BiocManager::install("scmap")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCMAP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scmap"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scmap:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scmap:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(seurat_object)

    output:
    tuple val(meta), path("${meta.id}_scmap_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scmap_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scmap_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SingleCellExperiment)
    library(jsonlite)

    # --- Singlecellexperiment [] ---
    # Key functions: SingleCellExperiment, logcounts, normcounts, rowData
    ---------------------------------------------------------------------
    sce <- SingleCellExperiment(assays = list(normcounts = as.matrix(yan)), colData = ann)
    logcounts(sce) <- log2(normcounts(sce) + 1)
    # use gene names as feature symbols
    rowData(sce)$feature_symbol <- rownames(sce)
    # --- Selectfeatures [] ---
    # Key functions: selectFeatures
    ---------------------------------------------------------------------
    sce <- selectFeatures(sce, suppress_plot = FALSE)
    # --- Table [] ---
    # Key functions: rowData
    ---------------------------------------------------------------------
    table(rowData(sce)$scmap_features)
    # --- Indexcluster [] ---
    # Key functions: indexCluster
    ---------------------------------------------------------------------
    sce <- indexCluster(sce)
    # --- Head [] ---
    # Key functions: metadata
    ---------------------------------------------------------------------
    head(metadata(sce)$scmap_cluster_index)
    # --- Scmapcluster [] ---
    # Key functions: scmapCluster, metadata
    ---------------------------------------------------------------------
    # --- Dim [] ---
    # Key functions: metadata
    ---------------------------------------------------------------------
    dim(metadata(sce)$scmap_cell_index$subclusters)
    metadata(sce)$scmap_cell_index$subclusters[1:5,1:5]
    # --- Scmapcell [] ---
    # Key functions: scmapCell, metadata
    ---------------------------------------------------------------------
    # --- scmap Cell2 Cluster [] ---
    # Key functions: scmapCell2Cluster, colData
    ---------------------------------------------------------------------

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scmap_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scmap_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scmap_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCMAP:", paste0("    scmap: ", packageVersion("scmap"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scmap_results.csv
    touch ${prefix}_scmap_output.rds
    echo "BIOC_SCMAP:" > versions.yml
    echo "    scmap: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCMAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(seurat_object) ]

    main:
    BIOC_SCMAP(ch_input)

    emit:
    results  = BIOC_SCMAP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCMAP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCMAP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCMAP.out.versions  // channel: path(versions.yml)
}
