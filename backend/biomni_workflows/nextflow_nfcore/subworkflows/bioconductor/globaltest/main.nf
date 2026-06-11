#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: globaltest — covariate_association_and_diagnostics
// Test a group of covariates for association with a response variable and visualize individual covariate and subject contributions.
// Input: Y, X
// Container: quay.io/biocontainers/bioconductor-globaltest:5.64.0--r45hdfd78af_0
// R packages: boot, globaltest, golubesets, gss, lungexpression, MASS
// Bioconductor: 3.20 | R: 4.4
// Requires: globaltest
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run the global test using gt()
//  * 2. [Core Analysis] Extract test statistics and p-values
//  * 3. [Visualization & Output] Generate a hierarchical clustering plot of covariate contributions using covariates()
//  * 4. [Visualization & Output] Generate a hierarchical clustering plot of subject contributions using subjects()

nextflow.enable.dsl = 2

process BIOC_GLOBALTEST_COVARIATE_ASSOCIATION_AND_DIAGNOSTICS {
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
    .bm_deps <- c("boot", "globaltest", "golubesets", "gss", "lungexpression", "MASS")
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
        
    # Load the required Bioconductor package
    library(globaltest)
    
    # Set global options as documented
    gt.options(trace=FALSE, max.print=45)
    
    # -------------------------------------------------------------------------
    # Stage 0: Read User Input Files
    # -------------------------------------------------------------------------
    
    # Read Y (numeric vector of response values)
    if (file.exists("Y.rds")) {
      Y <- readRDS("Y.rds")
    } else if (file.exists("Y.csv")) {
      Y_raw <- read.csv("Y.csv", header = FALSE)
      if (ncol(Y_raw) > 1 && nrow(Y_raw) == 1) {
        Y <- as.numeric(Y_raw[1, ])
      } else {
        Y <- as.numeric(Y_raw[, 1])
      }
    } else {
      stop("Error: Y file (Y.rds or Y.csv) not found in the working directory.")
    }
    
    # Ensure Y is a numeric vector
    if (is.data.frame(Y) || is.matrix(Y)) {
      Y <- as.numeric(Y[[1]])
    } else {
      Y <- as.numeric(Y)
    }
    
    # Read X (matrix of covariate measurements)
    if (file.exists("X.rds")) {
      X <- readRDS("X.rds")
    } else if (file.exists("X.csv")) {
      X <- read.csv("X.csv", row.names = 1, check.names = FALSE)
      X <- as.matrix(X)
    } else {
      stop("Error: X file (X.rds or X.csv) not found in the working directory.")
    }
    
    # -------------------------------------------------------------------------
    # Stage 1: Run the global test using gt()
    # -------------------------------------------------------------------------
    res <- gt(Y, X)
    
    # -------------------------------------------------------------------------
    # Stage 2: Extract test statistics and p-values
    # -------------------------------------------------------------------------
    p_val <- p.value(res)
    z_sc <- z.score(res)
    res_df <- result(res)
    sz <- size(res)
    
    # Save extracted values to output files
    write.csv(data.frame(p_value = p_val), "p_value.csv", row.names = FALSE)
    write.csv(data.frame(z_score = z_sc), "z_score.csv", row.names = FALSE)
    write.csv(res_df, "result.csv", row.names = TRUE)
    write.csv(data.frame(size = sz), "size.csv", row.names = FALSE)
    saveRDS(res, "res.rds")
    
    # -------------------------------------------------------------------------
    # Stage 3: Generate hierarchical clustering plot of covariate contributions
    # -------------------------------------------------------------------------
    pdf("covariates_plot.pdf")
    covs_res <- covariates(res)
    dev.off()
    
    # Save covariates result object
    saveRDS(covs_res, "covariates_result.rds")
    
    # -------------------------------------------------------------------------
    # Stage 4: Generate hierarchical clustering plot of subject contributions
    # -------------------------------------------------------------------------
    pdf("subjects_plot.pdf")
    subs_res <- subjects(res)
    dev.off()
    
    # Save subjects result object
    saveRDS(subs_res, "subjects_result.rds")

    writeLines(c(
        '"BIOC_GLOBALTEST_COVARIATE_ASSOCIATION_AND_DIAGNOSTICS":',
        paste0('    globaltest: ', as.character(packageVersion('globaltest')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_covariate_association_and_diagnostics.csv versions.yml
    """
}

workflow BIOC_GLOBALTEST_COVARIATE_ASSOCIATION_AND_DIAGNOSTICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Y, X ] ]

    main:
    BIOC_GLOBALTEST_COVARIATE_ASSOCIATION_AND_DIAGNOSTICS(ch_input)

    emit:
    tables   = BIOC_GLOBALTEST_COVARIATE_ASSOCIATION_AND_DIAGNOSTICS.out.tables
    plots    = BIOC_GLOBALTEST_COVARIATE_ASSOCIATION_AND_DIAGNOSTICS.out.plots
    objects  = BIOC_GLOBALTEST_COVARIATE_ASSOCIATION_AND_DIAGNOSTICS.out.objects
    versions = BIOC_GLOBALTEST_COVARIATE_ASSOCIATION_AND_DIAGNOSTICS.out.versions
}
