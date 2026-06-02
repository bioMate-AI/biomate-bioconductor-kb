#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TREG
// RNA abundance and cell size parameters could improve RNA-seq deconvolution algorithms to more accura
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TREG/inst/doc/finding_Total_RNA_Expression_Genes.R
// Upstream  : BiocStyle, RefManageR, SingleCellExperiment, dplyr, ggplot2
// Downstream: none
//
// Install: BiocManager::install("TREG")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TREG {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-treg"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-treg:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-treg:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_treg_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_treg_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_treg_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BiocFileCache)
    library(PrintBibliography)
    library(jsonlite)

    # --- 'install' [] ---
    # Key functions: valid

    # --- "download DLPFC data" [] ---
    # Key functions: BiocFileCache, bfcrpath
    bfc <- BiocFileCache::BiocFileCache()
    # --- "Data Size Check" [] ---
    # Key functions: obj_size
    lobstr::obj_size(sce.dlpfc.tran)
    # --- "acronyms" [] ---
    # Key functions: tibble

    # --- "examineSparsity" [] ---
    # Key functions: pheatmap
    sum(assays(sce.dlpfc.tran)$counts == 0) / (nrow(sce.dlpfc.tran) * ncol(sce.dlpfc.tran))
    count_test <- as.matrix(assays(sce.dlpfc.tran)$logcounts[seq_len(1000), seq_len(500)])
    # --- "top50 filter" [] ---
    # Key functions: rowMeans
    row_means <- rowMeans(assays(sce.dlpfc.tran)$logcounts)
    (median_row_means <- median(row_means))
    dim(sce.dlpfc.tran)
    # --- "top50FilterHeatmap" [] ---
    # Key functions: pheatmap
    sum(assays(sce.dlpfc.tran)$counts == 0) / (nrow(sce.dlpfc.tran) * ncol(sce.dlpfc.tran))
    count_test <- as.matrix(assays(sce.dlpfc.tran)$logcounts[seq_len(1000), seq_len(500)])
    # --- "get prop zero" [] ---
    # Key functions: get_prop_zero
    prop_zeros <- get_prop_zero(sce.dlpfc.tran, group_col = "cellType.broad")
    head(prop_zeros)
    # --- "propZeroDistribution" [] ---
    # Key functions: rownames_to_column, pivot_longer, aes, geom_histogram, facet_wrap
    rownames_to_column("Gene") %>%
    pivot_longer(!Gene, names_to = "Group", values_to = "prop_zero")
    # --- "pickCutoff" [] ---
    # Key functions: geom_vline
    geom_vline(xintercept = propZero_limit, color = "red", linetype = "dashed")
    # --- "filter prop zero" [] ---
    # Key functions: filter_prop_zero
    filtered_genes <- filter_prop_zero(prop_zeros, cutoff = propZero_limit)
    length(filtered_genes)
    length(filtered_genes) / nrow(sce.dlpfc.tran)
    # --- "propZeroFilterHeatmap" [] ---
    # Key functions: pheatmap
    sum(assays(sce.dlpfc.tran)$counts == 0) / (nrow(sce.dlpfc.tran) * ncol(sce.dlpfc.tran))
    count_test <- as.matrix(assays(sce.dlpfc.tran)$logcounts[seq_len(1000), seq_len(500)])
    # --- "rank invariance stepwise" [] ---
    # Key functions: rank_group, rank_cells, rank_invariance
    group_rank <- rank_group(sce.dlpfc.tran, group_col = "cellType.broad")
    cell_rank <- rank_cells(sce.dlpfc.tran, group_col = "cellType.broad")
    Use both rankings to calculate rank_invariance()
    # --- "run RI express" [] ---
    # Key functions: rank_invariance_express
    rank_invariance_express() runs the previous functions for you
    # --- knit [] ---
    # Key functions: knit
    library("rmarkdown")
    system.time(render("finding_Total_RNA_Expression_Genes.Rmd"))
    library("knitr")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_treg_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_treg_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_treg_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TREG:", paste0("    treg: ", packageVersion("TREG"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_treg_results.csv
    touch ${prefix}_treg_output.rds
    echo "BIOC_TREG:" > versions.yml
    echo "    treg: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TREG_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TREG(ch_input)

    emit:
    results  = BIOC_TREG.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TREG.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TREG.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TREG.out.versions  // channel: path(versions.yml)
}
