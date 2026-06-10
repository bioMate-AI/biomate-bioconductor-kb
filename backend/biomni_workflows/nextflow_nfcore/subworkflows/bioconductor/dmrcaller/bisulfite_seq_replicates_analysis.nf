#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DMRcaller — bisulfite_seq_replicates_analysis
// Identify DMRs from bisulfite sequencing data with biological replicates using beta regression.
// Input: replicates_joined.rds
// Container: quay.io/biocontainers/bioconductor-dmrcaller:1.42.0--r45ha27e39d_0
// R packages: DMRcaller, GenomicRanges
// Bioconductor: 3.20 | R: 4.4
// Requires: DMRcaller, GenomicRanges
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define condition vector
//  * 2. [Core Analysis] Compute DMRs across replicates using computeDMRsReplicates with test = "betareg"

nextflow.enable.dsl = 2

process BIOC_DMRCALLER_BISULFITE_SEQ_REPLICATES_ANALYSIS {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("DMRcaller", "GenomicRanges")
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
    library(DMRcaller)
    library(GenomicRanges)
    
    # Read the user input file
    # The user-provided replicates_joined.rds is a GRanges object containing joined methylation data with replicates
    syntheticDataReplicates <- readRDS("replicates_joined.rds")
    
    # 1. Define condition vector
    condition <- c("a", "a", "b", "b")
    
    # 2. Compute DMRs across replicates using computeDMRsReplicates with test = "betareg"
    # Keep every documented function call and its argument names EXACTLY as shown in the vignette
    DMRsReplicatesBins <- computeDMRsReplicates(methylationData = syntheticDataReplicates,
                                                condition = condition,
                                                regions = NULL,
                                                context = "CG",
                                                method = "bins",
                                                binSize = 100,
                                                test = "betareg",
                                                pseudocountM = 1,
                                                pseudocountN = 2,
                                                pValueThreshold = 0.01,
                                                minCytosinesCount = 4,
                                                minProportionDifference = 0.4,
                                                minGap = 0,
                                                minSize = 50,
                                                minReadsPerCytosine = 4,
                                                cores = 1)
    
    # Print the identified DMRs to console
    print(DMRsReplicatesBins)
    
    # Save the results to output files
    # Save as RDS object
    saveRDS(DMRsReplicatesBins, file = "DMRsReplicatesBins.rds")
    
    # Save as CSV table
    write.csv(as.data.frame(DMRsReplicatesBins), file = "DMRsReplicatesBins.csv", row.names = FALSE)
    
    # Generate a diagnostic plot of the identified DMRs and save as PDF
    pdf("DMRsReplicates_plot.pdf", width = 7, height = 5)
    if (length(DMRsReplicatesBins) > 0) {
      # Plot the distribution of DMR sizes
      hist(width(DMRsReplicatesBins), 
           main = "Distribution of Identified DMR Sizes", 
           xlab = "DMR Width (bp)", 
           col = "skyblue", 
           border = "white")
    } else {
      plot(1, type = "n", axes = FALSE, xlab = "", ylab = "", main = "No DMRs identified")
      text(1, 1, "No DMRs met the filtering criteria.", cex = 1.2)
    }
    dev.off()

    writeLines(c(
        '"BIOC_DMRCALLER_BISULFITE_SEQ_REPLICATES_ANALYSIS":',
        paste0('    DMRcaller: ', as.character(packageVersion('DMRcaller')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bisulfite_seq_replicates_analysis.csv versions.yml
    """
}

workflow BIOC_DMRCALLER_BISULFITE_SEQ_REPLICATES_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ replicates_joined.rds ] ]

    main:
    BIOC_DMRCALLER_BISULFITE_SEQ_REPLICATES_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DMRCALLER_BISULFITE_SEQ_REPLICATES_ANALYSIS.out.tables
    plots    = BIOC_DMRCALLER_BISULFITE_SEQ_REPLICATES_ANALYSIS.out.plots
    objects  = BIOC_DMRCALLER_BISULFITE_SEQ_REPLICATES_ANALYSIS.out.objects
    versions = BIOC_DMRCALLER_BISULFITE_SEQ_REPLICATES_ANALYSIS.out.versions
}
