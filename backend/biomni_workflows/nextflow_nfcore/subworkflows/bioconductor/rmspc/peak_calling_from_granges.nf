#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rmspc — peak_calling_from_granges
// Run MSPC peak calling using GRanges objects loaded in R.
// Input: GR1, GR2
// Container: quay.io/biocontainers/bioconductor-rmspc:1.16.0--r45hdfd78af_0
// R packages: GenomicRanges, rmspc, rtracklayer
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RMSPC_PEAK_CALLING_FROM_GRANGES {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-rmspc:1.16.0--r45hdfd78af_0"

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
    .bm_deps <- c("GenomicRanges", "rmspc", "rtracklayer")
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
    library(rmspc)
    library(GenomicRanges)
    library(rtracklayer)
    
    # Helper function to robustly load GRanges from GR1/GR2 (either RDS or BED format)
    load_granges <- function(filepath) {
      if (!file.exists(filepath)) {
        if (file.exists(paste0(filepath, ".rds"))) {
          filepath <- paste0(filepath, ".rds")
        } else if (file.exists(paste0(filepath, ".bed"))) {
          filepath <- paste0(filepath, ".bed")
        } else {
          stop(paste("Required input file not found:", filepath))
        }
      }
      
      # Try reading as RDS first
      obj <- tryCatch({
        readRDS(filepath)
      }, error = function(e) {
        NULL
      })
      
      if (inherits(obj, "GRanges")) {
        message(paste("Successfully loaded GRanges from RDS:", filepath))
        return(obj)
      }
      
      # Try importing as BED
      obj_bed <- tryCatch({
        rtracklayer::import(con = filepath, format = "bed")
      }, error = function(e) {
        stop(paste("Failed to read", filepath, "as RDS or BED file."))
      })
      
      message(paste("Successfully imported GRanges from BED:", filepath))
      return(obj_bed)
    }
    
    # --- Import BED files or RDS files as GRanges objects ---
    GR1 <- load_granges("GR1")
    GR2 <- load_granges("GR2")
    
    # --- Combine GRanges objects into a GRangesList ---
    GR <- GenomicRanges::GRangesList("GR1" = GR1, "GR2" = GR2)
    
    # --- Run the mspc function with the GRangesList and threshold ---
    results <- mspc(
        input = GR, replicateType = "Biological",
        stringencyThreshold = 1e-8, weakThreshold = 1e-4,
        gamma =  1e-8, GRanges = TRUE, keep = FALSE,
        multipleIntersections = "Highest",
        c = 2,alpha = 0.05)
    
    # --- Retrieve status and GRanges output objects ---
    status <- results\$status
    gr_objects <- results\$GRangesObjects
    
    # Save the full results object as RDS
    saveRDS(results, "mspc_results.rds")
    
    # Save execution summary to a text file
    sink("mspc_summary.txt")
    cat("MSPC Execution Status:", status, "\n\n")
    cat("Summary of generated GRanges objects:\n")
    for (name in names(gr_objects)) {
      cat(sprintf("- %s: %d ranges\n", name, length(gr_objects[[name]])))
    }
    sink()
    
    # Export Consensus Peaks if they exist
    if (!is.null(gr_objects\$ConsensusPeaks)) {
      # Export as BED
      rtracklayer::export(gr_objects\$ConsensusPeaks, "consensus_peaks.bed", format = "bed")
      
      # Export as CSV
      consensus_df <- as.data.frame(gr_objects\$ConsensusPeaks)
      write.csv(consensus_df, "consensus_peaks.csv", row.names = FALSE)
    }
    
    # Export all generated GRanges objects to CSVs for downstream analysis
    for (name in names(gr_objects)) {
      # Replace slashes in names to avoid directory path issues in filenames
      safe_name <- gsub("/", "_", name)
      df <- as.data.frame(gr_objects[[name]])
      write.csv(df, paste0("mspc_", safe_name, ".csv"), row.names = FALSE)
    }
    
    message("MSPC pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_RMSPC_PEAK_CALLING_FROM_GRANGES":',
        paste0('        rmspc: ', as.character(packageVersion("rmspc")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_peak_calling_from_granges.csv versions.yml
    """
}

workflow BIOC_RMSPC_PEAK_CALLING_FROM_GRANGES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ GR1, GR2 ] ]

    main:
    BIOC_RMSPC_PEAK_CALLING_FROM_GRANGES(ch_input)

    emit:
    tables   = BIOC_RMSPC_PEAK_CALLING_FROM_GRANGES.out.tables
    plots    = BIOC_RMSPC_PEAK_CALLING_FROM_GRANGES.out.plots
    objects  = BIOC_RMSPC_PEAK_CALLING_FROM_GRANGES.out.objects
    versions = BIOC_RMSPC_PEAK_CALLING_FROM_GRANGES.out.versions
}
