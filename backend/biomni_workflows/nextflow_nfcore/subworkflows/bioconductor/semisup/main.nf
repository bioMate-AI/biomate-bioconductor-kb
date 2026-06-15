#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: semisup — semi_supervised_association_testing
// Fit semi-supervised mixture models and test for associations between quantitative traits and SNPs/grouping variables.
// Input: y, snp
// Container: quay.io/biocontainers/bioconductor-semisup:1.34.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: semisup
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Binarise the SNP/grouping variable to define labelled (0) and unlabelled (NA) groups
//  * 2. [Core Analysis] Fit the mixture model to estimate parameters and predict class labels
//  * 3. [Core Analysis] Perform hypothesis testing using parametric bootstrapping or permutation to calculate p-values

nextflow.enable.dsl = 2

process BIOC_SEMISUP_SEMI_SUPERVISED_ASSOCIATION_TESTING {
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
    .bm_deps <- c("semisup")
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
        
        # Load required library
        library(semisup)
        
        # ==========================================
        # STAGE 0: Read User Input Files
        # ==========================================
        
        # Helper function to find input files in the working directory
        find_file <- function(possible_names) {
          extensions <- c("rds", "csv", "tsv", "txt")
          for (name in possible_names) {
            for (ext in extensions) {
              file_path <- paste0(name, ".", ext)
              if (file.exists(file_path)) {
                return(file_path)
              }
            }
          }
          return(NULL)
        }
        
        # Helper function to read data based on file extension
        read_data <- function(file_path) {
          ext <- tools::file_ext(file_path)
          if (ext == "rds") {
            return(readRDS(file_path))
          } else {
            sep <- if (ext == "csv") "," else ""
            # Read initial rows to check for headers
            test_df <- read.table(file_path, header = FALSE, nrows = 5, sep = sep)
            has_header <- !all(sapply(test_df, is.numeric)) && any(sapply(test_df, is.character))
            df <- read.table(file_path, header = has_header, sep = sep)
            return(df)
          }
        }
        
        # Locate the quantitative trait and SNP files
        y_file <- find_file(c("y", "Y"))
        snp_file <- find_file(c("snp", "SNPs"))
        
        if (is.null(y_file) || is.null(snp_file)) {
          stop("Error: Required input files (y/Y and snp/SNPs) not found in the working directory.")
        }
        
        y_raw <- read_data(y_file)
        snp_raw <- read_data(snp_file)
        
        # Standardize inputs to both vector (y, snp) and matrix (Y, SNPs) formats
        if (is.data.frame(y_raw) || is.matrix(y_raw)) {
          Y <- as.matrix(y_raw)
          y <- as.vector(Y[, 1])
        } else {
          y <- as.vector(y_raw)
          Y <- as.matrix(y)
        }
        
        if (is.data.frame(snp_raw) || is.matrix(snp_raw)) {
          SNPs <- as.matrix(snp_raw)
          snp <- as.vector(SNPs[, 1])
        } else {
          snp <- as.vector(snp_raw)
          SNPs <- as.matrix(snp)
        }
        
        # ==========================================
        # STAGE 1: Binarise the SNP/Grouping Variable
        # ==========================================
        
        n <- length(snp)
        
        z <- rep(NA,times=n)
        z[snp==0] <- 0
        
        n <- nrow(SNPs)
        p <- ncol(SNPs)
        
        Z <- matrix(NA,nrow=n,ncol=p)
        Z[SNPs==0] <- 0
        
        # ==========================================
        # STAGE 2: Fit the Mixture Model
        # ==========================================
        
        fit <- mixtura(y,z)
        class <- round(fit\$posterior)
        fit\$estim1
        fit\$estim0
        
        # Save model fitting results
        saveRDS(fit, "mixtura_fit.rds")
        
        # Save predicted class labels
        class_df <- data.frame(Observation = seq_along(class), Predicted_Class = class)
        write.csv(class_df, "predicted_classes.csv", row.names = FALSE)
        
        # Helper to save parameter estimates
        save_estimates <- function(estim, file_name) {
          flat_estim <- lapply(estim, function(x) paste(x, collapse = "; "))
          write.csv(as.data.frame(flat_estim), file_name, row.names = FALSE)
        }
        save_estimates(fit\$estim1, "estimates_alternative.csv")
        save_estimates(fit\$estim0, "estimates_null.csv")
        
        # ==========================================
        # STAGE 3: Perform Hypothesis Testing
        # ==========================================
        
        # Save hypothesis testing results
        save_scrutor <- function(res, prefix) {
          saveRDS(res, paste0(prefix, ".rds"))
          tryCatch({
            write.csv(as.data.frame(res), paste0(prefix, ".csv"), row.names = TRUE)
          }, error = function(e) {
            write.table(t(as.data.frame(unclass(res))), paste0(prefix, ".csv"), sep = ",", col.names = NA)
          })
        }
        
        is_y_vec <- NCOL(y_raw) == 1
        is_snp_vec <- NCOL(snp_raw) == 1
        
        if (is_y_vec && is_snp_vec) {
          res_y_z <- scrutor(y, z)
          save_scrutor(res_y_z, "scrutor_y_z")
        } else if (is_y_vec && !is_snp_vec) {
          res_y_Z <- scrutor(y, Z)
          save_scrutor(res_y_Z, "scrutor_y_Z")
        } else if (!is_y_vec && is_snp_vec) {
          res_Y_z <- scrutor(Y, z)
          save_scrutor(res_Y_z, "scrutor_Y_z")
        } else {
          res_Y_Z <- scrutor(Y, Z)
          save_scrutor(res_Y_Z, "scrutor_Y_Z")
        }
        
        # ==========================================
        # STAGE 4: Generate Visualizations
        # ==========================================
        
        order_idx <- order(is.na(z))
        y_plot <- y[order_idx]
        z_plot <- z[order_idx]
        class_plot <- class[order_idx]
        
        pdf("mixture_fit_plot.pdf", width = 8, height = 6)
        par(mar = c(4, 4, 3, 5))
        plot.new()
        plot.window(xlim = c(1, length(y_plot)), ylim = range(y_plot))
        box()
        axis(side = 1)
        axis(side = 2)
        title(xlab = "Index", ylab = "y", main = "Semi-supervised Mixture Model Classification")
        abline(v = sum(z_plot == 0, na.rm = TRUE) + 0.5, lty = 2)
        points(y_plot, col = ifelse(class_plot == 1, "red", "blue"), pch = 19)
        legend("topleft", legend = c("Class A (Labelled/Unlabelled)", "Class B (Unlabelled)"), col = c("blue", "red"), pch = 19)
        dev.off()
        
        message("Pipeline completed successfully. Outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_SEMISUP_SEMI_SUPERVISED_ASSOCIATION_TESTING":',
        paste0('    semisup: ', as.character(packageVersion('semisup')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_semi_supervised_association_testing.csv versions.yml
    """
}

workflow BIOC_SEMISUP_SEMI_SUPERVISED_ASSOCIATION_TESTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ y, snp ] ]

    main:
    BIOC_SEMISUP_SEMI_SUPERVISED_ASSOCIATION_TESTING(ch_input)

    emit:
    tables   = BIOC_SEMISUP_SEMI_SUPERVISED_ASSOCIATION_TESTING.out.tables
    plots    = BIOC_SEMISUP_SEMI_SUPERVISED_ASSOCIATION_TESTING.out.plots
    objects  = BIOC_SEMISUP_SEMI_SUPERVISED_ASSOCIATION_TESTING.out.objects
    versions = BIOC_SEMISUP_SEMI_SUPERVISED_ASSOCIATION_TESTING.out.versions
}
