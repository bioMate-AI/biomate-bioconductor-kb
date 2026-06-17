#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Melissa — melissa_clustering_imputation
// Jointly cluster single-cell methylomes and impute missing methylation states.
// Input: single_cell_methylome_data
// Container: quay.io/biocontainers/bioconductor-melissa:1.22.0--r44hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BPRMeth, GenomicRanges, Melissa, ggplot2
// Visualizations: bar plot, cluster plot
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Joint clustering and imputation of single-cell methylomes (no specific functions are documented in the provided text)

nextflow.enable.dsl = 2

process BIOC_MELISSA_MELISSA_CLUSTERING_IMPUTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("Melissa", "BPRMeth", "GenomicRanges", "ggplot2")
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
    library(Melissa)
    library(BPRMeth)
    library(GenomicRanges)
    library(ggplot2)
    
    # Define input file path
    input_file <- "single_cell_methylome_data"
    
    # Read the single-cell DNA methylation profiles
    # The input is expected to be an RDS file containing a list of cells,
    # where each cell is a list of genomic regions (matrices/data.frames of CpG sites).
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    message("Reading single-cell methylome data...")
    X <- readRDS(input_file)
    
    # Create Radial Basis Function (RBF) object using BPRMeth
    # M = 4 is a standard default for the number of basis functions
    message("Creating basis functions...")
    basis <- BPRMeth::create_rbf_object(M = 4)
    
    # Set the number of clusters (K)
    # Defaulting to 2 clusters, but can be adjusted based on biological expectation
    K <- 2
    
    # Run Melissa joint clustering and imputation model
    message("Running Melissa joint clustering and imputation...")
    res <- Melissa::melissa(
      X = X,
      K = K,
      basis = basis,
      max_iter = 100
    )
    
    # Perform imputation of missing methylation states using the trained model
    message("Imputing missing methylation states...")
    imputed_data <- Melissa::impute_methylome(
      X = X,
      obj = res
    )
    
    # Save the complete model results and imputed methylomes
    message("Saving results...")
    saveRDS(res, "melissa_model_results.rds")
    saveRDS(imputed_data, "imputed_methylomes.rds")
    
    # Extract cell names or generate default ones
    cell_names <- names(X)
    if (is.null(cell_names)) {
      cell_names <- paste0("Cell_", seq_along(X))
    }
    
    # Extract and save cluster assignments
    clusters <- NULL
    if (!is.null(res\$labels)) {
      clusters <- res\$labels
    } else if (!is.null(res\$r_nk)) {
      clusters <- max.col(res\$r_nk)
    }
    
    if (!is.null(clusters)) {
      df_clusters <- data.frame(
        Cell = cell_names,
        Cluster = clusters,
        stringsAsFactors = FALSE
      )
      write.csv(df_clusters, "cluster_assignments.csv", row.names = FALSE)
    }
    
    # Extract and save posterior cluster probabilities (responsibilities)
    if (!is.null(res\$r_nk)) {
      df_resp <- as.data.frame(res\$r_nk)
      colnames(df_resp) <- paste0("Cluster_", seq_len(ncol(df_resp)))
      df_resp <- cbind(Cell = cell_names, df_resp)
      write.csv(df_resp, "cluster_probabilities.csv", row.names = FALSE)
    }
    
    # Generate diagnostic plot of cluster responsibilities
    pdf("cluster_responsibilities_plot.pdf", width = 8, height = 6)
    if (!is.null(res\$r_nk)) {
      barplot(
        t(res\$r_nk),
        col = terrain.colors(K),
        main = "Cell Cluster Responsibilities",
        xlab = "Cells",
        ylab = "Probability",
        legend.text = paste("Cluster", seq_len(K)),
        args.legend = list(x = "topright", bty = "n")
      )
    } else {
      plot.new()
      text(0.5, 0.5, "No responsibility data available to plot", cex = 1.2)
    }
    dev.off()
    
    message("Pipeline completed successfully.")
    # ── BIOC_QC_HARNESS — Phase 3c bulk adoption (missing-value handling) ───
    # Defensive scan: list every *.rds the workflow produced, load each one,
    # compute NA fraction across numeric cells where the artifact is a
    # matrix or data.frame. Report max NA fraction across artifacts.
    # Threshold from bioc_missing_value_handling: < 5% pass.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()
    .na_fracs <- numeric(0)
    .scanned_files <- character(0)
    for (.rds_file in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .obj <- tryCatch(readRDS(.rds_file), error = function(e) NULL)
      .mat <- if (is.matrix(.obj) || is.data.frame(.obj)) .obj else NULL
      if (!is.null(.mat)) {
        .vals <- suppressWarnings(as.numeric(as.matrix(.mat)))
        if (length(.vals) > 0) {
          .na_fracs <- c(.na_fracs, mean(is.na(.vals)))
          .scanned_files <- c(.scanned_files, .rds_file)
        }
      }
    }
    .na_max <- if (length(.na_fracs) > 0) round(max(.na_fracs), 4) else NA_real_
    .gates_by_label[["missing-value handling"]] <- list(
      gate_row = "bioc_missing_value_handling",
      metric_name = "na_fraction_remaining",
      metric_value = .na_max,
      passes = isTRUE(is.finite(.na_max) && .na_max < 0.05),
      status = if (is.finite(.na_max)) paste0("computed (scanned ", length(.scanned_files), " rds files)")
               else "not_computed (no matrix/data.frame .rds artifact present)"
    )
    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_MELISSA_MELISSA_CLUSTERING_IMPUTATION",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_MELISSA_MELISSA_CLUSTERING_IMPUTATION":',
        paste0('    Melissa: ', as.character(packageVersion('Melissa')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_melissa_clustering_imputation.csv versions.yml
    """
}

workflow BIOC_MELISSA_MELISSA_CLUSTERING_IMPUTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ single_cell_methylome_data ] ]

    main:
    BIOC_MELISSA_MELISSA_CLUSTERING_IMPUTATION(ch_input)

    emit:
    tables   = BIOC_MELISSA_MELISSA_CLUSTERING_IMPUTATION.out.tables
    plots    = BIOC_MELISSA_MELISSA_CLUSTERING_IMPUTATION.out.plots
    objects  = BIOC_MELISSA_MELISSA_CLUSTERING_IMPUTATION.out.objects
    versions = BIOC_MELISSA_MELISSA_CLUSTERING_IMPUTATION.out.versions
}
