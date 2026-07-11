#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ENmix — customized_preprocessing
// Perform step-by-step customized quality control, background correction, dye-bias correction, normalization, probe-type bias adjustment, and filtering/imputation
// Input: directory path for idat files
// Container: quay.io/biocontainers/bioconductor-enmix:1.46.1--r45hdfd78af_0
// R packages: ENmix
// Bioconductor: 3.20 | R: 4.4
// Requires: ENmix
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read raw IDAT files using readidat
//  * 2. [Core Analysis] Extract quality control information using QCinfo
//  * 3. [Core Analysis] Perform background and dye-bias correction using preprocessENmix
//  * 4. [Core Analysis] Perform between-array quantile normalization using norm.quantile
//  * 5. [Core Analysis] Adjust for probe-type design bias using rcp
//  * 6. [Core Analysis] Filter low-quality/outlier data points and perform imputation using qcfilter

nextflow.enable.dsl = 2

process BIOC_ENMIX_CUSTOMIZED_PREPROCESSING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("ENmix")
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
    library(ENmix)
    
    # Identify the input directory containing raw IDAT files
    args <- commandArgs(trailingOnly = TRUE)
    if (length(args) > 0) {
      path <- args[1]
    } else {
      # Search for any directory containing .idat files in the current working directory
      idat_files <- list.files(pattern = "\\\\.idat(\\\\.gz)?\$", recursive = TRUE, ignore.case = TRUE)
      if (length(idat_files) > 0) {
        path <- unique(dirname(idat_files))[1]
      } else {
        path <- "idats" # Default fallback directory
      }
    }
    
    # Verify directory existence
    if (!dir.exists(path)) {
      stop(paste("Error: The specified IDAT directory does not exist:", path))
    }
    
    message(paste("Reading IDAT files from:", path))
    
    # 1. Read raw IDAT files using readidat
    rgSet <- readidat(path = path, recursive = TRUE)
    
    # 2. Extract quality control information using QCinfo
    message("Extracting QC information...")
    qc <- QCinfo(rgSet)
    
    # Save QC info to RDS and CSV summaries
    saveRDS(qc, file = "qc_info.rds")
    if (!is.null(qc\$badsample) && length(qc\$badsample) > 0) {
      write.csv(data.frame(BadSamples = qc\$badsample), file = "bad_samples.csv", row.names = FALSE)
    }
    if (!is.null(qc\$badCpG) && length(qc\$badCpG) > 0) {
      write.csv(data.frame(BadCpGs = qc\$badCpG), file = "bad_cpgs.csv", row.names = FALSE)
    }
    if (!is.null(qc\$outlier_sample) && length(qc\$outlier_sample) > 0) {
      write.csv(data.frame(OutlierSamples = qc\$outlier_sample), file = "outlier_samples.csv", row.names = FALSE)
    }
    
    # 3. Perform background and dye-bias correction using preprocessENmix
    message("Performing background and dye-bias correction...")
    mdat <- preprocessENmix(rgSet, bgParaEst = "oob", dyeCorr = "RELIC",
                            QCinfo = qc, nCores = 6)
    
    # 4. Perform between-array quantile normalization using norm.quantile
    message("Performing between-array normalization...")
    mdat <- norm.quantile(mdat, method = "quantile1")
    
    # Save normalized mdat object
    saveRDS(mdat, file = "normalized_mdat.rds")
    
    # 5. Adjust for probe-type design bias using rcp
    message("Adjusting for probe-type design bias (RCP)...")
    beta <- rcp(mdat, qcscore = qc)
    
    # 6. Filter low-quality/outlier data points and perform imputation using qcfilter
    message("Filtering low quality data points and performing imputation...")
    beta <- qcfilter(beta, qcscore = qc, rmcr = TRUE, impute = TRUE)
    
    # Save final beta values
    message("Saving final preprocessed beta values...")
    saveRDS(beta, file = "final_beta_matrix.rds")
    
    # Write a preview of the beta matrix to CSV
    write.csv(head(beta, 100), file = "final_beta_preview.csv")
    
    message("Customized preprocessing pipeline completed successfully!")
    # ── BIOC_QC_HARNESS — Phase 3c bulk adoption (missing-value handling) ───
    # Defensive scan: list every *.rds the workflow produced, load each one,
    # compute NA fraction across numeric cells where the artifact is a
    # matrix or data.frame. Report max NA fraction across artifacts.
    # Threshold from bioc_missing_value_handling: < 5% pass.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()
    .na_fracs <- numeric(0)
    .scanned_files <- character(0)
    for (.rds_file in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
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
      process = "BIOC_ENMIX_CUSTOMIZED_PREPROCESSING",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_ENMIX_CUSTOMIZED_PREPROCESSING":',
        paste0('    ENmix: ', as.character(packageVersion('ENmix')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_customized_preprocessing.csv versions.yml
    """
}

workflow BIOC_ENMIX_CUSTOMIZED_PREPROCESSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ directory path for idat files ] ]

    main:
    BIOC_ENMIX_CUSTOMIZED_PREPROCESSING(ch_input)

    emit:
    tables   = BIOC_ENMIX_CUSTOMIZED_PREPROCESSING.out.tables
    plots    = BIOC_ENMIX_CUSTOMIZED_PREPROCESSING.out.plots
    objects  = BIOC_ENMIX_CUSTOMIZED_PREPROCESSING.out.objects
    versions = BIOC_ENMIX_CUSTOMIZED_PREPROCESSING.out.versions
}
