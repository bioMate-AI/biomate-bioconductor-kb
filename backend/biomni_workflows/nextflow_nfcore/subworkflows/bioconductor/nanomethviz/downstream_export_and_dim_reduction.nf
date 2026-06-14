#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: NanoMethViz — downstream_export_and_dim_reduction
// Export methylation data to BSseq and edgeR formats, and perform dimensionality reduction (MDS/PCA).
// Input: nmr
// Container: quay.io/biocontainers/bioconductor-nanomethviz:2.8.1--r43hf17093f_0
// R packages: NanoMethViz, dplyr, ggplot2
// Bioconductor: 3.20 | R: 4.4
// Requires: NanoMethViz, dplyr, ggplot2
// Visualizations: MDS plot, PCA plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert NanoMethResult to BSseq using methy_to_bsseq()
//  * 2. [Core Analysis] Convert BSseq to edgeR format using bsseq_to_edger()
//  * 3. [Core Analysis] Convert BSseq to log-methylation-ratio matrix using bsseq_to_log_methy_ratio()
//  * 4. [Visualization & Output] Plot MDS using plot_mds() or PCA using plot_pca()

nextflow.enable.dsl = 2

process BIOC_NANOMETHVIZ_DOWNSTREAM_EXPORT_AND_DIM_REDUCTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("NanoMethViz", "dplyr", "ggplot2")
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
        library(NanoMethViz)
        library(dplyr)
        library(ggplot2)
        
        # 1. Load User Input
        # The pipeline reads the 'nmr' (NanoMethResult object) from the working directory.
        if (file.exists("nmr")) {
            nmr <- readRDS("nmr")
        } else if (file.exists("nmr.rds")) {
            nmr <- readRDS("nmr.rds")
        } else {
            stop("Error: Input file 'nmr' or 'nmr.rds' not found in the working directory.")
        }
        
        # 2. Convert NanoMethResult to BSseq
        bss <- methy_to_bsseq(nmr)
        saveRDS(bss, "bss.rds")
        
        # 3. Convert BSseq to edgeR format
        gene_regions <- exons_to_genes(NanoMethViz::exons(nmr))
        edger_mat <- bsseq_to_edger(bss, gene_regions)
        write.csv(as.data.frame(edger_mat), "edger_mat.csv", row.names = TRUE)
        
        # 4. Convert BSseq to log-methylation-ratio matrix
        lmr <- bsseq_to_log_methy_ratio(bss, regions = gene_regions)
        write.csv(as.data.frame(lmr), "lmr.csv", row.names = TRUE)
        
        # 5. Dimensionality Reduction and Plotting
        # Plot 1: Basic MDS
        p1 <- plot_mds(lmr) +
            ggtitle("MDS Plot")
        ggsave("plot_mds_basic.pdf", plot = p1, width = 7, height = 5)
        
        # Plot 2: Basic PCA
        p2 <- plot_pca(lmr) +
            ggtitle("PCA Plot")
        ggsave("plot_pca_basic.pdf", plot = p2, width = 7, height = 5)
        
        # Plot 3: Labeled MDS
        new_labels <- colnames(lmr)
        groups <- colnames(lmr)
        
        p3 <- plot_mds(lmr, labels = new_labels, groups = groups) +
            ggtitle("MDS Plot")
        ggsave("plot_mds_labeled.pdf", plot = p3, width = 7, height = 5)
        
        # Plot 4: Unlabeled MDS
        p4 <- plot_mds(lmr, labels = NULL, groups = groups) +
            ggtitle("MDS Plot")
        ggsave("plot_mds_unlabeled.pdf", plot = p4, width = 7, height = 5)

    writeLines(c(
        '"BIOC_NANOMETHVIZ_DOWNSTREAM_EXPORT_AND_DIM_REDUCTION":',
        paste0('    NanoMethViz: ', as.character(packageVersion('NanoMethViz')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_downstream_export_and_dim_reduction.csv versions.yml
    """
}

workflow BIOC_NANOMETHVIZ_DOWNSTREAM_EXPORT_AND_DIM_REDUCTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ nmr ] ]

    main:
    BIOC_NANOMETHVIZ_DOWNSTREAM_EXPORT_AND_DIM_REDUCTION(ch_input)

    emit:
    tables   = BIOC_NANOMETHVIZ_DOWNSTREAM_EXPORT_AND_DIM_REDUCTION.out.tables
    plots    = BIOC_NANOMETHVIZ_DOWNSTREAM_EXPORT_AND_DIM_REDUCTION.out.plots
    objects  = BIOC_NANOMETHVIZ_DOWNSTREAM_EXPORT_AND_DIM_REDUCTION.out.objects
    versions = BIOC_NANOMETHVIZ_DOWNSTREAM_EXPORT_AND_DIM_REDUCTION.out.versions
}
