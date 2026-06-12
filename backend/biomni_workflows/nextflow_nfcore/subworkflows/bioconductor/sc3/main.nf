#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SC3 — standard_sc3_clustering
// Run the standard SC3 clustering and biological analysis pipeline using the high-level wrapper function and visualize the results.
// Input: expression_matrix.csv, cell_metadata.csv
// Container: quay.io/biocontainers/bioconductor-sc3:1.38.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SC3, SingleCellExperiment
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a SingleCellExperiment object with counts and logcounts assays
//  * 2. [Input & Preparation] Define unique feature symbols in rowData
//  * 3. [Core Analysis] Run the main sc3 wrapper function
//  * 4. [Visualization & Output] Visualize results using interactive Shiny app or static plotting functions

nextflow.enable.dsl = 2

process BIOC_SC3_STANDARD_SC3_CLUSTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("SC3", "SummarizedExperiment")
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
            
    # Load required librarie    library(SummarizedExperiment)
s
    library(SC3)
    
    # Read user input files
    yan <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
    ann <- read.csv("cell_metadata.csv", row.names = 1, check.names = FALSE)
    
    # Create a SingleCellExperiment object
    sce <- SingleCellExperiment(
        assays = list(
            counts = as.matrix(yan),
            logcounts = log2(as.matrix(yan) + 1)
        ), 
        colData = ann
    )
    
    # define feature names in feature_symbol column
    rowData(sce)\$feature_symbol <- rownames(sce)
    # remove features with duplicated names
    sce <- sce[!duplicated(rowData(sce)\$feature_symbol), ]
    
    # Run SC3 clustering
    sce <- sc3(sce, ks = 2:4, biology = TRUE)
    
    # Save plots to PDF
    pdf("sc3_plots.pdf", width = 8, height = 8)
    
    print(sc3_plot_consensus(sce, k = 3))
    
    print(sc3_plot_consensus(
        sce, k = 3, 
        show_pdata = c(
            "sc3_3_clusters", 
            "sc3_3_log2_outlier_score"
        )
    ))
    
    print(sc3_plot_silhouette(sce, k = 3))
    
    print(sc3_plot_expression(sce, k = 3))
    
    print(sc3_plot_cluster_stability(sce, k = 3))
    
    print(sc3_plot_de_genes(sce, k = 3))
    
    print(sc3_plot_markers(sce, k = 3))
    
    dev.off()
    
    # Save results to files
    write.csv(as.data.frame(colData(sce)), "sc3_cell_metadata_results.csv", row.names = TRUE)
    write.csv(as.data.frame(rowData(sce)), "sc3_gene_metadata_results.csv", row.names = TRUE)
    saveRDS(sce, "sc3_sce_output.rds")

    writeLines(c(
        '"BIOC_SC3_STANDARD_SC3_CLUSTERING":',
        paste0('    SC3: ', as.character(packageVersion('SC3')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_sc3_clustering.csv versions.yml
    """
}

workflow BIOC_SC3_STANDARD_SC3_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, cell_metadata.csv ] ]

    main:
    BIOC_SC3_STANDARD_SC3_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_SC3_STANDARD_SC3_CLUSTERING.out.tables
    plots    = BIOC_SC3_STANDARD_SC3_CLUSTERING.out.plots
    objects  = BIOC_SC3_STANDARD_SC3_CLUSTERING.out.objects
    versions = BIOC_SC3_STANDARD_SC3_CLUSTERING.out.versions
}
