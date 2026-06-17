#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: consensusSeekeR — nucleosome_position_consensus
// Compare nucleosome positioning results from different software tools to find consensus nucleosome positions.
// Input: NOrMAL_nucleosome_positions, NOrMAL_nucleosome_ranges, PING_nucleosome_positions, PING_nucleosome_ranges, NucPosSimulator_nucleosome_positions, NucPosSimulator_nucleosome_ranges, chrList
// Container: quay.io/biocontainers/bioconductor-consensusseeker:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, consensusSeekeR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load nucleosome position and range datasets
//  * 2. [Input & Preparation] Assign software names as row names to the GRanges objects
//  * 3. [Input & Preparation] Run findConsensusPeakRegions with custom parameters
//  * 4. [Input & Preparation] Write named output files for the results

nextflow.enable.dsl = 2

process BIOC_CONSENSUSSEEKER_NUCLEOSOME_POSITION_CONSENSUS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("consensusSeekeR", "GenomicRanges")
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
    library(consensusSeekeR)
    library(GenomicRanges)
    
    # Define input file paths (expecting RDS files in the working directory)
    normal_pos_file <- "NOrMAL_nucleosome_positions.rds"
    normal_range_file <- "NOrMAL_nucleosome_ranges.rds"
    ping_pos_file <- "PING_nucleosome_positions.rds"
    ping_range_file <- "PING_nucleosome_ranges.rds"
    nucpos_pos_file <- "NucPosSimulator_nucleosome_positions.rds"
    nucpos_range_file <- "NucPosSimulator_nucleosome_ranges.rds"
    chr_list_file <- "chrList.rds"
    
    # Verify existence of all required input files
    required_files <- c(normal_pos_file, normal_range_file, ping_pos_file, ping_range_file,
                        nucpos_pos_file, nucpos_range_file, chr_list_file)
    
    missing_files <- required_files[!file.exists(required_files)]
    if (length(missing_files) > 0) {
      stop(paste("Missing required input files in the working directory:", paste(missing_files, collapse = ", ")))
    }
    
    # --- Load nucleosome position and range datasets ---
    message("Loading input datasets...")
    NOrMAL_nucleosome_positions <- readRDS(normal_pos_file)
    NOrMAL_nucleosome_ranges <- readRDS(normal_range_file)
    PING_nucleosome_positions <- readRDS(ping_pos_file)
    PING_nucleosome_ranges <- readRDS(ping_range_file)
    NucPosSimulator_nucleosome_positions <- readRDS(nucpos_pos_file)
    NucPosSimulator_nucleosome_ranges <- readRDS(nucpos_range_file)
    chrList <- readRDS(chr_list_file)
    
    # --- Assign software names as row names to the GRanges objects ---
    message("Assigning software names to GRanges objects...")
    names(NOrMAL_nucleosome_positions) <- rep("NOrMAL", length(NOrMAL_nucleosome_positions))
    names(NOrMAL_nucleosome_ranges) <- rep("NOrMAL", length(NOrMAL_nucleosome_ranges))
    
    names(PING_nucleosome_positions) <- rep("PING", length(PING_nucleosome_positions))
    names(PING_nucleosome_ranges) <- rep("PING", length(PING_nucleosome_ranges))
    
    names(NucPosSimulator_nucleosome_positions) <- rep("NucPosSimulator", 
                                    length(NucPosSimulator_nucleosome_positions))
    names(NucPosSimulator_nucleosome_ranges) <- rep("NucPosSimulator", 
                                    length(NucPosSimulator_nucleosome_ranges))
    
    # --- Run findConsensusPeakRegions with custom parameters ---
    message("Finding consensus peak regions...")
    results <- findConsensusPeakRegions(
                narrowPeaks = c(NOrMAL_nucleosome_ranges, PING_nucleosome_ranges,
                                    NucPosSimulator_nucleosome_ranges),
                peaks = c(NOrMAL_nucleosome_positions, PING_nucleosome_positions,
                                    NucPosSimulator_nucleosome_positions),
                chrInfo = chrList,
                extendingSize = 25,
                expandToFitPeakRegion = TRUE,
                shrinkToFitPeakRegion = TRUE,
                minNbrExp = 2,
                nbrThreads = 1)
    
    # Print the call and the first few consensus regions to stdout
    message("\n--- Analysis Call ---")
    print(results\$call)
    
    message("\n--- First 3 Consensus Regions ---")
    print(head(results\$consensusRanges, n = 3))
    
    # --- Write named output files for the results ---
    message("\nSaving results...")
    
    # Save the complete results list object
    saveRDS(results, file = "consensus_results.rds")
    
    # Save the consensus ranges as a GRanges RDS object
    saveRDS(results\$consensusRanges, file = "consensus_ranges.rds")
    
    # Export the consensus ranges as a CSV table for downstream analysis
    consensus_df <- as.data.frame(results\$consensusRanges)
    write.csv(consensus_df, file = "consensus_ranges.csv", row.names = FALSE)
    
    message("Pipeline completed successfully. Outputs saved to 'consensus_results.rds', 'consensus_ranges.rds', and 'consensus_ranges.csv'.")

    writeLines(c(
        '"BIOC_CONSENSUSSEEKER_NUCLEOSOME_POSITION_CONSENSUS":',
        paste0('    consensusSeekeR: ', as.character(packageVersion('consensusSeekeR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nucleosome_position_consensus.csv versions.yml
    """
}

workflow BIOC_CONSENSUSSEEKER_NUCLEOSOME_POSITION_CONSENSUS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ NOrMAL_nucleosome_positions, NOrMAL_nucleosome_ranges, PING_nucleosome_positions, PING_nucleosome_ranges, NucPosSimulator_nucleosome_positions, NucPosSimulator_nucleosome_ranges, chrList ] ]

    main:
    BIOC_CONSENSUSSEEKER_NUCLEOSOME_POSITION_CONSENSUS(ch_input)

    emit:
    tables   = BIOC_CONSENSUSSEEKER_NUCLEOSOME_POSITION_CONSENSUS.out.tables
    plots    = BIOC_CONSENSUSSEEKER_NUCLEOSOME_POSITION_CONSENSUS.out.plots
    objects  = BIOC_CONSENSUSSEEKER_NUCLEOSOME_POSITION_CONSENSUS.out.objects
    versions = BIOC_CONSENSUSSEEKER_NUCLEOSOME_POSITION_CONSENSUS.out.versions
}
