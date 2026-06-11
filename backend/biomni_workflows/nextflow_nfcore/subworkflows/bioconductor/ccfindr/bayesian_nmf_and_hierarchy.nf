#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ccfindr — bayesian_nmf_and_hierarchy
// Perform unsupervised clustering of single-cell RNA-seq data using Bayesian NMF, automatically determine the optimal rank, and visualize clusters and their hiera
// Input: matrix.mtx, genes.tsv, barcodes.tsv
// Container: quay.io/biocontainers/bioconductor-ccfindr:1.30.0--r45ha27e39d_0
// R packages: ccfindR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CCFINDR_BAYESIAN_NMF_AND_HIERARCHY {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-ccfindr:1.30.0--r45ha27e39d_0"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("ccfindR")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }
    
    # Load required libraries
    library(ccfindR)
    
    # Define the working directory containing the user input files:
    # - matrix.mtx
    # - genes.tsv
    # - barcodes.tsv
    dir <- "."
    
    # 1. Read 10x Genomics data to create an scNMFSet object
    sc <- read_10x(dir = dir, count = 'matrix.mtx', genes = 'genes.tsv', barcodes = 'barcodes.tsv')
    
    # 2. Filter cells based on UMI count thresholds
    # Capture any diagnostic plots generated during filtering
    pdf("qc_cell_filtering.pdf")
    sc <- filter_cells(sc, umi.min = 10^2.6, umi.max = 10^3.4)
    dev.off()
    
    # Define marker genes
    markers <- c('CD4','CD8A','CD8B','CD19','CD3G','CD3D',
                 'CD3Z','CD14')
    
    # 3. Filter genes with rescue of genes with modes at nonzero counts
    pdf("qc_gene_filtering.pdf")
    sc_rescue <- filter_genes(sc, markers = markers, vmr.min = 1.5, min.cells.expressed = 50,
                              rescue.genes = TRUE, progress.bar = FALSE)
    dev.off()
    
    # Assign gene symbols to row names
    rownames(sc_rescue) <- rowData(sc_rescue)[,2]
    sb <- sc_rescue
    
    # 4. Perform Bayesian NMF factorization across a range of ranks
    set.seed(42) # Ensure reproducibility
    sb <- vb_factorize(sb, ranks = seq(2,7), nrun = 5, verbose = 1, Tol = 1e-4, progress.bar = FALSE)
    
    # 5. Determine the optimal rank using marginal likelihood (evidence)
    measures_df <- measure(sb)
    write.csv(measures_df, "bayesian_nmf_measures.csv", row.names = FALSE)
    
    pdf("rank_evidence_plot.pdf")
    plot(sb)
    dev.off()
    
    opt_rank <- optimal_rank(sb)
    saveRDS(opt_rank, "optimal_rank.rds")
    
    # 6. Visualize basis (feature) and coefficient (cell) maps
    pdf("feature_map.pdf")
    feature_map(sb, markers = markers, rank = 5, max.per.cluster = 4, gene.name = rowData(sb)[,2],
             cexRow = 0.7)
    dev.off()
    
    # Define cell types and assign them to the basis and coefficient matrices for rank 5
    cell_type <- c('B_cell','CD8+_T','CD4+_T','Monocytes','NK')
    colnames(basis(sb)[ranks(sb) == 5][[1]]) <- cell_type
    rownames(coeff(sb)[ranks(sb) == 5][[1]]) <- cell_type
    
    pdf("cell_map.pdf")
    cell_map(sb, rank = 5)
    dev.off()
    
    # 7. Visualize clusters using t-SNE
    pdf("visualize_clusters.pdf")
    visualize_clusters(sb, rank = 5, cex = 0.7)
    dev.off()
    
    # 8. Build and plot a hierarchical tree of clusters across ranks
    tree <- build_tree(sb, rmax = 5)
    tree <- rename_tips(tree, rank = 5, tip.labels = cell_type)
    
    pdf("hierarchical_tree.pdf")
    plot_tree(tree, cex = 0.8, show.node.label = TRUE)
    dev.off()
    
    # Save final objects
    saveRDS(sb, "scNMFSet_final.rds")
    saveRDS(tree, "hierarchical_tree.rds")

    writeLines(c(
        '"BIOC_CCFINDR_BAYESIAN_NMF_AND_HIERARCHY":',
        paste0('        ccfindr: ', as.character(packageVersion("ccfindr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bayesian_nmf_and_hierarchy.csv versions.yml
    """
}

workflow BIOC_CCFINDR_BAYESIAN_NMF_AND_HIERARCHY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ matrix.mtx, genes.tsv, barcodes.tsv ] ]

    main:
    BIOC_CCFINDR_BAYESIAN_NMF_AND_HIERARCHY(ch_input)

    emit:
    tables   = BIOC_CCFINDR_BAYESIAN_NMF_AND_HIERARCHY.out.tables
    plots    = BIOC_CCFINDR_BAYESIAN_NMF_AND_HIERARCHY.out.plots
    objects  = BIOC_CCFINDR_BAYESIAN_NMF_AND_HIERARCHY.out.objects
    versions = BIOC_CCFINDR_BAYESIAN_NMF_AND_HIERARCHY.out.versions
}
