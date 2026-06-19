#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scmeth — comprehensive_qc_report
// Generate an all-inclusive HTML quality control report for a methylation dataset.
// Input: directory
// Container: quay.io/biocontainers/bioconductor-scmeth:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Hsapiens.UCSC.hg38, HDF5Array, scmeth
// QC: array detection QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the bsseq object from the HDF5 directory
//  * 2. [Visualization & Output] Generate the HTML quality control report using the report function

nextflow.enable.dsl = 2

process BIOC_SCMETH_COMPREHENSIVE_QC_REPORT {
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
    .bm_deps <- c("scmeth", "HDF5Array", "BSgenome.Hsapiens.UCSC.hg38")
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
    library(scmeth)
    library(HDF5Array)
    library(BSgenome.Hsapiens.UCSC.hg38)
    
    # Define input directory containing the HDF5-stored bsseq object
    # The pipeline reads the 'directory' folder from the working directory
    directory <- "directory"
    
    # Check if the input directory exists
    if (!dir.exists(directory)) {
      stop(paste("Input directory '", directory, "' does not exist in the current working directory.", sep = ""))
    }
    
    # 1. Load the bsseq object from the HDF5 directory
    message("Loading HDF5 Summarized Experiment...")
    bsObject <- HDF5Array::loadHDF5SummarizedExperiment(directory)
    
    # 2. Generate the HTML quality control report using the report function
    # We use the current working directory '.' as the output directory to ensure writability
    message("Generating comprehensive QC report...")
    report(bsObject, '.', Hsapiens, "hg38")
    
    # Verify output generation
    output_report <- "qcReport.html"
    if (file.exists(output_report)) {
      message(paste("Successfully generated QC report:", output_report))
    } else {
      warning("QC report file was not found in the output directory.")
    }
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # array detection QC — ExpressionSet detection p-values or detection-column data.frame.
    .adq_rate <- NA_real_
    for (.adq_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .adq_obj <- tryCatch(readRDS(.adq_rds), error = function(e) NULL)
      .adq_pv <- NULL
      if (!is.null(.adq_obj)) {
        if (inherits(.adq_obj, "ExpressionSet")) {
          .adq_pv <- tryCatch(Biobase::assayDataElement(.adq_obj, "Detection"), error = function(e) NULL)
        } else if (is.matrix(.adq_obj) || is.data.frame(.adq_obj)) {
          .adq_cols <- grep("(?i)(detection|pvalue|pval)", colnames(.adq_obj), value = TRUE)
          if (length(.adq_cols) > 0) .adq_pv <- as.matrix(.adq_obj[, .adq_cols, drop = FALSE])
        }
      }
      if (!is.null(.adq_pv) && length(.adq_pv) > 0) {
        .adq_rate <- round(mean(as.numeric(.adq_pv) < 0.05, na.rm = TRUE), 4); break
      }
    }
    .gates_by_label[["array detection QC"]] <- list(
      gate_row = "bioc_array_detection_qc",
      metric_name = "detection_rate",
      metric_value = .adq_rate,
      passes = isTRUE(is.finite(.adq_rate) && .adq_rate >= 0.75),
      status = if (is.finite(.adq_rate)) "computed (probe-detection p<0.05 fraction)"
               else "not_computed (no ExpressionSet/detection-p .rds present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_SCMETH_COMPREHENSIVE_QC_REPORT",
      domain  = "bioconductor",
      declared_qc_steps = c("array detection QC"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SCMETH_COMPREHENSIVE_QC_REPORT":',
        paste0('    scmeth: ', as.character(packageVersion('scmeth')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_comprehensive_qc_report.csv versions.yml
    """
}

workflow BIOC_SCMETH_COMPREHENSIVE_QC_REPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ directory ] ]

    main:
    BIOC_SCMETH_COMPREHENSIVE_QC_REPORT(ch_input)

    emit:
    tables   = BIOC_SCMETH_COMPREHENSIVE_QC_REPORT.out.tables
    plots    = BIOC_SCMETH_COMPREHENSIVE_QC_REPORT.out.plots
    objects  = BIOC_SCMETH_COMPREHENSIVE_QC_REPORT.out.objects
    versions = BIOC_SCMETH_COMPREHENSIVE_QC_REPORT.out.versions
}
