#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: HERON — smoothed_probe_level_analysis
// Reduce high-variability of peptide array data by smoothing across consecutive probes before calculating p-values and making calls.
// Input: seq_ds_qn, probe_meta
// Container: quay.io/biocontainers/bioconductor-heron:1.8.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: HERON, SummarizedExperiment
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert sequence dataset to probe dataset
//  * 2. [Core Analysis] Smooth probe-level data
//  * 3. [Core Analysis] Calculate probe-level p-values on the smoothed dataset
//  * 4. [Core Analysis] Make probe-level calls and get K-of-N statistics

nextflow.enable.dsl = 2

process BIOC_HERON_SMOOTHED_PROBE_LEVEL_ANALYSIS {
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
    .bm_deps <- c("HERON", "SummarizedExperiment")
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
    suppressPackageStartupMessages({
      library(HERON)
      library(SummarizedExperiment)
    })
    
    # Helper function to locate and read the input files robustly
    find_and_read_input <- function(var_name) {
      # Check for direct file, .rds, or .csv extensions
      extensions <- c("", ".rds", ".csv")
      file_path <- NULL
      
      for (ext in extensions) {
        candidate <- paste0(var_name, ext)
        if (file.exists(candidate)) {
          file_path <- candidate
          break
        }
      }
      
      if (is.null(file_path)) {
        stop(sprintf("Required input file for '%s' not found in the working directory.", var_name))
      }
      
      message(sprintf("Reading input '%s' from file: %s", var_name, file_path))
      
      if (grepl("\\\\.csv\$", file_path)) {
        return(read.csv(file_path, stringsAsFactors = FALSE))
      } else {
        return(readRDS(file_path))
      }
    }
    
    # 1. Load User Inputs
    seq_ds_qn <- find_and_read_input("seq_ds_qn")
    probe_meta <- find_and_read_input("probe_meta")
    
    # 2. Execute the Smoothed Probe-Level Analysis Workflow
    message("Converting sequence dataset to probe dataset...")
    probe_ds_qn <- convertSequenceDSToProbeDS(seq_ds_qn, probe_meta )
    
    message("Smoothing probe-level data...")
    smooth_ds <- smoothProbeDS(probe_ds_qn)
    
    message("Calculating probe-level p-values on the smoothed dataset...")
    probe_sm_pval <- calcCombPValues(smooth_ds)
    
    message("Making probe-level calls...")
    probe_sm_calls <- makeProbeCalls(probe_sm_pval)
    
    message("Calculating K-of-N statistics...")
    probe_sm_k_of_n <- getKofN(probe_sm_calls)
    
    # 3. Save Outputs
    message("Writing output files...")
    
    # Save RDS objects for downstream R analysis
    saveRDS(smooth_ds, "smooth_ds.rds")
    saveRDS(probe_sm_pval, "probe_sm_pval.rds")
    saveRDS(probe_sm_calls, "probe_sm_calls.rds")
    
    # Save CSV tables for easy inspection
    write.csv(probe_sm_k_of_n, "probe_sm_k_of_n.csv", row.names = TRUE)
    
    # Extract and save the calls matrix
    if ("calls" %in% assayNames(probe_sm_calls)) {
      calls_matrix <- assay(probe_sm_calls, "calls")
      write.csv(calls_matrix, "probe_sm_calls_matrix.csv", row.names = TRUE)
    }
    
    # Extract and save the adjusted p-values matrix
    if ("padj" %in% assayNames(probe_sm_pval)) {
      padj_matrix <- assay(probe_sm_pval, "padj")
      write.csv(padj_matrix, "probe_sm_padj_matrix.csv", row.names = TRUE)
    }
    
    # Optional: Generate a diagnostic plot of the smoothed vs unsmoothed intensities for a sample
    tryCatch({
      pdf("probe_smoothing_diagnostic.pdf", width = 8, height = 6)
      # Plot first 100 probes of the first sample as a comparison
      unsmoothed_vals <- assay(probe_ds_qn)[1:min(100, nrow(probe_ds_qn)), 1]
      smoothed_vals <- assay(smooth_ds)[1:min(100, nrow(smooth_ds)), 1]
      
      plot(unsmoothed_vals, type = "l", col = "red", lty = 2,
           main = "Probe Smoothing Comparison (First Sample, First 100 Probes)",
           xlab = "Probe Index", ylab = "Intensity")
      lines(smoothed_vals, col = "blue", lty = 1, lwd = 2)
      legend("topright", legend = c("Unsmoothed", "Smoothed"), 
             col = c("red", "blue"), lty = c(2, 1), lwd = c(1, 2))
      dev.off()
      message("Diagnostic plot saved to 'probe_smoothing_diagnostic.pdf'")
    }, error = function(e) {
      warning("Could not generate diagnostic plot: ", e\$message)
    })
    
    message("Workflow completed successfully.")

    writeLines(c(
        '"BIOC_HERON_SMOOTHED_PROBE_LEVEL_ANALYSIS":',
        paste0('    HERON: ', as.character(packageVersion('HERON')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_smoothed_probe_level_analysis.csv versions.yml
    """
}

workflow BIOC_HERON_SMOOTHED_PROBE_LEVEL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ seq_ds_qn, probe_meta ] ]

    main:
    BIOC_HERON_SMOOTHED_PROBE_LEVEL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_HERON_SMOOTHED_PROBE_LEVEL_ANALYSIS.out.tables
    plots    = BIOC_HERON_SMOOTHED_PROBE_LEVEL_ANALYSIS.out.plots
    objects  = BIOC_HERON_SMOOTHED_PROBE_LEVEL_ANALYSIS.out.objects
    versions = BIOC_HERON_SMOOTHED_PROBE_LEVEL_ANALYSIS.out.versions
}
