#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: paircompviz — paircomp_visualization
// Perform pairwise multiple comparison tests on highly variable features from a feature-by-sample matrix and visualize the significant differences using Hasse dia
// Input: input.csv
// Container: 1.48.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: paircompviz
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PAIRCOMPVIZ_PAIRCOMP_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("paircompviz")
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
    library(paircompviz)
    library(stats)
    
    # Define parameters
    p_adjust_method <- "holm"
    significance_level <- 0.05
    num_features <- 6
    
    # ==========================================
    # --- Read and Preprocess Input Data ---
    # ==========================================
    if (!file.exists("input.csv")) {
      stop("Input file 'input.csv' not found.")
    }
    
    # Read the feature-by-sample matrix
    data_matrix <- read.csv("input.csv", row.names = 1, check.names = FALSE)
    
    # If 'feature_id' is a column instead of row names, set it properly
    if ("feature_id" %in% colnames(data_matrix)) {
      rownames(data_matrix) <- data_matrix\$feature_id
      data_matrix\$feature_id <- NULL
    }
    
    # Ensure data is numeric
    data_matrix <- as.matrix(data_matrix)
    class(data_matrix) <- "numeric"
    
    # Handle small datasets gracefully
    num_features <- min(num_features, nrow(data_matrix))
    if (num_features < 2) {
      stop("At least 2 features are required for pairwise comparison.")
    }
    
    # ==========================================
    # --- Feature Selection & Reshaping ---
    # ==========================================
    # Select the top highly variable features to keep the Hasse diagram readable
    feature_variances <- apply(data_matrix, 1, var, na.rm = TRUE)
    top_feature_names <- names(sort(feature_variances, decreasing = TRUE))[1:num_features]
    selected_data <- data_matrix[top_feature_names, , drop = FALSE]
    
    # Reshape the selected features into a long format for pairwise testing
    # response: numeric values, grouping: feature identifiers
    df_long <- data.frame(
      value = as.vector(t(selected_data)),
      feature = factor(rep(rownames(selected_data), each = ncol(selected_data)))
    )
    df_long <- na.omit(df_long)
    
    # ==========================================
    # --- Pairwise Comparisons & CSV Export ---
    # ==========================================
    # Perform pairwise t-test
    pairwise_results <- pairwise.t.test(
      x = df_long\$value,
      g = df_long\$feature,
      p.adjust.method = p_adjust_method
    )
    
    # Convert the lower triangular p-value matrix to a tidy data frame
    p_matrix <- pairwise_results\$p.value
    p_df <- as.data.frame(as.table(p_matrix))
    colnames(p_df) <- c("Feature_A", "Feature_B", "P_Value")
    p_df <- na.omit(p_df)
    p_df\$Significant <- p_df\$P_Value < significance_level
    
    # Write the pairwise comparison table to CSV
    write.csv(p_df, "pairwise_pvalues.csv", row.names = FALSE)
    
    # ==========================================
    # --- Hasse Diagram Visualization (paircomp) ---
    # ==========================================
    # Helper function to safely generate and save Hasse diagrams
    generate_hasse_pdf <- function(filename, compress, title) {
      pdf(filename, width = 8, height = 8)
      tryCatch({
        paircomp(
          obj = df_long\$value,
          grouping = df_long\$feature,
          test = "t",
          level = significance_level,
          compress = compress,
          p.adjust.method = p_adjust_method,
          visualize = c("position", "size", "pvalue"),
          main = title
        )
      }, error = function(e) {
        # Fallback in case of broken transitivity or other plotting errors
        plot.new()
        text(0.5, 0.5, paste("Hasse diagram could not be generated:\n", e\$message), 
             cex = 0.8, col = "red", adj = 0.5)
        warning(paste("Failed to plot Hasse diagram for", filename, ":", e\$message))
      })
      dev.off()
    }
    
    # Generate standard Hasse diagram
    generate_hasse_pdf(
      filename = "hasse_diagram_t_test.pdf",
      compress = FALSE,
      title = "Pairwise Comparisons (T-Test)"
    )
    
    # Generate edge-compressed Hasse diagram
    generate_hasse_pdf(
      filename = "hasse_diagram_t_test_compressed.pdf",
      compress = TRUE,
      title = "Pairwise Comparisons (T-Test - Compressed)"
    )
    
    # ==========================================
    # --- Manual Hasse Diagram Construction ---
    # ==========================================
    # Demonstrate manual construction using transReduct and hasse
    pdf("hasse_diagram_manual.pdf", width = 8, height = 8)
    tryCatch({
      # Calculate means to establish direction/order
      means <- tapply(df_long\$value, df_long\$feature, mean, na.rm = TRUE)
      sorted_features <- names(sort(means))
      n <- length(sorted_features)
      
      # Initialize adjacency matrix
      adj_matrix <- matrix(0, nrow = n, ncol = n, dimnames = list(sorted_features, sorted_features))
      
      # Populate adjacency matrix based on significance and mean order
      for (i in 1:(n - 1)) {
        for (j in (i + 1):n) {
          f_i <- sorted_features[i]
          f_j <- sorted_features[j]
          
          p_val <- NA
          if (f_i %in% rownames(p_matrix) && f_j %in% colnames(p_matrix)) {
            p_val <- p_matrix[f_i, f_j]
          } else if (f_j %in% rownames(p_matrix) && f_i %in% colnames(p_matrix)) {
            p_val <- p_matrix[f_j, f_i]
          }
          
          # If significant, draw a directed edge from the larger mean (j) to the smaller mean (i)
          if (!is.na(p_val) && p_val < significance_level) {
            adj_matrix[j, i] <- 1
          }
        }
      }
      
      # Remove transitive edges using transReduct
      reduced_adj_matrix <- transReduct(adj_matrix)
      
      # Draw the Hasse diagram directly
      hasse(
        e = reduced_adj_matrix,
        v = sorted_features,
        main = "Manual Hasse Diagram (Transitive Reduction Applied)"
      )
    }, error = function(e) {
      plot.new()
      text(0.5, 0.5, paste("Manual Hasse diagram generation failed:\n", e\$message), 
           cex = 0.8, col = "red", adj = 0.5)
    })
    dev.off()
    
    message("Analysis complete. Outputs written successfully.")

    writeLines(c(
        '"BIOC_PAIRCOMPVIZ_PAIRCOMP_VISUALIZATION":',
        paste0('    paircompviz: ', as.character(packageVersion('paircompviz')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_paircomp_visualization.csv versions.yml
    """
}

workflow BIOC_PAIRCOMPVIZ_PAIRCOMP_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_PAIRCOMPVIZ_PAIRCOMP_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_PAIRCOMPVIZ_PAIRCOMP_VISUALIZATION.out.tables
    plots    = BIOC_PAIRCOMPVIZ_PAIRCOMP_VISUALIZATION.out.plots
    objects  = BIOC_PAIRCOMPVIZ_PAIRCOMP_VISUALIZATION.out.objects
    versions = BIOC_PAIRCOMPVIZ_PAIRCOMP_VISUALIZATION.out.versions
}
