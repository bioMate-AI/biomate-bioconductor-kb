#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gpls — multi_group_classification
// Fit a multi-group classification model using multinomial generalized partial least squares and evaluate performance.
// Input: x, y
// Container: quay.io/biocontainers/bioconductor-gpls:1.82.0--r45hdfd78af_0
// R packages: gpls
// Bioconductor: 3.20 | R: 4.4
// Requires: gpls
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit the multi-group model using glpls1a.mlogit (with intercept) or glpls1a.logit.all (without intercept)
//  * 2. [Core Analysis] Calculate leave-one-out cross-validation error using glpls1a.mlogit.cv.error

nextflow.enable.dsl = 2

process BIOC_GPLS_MULTI_GROUP_CLASSIFICATION {
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
    .bm_deps <- c("gpls")
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
        library(gpls)
        
        # Helper function to find input files
        find_file <- function(base_name) {
          extensions <- c("", ".csv", ".rds", ".tsv", ".txt")
          for (ext in extensions) {
            path <- paste0(base_name, ext)
            if (file.exists(path)) {
              return(path)
            }
          }
          stop(paste("Required input file for", base_name, "not found in the working directory."))
        }
        
        # Load data
        x_path <- find_file("x")
        y_path <- find_file("y")
        
        # Load X matrix
        if (grepl("\\\\.rds\$", x_path, ignore.case = TRUE)) {
          x <- as.matrix(readRDS(x_path))
        } else {
          sep <- if (grepl("\\\\.tsv\$", x_path, ignore.case = TRUE)) "\t" else ","
          df <- read.table(x_path, header = TRUE, sep = sep, stringsAsFactors = FALSE)
          if (!is.numeric(df[[1]])) {
            rownames(df) <- df[[1]]
            df <- df[-1]
          }
          x <- as.matrix(df)
        }
        
        # Load Y vector
        if (grepl("\\\\.rds\$", y_path, ignore.case = TRUE)) {
          y <- as.vector(readRDS(y_path))
        } else {
          sep <- if (grepl("\\\\.tsv\$", y_path, ignore.case = TRUE)) "\t" else ","
          df <- read.table(y_path, header = FALSE, sep = sep, stringsAsFactors = FALSE)
          if (nrow(df) == nrow(x) + 1) {
            df <- read.table(y_path, header = TRUE, sep = sep, stringsAsFactors = FALSE)
          }
          y <- as.vector(df[[1]])
        }
        
        # Ensure y is numeric/integer for classification
        y <- as.integer(as.factor(y))
        
        # 1. Fit the multi-group model using glpls1a.mlogit (with intercept) or glpls1a.logit.all (without intercept)
        # Note: We adapt rep(1, 10) to rep(1, nrow(x)) to match the input dimensions dynamically.
        fit1 <- glpls1a.mlogit(cbind(rep(1, nrow(x)), x), y, K.prov = 1, br = FALSE)
        fit2 <- glpls1a.logit.all(x, y, K.prov = 1, br = FALSE)
        fit3 <- glpls1a.mlogit(cbind(rep(1, nrow(x)), x), y, br = TRUE)
        fit4 <- glpls1a.logit.all(x, y, br = TRUE)
        
        # 2. Calculate leave-one-out cross-validation error using glpls1a.mlogit.cv.error
        cv1 <- glpls1a.mlogit.cv.error(x, y, br = FALSE)
        cv2 <- glpls1a.mlogit.cv.error(x, y, mlogit = FALSE, br = FALSE)
        cv3 <- glpls1a.mlogit.cv.error(x, y, br = TRUE)
        cv4 <- glpls1a.mlogit.cv.error(x, y, mlogit = FALSE, br = TRUE)
        
        # Save model fits
        saveRDS(fit1, "fit_mlogit_k1_nobr.rds")
        saveRDS(fit2, "fit_logitall_k1_nobr.rds")
        saveRDS(fit3, "fit_mlogit_br.rds")
        saveRDS(fit4, "fit_logitall_br.rds")
        
        # Save CV results
        saveRDS(cv1, "cv_mlogit_nobr.rds")
        saveRDS(cv2, "cv_logitall_nobr.rds")
        saveRDS(cv3, "cv_mlogit_br.rds")
        saveRDS(cv4, "cv_logitall_br.rds")
        
        # Write summary CSV
        cv_summary <- data.frame(
          Model = c("mlogit_nobr", "logitall_nobr", "mlogit_br", "logitall_br"),
          CV_Error_Rate = c(cv1\$error, cv2\$error, cv3\$error, cv4\$error)
        )
        write.csv(cv_summary, "cv_error_summary.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_GPLS_MULTI_GROUP_CLASSIFICATION":',
        paste0('    gpls: ', as.character(packageVersion('gpls')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_group_classification.csv versions.yml
    """
}

workflow BIOC_GPLS_MULTI_GROUP_CLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ x, y ] ]

    main:
    BIOC_GPLS_MULTI_GROUP_CLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_GPLS_MULTI_GROUP_CLASSIFICATION.out.tables
    plots    = BIOC_GPLS_MULTI_GROUP_CLASSIFICATION.out.plots
    objects  = BIOC_GPLS_MULTI_GROUP_CLASSIFICATION.out.objects
    versions = BIOC_GPLS_MULTI_GROUP_CLASSIFICATION.out.versions
}
