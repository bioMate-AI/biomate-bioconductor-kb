#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: enmix — custom_step_by_step_preprocessing
// Perform customized quality control, background/dye correction, normalization, probe-type bias adjustment, and filtering/imputation sequentially.
// Input: directory path for idat files, csv
// Container: quay.io/biocontainers/bioconductor-enmix:1.46.1--r45hdfd78af_0
// R packages: ENmix
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// QC: missing-value handling

nextflow.enable.dsl = 2

process BIOC_ENMIX_CUSTOM_STEP_BY_STEP_PREPROCESSING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-enmix:1.46.1--r45hdfd78af_0"

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
    .bm_deps <- c("ENmix", "SummarizedExperiment")
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
    library(SummarizedExperiment)
    library(ENmix)
    
    # ----------------------------------------------------------------------
    # --- Locate User Inputs (IDAT directory and CSV sample sheet) ---
    # ----------------------------------------------------------------------
    message("Searching for IDAT directory and CSV sample sheet...")
    
    # Find a directory in the current working directory containing .idat files
    all_dirs <- list.dirs(".", recursive = TRUE)
    idat_dir <- NULL
    for (d in all_dirs) {
      idat_files <- list.files(d, pattern = "\\\\.idat(\\\\.gz)?\$", ignore.case = TRUE)
      if (length(idat_files) > 0) {
        idat_dir <- d
        break
      }
    }
    
    if (is.null(idat_dir)) {
      stop("Error: No directory containing IDAT files found in the current working directory.")
    }
    message("Found IDAT directory: ", idat_dir)
    
    # Find CSV sample sheet
    csv_files <- list.files(".", pattern = "\\\\.csv\$", full.names = TRUE, recursive = TRUE)
    sample_sheet_path <- NULL
    if (length(csv_files) > 0) {
      # Prefer files with "sample", "sheet", "target", or "pheno" in the name
      idx <- grep("sample|sheet|target|pheno", csv_files, ignore.case = TRUE)
      if (length(idx) > 0) {
        sample_sheet_path <- csv_files[idx[1]]
      } else {
        sample_sheet_path <- csv_files[1]
      }
    }
    
    if (is.null(sample_sheet_path)) {
      warning("Warning: No CSV sample sheet found in the current working directory.")
    } else {
      message("Found sample sheet: ", sample_sheet_path)
      # Read and verify the sample sheet
      sheet <- read.csv(sample_sheet_path, stringsAsFactors = FALSE)
      write.csv(sheet, "loaded_sample_sheet_check.csv", row.names = FALSE)
    }
    
    # ----------------------------------------------------------------------
    # --- Read raw IDAT files ---
    # ----------------------------------------------------------------------
    message("Reading IDAT files...")
    rgSet <- readidat(path = idat_dir, recursive = TRUE)
    
    # If a sample sheet was found, attempt to attach it to rgSet as colData
    if (!is.null(sample_sheet_path) && exists("sheet")) {
      tryCatch({
        if ("Slide" %in% colnames(sheet) && "Array" %in% colnames(sheet)) {
          rownames(sheet) <- paste(sheet\$Slide, sheet\$Array, sep = "_")
          common_samples <- intersect(rownames(sheet), colnames(rgSet))
          if (length(common_samples) > 0) {
            colData(rgSet) <- as(sheet[colnames(rgSet), ], "DataFrame")
            message("Successfully attached sample sheet metadata to rgSet.")
          }
        }
      }, error = function(e) {
        message("Could not attach sample sheet to rgSet: ", e\$message)
      })
    }
    
    # ----------------------------------------------------------------------
    # --- Extract quality control information ---
    # ----------------------------------------------------------------------
    message("Extracting QC info...")
    qc <- QCinfo(rgSet)
    saveRDS(qc, "qc_info.rds")
    
    # ----------------------------------------------------------------------
    # --- Background correction and dye bias correction ---
    # ----------------------------------------------------------------------
    message("Performing background and dye bias correction...")
    mdat <- preprocessENmix(rgSet, bgParaEst="oob", dyeCorr="RELIC",
                            QCinfo=qc, nCores=6)
    saveRDS(mdat, "preprocess_mdat.rds")
    
    # ----------------------------------------------------------------------
    # --- Between-array normalization ---
    # ----------------------------------------------------------------------
    message("Performing between-array normalization...")
    mdat <- norm.quantile(mdat, method="quantile1")
    saveRDS(mdat, "normalized_mdat.rds")
    
    # ----------------------------------------------------------------------
    # --- Probe-type bias adjustment ---
    # ----------------------------------------------------------------------
    message("Adjusting for probe-type design bias...")
    beta <- rcp(mdat, qcscore=qc)
    saveRDS(beta, "rcp_beta.rds")
    
    # ----------------------------------------------------------------------
    # --- Filter low quality/outlier data points and perform ---
    # ----------------------------------------------------------------------
    message("Filtering and imputing missing values...")
    beta <- qcfilter(beta, qcscore=qc, rmcr=TRUE, impute=TRUE)
    saveRDS(beta, "final_filtered_imputed_beta.rds")
    
    # Write final beta values to CSV
    message("Writing final beta values to CSV...")
    write.csv(beta, "final_beta_values.csv", row.names = TRUE)
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_ENMIX_CUSTOM_STEP_BY_STEP_PREPROCESSING":',
        paste0('        enmix: ', as.character(packageVersion("enmix")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_step_by_step_preprocessing.csv versions.yml
    """
}

workflow BIOC_ENMIX_CUSTOM_STEP_BY_STEP_PREPROCESSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ directory path for idat files, csv ] ]

    main:
    BIOC_ENMIX_CUSTOM_STEP_BY_STEP_PREPROCESSING(ch_input)

    emit:
    tables   = BIOC_ENMIX_CUSTOM_STEP_BY_STEP_PREPROCESSING.out.tables
    plots    = BIOC_ENMIX_CUSTOM_STEP_BY_STEP_PREPROCESSING.out.plots
    objects  = BIOC_ENMIX_CUSTOM_STEP_BY_STEP_PREPROCESSING.out.objects
    versions = BIOC_ENMIX_CUSTOM_STEP_BY_STEP_PREPROCESSING.out.versions
}
