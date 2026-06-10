#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MPFE — methylation_pattern_estimation
// Estimate and visualize the distribution of DNA methylation patterns from bisulfite sequencing count data, correcting for non-conversion and sequencing errors.
// Input: table_of_counts.txt
// Container: quay.io/biocontainers/bioconductor-mpfe:1.46.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MPFE
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the count data
//  * 2. [Core Analysis] Estimate methylation pattern distributions using estimatePatterns(), specifying non-conversion (epsilon) and sequencing error (eta
//  * 3. [Visualization & Output] Plot the comparison between observed and estimated distributions using plotPatterns()
//  * 4. [Visualization & Output] Visualize the patterns and their frequencies as a grid map using patternMap()

nextflow.enable.dsl = 2

process BIOC_MPFE_METHYLATION_PATTERN_ESTIMATION {
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
        
        # Load required library
        library(MPFE)
        
        # 1. Load the count data
        # The pipeline reads EXACTLY 'table_of_counts.txt' from the working directory.
        # This file must contain a header, with the first column listing the methylation patterns
        # (e.g., "m00000") and subsequent columns containing read counts for each sample.
        if (!file.exists("table_of_counts.txt")) {
          stop("Error: Required input file 'table_of_counts.txt' not found in the working directory.")
        }
        
        patternsExample <- read.table("table_of_counts.txt", header = TRUE, stringsAsFactors = FALSE)
        
        # 2. Estimate methylation pattern distributions using estimatePatterns()
        # Specifying non-conversion (epsilon) and sequencing error (eta) rates.
        
        # First, run estimation on column 2 only (as in the documented code)
        est_col2 <- estimatePatterns(patternsExample, epsilon=0.01, column=2)
        
        # Save the single-column estimation result
        write.csv(est_col2[[1]], "estimates_column2_only.csv", row.names = FALSE)
        
        # Second, run estimation on all columns with site-dependent sequencing error rates (eta)
        # Dynamically determine the number of CpG sites from the pattern string length
        n_cpg <- nchar(gsub("^m", "", as.character(patternsExample[1, 1])))
        eta_array <- rep(0.01, n_cpg)
        if (n_cpg > 0) eta_array[1] <- 0.008
        if (n_cpg > 1) eta_array[n_cpg] <- 0.008
        
        estimates <- estimatePatterns(patternsExample,
                                      epsilon=0.01,
                                      eta=eta_array)
        
        # Save the complete estimates object and individual tables
        saveRDS(estimates, "estimates.rds")
        for (i in seq_along(estimates)) {
          write.csv(estimates[[i]], paste0("estimates_sample_", i, ".csv"), row.names = FALSE)
        }
        
        # 3. Plot the comparison between observed and estimated distributions using plotPatterns()
        pdf("plot_patterns_sample2.pdf", width = 8, height = 10)
        # Safely select the second sample if available, otherwise fallback to the first
        plot_idx <- min(2, length(estimates))
        plotPatterns(estimates[[plot_idx]])
        dev.off()
        
        # 4. Visualize the patterns and their frequencies as a grid map using patternMap()
        pdf("pattern_maps.pdf", width = 10, height = 10)
        par(mfrow=c(2, 2))
        
        patternMap(estimates[[1]],
                   maxFreq=0.5,
                   main='Estimated frequencies')
        
        patternMap(estimates[[1]],
                   estimatedDistribution=FALSE,
                   maxFreq=0.5,
                   topDown=FALSE,
                   main='Observed frequencies')
        
        patternMap(estimates[[1]],
                   maxFreq=0.5,
                   methCol=colorRampPalette(c('red', 'blue')),
                   unMethCol='lightgrey',
                   main='Estimated frequencies')
        
        patternMap(estimates[[1]],
                   estimatedDistribution=FALSE,
                   maxFreq=0.5,
                   methCol=c('bisque4', 'azure4'),
                   unMethCol=c('beige', 'azure'),
                   main='Observed frequencies')
        
        dev.off()

    writeLines(c(
        '"BIOC_MPFE_METHYLATION_PATTERN_ESTIMATION":',
        paste0('    MPFE: ', as.character(packageVersion('MPFE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methylation_pattern_estimation.csv versions.yml
    """
}

workflow BIOC_MPFE_METHYLATION_PATTERN_ESTIMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ table_of_counts.txt ] ]

    main:
    BIOC_MPFE_METHYLATION_PATTERN_ESTIMATION(ch_input)

    emit:
    tables   = BIOC_MPFE_METHYLATION_PATTERN_ESTIMATION.out.tables
    plots    = BIOC_MPFE_METHYLATION_PATTERN_ESTIMATION.out.plots
    objects  = BIOC_MPFE_METHYLATION_PATTERN_ESTIMATION.out.objects
    versions = BIOC_MPFE_METHYLATION_PATTERN_ESTIMATION.out.versions
}
