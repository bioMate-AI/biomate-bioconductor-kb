#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: dittoSeq
// A universal, user friendly, single-cell and bulk RNA sequencing visualization toolkit that allows hi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/dittoSeq/inst/doc/dittoSeq.R
// Upstream  : BiocStyle, SummarizedExperiment, bluster, scRNAseq, scater
// Downstream: none
//
// Install: BiocManager::install("dittoSeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DITTOSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dittoseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dittoseq:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dittoseq:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(seurat_object)

    output:
    tuple val(meta), path("${meta.id}_dittoseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dittoseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dittoseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(dittoSeq)
    library(BaronPancreasData)
    library(FindMarkers)
    library(Idents)
    library(Seurat)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Metadata and Gene Querying [] ---
    # Key functions: getMetas, isMeta, metaLevels, getGenes, isGene
    meta_slots <- getMetas(bulk_sce)
    has_conds <- isMeta("conditions", bulk_sce)
    cond_levels <- metaLevels("conditions", bulk_sce)
    all_genes <- getGenes(bulk_sce)
    has_gene1 <- isGene("gene1", bulk_sce)
    gene_check <- isGene(
        c("gene1", "gene2", "non-existent"),
        bulk_sce,
        return.values = TRUE
    )


    # --- Dimensionality Reduction and Scatter Visualisation [] ---
    # Key functions: dittoDimPlot, dittoScatterPlot, getReductions
    avail_reductions <- getReductions(bulk_sce)
    dim_plot <- dittoDimPlot(
        object = bulk_sce,
        var = "conditions",
        reduction.use = "pca",
        size = 3,
        do.ellipse = TRUE
    )
    scatter_plot <- dittoScatterPlot(
        object = bulk_sce,
        x.var = "gene1",
        y.var = "gene2",
        color.var = "conditions"
    )


    # --- Expression and Distribution Profiling [] ---
    # Key functions: dittoPlot, dittoBoxPlot, dittoBarPlot, dittoHeatmap
    violin_plot <- dittoPlot(
        object = bulk_sce,
        var = "gene1",
        group.by = "conditions"
    )
    box_plot <- dittoBoxPlot(
        object = bulk_sce,
        var = "gene1",
        group.by = "conditions"
    )
    bar_plot <- dittoBarPlot(
        object = bulk_sce,
        var = "conditions",
        group.by = "conditions"
    )
    heatmap_plot <- dittoHeatmap(
        object = bulk_sce,
        genes = getGenes(bulk_sce)[1:5],
        annot.by = "conditions"
    )


    # --- Hexagonal Binning Visualisation [] ---
    # Key functions: dittoDimHex, dittoScatterHex
    hex_dim_plot <- dittoDimHex(
        object = bulk_sce,
        var = "gene1",
        reduction.use = "pca"
    )
    hex_scatter_plot <- dittoScatterHex(
        object = bulk_sce,
        x.var = "gene1",
        y.var = "gene2",
        color.var = "conditions",
        max.density = 10
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dittoseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dittoseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dittoseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DITTOSEQ:", paste0("    dittoseq: ", packageVersion("dittoSeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dittoseq_results.csv
    touch ${prefix}_dittoseq_output.rds
    echo "BIOC_DITTOSEQ:" > versions.yml
    echo "    dittoseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DITTOSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(seurat_object) ]

    main:
    BIOC_DITTOSEQ(ch_input)

    emit:
    results  = BIOC_DITTOSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DITTOSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DITTOSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DITTOSEQ.out.versions  // channel: path(versions.yml)
}
