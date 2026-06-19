#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: AffiXcan — grex_training_and_imputation
// Train GReX models using expression and TBA data, then impute GReX values on a test dataset.
// Input: exprMatrix, training.tba.toydata.rds, regionAssoc, trainingCovariates, testing.tba.toydata.rds
// Container: quay.io/biocontainers/bioconductor-affixcan:1.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: AffiXcan, MultiAssayExperiment, SummarizedExperiment
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Train the GReX models using affiXcanTrain()
//  * 2. [Core Analysis] Impute GReX values on the test dataset using affiXcanImpute()
//  * 3. [Visualization & Output] Extract the imputed GReX matrix from the resulting SummarizedExperiment

nextflow.enable.dsl = 2

process BIOC_AFFIXCAN_GREX_TRAINING_AND_IMPUTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("MultiAssayExperiment", "AffiXcan", "SummarizedExperiment")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(MultiAssayExperiment)
    library(SummarizedExperiment)
    library(AffiXcan)
    
    # Helper function to robustly read user input files from the working directory
    read_input <- function(name) {
      # Try various extensions in case the user provided them
      for (ext in c("", ".rds", ".RDS", ".RData", ".rdata", ".csv", ".tsv")) {
        file_path <- paste0(name, ext)
        if (file.exists(file_path)) {
          if (grepl("\\\\.rds\$", tolower(file_path))) {
            return(readRDS(file_path))
          } else if (grepl("\\\\.rdata\$", tolower(file_path))) {
            env <- new.env()
            load(file_path, envir = env)
            return(get(ls(env)[1], envir = env))
          } else if (grepl("\\\\.csv\$", tolower(file_path))) {
            return(read.csv(file_path, header = TRUE, stringsAsFactors = FALSE))
          } else if (grepl("\\\\.tsv\$", tolower(file_path))) {
            return(read.delim(file_path, header = TRUE, stringsAsFactors = FALSE))
          } else {
            # No extension or unknown, try reading as RDS first, then RData, then table
            res <- tryCatch({
              readRDS(file_path)
            }, error = function(e) {
              tryCatch({
                env <- new.env()
                load(file_path, envir = env)
                get(ls(env)[1], envir = env)
              }, error = function(e2) {
                read.table(file_path, header = TRUE, stringsAsFactors = FALSE)
              })
            })
            return(res)
          }
        }
      }
      stop(paste("Required input file not found:", name))
    }
    
    # 1. Read User Inputs
    exprMatrix <- read_input("exprMatrix")
    regionAssoc <- read_input("regionAssoc")
    trainingCovariates <- read_input("trainingCovariates")
    
    trainingTbaPaths <- "training.tba.toydata.rds"
    testingTbaPaths <- "testing.tba.toydata.rds"
    
    # Verify that the TBA paths exist
    if (!file.exists(trainingTbaPaths)) {
      stop(paste("Required TBA file not found:", trainingTbaPaths))
    }
    if (!file.exists(testingTbaPaths)) {
      stop(paste("Required TBA file not found:", testingTbaPaths))
    }
    
    # 2. Train GReX Models
    assay <- "values"
    
    training <- affiXcanTrain(exprMatrix=exprMatrix, assay=assay,
        tbaPaths=trainingTbaPaths, regionAssoc=regionAssoc, cov=trainingCovariates,
        varExplained=80, scale=TRUE)
    
    # Save trained model object
    saveRDS(training, "affiXcan_training_model.rds")
    
    # 3. Impute GReX Values
    exprmatrix <- affiXcanImpute(tbaPaths=testingTbaPaths,
        affiXcanTraining=training, scale=TRUE)
    
    # Save imputed SummarizedExperiment object
    saveRDS(exprmatrix, "imputed_grex_se.rds")
    
    # 4. Extract and Save Imputed GReX Matrix
    grexMatrix <- assays(exprmatrix)\$GReX
    write.csv(as.data.frame(grexMatrix), "imputed_grex_matrix.csv", row.names = TRUE)
    
    # 5. Generate Diagnostic Plot
    pdf("imputed_grex_distribution.pdf")
    hist(grexMatrix, main="Distribution of Imputed GReX Values", xlab="GReX", col="skyblue", border="white")
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
      process = "BIOC_AFFIXCAN_GREX_TRAINING_AND_IMPUTATION",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_AFFIXCAN_GREX_TRAINING_AND_IMPUTATION":',
        paste0('    AffiXcan: ', as.character(packageVersion('AffiXcan')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_grex_training_and_imputation.csv versions.yml
    """
}

workflow BIOC_AFFIXCAN_GREX_TRAINING_AND_IMPUTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exprMatrix, training.tba.toydata.rds, regionAssoc, trainingCovariates, testing.tba.toydata.rds ] ]

    main:
    BIOC_AFFIXCAN_GREX_TRAINING_AND_IMPUTATION(ch_input)

    emit:
    tables   = BIOC_AFFIXCAN_GREX_TRAINING_AND_IMPUTATION.out.tables
    plots    = BIOC_AFFIXCAN_GREX_TRAINING_AND_IMPUTATION.out.plots
    objects  = BIOC_AFFIXCAN_GREX_TRAINING_AND_IMPUTATION.out.objects
    versions = BIOC_AFFIXCAN_GREX_TRAINING_AND_IMPUTATION.out.versions
}
