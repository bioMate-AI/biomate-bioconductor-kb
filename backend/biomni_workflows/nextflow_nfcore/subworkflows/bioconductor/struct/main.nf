#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: struct — struct_pca_pipeline
// Perform mean centering and Principal Component Analysis (PCA) on a feature-by-sample dataset using custom-defined struct models and sequences, and visualize the
// Input: input.csv
// Container: 1.22.1--r45hdfd78af_0
// R packages: ggplot2, struct
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, struct
// Visualizations: PCA plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_STRUCT_STRUCT_PCA_PIPELINE {
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
    .bm_deps <- c("ggplot2", "struct")
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
    suppressPackageStartupMessages({
      library(struct)
      library(ggplot2)
    })
    
    # Disable online ontology lookup to ensure offline robustness
    ontology_online(FALSE)
    
    # ==========================================
    # 1. Read and Preprocess Input Data
    # ==========================================
    if (!file.exists("input.csv")) {
      stop("Error: input.csv not found in the working directory.")
    }
    
    # Read the feature-by-sample matrix
    raw_data <- read.csv("input.csv", check.names = FALSE, stringsAsFactors = FALSE)
    
    # Identify and set row names (features)
    if (is.character(raw_data[[1]]) || is.factor(raw_data[[1]])) {
      rownames(raw_data) <- raw_data[[1]]
      raw_data <- raw_data[, -1, drop = FALSE]
    } else {
      rownames(raw_data) <- paste0("Feature_", seq_len(nrow(raw_data)))
    }
    
    # Transpose to sample-by-feature (samples in rows, features in columns)
    data_matrix <- t(as.matrix(raw_data))
    
    # Handle missing values by mean imputation per feature
    if (any(is.na(data_matrix))) {
      for (col in seq_len(ncol(data_matrix))) {
        na_idx <- is.na(data_matrix[, col])
        if (any(na_idx)) {
          data_matrix[na_idx, col] <- mean(data_matrix[!na_idx, col], na_rm = TRUE)
        }
      }
    }
    
    # Remove zero-variance features
    feature_vars <- apply(data_matrix, 2, var, na.rm = TRUE)
    valid_features <- !is.na(feature_vars) & feature_vars > 1e-8
    data_matrix <- data_matrix[, valid_features, drop = FALSE]
    
    if (ncol(data_matrix) < 2 || nrow(data_matrix) < 2) {
      stop("Error: Insufficient features or samples with non-zero variance for PCA.")
    }
    
    # Create sample metadata (dummy groups for visualization)
    sample_names <- rownames(data_matrix)
    sample_meta <- data.frame(
      SampleID = sample_names,
      Group = factor(rep(c("Group1", "Group2"), length.out = length(sample_names))),
      row.names = sample_names
    )
    
    # Create variable metadata
    variable_meta <- data.frame(
      FeatureID = colnames(data_matrix),
      row.names = colnames(data_matrix)
    )
    
    # Construct the DatasetExperiment object
    DE <- DatasetExperiment(
      data = as.data.frame(data_matrix),
      sample_meta = sample_meta,
      variable_meta = variable_meta,
      name = "Input Dataset",
      description = "Dataset processed from input.csv"
    )
    
    # ==========================================
    # 2. Define Custom Struct Models
    # ==========================================
    
    # Define Mean Centering Model
    mean_centre <- set_struct_obj(
      class_name = 'mean_centre', 
      struct_obj = 'model',       
      params = character(0),            
      outputs = c(centred = 'DatasetExperiment', mean = 'numeric'),
      private = character(0),
      prototype = list(predicted = 'centred')
    )
    
    set_obj_method(
      class_name = 'mean_centre',
      method_name = 'model_train',
      definition = function(M, D) {
        M\$mean <- colMeans(D\$data)
        return(M)
      }
    )
    
    set_obj_method(
      class_name = 'mean_centre',
      method_name = 'model_predict',
      definition = function(M, D) {
        D\$data <- D\$data - rep(M\$mean, rep.int(nrow(D\$data), ncol(D\$data)))
        M\$centred <- D
        return(M)
      }
    )
    
    # Define PCA Model using an entity parameter
    npc <- entity(
      name = 'Number of principal components',
      description = 'The number of principal components to calculate',
      type = c('numeric', 'integer'),
      value = 2,
      max_length = 1
    )
    
    PCA <- set_struct_obj(
      class_name = 'PCA', 
      struct_obj = 'model',       
      params = c(number_components = 'entity'),                
      outputs = c(scores = 'DatasetExperiment', loadings = 'data.frame'),
      private = character(0),
      prototype = list(
        number_components = npc,
        ontology = 'OBI:0200051',
        predicted = 'scores'
      )
    )
    
    set_obj_method(
      class_name = 'PCA',
      method_name = 'model_train',
      definition = function(M, D) {
        A <- min(M\$number_components, ncol(D\$data), nrow(D\$data))
        X <- as.matrix(D\$data)
        model <- svd(X, A, A)
        P <- as.data.frame(model\$v)
        varnames <- paste0('PC', seq_len(A))
        rownames(P) <- colnames(X)
        colnames(P) <- varnames
        M\$loadings <- P
        return(M)
      }
    )
    
    set_obj_method(
      class_name = 'PCA',
      method_name = 'model_predict',
      definition = function(M, D) {
        A <- min(M\$number_components, ncol(D\$data), nrow(D\$data))
        X <- as.matrix(D\$data)
        P <- M\$loadings
        scores_matrix <- X %*% as.matrix(P)
        scores_df <- as.data.frame(scores_matrix)
        rownames(scores_df) <- rownames(X)
        varnames <- paste0('PC', seq_len(A))
        colnames(scores_df) <- varnames
        
        S <- DatasetExperiment(
          data = scores_df,
          sample_meta = D\$sample_meta,
          variable_meta = data.frame(PC = varnames, row.names = varnames)
        )
        M\$scores <- S
        return(M)
      }
    )
    
    # ==========================================
    # 3. Define Custom Chart Object
    # ==========================================
    set_struct_obj(
      class_name = 'pca_scores_plot',
      struct_obj = 'chart',
      params = c(factor_name = 'character'),
      prototype = list(
        name = 'PCA scores plot',
        description = 'Scatter plot of the first two principal components',
        libraries = 'ggplot2'
      )
    )
    
    set_obj_method(
      class_name = 'pca_scores_plot',
      method_name = 'chart_plot',
      signature = c('pca_scores_plot', 'PCA'),
      definition = function(obj, dobj) {
        if (!is(dobj, 'PCA')) {
          stop('This chart is only for PCA objects')
        }
        S <- dobj\$scores\$data
        S\$factor_name <- dobj\$scores\$sample_meta[[obj\$factor_name]]
        
        g <- ggplot(data = S, aes(x = PC1, y = PC2, colour = factor_name)) +
          geom_point(size = 3, alpha = 0.8) +
          labs(
            title = "PCA Scores Plot",
            x = "Principal Component 1 (PC1)",
            y = "Principal Component 2 (PC2)",
            colour = obj\$factor_name
          ) +
          theme_bw() +
          theme(plot.title = element_text(hjust = 0.5, face = "bold"))
        return(g)
      }
    )
    
    # ==========================================
    # 4. Build and Run the Workflow Sequence
    # ==========================================
    # Determine optimal number of components (max 2 for visualization)
    n_comp <- min(2, ncol(data_matrix), nrow(data_matrix))
    
    # Create model sequence: Mean Centering followed by PCA
    MS <- mean_centre() + PCA(number_components = n_comp)
    
    # Apply the sequence to the DatasetExperiment
    MS <- model_apply(MS, DE)
    
    # ==========================================
    # 5. Extract and Export Results
    # ==========================================
    # Extract PCA scores (default predicted output of the sequence)
    scores_de <- predicted(MS)
    scores_df <- scores_de\$data
    
    # Extract PCA loadings from the second model in the sequence
    pca_model <- MS[2]
    loadings_df <- pca_model\$loadings
    
    # Write outputs to CSV
    write.csv(scores_df, "pca_scores.csv", row.names = TRUE)
    write.csv(loadings_df, "pca_loadings.csv", row.names = TRUE)
    
    # Generate and save the PCA scores plot
    C <- pca_scores_plot(factor_name = 'Group')
    p <- chart_plot(C, pca_model)
    
    pdf("pca_scores_plot.pdf", width = 6, height = 5)
    print(p)
    dev.off()
    
    message("Pipeline completed successfully. Outputs written: pca_scores.csv, pca_loadings.csv, pca_scores_plot.pdf")

    writeLines(c(
        '"BIOC_STRUCT_STRUCT_PCA_PIPELINE":',
        paste0('    struct: ', as.character(packageVersion('struct')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_struct_pca_pipeline.csv versions.yml
    """
}

workflow BIOC_STRUCT_STRUCT_PCA_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_STRUCT_STRUCT_PCA_PIPELINE(ch_input)

    emit:
    tables   = BIOC_STRUCT_STRUCT_PCA_PIPELINE.out.tables
    plots    = BIOC_STRUCT_STRUCT_PCA_PIPELINE.out.plots
    objects  = BIOC_STRUCT_STRUCT_PCA_PIPELINE.out.objects
    versions = BIOC_STRUCT_STRUCT_PCA_PIPELINE.out.versions
}
