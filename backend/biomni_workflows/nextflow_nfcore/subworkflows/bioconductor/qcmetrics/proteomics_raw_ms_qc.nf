#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: qcmetrics — proteomics_raw_ms_qc
// Generate a quality control report for raw mass spectrometry proteomics data (mzXML/mzML) including chromatograms, MS space, and m/z delta plots.
// Input: exp.rda
// Container: quay.io/biocontainers/bioconductor-qcmetrics:1.48.0--r45hdfd78af_0
// R packages: MSnbase, ggplot2, qcmetrics
// Bioconductor: 3.20 | R: 4.4
// Requires: MSnbase, ggplot2, qcmetrics
// Visualizations: array QC report
// QC: array detection QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load raw mass spectrometry data
//  * 2. [Input & Preparation] Create a chromatogram QC metric
//  * 3. [Visualization & Output] Create an MS space 2D plot QC metric
//  * 4. [Visualization & Output] Create an m/z delta plot QC metric
//  * 5. [Core Analysis] Combine metrics into a QcMetrics object and add instrument metadata
//  * 6. [Visualization & Output] Generate the QC report

nextflow.enable.dsl = 2

process BIOC_QCMETRICS_PROTEOMICS_RAW_MS_QC {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("MSnbase", "ggplot2", "qcmetrics")
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
    library(qcmetrics)
    library(MSnbase)
    library(ggplot2)
    
    # 1. Load raw mass spectrometry data
    input_file <- "exp.rda"
    if (!file.exists(input_file)) {
      stop(paste("Required input file", input_file, "not found in the working directory."))
    }
    
    # Load the MSnExp object (expected to be named 'exp')
    load(input_file)
    
    if (!exists("exp") || !inherits(exp, "MSnExp")) {
      stop("The loaded file does not contain an 'MSnExp' object named 'exp'.")
    }
    
    # 2. Create a chromatogram QC metric
    qc1 <- QcMetric(name = "Chromatogram")
    x <- rtime(exp)
    y <- precursorIntensity(exp)
    o <- order(x)
    qcdata(qc1, "x") <- x[o]
    qcdata(qc1, "y") <- y[o]
    plot(qc1) <- function(object, ...)
        plot(qcdata(object, "x"),
             qcdata(object, "y"),
             col = "darkgrey", type ="l",
             xlab = "retention time",
             ylab = "precursor intensity")
    
    # 3. Create an MS space 2D plot QC metric
    qc2 <- QcMetric(name = "MS space")
    qcdata(qc2, "p2d") <- plot2d(exp, z = "charge", plot = FALSE)
    plot(qc2) <- function(object) {
        require("ggplot2")
        print(qcdata(object, "p2d"))
    }
    
    # 4. Create an m/z delta plot QC metric
    qc3 <- QcMetric(name = "m/z delta plot")
    qcdata(qc3, "pmz") <- plotMzDelta(exp, plot = FALSE, verbose = FALSE)
    plot(qc3) <- function(object)
        suppressWarnings(print(qcdata(object, "pmz")))
    
    # 5. Combine metrics into a QcMetrics object and add instrument metadata
    protqcm <- QcMetrics(qcdata = list(qc1, qc2, qc3))
    metadata(protqcm) <- list(
        data = "PXD000001",
        instrument = experimentData(exp)@instrumentModel,
        source = experimentData(exp)@ionSource,
        analyser = experimentData(exp)@analyser,
        detector = experimentData(exp)@detectorType,
        manufacurer = experimentData(exp)@instrumentManufacturer)
    
    # 6. Generate the QC report and other outputs
    # Save the QcMetrics object as RDS
    saveRDS(protqcm, file = "protqcm.rds")
    
    # Export chromatogram data to CSV
    chrom_df <- data.frame(
      retention_time = qcdata(qc1, "x"),
      precursor_intensity = qcdata(qc1, "y")
    )
    write.csv(chrom_df, file = "chromatogram_data.csv", row.names = FALSE)
    
    # Generate PDF of the individual plots
    pdf("qc_plots.pdf", width = 7, height = 7)
    plot(qc1)
    plot(qc2)
    plot(qc3)
    dev.off()
    
    # Generate the official qcReport
    qcReport(protqcm, reportname = "protqc")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # array detection QC — ExpressionSet detection p-values or detection-column data.frame.
    .adq_rate <- NA_real_
    for (.adq_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
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
      process = "BIOC_QCMETRICS_PROTEOMICS_RAW_MS_QC",
      domain  = "bioconductor",
      declared_qc_steps = c("array detection QC"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_QCMETRICS_PROTEOMICS_RAW_MS_QC":',
        paste0('    qcmetrics: ', as.character(packageVersion('qcmetrics')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_proteomics_raw_ms_qc.csv versions.yml
    """
}

workflow BIOC_QCMETRICS_PROTEOMICS_RAW_MS_QC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exp.rda ] ]

    main:
    BIOC_QCMETRICS_PROTEOMICS_RAW_MS_QC(ch_input)

    emit:
    tables   = BIOC_QCMETRICS_PROTEOMICS_RAW_MS_QC.out.tables
    plots    = BIOC_QCMETRICS_PROTEOMICS_RAW_MS_QC.out.plots
    objects  = BIOC_QCMETRICS_PROTEOMICS_RAW_MS_QC.out.objects
    versions = BIOC_QCMETRICS_PROTEOMICS_RAW_MS_QC.out.versions
}
