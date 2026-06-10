#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: qcmetrics — proteomics_raw_ms_qc
// Generate a quality control report for raw mass spectrometry proteomics data (mzXML/mzML) including chromatograms, MS space, and m/z delta plots.
// Input: exp.rda
// Container: quay.io/biocontainers/bioconductor-qcmetrics:1.48.0--r45hdfd78af_0
// R packages: MSnbase, ggplot2, qcmetrics
// Bioconductor: 3.20 | R: 4.4
// Requires: MSnbase, ggplot2, qcmetrics
// Visualizations: plot (ggplot/base)
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

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    .bm_deps <- c("MSnbase", "ggplot2", "qcmetrics")
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
