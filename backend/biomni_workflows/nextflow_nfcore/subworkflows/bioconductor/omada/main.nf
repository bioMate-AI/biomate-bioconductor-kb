#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: omada — automated_clustering_cascade
// Run the entire automated machine learning cascade to select features, determine the optimal number of clusters, and perform clustering on gene expression data.
// Input: expression_matrix.csv
// Container: quay.io/biocontainers/bioconductor-omada:1.12.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: omada
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run the automated cascade using omada
//  * 2. [Core Analysis] Extract partition agreement, feature selection, cluster voting, and sample membership results
//  * 3. [Visualization & Output] Plot the diagnostic results

nextflow.enable.dsl = 2

process BIOC_OMADA_AUTOMATED_CLUSTERING_CASCADE {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(omada)
    
    # Read the user-provided gene expression matrix
    # The file must be in the working directory, with samples as rows/columns and no NA values.
    if (!file.exists("expression_matrix.csv")) {
      stop("Error: 'expression_matrix.csv' not found in the working directory.")
    }
    
    # Load the data. We assume the first column contains row names (e.g., sample or gene IDs).
    toy_genes <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
    
    # Run the automated machine learning cascade
    omada.analysis <- omada(toy_genes, method.upper.k = 6)
    
    # Extract partition agreement, feature selection, cluster voting, and sample membership results
    pa.scores <- get_partition_agreement_scores(omada.analysis)
    fs.scores <- get_feature_selection_scores(omada.analysis)
    fs.optimal.features <- 
      get_feature_selection_optimal_features(omada.analysis)
    fs.optimal.number.of.features <- 
      get_feature_selection_optimal_number_of_features(omada.analysis)
    
    cv.scores <- get_cluster_voting_scores(omada.analysis)
    cv.memberships <- get_cluster_voting_memberships(omada.analysis)
    cv.metrics.votes <- get_cluster_voting_metric_votes(omada.analysis)
    cv.k.votes <- get_cluster_voting_k_votes(omada.analysis)
    sample.memberships <- get_sample_memberships(omada.analysis)
    
    # Save the main analysis object
    saveRDS(omada.analysis, "omada_analysis.rds")
    
    # Helper function to safely write outputs to CSV or RDS depending on structure
    save_output <- function(obj, filename) {
      tryCatch({
        if (is.data.frame(obj) || is.matrix(obj)) {
          write.csv(obj, filename, row.names = TRUE)
        } else if (is.list(obj)) {
          saveRDS(obj, gsub("\\\\.csv\$", ".rds", filename))
        } else {
          write.csv(data.frame(Value = obj), filename, row.names = TRUE)
        }
      }, error = function(e) {
        warning(paste("Could not write output to", filename, ":", e\$message))
      })
    }
    
    # Save extracted results to files
    save_output(pa.scores, "partition_agreement_scores.csv")
    save_output(fs.scores, "feature_selection_scores.csv")
    
    tryCatch({
      writeLines(as.character(fs.optimal.features), "fs_optimal_features.txt")
    }, error = function(e) {
      warning("Could not write fs_optimal_features.txt")
    })
    
    tryCatch({
      writeLines(as.character(fs.optimal.number.of.features), "fs_optimal_number_of_features.txt")
    }, error = function(e) {
      warning("Could not write fs_optimal_number_of_features.txt")
    })
    
    save_output(cv.scores, "cluster_voting_scores.csv")
    save_output(cv.memberships, "cluster_voting_memberships.csv")
    save_output(cv.metrics.votes, "cluster_voting_metric_votes.csv")
    save_output(cv.k.votes, "cluster_voting_k_votes.csv")
    save_output(sample.memberships, "sample_memberships.csv")
    
    # Plot diagnostic results to PDF files
    pdf("partition_agreement_plot.pdf")
    print(plot_partition_agreement(omada.analysis))
    dev.off()
    
    pdf("feature_selection_plot.pdf")
    print(plot_feature_selection(omada.analysis))
    dev.off()
    
    pdf("cluster_voting_plot.pdf")
    print(plot_cluster_voting(omada.analysis))
    dev.off()

    writeLines(c(
        '"BIOC_OMADA_AUTOMATED_CLUSTERING_CASCADE":',
        paste0('    omada: ', as.character(packageVersion('omada')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_automated_clustering_cascade.csv versions.yml
    """
}

workflow BIOC_OMADA_AUTOMATED_CLUSTERING_CASCADE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv ] ]

    main:
    BIOC_OMADA_AUTOMATED_CLUSTERING_CASCADE(ch_input)

    emit:
    tables   = BIOC_OMADA_AUTOMATED_CLUSTERING_CASCADE.out.tables
    plots    = BIOC_OMADA_AUTOMATED_CLUSTERING_CASCADE.out.plots
    objects  = BIOC_OMADA_AUTOMATED_CLUSTERING_CASCADE.out.objects
    versions = BIOC_OMADA_AUTOMATED_CLUSTERING_CASCADE.out.versions
}
