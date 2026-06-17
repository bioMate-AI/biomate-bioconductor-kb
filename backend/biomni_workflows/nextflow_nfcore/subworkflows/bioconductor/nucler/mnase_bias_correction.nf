#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: nucler — mnase_bias_correction
// Correct nucleosomal DNA coverage profiles using a mock control sample of naked DNA digested with MNase.
// Input: nucleosomal_coverage.RData, control_coverage.RData
// Container: quay.io/biocontainers/bioconductor-nucler:2.42.0--r45hdfd78af_0
// R packages: GenomicRanges, IRanges, ggplot2, nucleR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NUCLER_MNASE_BIAS_CORRECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-nucler:2.42.0--r45hdfd78af_0"

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
    .bm_deps <- c("GenomicRanges", "IRanges", "ggplot2", "nucleR")
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
    library(nucleR)
    library(IRanges)
    library(GenomicRanges)
    library(ggplot2)
    
    # ------------------------------------------------------------------------------
    # --- Load User Input Files ---
    # ------------------------------------------------------------------------------
    # Load nucleosomal coverage (RleList)
    if (!file.exists("nucleosomal_coverage.RData")) {
      stop("Error: 'nucleosomal_coverage.RData' not found in the working directory.")
    }
    env_exp <- new.env()
    load("nucleosomal_coverage.RData", envir = env_exp)
    exp_objs <- ls(env_exp)
    if (length(exp_objs) == 0) {
      stop("Error: 'nucleosomal_coverage.RData' is empty.")
    }
    exp <- env_exp[[exp_objs[1]]]
    
    # Load control coverage (RleList)
    if (!file.exists("control_coverage.RData")) {
      stop("Error: 'control_coverage.RData' not found in the working directory.")
    }
    env_ctr <- new.env()
    load("control_coverage.RData", envir = env_ctr)
    ctr_objs <- ls(env_ctr)
    if (length(ctr_objs) == 0) {
      stop("Error: 'control_coverage.RData' is empty.")
    }
    ctr <- env_ctr[[ctr_objs[1]]]
    
    # ------------------------------------------------------------------------------
    # --- MNase Bias Correction ---
    # ------------------------------------------------------------------------------
    # Correct nucleosomal DNA coverage profiles using the mock control sample
    corrected <- controlCorrection(exp, ctr)
    
    # ------------------------------------------------------------------------------
    # --- Save Outputs ---
    # ------------------------------------------------------------------------------
    # Save the corrected coverage object
    saveRDS(corrected, file = "corrected_coverage.rds")
    save(corrected, file = "corrected_coverage.RData")
    
    # Generate a comparison plot for the first chromosome/scaffold
    tryCatch({
      chr_name <- names(exp)[1]
      if (!is.null(chr_name)) {
        exp_vec <- as.vector(exp[[chr_name]])
        corr_vec <- as.vector(corrected[[chr_name]])
        
        # Limit plot to the first 5000 bp (or maximum available length)
        plot_len <- min(5000, length(exp_vec), length(corr_vec))
        
        if (plot_len > 0) {
          plot_data <- rbind(
            data.frame(
              position = 1:plot_len,
              coverage = exp_vec[1:plot_len],
              type = "Original"
            ),
            data.frame(
              position = 1:plot_len,
              coverage = corr_vec[1:plot_len],
              type = "Corrected"
            )
          )
          
          pdf("mnase_bias_correction_plot.pdf", width = 8, height = 4)
          p <- ggplot(plot_data, aes(x = position, y = coverage, color = type)) +
            geom_line(alpha = 0.8) +
            labs(
              title = paste("MNase Bias Correction -", chr_name),
              x = "Genomic Position (bp)",
              y = "Coverage",
              color = "Profile"
            ) +
            theme_minimal()
          print(p)
          dev.off()
          message("Plot saved to 'mnase_bias_correction_plot.pdf'")
        }
      }
    }, error = function(e) {
      warning("Could not generate comparison plot: ", e\$message)
    })
    
    message("Pipeline completed successfully. Corrected coverage saved to 'corrected_coverage.rds' and 'corrected_coverage.RData'.")

    writeLines(c(
        '"BIOC_NUCLER_MNASE_BIAS_CORRECTION":',
        paste0('        nucler: ', as.character(packageVersion("nucler")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mnase_bias_correction.csv versions.yml
    """
}

workflow BIOC_NUCLER_MNASE_BIAS_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ nucleosomal_coverage.RData, control_coverage.RData ] ]

    main:
    BIOC_NUCLER_MNASE_BIAS_CORRECTION(ch_input)

    emit:
    tables   = BIOC_NUCLER_MNASE_BIAS_CORRECTION.out.tables
    plots    = BIOC_NUCLER_MNASE_BIAS_CORRECTION.out.plots
    objects  = BIOC_NUCLER_MNASE_BIAS_CORRECTION.out.objects
    versions = BIOC_NUCLER_MNASE_BIAS_CORRECTION.out.versions
}
