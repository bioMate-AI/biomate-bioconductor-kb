#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scDotPlot
// Dot plots of single-cell RNA-seq data allow for an examination of the relationships between cell gro
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scDotPlot/inst/doc/scDotPlot.R
// Upstream  : AnnotationDbi, Seurat, SeuratObject, dplyr, ggsci
// Downstream: none
//
// Install: BiocManager::install("scDotPlot")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCDOTPLOT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scdotplot"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scdotplot:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scdotplot:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(seurat_object)

    output:
    tuple val(meta), path("${meta.id}_scdotplot_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scdotplot_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scdotplot_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(scDotPlot)
    library(DefaultAssay)
    library(FindAllMarkers)
    library(ZeiselBrainData)
    library(jsonlite)

    # --- Scaled SingleCellExperiment Dot Plot Visualization [] ---
    # Key functions: scDotPlot
    plot_sce_scaled <- scDotPlot(
        object = sce,
        scale = TRUE,
        features = features,
        group = "level2class",
        groupAnno = "level1class",
        featureAnno = "Marker",
        groupLegends = FALSE,
        annoColors = list(
            "level1class" = ggsci::pal_d3()(7),
            "Marker" = ggsci::pal_d3()(7)
        ),
        annoWidth = 0.02
    )


    # --- Seurat Dot Plot Visualization [] ---
    # Key functions: scDotPlot
    plot_seurat <- scDotPlot(
        object = pbmc_small,
        features = features,
        group = "RNA_snn_res.1",
        groupAnno = "RNA_snn_res.1",
        featureAnno = "cluster",
        annoColors = list(
            "RNA_snn_res.1" = ggsci::pal_d3()(7),
            "cluster" = ggsci::pal_d3()(7)
        ),
        groupLegends = FALSE,
        annoWidth = 0.075
    )


    # --- Scaled Seurat Dot Plot Visualization [] ---
    # Key functions: scDotPlot
    plot_seurat_scaled <- scDotPlot(
        object = pbmc_small,
        scale = TRUE,
        features = features,
        group = "RNA_snn_res.1",
        groupAnno = "RNA_snn_res.1",
        featureAnno = "cluster",
        annoColors = list(
            "RNA_snn_res.1" = ggsci::pal_d3()(7),
            "cluster" = ggsci::pal_d3()(7)
        ),
        groupLegends = FALSE,
        annoWidth = 0.075
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scdotplot_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scdotplot_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scdotplot_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCDOTPLOT:", paste0("    scdotplot: ", packageVersion("scDotPlot"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scdotplot_results.csv
    touch ${prefix}_scdotplot_output.rds
    echo "BIOC_SCDOTPLOT:" > versions.yml
    echo "    scdotplot: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCDOTPLOT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(seurat_object) ]

    main:
    BIOC_SCDOTPLOT(ch_input)

    emit:
    results  = BIOC_SCDOTPLOT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCDOTPLOT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCDOTPLOT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCDOTPLOT.out.versions  // channel: path(versions.yml)
}
