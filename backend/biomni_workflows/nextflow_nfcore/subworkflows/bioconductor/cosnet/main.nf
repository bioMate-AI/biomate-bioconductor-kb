#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: COSNet — cosnet_cross_validation
// Perform automated cross-validation to predict node labels and evaluate performance on a similarity network.
// Input: Yeast.STRING.data, Yeast.STRING.FunCat
// Container: quay.io/biocontainers/bioconductor-cosnet:1.44.0--r45h01b2380_0
// R packages: bionetdata, COSNet, PerfMeas
// Bioconductor: 3.20 | R: 4.4
// Requires: COSNet, PerfMeas
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load user input files
//  * 2. [Visualization & Output] Preprocess the label matrix
//  * 3. [Visualization & Output] Run cross-validation using cosnet.cross.validation
//  * 4. [Visualization & Output] Extract predictions, scores, and labels from the output
//  * 5. [Visualization & Output] Evaluate performance using PerfMeas
//  * 6. [Visualization & Output] Write outputs to files

nextflow.enable.dsl = 2

process BIOC_COSNET_COSNET_CROSS_VALIDATION {
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
    .bm_deps <- c("bionetdata", "COSNet", "PerfMeas")
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
    library(COSNet)
    library(PerfMeas)
    
    # Helper function to robustly load input files (RDS or text format)
    load_data <- function(filename) {
      if (!file.exists(filename)) {
        stop(paste("Required input file missing:", filename))
      }
      
      # Try reading as RDS first
      res <- tryCatch({
        readRDS(filename)
      }, error = function(e) {
        NULL
      })
      if (!is.null(res)) return(res)
      
      # Try reading as table with row names
      res <- tryCatch({
        as.matrix(read.table(filename, header = TRUE, row.names = 1, check.names = FALSE))
      }, error = function(e) {
        NULL
      })
      if (!is.null(res)) return(res)
      
      # Try reading as table without row names
      res <- tryCatch({
        as.matrix(read.table(filename, header = TRUE, check.names = FALSE))
      }, error = function(e) {
        NULL
      })
      if (!is.null(res)) return(res)
      
      stop(paste("Failed to parse file:", filename))
    }
    
    # --- Load user input files ---
    Yeast.STRING.data <- load_data("Yeast.STRING.data")
    Yeast.STRING.FunCat <- load_data("Yeast.STRING.FunCat")
    
    # --- Preprocess the label matrix ---
    # Excluding the dummy "00" root if present
    to.be.excl <- which(colnames(Yeast.STRING.FunCat) == "00")
    if (length(to.be.excl) > 0) {
      Yeast.STRING.FunCat <- Yeast.STRING.FunCat[, -to.be.excl]
    }
    
    # Choosing the first 35 classes (or all available if fewer than 35)
    num_classes <- min(35, ncol(Yeast.STRING.FunCat))
    labeling <- Yeast.STRING.FunCat[, 1:num_classes, drop = FALSE]
    
    # Convert 0 (negative) values to -1 for both the full matrix and the target labeling
    Yeast.STRING.FunCat[Yeast.STRING.FunCat == 0] <- -1
    labeling[labeling <= 0] <- -1
    
    # --- Run cross-validation using cosnet.cross.validation ---
    out <- cosnet.cross.validation(labeling, Yeast.STRING.data, 5, cost=0)
    out.r <- cosnet.cross.validation(labeling, Yeast.STRING.data, 5, cost=0.0001)
    
    # --- Extract predictions, scores, and labels from the output ---
    predictions <- out\$predictions
    scores <- out\$scores
    labels <- out\$labels
    predictions.r <- out.r\$predictions
    scores.r <- out.r\$scores
    labels.r <- out.r\$labels
    
    # --- Evaluate performance using PerfMeas ---
    # F-score
    Fs <- F.measure.single.over.classes(labels, predictions)
    Fs.r <- F.measure.single.over.classes(labels.r, predictions.r)
    
    # AUC (requires labels to be 0/1 instead of -1/1)
    labels_auc <- labels
    labels_auc[labels_auc <= 0] <- 0
    labels_r_auc <- labels.r
    labels_r_auc[labels_r_auc <= 0] <- 0
    
    auc <- AUC.single.over.classes(labels_auc, scores)
    auc.r <- AUC.single.over.classes(labels_r_auc, scores.r)
    
    # Precision at multiple recall levels
    PXR <- precision.at.multiple.recall.level.over.classes(labels_auc, scores, seq(from=0.1, to=1, by=0.1))
    PXR.r <- precision.at.multiple.recall.level.over.classes(labels_r_auc, scores.r, seq(from=0.1, to=1, by=0.1))
    
    # --- Write outputs to files ---
    # Save predictions and scores as CSV
    write.csv(predictions, "predictions_unregularized.csv", row.names = TRUE)
    write.csv(scores, "scores_unregularized.csv", row.names = TRUE)
    write.csv(predictions.r, "predictions_regularized.csv", row.names = TRUE)
    write.csv(scores.r, "scores_regularized.csv", row.names = TRUE)
    
    # Save performance metrics summary
    metrics_summary <- list(
      unregularized = list(
        avg_F_score = Fs\$average[4],
        avg_AUC = auc\$average,
        avg_PXR = PXR\$avgPXR
      ),
      regularized = list(
        avg_F_score = Fs.r\$average[4],
        avg_AUC = auc.r\$average,
        avg_PXR = PXR.r\$avgPXR
      )
    )
    saveRDS(metrics_summary, "performance_metrics.rds")
    
    # Write a text report of the performance
    sink("performance_report.txt")
    cat("=== COSNet Cross-Validation Performance Report ===\n\n")
    cat("Unregularized COSNet (cost = 0):\n")
    cat("  Average F-score: ", Fs\$average[4], "\n")
    cat("  Average AUC:     ", auc\$average, "\n\n")
    cat("Regularized COSNet (cost = 0.0001):\n")
    cat("  Average F-score: ", Fs.r\$average[4], "\n")
    cat("  Average AUC:     ", auc.r\$average, "\n\n")
    cat("Precision at Recall Levels (Unregularized):\n")
    print(PXR\$avgPXR)
    cat("\nPrecision at Recall Levels (Regularized):\n")
    print(PXR.r\$avgPXR)
    sink()
    
    # Generate Precision-Recall comparison plot
    pdf("precision_recall_comparison.pdf", width = 7, height = 5)
    plot(seq(from=0.1, to=1, by=0.1), PXR\$avgPXR, type = "b", col = "blue", pch = 19,
         ylim = c(0, 1), xlab = "Recall", ylab = "Precision", 
         main = "Precision-Recall Curve Comparison")
    lines(seq(from=0.1, to=1, by=0.1), PXR.r\$avgPXR, type = "b", col = "red", pch = 18)
    legend("topright", legend = c("Unregularized (cost=0)", "Regularized (cost=0.0001)"),
           col = c("blue", "red"), pch = c(19, 18), lty = 1)
    dev.off()

    writeLines(c(
        '"BIOC_COSNET_COSNET_CROSS_VALIDATION":',
        paste0('    COSNet: ', as.character(packageVersion('COSNet')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cosnet_cross_validation.csv versions.yml
    """
}

workflow BIOC_COSNET_COSNET_CROSS_VALIDATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Yeast.STRING.data, Yeast.STRING.FunCat ] ]

    main:
    BIOC_COSNET_COSNET_CROSS_VALIDATION(ch_input)

    emit:
    tables   = BIOC_COSNET_COSNET_CROSS_VALIDATION.out.tables
    plots    = BIOC_COSNET_COSNET_CROSS_VALIDATION.out.plots
    objects  = BIOC_COSNET_COSNET_CROSS_VALIDATION.out.objects
    versions = BIOC_COSNET_COSNET_CROSS_VALIDATION.out.versions
}
