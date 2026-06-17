#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ccfindR — bayesian_nmf
// Perform unsupervised clustering of single-cell RNA-seq data using Variational Bayesian NMF to statistically determine the optimal rank and build a hierarchical 
// Input: matrix.mtx, genes.tsv, barcodes.tsv
// Container: quay.io/biocontainers/bioconductor-ccfindr:1.30.0--r45ha27e39d_0
// R packages: ccfindR
// Bioconductor: 3.20 | R: 4.4
// Requires: ccfindR
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read 10x Genomics data into an scNMFSet object
//  * 2. [Core Analysis] Filter cells and genes (including gene rescue)
//  * 3. [Core Analysis] Perform Variational Bayesian NMF factorization across a range of ranks
//  * 4. [Core Analysis] Determine the optimal rank using marginal likelihood (ML)
//  * 5. [Visualization & Output] Visualize basis and coefficient matrices via heatmaps and t-SNE
//  * 6. [Visualization & Output] Build and plot a hierarchical tree of clusters across ranks

nextflow.enable.dsl = 2

process BIOC_CCFINDR_BAYESIAN_NMF {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("ccfindR", "SummarizedExperiment")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
        library(SummarizedExperiment)
        
        # Define directory containing the user input files
        dir <- "."
        
        # 1. Read 10x Genomics data into an scNMFSet object
        sc <- read_10x(dir = dir, count = 'matrix.mtx', genes = 'genes.tsv', barcodes = 'barcodes.tsv')
        
        # 2. Filter cells and genes (including gene rescue)
        pdf("qc_filter_cells.pdf")
        sc <- filter_cells(sc)
        dev.off()
        
        pdf("qc_filter_genes.pdf")
        sc_rescue <- filter_genes(sc, vmr.min = 1.5, min.cells.expressed = 50, rescue.genes = TRUE, progress.bar = FALSE)
        dev.off()
        
        rownames(sc_rescue) <- rowData(sc_rescue)[,2]
        sb <- sc_rescue
        
        # 3. Perform Variational Bayesian NMF factorization across a range of ranks
        set.seed(2)
        sb <- vb_factorize(sb, ranks =3, verbose = 3, Tol = 2e-4, hyper.update.n0 = 5)
        sb <- vb_factorize(sb, ranks = seq(2,7), nrun = 5, verbose = 1, Tol = 1e-4, progress.bar = FALSE)
        
        # 4. Determine the optimal rank using marginal likelihood (ML)
        sb_measure <- measure(sb)
        write.csv(sb_measure, "bayesian_nmf_measures.csv", row.names = FALSE)
        
        pdf("bayesian_nmf_rank_plot.pdf")
        plot(sb)
        dev.off()
        
        opt_rank <- optimal_rank(sb)
        saveRDS(opt_rank, "optimal_rank.rds")
        
        sb_ranks <- ranks(sb)
        basis_ropt_head <- head(basis(sb)[ranks(sb)==opt_rank\$ropt][[1]])
        write.csv(basis_ropt_head, "basis_matrix_rank_opt_head.csv")
        
        # 5. Visualize basis and coefficient matrices via heatmaps and t-SNE
        pdf("feature_map_rank_opt.pdf")
        feature_map(sb, rank = opt_rank\$ropt, max.per.cluster = 4, gene.name = rowData(sb)[,2], cexRow = 0.7)
        dev.off()
        
        cell_type <- paste0('Cluster_', 1:opt_rank\$ropt)
        colnames(basis(sb)[ranks(sb) == opt_rank\$ropt][[1]]) <- cell_type
        rownames(coeff(sb)[ranks(sb) == opt_rank\$ropt][[1]]) <- cell_type
        
        pdf("cell_map_rank_opt.pdf")
        cell_map(sb, rank = opt_rank\$ropt)
        dev.off()
        
        pdf("visualize_clusters_rank_opt.pdf")
        visualize_clusters(sb, rank = opt_rank\$ropt, cex = 0.7)
        dev.off()
        
        # 6. Build and plot a hierarchical tree of clusters across ranks
        tree <- build_tree(sb, rmax = opt_rank\$ropt)
        tree <- rename_tips(tree, rank = opt_rank\$ropt, tip.labels = cell_type)
        
        pdf("hierarchical_tree.pdf")
        plot_tree(tree, cex = 0.8, show.node.label = TRUE)
        dev.off()
        
        # Save final objects
        saveRDS(sb, "scNMFSet_final.rds")
        saveRDS(tree, "hierarchical_tree.rds")

    writeLines(c(
        '"BIOC_CCFINDR_BAYESIAN_NMF":',
        paste0('    ccfindR: ', as.character(packageVersion('ccfindR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bayesian_nmf.csv versions.yml
    """
}

workflow BIOC_CCFINDR_BAYESIAN_NMF_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ matrix.mtx, genes.tsv, barcodes.tsv ] ]

    main:
    BIOC_CCFINDR_BAYESIAN_NMF(ch_input)

    emit:
    tables   = BIOC_CCFINDR_BAYESIAN_NMF.out.tables
    plots    = BIOC_CCFINDR_BAYESIAN_NMF.out.plots
    objects  = BIOC_CCFINDR_BAYESIAN_NMF.out.objects
    versions = BIOC_CCFINDR_BAYESIAN_NMF.out.versions
}
