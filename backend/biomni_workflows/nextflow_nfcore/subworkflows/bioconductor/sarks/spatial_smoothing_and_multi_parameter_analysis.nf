#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sarks — spatial_smoothing_and_multi_parameter_analysis
// Identify multi-motif domains and motifs using spatial smoothing and multiple parameter combinations.
// Input: simulatedSeqs, simulatedScores
// Container: quay.io/biocontainers/bioconductor-sarks:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, rJava, sarks
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize Java virtual machine
//  * 2. [Input & Preparation] Load sequences and scores
//  * 3. [Core Analysis] Initialize Sarks object with spatialLength and nThreads
//  * 4. [Input & Preparation] Define filters with multiple halfWindow and spatialLength values
//  * 5. [Core Analysis] Calculate permutation distribution
//  * 6. [Core Analysis] Determine permutation thresholds with higher nSigma
//  * 7. [Core Analysis] Detect merged k-mer subpeaks
//  * 8. [Visualization & Output] Extract block information for visualization
//  * 9. [Core Analysis] Estimate false positive rate

nextflow.enable.dsl = 2

process BIOC_SARKS_SPATIAL_SMOOTHING_AND_MULTI_PARAMETER_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("rJava", "sarks", "ggplot2")
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
    
    # Set java parameters before loading rJava to allocate sufficient heap space
    options(java.parameters = '-Xmx8G')
    library(rJava)
    .jinit()
    library(sarks)
    library(ggplot2)
    
    # Read user input files from the working directory
    # The pipeline reads EXACTLY these files:
    # - simulatedSeqs (named character vector of sequences)
    # - simulatedScores (named numeric vector of scores)
    if (file.exists("simulatedSeqs.rds")) {
      simulatedSeqs <- readRDS("simulatedSeqs.rds")
    } else if (file.exists("simulatedSeqs")) {
      simulatedSeqs <- readRDS("simulatedSeqs")
    } else {
      stop("Error: 'simulatedSeqs' file not found in the working directory.")
    }
    
    if (file.exists("simulatedScores.rds")) {
      simulatedScores <- readRDS("simulatedScores.rds")
    } else if (file.exists("simulatedScores")) {
      simulatedScores <- readRDS("simulatedScores")
    } else {
      stop("Error: 'simulatedScores' file not found in the working directory.")
    }
    
    # Initialize Sarks object with spatialLength and nThreads
    sarks <- Sarks(simulatedSeqs, simulatedScores, halfWindow=4, spatialLength=3, nThreads=4)
    
    # Define filters with multiple halfWindow and spatialLength values
    filters <- sarksFilters(halfWindow=c(4, 8), spatialLength=c(2, 3), minGini=1.1)
    
    # Calculate permutation distribution
    permDist <- permutationDistribution(sarks, reps=250, filters, seed=123)
    
    # Determine permutation thresholds with higher nSigma
    thresholds <- permutationThresholds(filters, permDist, nSigma=5.0)
    
    # Detect merged k-mer subpeaks
    peaks <- mergedKmerSubPeaks(sarks, filters, thresholds)
    
    # Extract block information for visualization (wrapped in tryCatch for robustness)
    block22 <- tryCatch({
      blockInfo(sarks, block='22', filters, thresholds)
    }, error = function(e) {
      warning("Could not extract block '22' directly. Attempting fallback to first available block.")
      if (length(simulatedSeqs) > 0) {
        fallback_block <- names(simulatedSeqs)[1]
        blockInfo(sarks, block=fallback_block, filters, thresholds)
      } else {
        NULL
      }
    })
    
    # Estimate false positive rate
    fpr = estimateFalsePositiveRate(sarks, reps=250, filters, thresholds, seed=321)
    
    # Write meaningful results to output files
    write.csv(peaks, "merged_kmer_subpeaks.csv", row.names=FALSE)
    saveRDS(permDist, "permutation_distribution.rds")
    saveRDS(thresholds, "permutation_thresholds.rds")
    saveRDS(fpr, "false_positive_rate.rds")
    
    if (!is.null(fpr\$ci)) {
      write.csv(fpr\$ci, "false_positive_rate_ci.csv", row.names=FALSE)
    }
    
    # Plot and save visualization if block info is available
    if (!is.null(block22)) {
      ggo <- ggplot(block22, aes(x=wi+1))
      ggo <- ggo + geom_point(aes(y=windowed), alpha=0.6, size=1)
      ggo <- ggo + geom_line(aes(y=spatialWindowed), alpha=0.6)
      ggo <- ggo + geom_hline(aes(yintercept=spatialTheta), color='red')
      ggo <- ggo + ylab('yhat') + ggtitle(paste('Input Sequence', unique(block22\$block)))
      ggo <- ggo + theme_bw()
      ggsave("block_visualization.pdf", plot=ggo, width=7, height=5)
    }

    writeLines(c(
        '"BIOC_SARKS_SPATIAL_SMOOTHING_AND_MULTI_PARAMETER_ANALYSIS":',
        paste0('    sarks: ', as.character(packageVersion('sarks')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatial_smoothing_and_multi_parameter_analysis.csv versions.yml
    """
}

workflow BIOC_SARKS_SPATIAL_SMOOTHING_AND_MULTI_PARAMETER_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ simulatedSeqs, simulatedScores ] ]

    main:
    BIOC_SARKS_SPATIAL_SMOOTHING_AND_MULTI_PARAMETER_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SARKS_SPATIAL_SMOOTHING_AND_MULTI_PARAMETER_ANALYSIS.out.tables
    plots    = BIOC_SARKS_SPATIAL_SMOOTHING_AND_MULTI_PARAMETER_ANALYSIS.out.plots
    objects  = BIOC_SARKS_SPATIAL_SMOOTHING_AND_MULTI_PARAMETER_ANALYSIS.out.objects
    versions = BIOC_SARKS_SPATIAL_SMOOTHING_AND_MULTI_PARAMETER_ANALYSIS.out.versions
}
