#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ILoReg
// ILoReg is a tool for identification of cell populations from scRNA-seq data. In particular, ILoReg i
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ILoReg/inst/doc/ILoReg.R
// Upstream  : SingleCellExperiment, cowplot
// Downstream: none
//
// Install: BiocManager::install("ILoReg")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ILOREG {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-iloreg"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-iloreg:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-iloreg:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_iloreg_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_iloreg_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_iloreg_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AnnotationScatterPlot)
    library(ClusteringScatterPlot)
    library(GeneHeatmap)
    library(GeneScatterPlot)
    library(RenameAllClusters)
    library(RenameCluster)
    library(SelectKClusters)
    library(VlnPlot)
    library(jsonlite)

    # --- Violin plot per cluster [] ---
    # Key functions: VlnPlot
    VlnPlot(sce,genes = c("CD3D"),return.plot = FALSE,rotate.x.axis.labels = TRUE)
    # --- Grid analysis [] ---
    # Key functions: plot_grid, ClusteringScatterPlot, GeneScatterPlot, GeneHeatmap, RenameAllClusters, SelectKClusters, RenameCluster, mapvalues
    sce <- SelectKClusters(sce,K=5)
    custom_annotation <- plyr::mapvalues(metadata(sce)$iloreg$clustering.manual,c(1,2,3,4,5),LETTERS[1:5])
    AnnotationScatterPlot(sce,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_iloreg_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_iloreg_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_iloreg_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ILOREG:", paste0("    iloreg: ", packageVersion("ILoReg"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_iloreg_results.csv
    touch ${prefix}_iloreg_output.rds
    echo "BIOC_ILOREG:" > versions.yml
    echo "    iloreg: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ILOREG_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ILOREG(ch_input)

    emit:
    results  = BIOC_ILOREG.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ILOREG.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ILOREG.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ILOREG.out.versions  // channel: path(versions.yml)
}
