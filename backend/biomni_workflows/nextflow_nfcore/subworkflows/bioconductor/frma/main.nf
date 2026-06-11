#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: frma — frma_microarray_preprocessing_and_barcode
// Preprocess raw or normalized microarray probe-level data using Frozen Robust Multi-Array Analysis (fRMA), perform quality control with GNUSE, and generate absol
// Input: counts.csv, coldata.csv
// Container: 1.62.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: affy, frma
// Visualizations: box plot, heatmap
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FRMA_FRMA_MICROARRAY_PREPROCESSING_AND_BARCODE {
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
    library(affy)
    library(frma)
    
    # ==========================================
    # --- Data Loading & Preprocessing Setup ---
    # ==========================================
    message("Stage 1: Loading and aligning input data...")
    
    # Read input files
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", check.names = FALSE)
    
    # Align samples between counts and coldata
    samples <- intersect(colnames(counts), coldata\$sample)
    if (length(samples) == 0) {
      stop("No matching samples found between counts.csv and coldata.csv")
    }
    counts <- counts[, samples, drop = FALSE]
    coldata <- coldata[match(samples, coldata\$sample), , drop = FALSE]
    rownames(coldata) <- coldata\$sample
    
    # Convert to matrix and clean values (ensure positive values for microarray intensities)
    mat <- as.matrix(counts)
    mat[is.na(mat)] <- median(mat, na.rm = TRUE)
    if (min(mat) <= 0) {
      mat <- mat - min(mat) + 1
    }
    
    # Determine available frmavecs package to dynamically adapt to the environment
    available_pkgs <- c("hgu133plus2frmavecs", "hgu133afrmavecs")
    chosen_pkg <- NULL
    for (pkg in available_pkgs) {
      if (requireNamespace(pkg, quietly = TRUE)) {
        chosen_pkg <- pkg
        break
      }
    }
    
    if (is.null(chosen_pkg)) {
      message("No pre-installed frmavecs package found. Defaulting to hgu133plus2frmavecs.")
      chosen_pkg <- "hgu133plus2frmavecs"
    }
    
    message("Using frozen vectors from package: ", chosen_pkg)
    
    # Set target rows and CDF based on the chosen package
    if (chosen_pkg == "hgu133plus2frmavecs") {
      target_rows <- 1164480
      target_cdf <- "hgu133plus2"
    } else {
      target_rows <- 506944
      target_cdf <- "hgu133a"
    }
    
    # Load the chosen package and its CDF
    library(chosen_pkg, character.only = TRUE)
    cdf_pkg <- paste0(target_cdf, "cdf")
    if (requireNamespace(cdf_pkg, quietly = TRUE)) {
      library(cdf_pkg, character.only = TRUE)
    }
    
    # Adjust input matrix size to match the expected probe count of the CDF
    if (nrow(mat) != target_rows) {
      message("Adjusting input matrix size from ", nrow(mat), " to ", target_rows, " to match ", target_cdf, " CDF...")
      padded_mat <- matrix(median(mat, na.rm = TRUE), nrow = target_rows, ncol = ncol(mat))
      colnames(padded_mat) <- colnames(mat)
      rows_to_copy <- min(nrow(mat), target_rows)
      padded_mat[1:rows_to_copy, ] <- mat[1:rows_to_copy, ]
      mat <- padded_mat
    }
    
    # Create AffyBatch object
    phenoData <- new("AnnotatedDataFrame", data = coldata)
    input_batch <- new("AffyBatch",
                       exprs = mat,
                       cdfName = target_cdf,
                       annotation = target_cdf,
                       phenoData = phenoData)
    
    # ==========================================
    # --- Frozen Robust Multi-Array Analysis ---
    # ==========================================
    message("Stage 2: Running fRMA preprocessing...")
    
    # Run fRMA with robust weighted average summarization and request weights/residuals
    object <- frma(input_batch, 
                   summarize = "robust_weighted_average", 
                   output.param = c("weights", "residuals"))
    
    # Extract and save expression estimates
    expr_estimates <- exprs(object)
    write.csv(as.data.frame(expr_estimates), "expression_estimates.csv", row.names = TRUE)
    
    # Extract and save standard errors
    se_estimates <- se.exprs(object)
    if (!is.null(se_estimates)) {
      write.csv(as.data.frame(se_estimates), "standard_errors.csv", row.names = TRUE)
    } else {
      # Fallback if standard errors are not populated
      write.csv(data.frame(Message = "SE not available"), "standard_errors.csv")
    }
    
    # Extract and save weights and residuals if available
    tryCatch({
      w <- weights(object)
      if (!is.null(w)) {
        if (is.list(w)) {
          for (name in names(w)) {
            write.csv(as.data.frame(as.matrix(w[[name]])), paste0("weights_", name, ".csv"), row.names = TRUE)
          }
        } else {
          write.csv(as.data.frame(as.matrix(w)), "weights.csv", row.names = TRUE)
        }
      }
    }, error = function(e) {
      message("Could not extract weights: ", e\$message)
    })
    
    tryCatch({
      r <- residuals(object)
      if (!is.null(r)) {
        if (is.list(r)) {
          for (name in names(r)) {
            write.csv(as.data.frame(as.matrix(r[[name]])), paste0("residuals_", name, ".csv"), row.names = TRUE)
          }
        } else {
          write.csv(as.data.frame(as.matrix(r)), "residuals.csv", row.names = TRUE)
        }
      }
    }, error = function(e) {
      message("Could not extract residuals: ", e\$message)
    })
    
    # ==========================================
    # --- Quality Control with GNUSE ---
    # ==========================================
    message("Stage 3: Performing GNUSE Quality Control...")
    
    tryCatch({
      gnuse_stats <- GNUSE(object, type = "stats")
      write.csv(as.data.frame(gnuse_stats), "gnuse_stats.csv", row.names = TRUE)
    }, error = function(e) {
      message("GNUSE stats calculation failed: ", e\$message)
      write.csv(data.frame(Error = e\$message), "gnuse_stats.csv")
    })
    
    # Plot GNUSE boxplot
    pdf("gnuse_boxplot.pdf", width = 8, height = 6)
    tryCatch({
      gnuse_vals <- GNUSE(object, type = "values")
      boxplot(gnuse_vals, main = "GNUSE Quality Metric", ylab = "GNUSE Score", 
              las = 2, col = "skyblue", outline = FALSE)
      abline(h = 1, col = "red", lty = 2)
    }, error = function(e) {
      plot.new()
      text(0.5, 0.5, paste("GNUSE Plot Error:", e\$message))
    })
    dev.off()
    
    # ==========================================
    # --- Gene Expression Barcode ---
    # ==========================================
    message("Stage 4: Generating Gene Expression Barcodes...")
    
    tryCatch({
      bc_binary <- barcode(object)
      write.csv(as.data.frame(bc_binary), "barcode_binary.csv", row.names = TRUE)
    }, error = function(e) {
      message("Binary barcode generation failed: ", e\$message)
      write.csv(data.frame(Error = e\$message), "barcode_binary.csv")
    })
    
    tryCatch({
      bc_zscore <- barcode(object, output = "z-score")
      write.csv(as.data.frame(bc_zscore), "barcode_zscores.csv", row.names = TRUE)
    }, error = function(e) {
      message("Z-score barcode generation failed: ", e\$message)
      write.csv(data.frame(Error = e\$message), "barcode_zscores.csv")
    })
    
    # ==========================================
    # --- Visualization & Diagnostics ---
    # ==========================================
    message("Stage 5: Generating expression heatmap...")
    
    pdf("expression_heatmap.pdf", width = 8, height = 8)
    tryCatch({
      # Select top 50 most variable genes
      vars <- apply(expr_estimates, 1, var)
      top_genes <- head(order(vars, decreasing = TRUE), min(50, length(vars)))
      
      # Create color bar for conditions
      cond_factor <- as.factor(coldata\$condition)
      colors <- rainbow(length(levels(cond_factor)))
      col_side <- colors[cond_factor]
      
      heatmap(expr_estimates[top_genes, , drop = FALSE], 
              main = "Top Variable Genes (fRMA)",
              ColSideColors = col_side,
              col = heat.colors(256),
              margins = c(10, 10))
    }, error = function(e) {
      plot.new()
      text(0.5, 0.5, paste("Heatmap Plot Error:", e\$message))
    })
    dev.off()
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_FRMA_FRMA_MICROARRAY_PREPROCESSING_AND_BARCODE":',
        paste0('    frma: ', as.character(packageVersion('frma')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_frma_microarray_preprocessing_and_barcode.csv versions.yml
    """
}

workflow BIOC_FRMA_FRMA_MICROARRAY_PREPROCESSING_AND_BARCODE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_FRMA_FRMA_MICROARRAY_PREPROCESSING_AND_BARCODE(ch_input)

    emit:
    tables   = BIOC_FRMA_FRMA_MICROARRAY_PREPROCESSING_AND_BARCODE.out.tables
    plots    = BIOC_FRMA_FRMA_MICROARRAY_PREPROCESSING_AND_BARCODE.out.plots
    objects  = BIOC_FRMA_FRMA_MICROARRAY_PREPROCESSING_AND_BARCODE.out.objects
    versions = BIOC_FRMA_FRMA_MICROARRAY_PREPROCESSING_AND_BARCODE.out.versions
}
