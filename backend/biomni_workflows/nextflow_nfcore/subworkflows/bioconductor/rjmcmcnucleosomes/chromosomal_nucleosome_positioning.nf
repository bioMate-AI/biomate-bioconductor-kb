#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RJMCMCNucleosomes — chromosomal_nucleosome_positioning
// Run the entire nucleosome positioning pipeline (segmentation, RJMCMC, merging, and post-processing) on a single chromosome in one step.
// Input: syntheticNucleosomeReads$dataIP
// Container: quay.io/biocontainers/bioconductor-rjmcmcnucleosomes:1.34.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, RJMCMCNucleosomes
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run rjmcmcCHR on the chromosome GRanges object to automatically segment, run RJMCMC, merge, and post-process

nextflow.enable.dsl = 2

process BIOC_RJMCMCNUCLEOSOMES_CHROMOSOMAL_NUCLEOSOME_POSITIONING {
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
        
        # Load required libraries
        library(RJMCMCNucleosomes)
        library(GenomicRanges)
        
        # Define input file path
        input_file <- "syntheticNucleosomeReads_dataIP.csv"
        
        # Check if the input file exists
        if (!file.exists(input_file)) {
          stop(paste("Required input file '", input_file, "' not found in the working directory.", sep = ""))
        }
        
        # Read the user input data frame
        syntheticNucleosomeReads_dataIP <- read.csv(input_file, stringsAsFactors = FALSE)
        
        # Ensure standard column names for GRanges compatibility
        if ("chr" %in% colnames(syntheticNucleosomeReads_dataIP) && !("seqnames" %in% colnames(syntheticNucleosomeReads_dataIP))) {
          colnames(syntheticNucleosomeReads_dataIP)[colnames(syntheticNucleosomeReads_dataIP) == "chr"] <- "seqnames"
        }
        
        ## Use the dataset to create a GRanges object
        sampleGRanges <- GRanges(syntheticNucleosomeReads_dataIP)
        
        ## Extract the chromosome name from the reads
        chr_name <- as.character(unique(seqnames(sampleGRanges)))[1]
        
        ## Run RJMCMC on all reads
        result <- rjmcmcCHR(reads = sampleGRanges,
                        seqName = chr_name, dirOut = "testRJMCMCCHR",
                        zeta = 147, delta=50, maxLength=1200,
                        nbrIterations = 500, lambda = 3, kMax = 30,
                        minInterval = 146, maxInterval = 292, minReads = 5,
                        vSeed = 10113, nbCores = 2, saveAsRDS = FALSE,
                        saveSEG = FALSE)
        
        # Print the result summary to console
        print(result)
        
        # Save the complete result object as an RDS file
        saveRDS(result, file = "rjmcmc_chromosomal_results.rds")
        
        # Safely check if result has a 'mu' component containing the positions
        has_mu <- FALSE
        if (!is.null(result)) {
          tryCatch({
            if (!is.null(result\$mu)) has_mu <- TRUE
          }, error = function(e) {})
        }
        
        # Export predicted nucleosome positions to a CSV file
        if (!is.null(result)) {
          if (inherits(result, "GRanges")) {
            df_mu <- as.data.frame(result)
          } else if (has_mu) {
            if (inherits(result\$mu, "GRanges")) {
              df_mu <- as.data.frame(result\$mu)
            } else {
              df_mu <- data.frame(position = result\$mu)
            }
          } else {
            df_mu <- data.frame(position = result)
          }
          write.csv(df_mu, "predicted_nucleosome_positions.csv", row.names = FALSE)
        }
        
        # Generate and save the visualization plot
        pdf("predicted_nucleosomes_plot.pdf", width = 10, height = 6)
        tryCatch({
          if (!is.null(result)) {
            # Wrap the predicted positions in a GRangesList for plotting
            if (inherits(result, "GRanges")) {
              plot_list <- GRangesList(Predicted = result)
            } else if (has_mu) {
              if (inherits(result\$mu, "GRanges")) {
                plot_list <- GRangesList(Predicted = result\$mu)
              } else {
                plot_list <- GRangesList(Predicted = GRanges(
                  seqnames = rep(chr_name, length(result\$mu)),
                  ranges = IRanges(start = result\$mu, end = result\$mu),
                  strand = rep("*", length(result\$mu))
                ))
              }
            } else {
              plot_list <- GRangesList(Predicted = GRanges(
                seqnames = rep(chr_name, length(result)),
                ranges = IRanges(start = result, end = result),
                strand = rep("*", length(result))
              ))
            }
            plotNucleosomes(nucleosomePositions = plot_list, reads = sampleGRanges, names = c("Predicted"))
          }
        }, error = function(e) {
          warning("Visualization plot could not be generated: ", e\$message)
        })
        dev.off()

    writeLines(c(
        '"BIOC_RJMCMCNUCLEOSOMES_CHROMOSOMAL_NUCLEOSOME_POSITIONING":',
        paste0('    RJMCMCNucleosomes: ', as.character(packageVersion('RJMCMCNucleosomes')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chromosomal_nucleosome_positioning.csv versions.yml
    """
}

workflow BIOC_RJMCMCNUCLEOSOMES_CHROMOSOMAL_NUCLEOSOME_POSITIONING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ syntheticNucleosomeReads$dataIP ] ]

    main:
    BIOC_RJMCMCNUCLEOSOMES_CHROMOSOMAL_NUCLEOSOME_POSITIONING(ch_input)

    emit:
    tables   = BIOC_RJMCMCNUCLEOSOMES_CHROMOSOMAL_NUCLEOSOME_POSITIONING.out.tables
    plots    = BIOC_RJMCMCNUCLEOSOMES_CHROMOSOMAL_NUCLEOSOME_POSITIONING.out.plots
    objects  = BIOC_RJMCMCNUCLEOSOMES_CHROMOSOMAL_NUCLEOSOME_POSITIONING.out.objects
    versions = BIOC_RJMCMCNUCLEOSOMES_CHROMOSOMAL_NUCLEOSOME_POSITIONING.out.versions
}
