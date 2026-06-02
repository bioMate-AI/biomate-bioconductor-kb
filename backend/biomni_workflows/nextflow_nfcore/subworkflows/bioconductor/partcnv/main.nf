#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: partCNV
// This package uses a statistical framework for rapid and accurate detection of aneuploid cells with l
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/partCNV/inst/doc/partCNV_vignette.R
// Upstream  : Seurat, devtools, ggplot2
// Downstream: none
//
// Install: BiocManager::install("partCNV")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PARTCNV {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-partcnv"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-partcnv:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-partcnv:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_partcnv_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_partcnv_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_partcnv_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CreateSeuratObject)
    library(DimPlot)
    library(FindVariableFeatures)
    library(GetCytoLocation)
    library(GetExprCountCyto)
    library(NormalizeData)
    library(RunPCA)
    library(ScaleData)
    library(jsonlite)

    # --- Normalize Data [] ---
    # Key functions: NormalizeData
    library(Seurat)
    Seurat_obj <- NormalizeData(Your_SeuratObj, normalization.method = "LogNormalize", scale.factor = 10000)
    # --- Get Cyto Location [] ---
    # Key functions: GetCytoLocation
    res <- GetCytoLocation(cyto_feature = "chr20(q11.1-q13.1)")
    # --- Get Expr Count Cyto [] ---
    # Key functions: GetExprCountCyto
    GEout <- GetExprCountCyto(cytoloc_output = res, Counts = as.matrix(SimData), normalization = TRUE, qt_cutoff = 0.99)
    # --- part C N V [] ---
    # Key functions: partCNV
    pcout <- partCNV(int_counts = GEout$ProcessedCount,
    # --- PCA dimensionality reduction [] ---
    # Key functions: CreateSeuratObject, NormalizeData, FindVariableFeatures, ScaleData, RunPCA
    library(Seurat)
    sim_seurat <- CreateSeuratObject(counts = SimData)
    sim_seurat <- NormalizeData(sim_seurat, normalization.method = "LogNormalize", scale.factor = 10000)
    # --- Cluster UMAP/tSNE plot [] ---
    # Key functions: DimPlot
    library(ggplot2)
    DimPlot(sim_seurat, reduction = "umap", group = "partCNV_label") + ggtitle(paste0("partCNV (", signif(p1,2)*100, "%)"))
    # --- Get Cyto Location [] ---
    # Key functions: GetCytoLocation, GetExprCountCyto
    res <- GetCytoLocation(cyto_feature = "chr20(q11.1-q13.1)")
    GEout <- GetExprCountCyto(cytoloc_output = res, Counts = as.matrix(SimData), normalization = TRUE, qt_cutoff = 0.99)
    # --- part C N V H [] ---
    # Key functions: partCNVH
    pcHout <- partCNVH(int_counts = GEout$ProcessedCount,
    # --- PCA dimensionality reduction [] ---
    # Key functions: CreateSeuratObject, NormalizeData, FindVariableFeatures, ScaleData, RunPCA
    library(Seurat)
    sim_seurat <- CreateSeuratObject(counts = SimData)
    sim_seurat <- NormalizeData(sim_seurat, normalization.method = "LogNormalize", scale.factor = 10000)
    # --- Cluster UMAP/tSNE plot [] ---
    # Key functions: DimPlot
    library(ggplot2)
    DimPlot(sim_seurat, reduction = "umap", group = "partCNVH_label") + ggtitle(paste0("partCNVH (", signif(p2,2)*100, "%)"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_partcnv_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_partcnv_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_partcnv_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PARTCNV:", paste0("    partcnv: ", packageVersion("partCNV"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_partcnv_results.csv
    touch ${prefix}_partcnv_output.rds
    echo "BIOC_PARTCNV:" > versions.yml
    echo "    partcnv: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PARTCNV_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PARTCNV(ch_input)

    emit:
    results  = BIOC_PARTCNV.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PARTCNV.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PARTCNV.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PARTCNV.out.versions  // channel: path(versions.yml)
}
