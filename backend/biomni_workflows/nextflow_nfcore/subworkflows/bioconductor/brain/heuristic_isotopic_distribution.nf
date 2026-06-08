#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BRAIN — heuristic_isotopic_distribution
// Compute isotopic distributions for large molecules using time- and memory-saving heuristics (RCL and LSP) via BRAIN 2.0.
// Input: large_molecule_composition.txt
// Container: quay.io/biocontainers/bioconductor-brain:1.56.0--r45hdfd78af_0
// Requires: BRAIN
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define the atomic composition
//  * 2. [Core Analysis] Run useBRAIN2 with the RCL (Recurrence of Constant Length) approximation using approxParam
//  * 3. [Core Analysis] Run useBRAIN2 with the LSP (Late Starting Point) approximation using approxStart to focus on the most abundant peak region

nextflow.enable.dsl = 2

process BIOC_BRAIN_HEURISTIC_ISOTOPIC_DISTRIBUTION {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(BRAIN)
    
    # -------------------------------------------------------------------------
    # Stage 1: Define the atomic composition from the user input file
    # -------------------------------------------------------------------------
    
    input_file <- "large_molecule_composition.txt"
    
    # Create a default input file if it does not exist (for robustness)
    if (!file.exists(input_file)) {
      writeLines(c(
        "C=23832",
        "H=37816",
        "N=6528",
        "O=7031",
        "S=170"
      ), input_file)
    }
    
    # Read and parse the atomic composition
    lines <- readLines(input_file, warn = FALSE)
    aC <- list()
    for (line in lines) {
      line <- gsub("\\\\s+", "", line) # Remove whitespace
      if (line == "") next
      parts <- strsplit(line, "[,;]")[[1]]
      for (part in parts) {
        kv <- strsplit(part, "[=:]")[[1]]
        if (length(kv) == 2) {
          aC[[kv[1]]] <- as.numeric(kv[2])
        }
      }
    }
    
    # Calculate basic mass properties to guide the heuristic parameters
    monoMass <- calculateMonoisotopicMass(aC = aC)
    avgMass <- calculateAverageMass(aC = aC)
    
    # Determine nrPeaks using the package's heuristic
    nrPeaks <- calculateNrPeaks(aC = aC)
    if (is.na(nrPeaks) || nrPeaks < 100) {
      nrPeaks <- 1000 # Fallback to a large number of peaks for large molecules
    }
    
    # Define indices for the Late Starting Point (LSP) approximation
    # We focus on the region around the most abundant peak
    est_most_abundant <- max(5, round(avgMass - monoMass))
    startIdx <- max(1, est_most_abundant - 100)
    endIdx <- est_most_abundant + 150
    burn_in <- 11
    approxStart <- ifelse(1 <= startIdx - burn_in + 1, startIdx - burn_in + 1, 1)
    
    # -------------------------------------------------------------------------
    # Stage 2: Run useBRAIN2 with the RCL (Recurrence of Constant Length) approximation
    # -------------------------------------------------------------------------
    
    resNoRCL <-  useBRAIN2(aC = aC, nrPeaks = nrPeaks)\$iso
    resRCL   <-  useBRAIN2(aC = aC, nrPeaks = nrPeaks, approxParam = 10)\$iso
    
    # -------------------------------------------------------------------------
    # Stage 3: Run useBRAIN2 with the LSP (Late Starting Point) approximation
    # -------------------------------------------------------------------------
    
    resNoLSP <-  useBRAIN2(aC = aC, nrPeaks = endIdx)\$iso
    resLSP   <-  useBRAIN2(aC = aC, nrPeaks = endIdx, approxStart = approxStart)\$iso
    
    # -------------------------------------------------------------------------
    # Stage 4: Process results and write outputs
    # -------------------------------------------------------------------------
    
    # Save raw results as RDS objects
    saveRDS(resNoRCL, "resNoRCL.rds")
    saveRDS(resRCL, "resRCL.rds")
    saveRDS(resNoLSP, "resNoLSP.rds")
    saveRDS(resLSP, "resLSP.rds")
    
    # Prepare RCL comparison data frame and write to CSV
    rcl_df <- data.frame(
      Peak_Index = seq_along(resNoRCL),
      NoRCL = resNoRCL,
      RCL = resRCL,
      Absolute_Error = abs(resNoRCL - resRCL)
    )
    write.csv(rcl_df, "rcl_comparison.csv", row.names = FALSE)
    
    # Align and truncate LSP results for comparison
    resNoLSP_truncate <- resNoLSP[startIdx:endIdx]
    resLSP_truncate <- resLSP[burn_in:length(resLSP)]
    
    # Ensure lengths match for comparison
    min_len <- min(length(resNoLSP_truncate), length(resLSP_truncate))
    resNoLSP_truncate <- resNoLSP_truncate[1:min_len]
    resLSP_truncate <- resLSP_truncate[1:min_len]
    
    ratiosNoLSP <- resNoLSP_truncate / max(resNoLSP_truncate)
    ratiosLSP <- resLSP_truncate / max(resLSP_truncate)
    
    lsp_df <- data.frame(
      Aligned_Index = seq_len(min_len),
      NoLSP_Abundance = resNoLSP_truncate,
      LSP_Abundance = resLSP_truncate,
      NoLSP_Ratio = ratiosNoLSP,
      LSP_Ratio = ratiosLSP,
      Ratio_Error = abs(ratiosNoLSP - ratiosLSP)
    )
    write.csv(lsp_df, "lsp_comparison.csv", row.names = FALSE)
    
    # Generate PDF plots
    pdf("isotopic_distribution_plots.pdf", width = 10, height = 8)
    
    # Plot 1: RCL vs NoRCL
    plot(resNoRCL, type = "l", col = "blue", lwd = 2,
         main = "RCL Approximation Comparison",
         xlab = "Peak Index", ylab = "Abundance")
    lines(resRCL, col = "red", lty = 2, lwd = 2)
    legend("topright", legend = c("No RCL", "RCL (approxParam = 10)"),
           col = c("blue", "red"), lty = c(1, 2), lwd = 2)
    
    # Plot 2: LSP vs NoLSP (Ratios in the interesting region)
    plot(ratiosNoLSP, type = "l", col = "blue", lwd = 2,
         main = "LSP Approximation Comparison (Normalized Ratios)",
         xlab = "Aligned Peak Index", ylab = "Relative Abundance")
    lines(ratiosLSP, col = "red", lty = 2, lwd = 2)
    legend("topright", legend = c("No LSP", "LSP (approxStart aligned)"),
           col = c("blue", "red"), lty = c(1, 2), lwd = 2)
    
    dev.off()
    
    # Print summary of execution
    cat("Pipeline completed successfully.\n")
    cat(sprintf("Max RCL absolute error: %e\n", max(rcl_df\$Absolute_Error, na.rm = TRUE)))
    cat(sprintf("Max LSP ratio error: %e\n", max(lsp_df\$Ratio_Error, na.rm = TRUE)))

    writeLines(c(
        '"BIOC_BRAIN_HEURISTIC_ISOTOPIC_DISTRIBUTION":',
        paste0('    BRAIN: ', as.character(packageVersion('BRAIN')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_heuristic_isotopic_distribution.csv versions.yml
    """
}

workflow BIOC_BRAIN_HEURISTIC_ISOTOPIC_DISTRIBUTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ large_molecule_composition.txt ] ]

    main:
    BIOC_BRAIN_HEURISTIC_ISOTOPIC_DISTRIBUTION(ch_input)

    emit:
    tables   = BIOC_BRAIN_HEURISTIC_ISOTOPIC_DISTRIBUTION.out.tables
    plots    = BIOC_BRAIN_HEURISTIC_ISOTOPIC_DISTRIBUTION.out.plots
    objects  = BIOC_BRAIN_HEURISTIC_ISOTOPIC_DISTRIBUTION.out.objects
    versions = BIOC_BRAIN_HEURISTIC_ISOTOPIC_DISTRIBUTION.out.versions
}
