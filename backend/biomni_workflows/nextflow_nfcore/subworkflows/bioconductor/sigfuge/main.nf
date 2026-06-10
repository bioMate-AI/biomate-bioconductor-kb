#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SigFuge — sigfuge_significance_testing
// Cluster RNA-seq coverage data and test the statistical significance of the resulting clusters.
// Input: coverage_data.RData, clusters.csv
// Container: quay.io/biocontainers/bioconductor-sigfuge:1.44.0--r44hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SigFuge, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the coverage data and cluster assignments
//  * 2. [Visualization & Output] Visualize the coverage curves across clusters using sfPlot
//  * 3. [Core Analysis] Cluster the coverage curves using sfCluster
//  * 4. [Core Analysis] Test the significance of the clusters using sfSignificance

nextflow.enable.dsl = 2

process BIOC_SIGFUGE_SIGFUGE_SIGNIFICANCE_TESTING {
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
    library(SigFuge)
    library(ggplot2)
    
    # 1. Load the coverage data and cluster assignments
    if (!file.exists("coverage_data.RData")) {
      stop("Error: coverage_data.RData not found in the working directory.")
    }
    if (!file.exists("clusters.csv")) {
      stop("Error: clusters.csv not found in the working directory.")
    }
    
    # Load coverage data from RData
    env <- new.env()
    load("coverage_data.RData", envir = env)
    var_names <- names(env)
    if (length(var_names) == 0) {
      stop("Error: Loaded RData file is empty.")
    }
    
    # Identify the coverage data object (matrix or GRanges)
    data_obj <- NULL
    for (var in var_names) {
      obj <- env[[var]]
      if (is.matrix(obj) || inherits(obj, "GRanges") || is.data.frame(obj)) {
        data_obj <- obj
        break
      }
    }
    if (is.null(data_obj)) {
      data_obj <- env[[var_names[1]]]
    }
    if (is.data.frame(data_obj)) {
      data_obj <- as.matrix(data_obj)
    }
    
    # Load cluster assignments
    clusters_df <- read.csv("clusters.csv")
    if ("cluster" %in% colnames(clusters_df)) {
      classlabel <- clusters_df\$cluster
    } else if ("classlabel" %in% colnames(clusters_df)) {
      classlabel <- clusters_df\$classlabel
    } else {
      # Fallback to the last column
      classlabel <- clusters_df[[ncol(clusters_df)]]
    }
    classlabel <- as.factor(classlabel)
    
    # 2. Visualize the coverage curves across clusters using sfPlot
    message("Generating coverage plots...")
    p <- sfPlot(data = data_obj, classlabel = classlabel)
    ggsave("coverage_curves.pdf", plot = p, width = 10, height = 8)
    
    # 3. Cluster the coverage curves using sfCluster
    message("Clustering coverage curves...")
    cluster_results <- sfCluster(data = data_obj)
    saveRDS(cluster_results, "sf_cluster_results.rds")
    
    # Save computed cluster labels if available
    if (!is.null(cluster_results)) {
      if (is.list(cluster_results) && "classlabel" %in% names(cluster_results)) {
        computed_labels <- cluster_results\$classlabel
      } else {
        computed_labels <- cluster_results
      }
      write.csv(data.frame(Sample = seq_along(computed_labels), Cluster = computed_labels), 
                "computed_clusters.csv", row.names = FALSE)
    }
    
    # 4. Test the significance of the clusters using sfSignificance
    message("Testing significance of clusters...")
    sig_result <- sfSignificance(data = data_obj, classlabel = classlabel, nsim = 100)
    saveRDS(sig_result, "sigfuge_significance_result.rds")
    
    # Extract and save significance metrics
    pval <- tryCatch({
      if (is.list(sig_result) && "pval" %in% names(sig_result)) {
        sig_result\$pval
      } else if (is(sig_result, "sigclust") || inherits(sig_result, "sigclust")) {
        sig_result@pval
      } else {
        NA
      }
    }, error = function(e) NA)
    
    pval_norm <- tryCatch({
      if (is.list(sig_result) && "pvalnorm" %in% names(sig_result)) {
        sig_result\$pvalnorm
      } else if (is(sig_result, "sigclust") || inherits(sig_result, "sigclust")) {
        sig_result@pvalnorm
      } else {
        NA
      }
    }, error = function(e) NA)
    
    summary_df <- data.frame(
      Metric = c("p-value", "p-value (normal approximation)"),
      Value = c(pval, pval_norm)
    )
    write.csv(summary_df, "significance_summary.csv", row.names = FALSE)
    
    message("SigFuge significance testing pipeline completed successfully.")

    writeLines(c(
        '"BIOC_SIGFUGE_SIGFUGE_SIGNIFICANCE_TESTING":',
        paste0('    SigFuge: ', as.character(packageVersion('SigFuge')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sigfuge_significance_testing.csv versions.yml
    """
}

workflow BIOC_SIGFUGE_SIGFUGE_SIGNIFICANCE_TESTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ coverage_data.RData, clusters.csv ] ]

    main:
    BIOC_SIGFUGE_SIGFUGE_SIGNIFICANCE_TESTING(ch_input)

    emit:
    tables   = BIOC_SIGFUGE_SIGFUGE_SIGNIFICANCE_TESTING.out.tables
    plots    = BIOC_SIGFUGE_SIGFUGE_SIGNIFICANCE_TESTING.out.plots
    objects  = BIOC_SIGFUGE_SIGFUGE_SIGNIFICANCE_TESTING.out.objects
    versions = BIOC_SIGFUGE_SIGFUGE_SIGNIFICANCE_TESTING.out.versions
}
