#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: snm — reference_design_normalization
// Normalize two-color microarray data utilizing a reference design, either on raw channels or after subtracting the reference channel from the experimental channe
// Input: raw.data, bio.var, adj.var, int.var
// Container: quay.io/biocontainers/bioconductor-snm:1.58.0--r45hdfd78af_0
// R packages: snm
// Bioconductor: 3.20 | R: 4.4
// Requires: snm
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run the snm function on raw channels
//  * 2. [Core Analysis] Alternatively, subtract the reference channel from the experimental channel, adjust the covariate matrices, and run snm on the sub

nextflow.enable.dsl = 2

process BIOC_SNM_REFERENCE_DESIGN_NORMALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("snm")
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
        library(snm)
        
        # Helper function to robustly read input files of various formats
        read_input <- function(base_name) {
          possible_files <- c(
            base_name,
            paste0(base_name, ".rds"),
            paste0(base_name, ".csv"),
            paste0(base_name, ".tsv"),
            paste0(base_name, ".txt")
          )
          for (f in possible_files) {
            if (file.exists(f)) {
              if (grepl("\\\\.rds\$", f, ignore.case = TRUE)) {
                return(readRDS(f))
              } else if (grepl("\\\\.csv\$", f, ignore.case = TRUE)) {
                df <- read.csv(f, row.names = 1, check.names = FALSE)
                return(as.matrix(df))
              } else if (grepl("\\\\.(tsv|txt)\$", f, ignore.case = TRUE)) {
                df <- read.delim(f, row.names = 1, check.names = FALSE)
                return(as.matrix(df))
              } else {
                res <- tryCatch(readRDS(f), error = function(e) NULL)
                if (!is.null(res)) return(res)
                res <- tryCatch(as.matrix(read.table(f, header = TRUE, row.names = 1, check.names = FALSE)), error = function(e) NULL)
                if (!is.null(res)) return(res)
              }
            }
          }
          stop(paste("Required input file not found:", base_name))
        }
        
        # Construct the refChannel list from user input files
        refChannel <- list()
        refChannel\$raw.data <- as.matrix(read_input("raw.data"))
        refChannel\$bio.var <- as.matrix(read_input("bio.var"))
        
        # adj.var is optional in some designs, handle gracefully if missing
        refChannel\$adj.var <- tryCatch({
          read_input("adj.var")
        }, error = function(e) {
          NULL
        })
        
        refChannel\$int.var <- as.data.frame(read_input("int.var"))
        
        # Read true.nulls if available, otherwise default to all probe indices
        refChannel\$true.nulls <- tryCatch({
          val <- read_input("true.nulls")
          if (is.data.frame(val) || is.matrix(val)) {
            as.vector(val[, 1])
          } else {
            as.vector(val)
          }
        }, error = function(e) {
          1:nrow(refChannel\$raw.data)
        })
        
        # Stage 1: Run the snm function on raw channels
        snm.obj3 <- snm(refChannel\$raw.data, refChannel\$bio.var,
                                    refChannel\$adj.var, refChannel\$int.var)
        ks3 <- ks.test(snm.obj3\$pval[refChannel\$true.nulls],"punif")
        
        # Stage 2: Subtract the reference channel from the experimental channel,
        # adjust the covariate matrices, and run snm on the subtracted data
        n_cols <- ncol(refChannel\$raw.data)
        half_n <- n_cols / 2
        
        refChannel\$raw.data <- refChannel\$raw.data[, 1:half_n, drop = FALSE] - 
                               refChannel\$raw.data[, (half_n + 1):n_cols, drop = FALSE]
        
        refChannel\$bio.var <- refChannel\$bio.var[1:half_n, , drop = FALSE]
        keep_bio <- apply(refChannel\$bio.var, 2, function(x) length(unique(x)) > 1)
        refChannel\$bio.var <- refChannel\$bio.var[, keep_bio, drop = FALSE]
        
        if (!is.null(refChannel\$adj.var)) {
          refChannel\$adj.var <- refChannel\$adj.var[1:half_n, , drop = FALSE]
          keep_adj <- apply(refChannel\$adj.var, 2, function(x) length(unique(x)) > 1)
          refChannel\$adj.var <- refChannel\$adj.var[, keep_adj, drop = FALSE]
          if (ncol(refChannel\$adj.var) == 0) refChannel\$adj.var <- NULL
        }
        
        refChannel\$int.var <- refChannel\$int.var[1:half_n, , drop = FALSE]
        keep_int <- sapply(refChannel\$int.var, function(x) length(unique(x)) > 1)
        refChannel\$int.var <- refChannel\$int.var[, keep_int, drop = FALSE]
        if (ncol(refChannel\$int.var) == 0) refChannel\$int.var <- NULL
        
        snm.obj4 <- snm(refChannel\$raw.data, refChannel\$bio.var,
                                    refChannel\$adj.var, refChannel\$int.var)
        ks4 <- ks.test(snm.obj4\$pval[refChannel\$true.nulls],"punif")
        
        # Write meaningful output files
        saveRDS(snm.obj3, "snm_obj3.rds")
        saveRDS(snm.obj4, "snm_obj4.rds")
        
        write.csv(snm.obj3\$norm.dat, "normalized_data_obj3.csv", row.names = TRUE)
        write.csv(snm.obj4\$norm.dat, "normalized_data_obj4.csv", row.names = TRUE)
        
        write.csv(data.frame(Probe = rownames(snm.obj3\$norm.dat), PValue = snm.obj3\$pval), "pvalues_obj3.csv", row.names = FALSE)
        write.csv(data.frame(Probe = rownames(snm.obj4\$norm.dat), PValue = snm.obj4\$pval), "pvalues_obj4.csv", row.names = FALSE)
        
        # Save KS test results
        sink("ks_test_results.txt")
        cat("=== KS Test for snm.obj3 ===\n")
        print(ks3)
        cat("\n=== KS Test for snm.obj4 ===\n")
        print(ks4)
        sink()
        
        # Save diagnostic plots
        pdf("diagnostic_plots.pdf", width = 10, height = 8)
        plot(snm.obj3)
        plot(snm.obj4)
        dev.off()

    writeLines(c(
        '"BIOC_SNM_REFERENCE_DESIGN_NORMALIZATION":',
        paste0('    snm: ', as.character(packageVersion('snm')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_reference_design_normalization.csv versions.yml
    """
}

workflow BIOC_SNM_REFERENCE_DESIGN_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw.data, bio.var, adj.var, int.var ] ]

    main:
    BIOC_SNM_REFERENCE_DESIGN_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_SNM_REFERENCE_DESIGN_NORMALIZATION.out.tables
    plots    = BIOC_SNM_REFERENCE_DESIGN_NORMALIZATION.out.plots
    objects  = BIOC_SNM_REFERENCE_DESIGN_NORMALIZATION.out.objects
    versions = BIOC_SNM_REFERENCE_DESIGN_NORMALIZATION.out.versions
}
