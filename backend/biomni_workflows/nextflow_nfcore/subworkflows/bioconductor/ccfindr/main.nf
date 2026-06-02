#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ccfindR
// A collection of tools for cancer genomic data clustering analyses, including those for single cell R
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ccfindR/inst/doc/ccfindR.R
// Upstream  : S4Vectors
// Downstream: none
//
// Install: BiocManager::install("ccfindR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CCFINDR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ccfindr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ccfindr:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ccfindr:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ccfindr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ccfindr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ccfindr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ccfindR)
    library(jsonlite)

    # --- Quality Control and Filtering [] ---
    # Key functions: filter_cells, filter_genes, remove_zeros
    sc_filtered <- filter_cells(sc, umi.min = 10^2.6, umi.max = 10^3.4)
    markers <- c("CD4", "CD8A", "CD8B", "CD19", "CD3G", "CD3D", "CD3Z", "CD14")
    sc_clean <- filter_genes(
        sc_filtered,
        markers = markers,
        vmr.min = 1.5,
        min.cells.expressed = 50,
        rescue.genes = TRUE,
        progress.bar = FALSE
    )
    sc_clean <- remove_zeros(sc_clean)


    # --- Non-negative Matrix Factorization [] ---
    # Key functions: factorize, measure
    sc_fact <- factorize(
        sc_clean,
        ranks = seq(3, 5),
        nrun = 5,
        verbose = 1,
        progress.bar = FALSE
    )
    perf_measures <- measure(sc_fact)


    # --- Bayesian Variational Factorization [] ---
    # Key functions: vb_factorize, optimal_rank, ranks, basis
    sb <- vb_factorize(
        sc_clean,
        ranks = seq(2, 5),
        nrun = 5,
        verbose = 1,
        Tol = 1e-4,
        progress.bar = FALSE
    )
    opt_r <- optimal_rank(sb)
    all_ranks <- ranks(sb)
    basis_mat <- basis(sb)[all_ranks == opt_r][[1]]


    # --- Cluster Visualization and Mapping [] ---
    # Key functions: feature_map, cell_map, visualize_clusters
    markers <- c("CD4", "CD8A", "CD8B", "CD19", "CD3G", "CD3D", "CD3Z", "CD14")
    feature_map(
        sb,
        markers = markers,
        rank = 5,
        max.per.cluster = 4,
        gene.name = rowData(sb)[, 2],
        cexRow = 0.7
    )
    cell_map(sb, rank = 5)
    visualize_clusters(sb, rank = 5, cex = 0.7)


    # --- Hierarchical Tree Construction [] ---
    # Key functions: build_tree, rename_tips, plot_tree
    cell_types <- c("B_cell", "CD8+_T", "CD4+_T", "Monocytes", "NK")
    tree <- build_tree(sb, rmax = 5)
    tree <- rename_tips(tree, rank = 5, tip.labels = cell_types)
    plot_tree(tree, cex = 0.8, show.node.label = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ccfindr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ccfindr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ccfindr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CCFINDR:", paste0("    ccfindr: ", packageVersion("ccfindR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ccfindr_results.csv
    touch ${prefix}_ccfindr_output.rds
    echo "BIOC_CCFINDR:" > versions.yml
    echo "    ccfindr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CCFINDR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CCFINDR(ch_input)

    emit:
    results  = BIOC_CCFINDR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CCFINDR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CCFINDR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CCFINDR.out.versions  // channel: path(versions.yml)
}
