#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MsQuality — spectral_qc_spectra_msexperiment
// Calculate and visualize HUPO-PSI mzQC quality metrics from mass spectrometry spectral data using Spectra or MsExperiment objects.
// Input: fls, sample_metadata.csv
// Container: quay.io/biocontainers/bioconductor-msquality:1.10.0--r45hdfd78af_0
// R packages: BiocParallel, Chromatograms, knitr, MsExperiment, MsQuality, Spectra
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, Chromatograms, MsExperiment, MsQuality, Spectra
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load libraries and register parallel backend
//  * 2. [Input & Preparation] Create a Spectra object from raw files
//  * 3. [Input & Preparation] Create an MsExperiment object to group samples and link sample metadata
//  * 4. [Core Analysis] Retrieve available metrics using qualityMetrics()
//  * 5. [Core Analysis] Calculate metrics using calculateMetrics()
//  * 6. [Visualization & Output] Visualize metrics using plotMetric() or explore interactively with shinyMsQuality()

nextflow.enable.dsl = 2

process BIOC_MSQUALITY_SPECTRAL_QC_SPECTRA_MSEXPERIMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("BiocParallel", "Chromatograms", "knitr", "MsExperiment", "MsQuality", "Spectra")
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
    
    # 1. Load libraries and register parallel backend
    library("Spectra")
    library("MsExperiment")
    library("Chromatograms")
    library("MsQuality")
    library("BiocParallel")
    
    register(SerialParam())
    
    # Read user inputs from the working directory
    if (!file.exists("sample_metadata.csv")) {
        stop("Error: sample_metadata.csv not found in the working directory.")
    }
    sample_metadata <- read.csv("sample_metadata.csv", stringsAsFactors = FALSE)
    sd <- DataFrame(sample_metadata)
    
    fls <- list.files(pattern = "\\\\.(mzML|mzXML|cdf|CDF)\$", ignore.case = TRUE, full.names = TRUE)
    if (length(fls) == 0) {
        stop("Error: No mzML, mzXML, or CDF files found in the working directory.")
    }
    
    # Align files and metadata to ensure matching lengths
    n_samples <- min(nrow(sd), length(fls))
    if (n_samples == 0) {
        stop("Error: No matching samples and files found. Ensure sample_metadata.csv is not empty and mzML/mzXML/CDF files are present.")
    }
    sd <- sd[1:n_samples, , drop = FALSE]
    fls <- fls[1:n_samples]
    
    # 2. Create a Spectra object from raw files
    sps_sciex <- Spectra(fls, backend = MsBackendMzR())
    
    # 3. Create an MsExperiment object to group samples and link sample metadata
    lmse <- MsExperiment()
    sampleData(lmse) <- sd
    experimentFiles(lmse) <- MsExperimentFiles(mzML_files = fls)
    spectra(lmse) <- sps_sciex
    lmse <- linkSampleData(lmse, with = "experimentFiles.mzML_files",
        sampleIndex = seq_len(n_samples), withIndex = seq_len(n_samples))
    
    # 4. Retrieve available metrics using qualityMetrics()
    # 5. Calculate metrics using calculateMetrics()
    metrics_sps_Q1 <- calculateMetrics(object = sps_sciex,
        metrics = qualityMetrics(sps_sciex), filterEmptyObject = FALSE,
        relativeTo = "Q1", msLevel = 1L)
    
    metrics_msexp <- calculateMetrics(object = lmse,
        metrics = qualityMetrics(lmse), filterEmptyObject = TRUE,
        relativeTo = "Q1", msLevel = 1L)
    
    # Save calculated metrics to CSV and RDS
    write.csv(as.data.frame(metrics_sps_Q1), "metrics_sps_Q1.csv", row.names = TRUE)
    write.csv(as.data.frame(metrics_msexp), "metrics_msexp.csv", row.names = TRUE)
    saveRDS(metrics_sps_Q1, "metrics_sps_Q1.rds")
    saveRDS(metrics_msexp, "metrics_msexp.rds")
    
    # 6. Visualize metrics using plotMetric() or explore interactively with shinyMsQuality()
    pdf("msquality_plots.pdf", width = 8, height = 6)
    tryCatch({
        plotMetric(qc = metrics_msexp, metric = "numberSpectra")
    }, error = function(e) {
        warning("Failed to plot numberSpectra: ", e\$message)
    })
    
    tryCatch({
        plotMetric(qc = metrics_msexp, metric = "ticQuartileToQuartileLogRatio")
    }, error = function(e) {
        warning("Failed to plot ticQuartileToQuartileLogRatio: ", e\$message)
    })
    dev.off()
    
    if (interactive()) {
        shinyMsQuality(qc = metrics_msexp)
    } else {
        message("Skipping interactive shinyMsQuality() in non-interactive mode.")
    }

    writeLines(c(
        '"BIOC_MSQUALITY_SPECTRAL_QC_SPECTRA_MSEXPERIMENT":',
        paste0('    MsQuality: ', as.character(packageVersion('MsQuality')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spectral_qc_spectra_msexperiment.csv versions.yml
    """
}

workflow BIOC_MSQUALITY_SPECTRAL_QC_SPECTRA_MSEXPERIMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fls, sample_metadata.csv ] ]

    main:
    BIOC_MSQUALITY_SPECTRAL_QC_SPECTRA_MSEXPERIMENT(ch_input)

    emit:
    tables   = BIOC_MSQUALITY_SPECTRAL_QC_SPECTRA_MSEXPERIMENT.out.tables
    plots    = BIOC_MSQUALITY_SPECTRAL_QC_SPECTRA_MSEXPERIMENT.out.plots
    objects  = BIOC_MSQUALITY_SPECTRAL_QC_SPECTRA_MSEXPERIMENT.out.objects
    versions = BIOC_MSQUALITY_SPECTRAL_QC_SPECTRA_MSEXPERIMENT.out.versions
}
