#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sarks — basic_motif_discovery
// Identify individual sequence motifs correlated with numeric scores without spatial smoothing.
// Input: simulatedSeqs, simulatedScores
// Container: quay.io/biocontainers/bioconductor-sarks:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: rJava, sarks
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize Java virtual machine with sufficient memory
//  * 2. [Input & Preparation] Load sequences and scores
//  * 3. [Core Analysis] Initialize Sarks object with halfWindow parameter
//  * 4. [Input & Preparation] Define filters with spatialLength=0
//  * 5. [Core Analysis] Calculate permutation distribution
//  * 6. [Core Analysis] Determine permutation thresholds
//  * 7. [Core Analysis] Detect k-mer peaks
//  * 8. [Core Analysis] Merge redundant subpeaks and extend k-mers
//  * 9. [Core Analysis] Estimate false positive rate

nextflow.enable.dsl = 2

process BIOC_SARKS_BASIC_MOTIF_DISCOVERY {
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
    .bm_deps <- c("rJava", "sarks")
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
    
    # Set Java parameters and initialize JVM before loading sarks
    options(java.parameters = '-Xmx8G')
    library(rJava)
    .jinit()
    library(sarks)
    
    # Helper function to robustly read the user input files
    read_input <- function(filename) {
      if (file.exists(filename)) {
        return(readRDS(filename))
      } else if (file.exists(paste0(filename, ".rds"))) {
        return(readRDS(paste0(filename, ".rds")))
      } else {
        stop(paste("Required input file not found:", filename))
      }
    }
    
    # Load user input sequences and scores
    simulatedSeqs <- read_input("simulatedSeqs")
    simulatedScores <- read_input("simulatedScores")
    
    # Run the SArKS pipeline exactly as documented
    sarks <- Sarks(simulatedSeqs, simulatedScores, halfWindow=4)
    filters <- sarksFilters(halfWindow=4, spatialLength=0, minGini=1.1)
    permDist <- permutationDistribution(sarks, reps=250, filters, seed=123)
    thresholds <- permutationThresholds(filters, permDist, nSigma=2.0)
    peaks <- kmerPeaks(sarks, filters, thresholds)
    nonRedundantPeaks <- mergedKmerSubPeaks(sarks, filters, thresholds)
    extendedPeaks <- extendKmers(sarks, nonRedundantPeaks)
    fpr = estimateFalsePositiveRate(sarks, reps=250, filters, thresholds, seed=321)
    
    # Write meaningful output files
    write.csv(peaks, "peaks.csv", row.names = FALSE)
    write.csv(nonRedundantPeaks, "non_redundant_peaks.csv", row.names = FALSE)
    write.csv(extendedPeaks, "extended_peaks.csv", row.names = FALSE)
    write.csv(fpr\$ci, "fpr_confidence_intervals.csv", row.names = FALSE)
    saveRDS(fpr, "fpr_results.rds")
    
    # Generate and save the yhat plot
    yhat <- sarks\$getYhat()
    i0based <- seq(0, length(yhat) - 1)
    pdf("yhat_plot.pdf", width = 7, height = 5)
    plot(i0based, yhat, type = 'l', xlab = 'i', ylab = 'yhat', main = 'SArKS Smoothing Window Scores (yhat)')
    dev.off()

    writeLines(c(
        '"BIOC_SARKS_BASIC_MOTIF_DISCOVERY":',
        paste0('    sarks: ', as.character(packageVersion('sarks')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_basic_motif_discovery.csv versions.yml
    """
}

workflow BIOC_SARKS_BASIC_MOTIF_DISCOVERY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ simulatedSeqs, simulatedScores ] ]

    main:
    BIOC_SARKS_BASIC_MOTIF_DISCOVERY(ch_input)

    emit:
    tables   = BIOC_SARKS_BASIC_MOTIF_DISCOVERY.out.tables
    plots    = BIOC_SARKS_BASIC_MOTIF_DISCOVERY.out.plots
    objects  = BIOC_SARKS_BASIC_MOTIF_DISCOVERY.out.objects
    versions = BIOC_SARKS_BASIC_MOTIF_DISCOVERY.out.versions
}
