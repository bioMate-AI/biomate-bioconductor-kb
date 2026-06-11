#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: consensusSeekeR — chip_seq_consensus_from_narrowpeak
// Identify consensus peak regions from multiple ChIP-Seq replicates or experiments starting from NarrowPeak files.
// Input: file_narrowPeak, chrList
// Container: quay.io/biocontainers/bioconductor-consensusseeker:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, consensusSeekeR, rtracklayer
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load Input Files
//  * 2. [Input & Preparation] Write Outputs

nextflow.enable.dsl = 2

process BIOC_CONSENSUSSEEKER_CHIP_SEQ_CONSENSUS_FROM_NARROWPEAK {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
            
            # Load required libraries
            library(consensusSeekeR)
            library(GenomicRanges)
            library(rtracklayer)
            
            # -----------------------------------------------------------------------------
            # --- Load Input Files ---
            # -----------------------------------------------------------------------------
            
            # Locate narrowPeak files in the working directory
            files <- list.files(pattern = "\\\\.narrowPeak\$")
            if (file.exists("file_narrowPeak") && !("file_narrowPeak" %in% files)) {
              files <- c("file_narrowPeak", files)
            }
            
            if (length(files) == 0) {
              stop("Error: No narrowPeak files found in the working directory.")
            }
            
            # Locate and load the Seqinfo object (chrList)
            if (file.exists("chrList.rds")) {
              chrList <- readRDS("chrList.rds")
            } else if (file.exists("chrList")) {
              chrList <- readRDS("chrList")
            } else {
              stop("Error: chrList (Seqinfo object) file not found in the working directory.")
            }
            
            # -----------------------------------------------------------------------------
            # Stage 2 & 3: Process Replicates, Assign Experiment Names & Unique Feature Names
            # -----------------------------------------------------------------------------
            
            narrowPeaks_list <- list()
            peaks_list <- list()
            
            for (i in seq_along(files)) {
              input_file <- files[i]
              
              # Read the narrowPeak file to extract both regions and peak positions
              result <- readNarrowPeakFile(input_file, extractRegions = TRUE, extractPeaks = TRUE)
              
              narrowPeak_all <- result\$narrowPeak
              peak_all <- result\$peak
              
              # Filter and align seqinfo to match the user-provided chrList
              seqlevels(narrowPeak_all, pruning.mode = "coarse") <- intersect(seqlevels(narrowPeak_all), seqlevels(chrList))
              seqlevels(narrowPeak_all) <- seqlevels(chrList)
              seqinfo(narrowPeak_all) <- chrList
              
              seqlevels(peak_all, pruning.mode = "coarse") <- intersect(seqlevels(peak_all), seqlevels(chrList))
              seqlevels(peak_all) <- seqlevels(chrList)
              seqinfo(peak_all) <- chrList
              
              # Trim ranges to ensure they do not exceed chromosome boundaries
              narrowPeak_all <- GenomicRanges::trim(narrowPeak_all)
              peak_all <- GenomicRanges::trim(peak_all)
              
              # Assign experiment names as row names to the GRanges objects
              exp_name <- paste0("rep", sprintf("%02d", i))
              names(narrowPeak_all) <- rep(exp_name, length(narrowPeak_all))
              names(peak_all)       <- rep(exp_name, length(peak_all))
              
              # Assign unique feature names to the name metadata column to pair them
              narrowPeak_all\$name <- paste0("peak_", exp_name, "_", seq_along(narrowPeak_all))
              peak_all\$name       <- paste0("peak_", exp_name, "_", seq_along(peak_all))
              
              narrowPeaks_list[[i]] <- narrowPeak_all
              peaks_list[[i]] <- peak_all
            }
            
            # Combine all replicates into single GRanges objects
            all_narrowPeaks <- do.call(c, narrowPeaks_list)
            all_peaks <- do.call(c, peaks_list)
            
            # -----------------------------------------------------------------------------
            # Stage 4 & 5: Run findConsensusPeakRegions
            # -----------------------------------------------------------------------------
            
            results <- findConsensusPeakRegions(
                        narrowPeaks = all_narrowPeaks,
                        peaks = all_peaks,
                        chrInfo = chrList,
                        extendingSize = 100,
                        expandToFitPeakRegion = TRUE,
                        shrinkToFitPeakRegion = TRUE,
                        minNbrExp = min(2, length(files)),
                        nbrThreads = 1)
            
            # Print the call and the first few consensus regions to console
            print(results\$call)
            print(head(results\$consensusRanges, n = 3))
            
            # -----------------------------------------------------------------------------
            # --- Write Outputs ---
            # -----------------------------------------------------------------------------
            
            # Save the consensus ranges as an RDS object
            saveRDS(results\$consensusRanges, file = "consensus_regions.rds")
            
            # Save the consensus ranges as a CSV table
            consensus_df <- as.data.frame(results\$consensusRanges)
            write.csv(consensus_df, file = "consensus_regions.csv", row.names = FALSE)
            
            # Save a summary text file containing the call and basic statistics
            summary_conn <- file("consensus_summary.txt", "w")
            writeLines("Consensus Peak Regions Analysis Summary", summary_conn)
            writeLines("========================================", summary_conn)
            writeLines(paste("Call:", deparse(results\$call)), summary_conn)
            writeLines(paste("Total consensus regions identified:", length(results\$consensusRanges)), summary_conn)
            close(summary_conn)

    writeLines(c(
        '"BIOC_CONSENSUSSEEKER_CHIP_SEQ_CONSENSUS_FROM_NARROWPEAK":',
        paste0('    consensusSeekeR: ', as.character(packageVersion('consensusSeekeR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chip_seq_consensus_from_narrowpeak.csv versions.yml
    """
}

workflow BIOC_CONSENSUSSEEKER_CHIP_SEQ_CONSENSUS_FROM_NARROWPEAK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ file_narrowPeak, chrList ] ]

    main:
    BIOC_CONSENSUSSEEKER_CHIP_SEQ_CONSENSUS_FROM_NARROWPEAK(ch_input)

    emit:
    tables   = BIOC_CONSENSUSSEEKER_CHIP_SEQ_CONSENSUS_FROM_NARROWPEAK.out.tables
    plots    = BIOC_CONSENSUSSEEKER_CHIP_SEQ_CONSENSUS_FROM_NARROWPEAK.out.plots
    objects  = BIOC_CONSENSUSSEEKER_CHIP_SEQ_CONSENSUS_FROM_NARROWPEAK.out.objects
    versions = BIOC_CONSENSUSSEEKER_CHIP_SEQ_CONSENSUS_FROM_NARROWPEAK.out.versions
}
