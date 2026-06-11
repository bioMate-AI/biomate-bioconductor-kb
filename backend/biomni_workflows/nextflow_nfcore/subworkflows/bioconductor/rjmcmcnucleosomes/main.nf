#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RJMCMCNucleosomes — segmented_nucleosome_positioning
// Segment a genomic region, run RJMCMC on individual segments, merge the results, post-process to reduce false positives, and visualize predicted nucleosomes.
// Input: sample$dataIP
// Container: quay.io/biocontainers/bioconductor-rjmcmcnucleosomes:1.34.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, RJMCMCNucleosomes
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Segment the analyzed region into candidate regions using segmentation
//  * 2. [Core Analysis] Run RJMCMC on individual segments using rjmcmc
//  * 3. [Core Analysis] Merge predicted nucleosomes from all segments using mergeAllRDSFilesFromDirectory
//  * 4. [Core Analysis] Post-process predictions on the merged region using postTreatment
//  * 5. [Visualization & Output] Visualize predicted nucleosomes using plotNucleosomes

nextflow.enable.dsl = 2

process BIOC_RJMCMCNUCLEOSOMES_SEGMENTED_NUCLEOSOME_POSITIONING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
        
    library(RJMCMCNucleosomes)
    library(GenomicRanges)
    
    # ==========================================
    # 1. Read User Input
    # ==========================================
    # The pipeline reads the user-provided sample\$dataIP from the working directory.
    # We support both CSV and RDS formats for maximum compatibility.
    if (file.exists("sample_dataIP.csv")) {
      sample_dataIP <- read.csv("sample_dataIP.csv", stringsAsFactors = FALSE)
    } else if (file.exists("sample_dataIP.rds")) {
      sample_dataIP <- readRDS("sample_dataIP.rds")
    } else {
      stop("Required input file 'sample_dataIP.csv' or 'sample_dataIP.rds' not found in the working directory.")
    }
    
    # Reconstruct the sample list structure expected by the vignette
    sample <- list(dataIP = sample_dataIP)
    
    # Optional: Read true nucleosome positions if available for the "Sample" track in the plot.
    # If not available, we default to empty vectors so the pipeline runs without errors.
    sample\$wp <- list(nucleopos = numeric(0))
    sample\$fuz <- list(nucleopos = numeric(0))
    
    if (file.exists("sample_wp_nucleopos.csv")) {
      sample\$wp\$nucleopos <- read.csv("sample_wp_nucleopos.csv")\$nucleopos
    }
    if (file.exists("sample_fuz_nucleopos.csv")) {
      sample\$fuz\$nucleopos <- read.csv("sample_fuz_nucleopos.csv")\$nucleopos
    }
    
    # ==========================================
    # 2. Segment Analyzed Region
    # ==========================================
    # Transform sample dataset into GRanges object
    sampleGRanges <- GRanges(seqnames = sample\$dataIP\$chr, 
                            ranges = IRanges(start = sample\$dataIP\$start, 
                                             end = sample\$dataIP\$end), 
                            strand = sample\$dataIP\$strand)
    
    # Segment sample into candidate regions
    sampleSegmented <- segmentation(reads = sampleGRanges, zeta = 147, 
                                    delta = 40, maxLength = 1000)
    
    # Number of segments created
    message("Number of segments created: ", length(sampleSegmented))
    
    # ==========================================
    # 3. Run RJMCMC on Individual Segments
    # ==========================================
    # Create a directory to store the RDS results for each segment
    output_dir <- "segment_results"
    if (dir.exists(output_dir)) {
      unlink(output_dir, recursive = TRUE)
    }
    dir.create(output_dir, showWarnings = FALSE)
    
    # Run RJMCMC analysis on each segment and save to RDS
    message("Running RJMCMC on individual segments...")
    for (i in seq_along(sampleSegmented)) {
      segment <- sampleSegmented[[i]]
      
      # Run RJMCMC analysis using the documented parameters
      resultSegment <- rjmcmc(reads = segment, nbrIterations = 100000, 
                              lambda = 3, kMax = 30,
                              minInterval = 100, maxInterval = 200, 
                              minReads = 5, vSeed = 1921)
      
      # Save the segment result to an RDS file
      segment_file <- file.path(output_dir, sprintf("segment_%02d.rds", i))
      saveRDS(resultSegment, file = segment_file)
    }
    
    # ==========================================
    # 4. Merge Predicted Nucleosomes
    # ==========================================
    # Merging predicted nucleosomes from all segments
    resultsAllMerged <- mergeAllRDSFilesFromDirectory(output_dir)
    
    # Save the merged results
    saveRDS(resultsAllMerged, "results_all_merged.rds")
    
    # ==========================================
    # 5. Post-Process Predictions
    # ==========================================
    # Split reads from the initial sample data into forward and reverse subsets
    reads <- GRanges(sample\$dataIP)
    
    # Number of nucleosomes before the post-treatment
    message("Number of nucleosomes before post-treatment: ", resultsAllMerged\$k)
    
    # Use the post-treatment function
    resultsPostTreatment <- postTreatment(reads = reads,
                                          resultRJMCMC = resultsAllMerged,
                                          extendingSize = 15,
                                          chrLength = max(start(reads), end(reads)) + 1000)
    
    # Number of nucleosomes after the post-treatment
    message("Number of nucleosomes after post-treatment: ", length(resultsPostTreatment))
    
    # Save post-treated nucleosomes
    saveRDS(resultsPostTreatment, "results_post_treatment.rds")
    df_post_treatment <- as.data.frame(resultsPostTreatment)
    write.csv(df_post_treatment, "predicted_nucleosomes.csv", row.names = FALSE)
    
    # ==========================================
    # 6. Visualization
    # ==========================================
    # Extract reads to create a GRanges
    reads <- GRanges(sample\$dataIP)
    
    # Merge predictions from before post-treatment and after post-treatment in a list
    true_positions <- c(sample\$wp\$nucleopos, sample\$fuz\$nucleopos)
    
    if (length(true_positions) > 0) {
      chr_name <- as.character(sample\$dataIP\$chr[1])
      resultsBeforeAndAfter <- GRangesList(
        Sample = GRanges(
          rep(chr_name, length(true_positions)), 
          ranges = IRanges(start = true_positions,
                           end = true_positions), 
          strand = rep("*", length(true_positions))
        ),
        BeforePostTreatment = resultsAllMerged\$mu,
        AfterPostTreatment = resultsPostTreatment
      )
      plot_names <- c("Sample", "RJMCMC", "After Post-Treatment")
    } else {
      resultsBeforeAndAfter <- GRangesList(
        BeforePostTreatment = resultsAllMerged\$mu,
        AfterPostTreatment = resultsPostTreatment
      )
      plot_names <- c("RJMCMC", "After Post-Treatment")
    }
    
    # Create and save the plot
    pdf("nucleosome_positions_plot.pdf", width = 10, height = 7)
    plotNucleosomes(nucleosomePositions = resultsBeforeAndAfter, reads = reads, 
                    names = plot_names)
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to 'predicted_nucleosomes.csv' and 'nucleosome_positions_plot.pdf'.")

    writeLines(c(
        '"BIOC_RJMCMCNUCLEOSOMES_SEGMENTED_NUCLEOSOME_POSITIONING":',
        paste0('    RJMCMCNucleosomes: ', as.character(packageVersion('RJMCMCNucleosomes')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_segmented_nucleosome_positioning.csv versions.yml
    """
}

workflow BIOC_RJMCMCNUCLEOSOMES_SEGMENTED_NUCLEOSOME_POSITIONING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample$dataIP ] ]

    main:
    BIOC_RJMCMCNUCLEOSOMES_SEGMENTED_NUCLEOSOME_POSITIONING(ch_input)

    emit:
    tables   = BIOC_RJMCMCNUCLEOSOMES_SEGMENTED_NUCLEOSOME_POSITIONING.out.tables
    plots    = BIOC_RJMCMCNUCLEOSOMES_SEGMENTED_NUCLEOSOME_POSITIONING.out.plots
    objects  = BIOC_RJMCMCNUCLEOSOMES_SEGMENTED_NUCLEOSOME_POSITIONING.out.objects
    versions = BIOC_RJMCMCNUCLEOSOMES_SEGMENTED_NUCLEOSOME_POSITIONING.out.versions
}
