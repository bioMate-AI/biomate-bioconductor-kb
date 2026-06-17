#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pcaMethods — pca_and_imputation
// Perform PCA on a matrix containing missing values and impute the missing values to obtain a complete dataset.
// Input: metaboliteData
// Container: quay.io/biocontainers/bioconductor-pcamethods:2.2.0--r45ha27e39d_0
// R packages: Biobase, ggplot2, pcaMethods
// Bioconductor: 3.20 | R: 4.4
// Requires: pcaMethods
// Visualizations: PCA plot
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run PCA using a method that handles missing values (e.g., PPCA)
//  * 2. [Core Analysis] Impute missing values using completeObs

nextflow.enable.dsl = 2

process BIOC_PCAMETHODS_PCA_AND_IMPUTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("Biobase", "ggplot2", "pcaMethods")
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
    library(pcaMethods)
    
    # Locate and read the user input file
    # The user input is specified as 'metaboliteData' (matrix containing missing values represented as NA)
    input_file <- "metaboliteData.csv"
    if (!file.exists(input_file)) {
      if (file.exists("metaboliteData")) {
        input_file <- "metaboliteData"
      } else if (file.exists("metaboliteData.txt")) {
        input_file <- "metaboliteData.txt"
      } else {
        stop("Error: Input file 'metaboliteData' (CSV or TXT format) not found in the working directory.")
      }
    }
    
    # Read the matrix data
    mD_df <- read.csv(input_file, row.names = 1, check.names = FALSE)
    mD <- as.matrix(mD_df)
    
    # 1. Run PCA using a method that handles missing values (PPCA)
    # Keep function call and arguments exactly as documented
    pc <- pca(mD, nPcs=3, method="ppca")
    
    # 2. Impute missing values using completeObs
    # Keep function call and arguments exactly as documented
    imputed <- completeObs(pc)
    
    # Write named output files for the meaningful results
    write.csv(imputed, "imputed_metaboliteData.csv", row.names = TRUE)
    write.csv(scores(pc), "pca_scores.csv", row.names = TRUE)
    write.csv(loadings(pc), "pca_loadings.csv", row.names = TRUE)
    saveRDS(pc, "pca_model.rds")
    
    # Generate diagnostic plots
    pdf("pca_plots.pdf", width = 7, height = 7)
    plotPcs(pc, pc=1:3, type="score")
    dev.off()
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
      process = "BIOC_PCAMETHODS_PCA_AND_IMPUTATION",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_PCAMETHODS_PCA_AND_IMPUTATION":',
        paste0('    pcaMethods: ', as.character(packageVersion('pcaMethods')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pca_and_imputation.csv versions.yml
    """
}

workflow BIOC_PCAMETHODS_PCA_AND_IMPUTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ metaboliteData ] ]

    main:
    BIOC_PCAMETHODS_PCA_AND_IMPUTATION(ch_input)

    emit:
    tables   = BIOC_PCAMETHODS_PCA_AND_IMPUTATION.out.tables
    plots    = BIOC_PCAMETHODS_PCA_AND_IMPUTATION.out.plots
    objects  = BIOC_PCAMETHODS_PCA_AND_IMPUTATION.out.objects
    versions = BIOC_PCAMETHODS_PCA_AND_IMPUTATION.out.versions
}
