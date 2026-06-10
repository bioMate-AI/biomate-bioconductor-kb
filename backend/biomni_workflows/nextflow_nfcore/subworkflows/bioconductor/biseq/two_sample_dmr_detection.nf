#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BiSeq — two_sample_dmr_detection
// Detect differentially methylated regions (DMRs) between exactly two samples.
// Input: predictedMeth
// Container: quay.io/biocontainers/bioconductor-biseq:1.50.0--r45hdfd78af_0
// R packages: BiSeq, GenomicRanges
// Bioconductor: 3.20 | R: 4.4
// Requires: BiSeq, GenomicRanges
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compare two samples and aggregate sites surpassing the minimum difference

nextflow.enable.dsl = 2

process BIOC_BISEQ_TWO_SAMPLE_DMR_DETECTION {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("BiSeq", "GenomicRanges")
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
    library(BiSeq)
    library(GenomicRanges)
    
    # Read the user input file
    input_file <- "predictedMeth.rds"
    if (!file.exists(input_file)) {
      stop(paste("Input file", input_file, "not found in the working directory."))
    }
    
    predictedMeth <- readRDS(input_file)
    
    # Ensure the input object is of the correct class
    if (!inherits(predictedMeth, "BSrel")) {
      stop("The input object must be of class 'BSrel'.")
    }
    
    if (ncol(predictedMeth) < 2) {
      stop("The input BSrel object must contain at least two samples.")
    }
    
    sample_names <- colnames(predictedMeth)
    
    # === DOCUMENTED CODE ===
    DMRs.2 <- compareTwoSamples(object = predictedMeth,
                                sample1 = sample_names[1],
                                sample2 = sample_names[2],
                                minDiff = 0.3,
                                max.dist = 100)
    # === END DOCUMENTED CODE ===
    
    # Save the results as an RDS object
    saveRDS(DMRs.2, "DMRs_2.rds")
    
    # Export the results to a CSV table
    dmr_df <- as.data.frame(DMRs.2)
    write.csv(dmr_df, "DMRs_2.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_BISEQ_TWO_SAMPLE_DMR_DETECTION":',
        paste0('    BiSeq: ', as.character(packageVersion('BiSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_two_sample_dmr_detection.csv versions.yml
    """
}

workflow BIOC_BISEQ_TWO_SAMPLE_DMR_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ predictedMeth ] ]

    main:
    BIOC_BISEQ_TWO_SAMPLE_DMR_DETECTION(ch_input)

    emit:
    tables   = BIOC_BISEQ_TWO_SAMPLE_DMR_DETECTION.out.tables
    plots    = BIOC_BISEQ_TWO_SAMPLE_DMR_DETECTION.out.plots
    objects  = BIOC_BISEQ_TWO_SAMPLE_DMR_DETECTION.out.objects
    versions = BIOC_BISEQ_TWO_SAMPLE_DMR_DETECTION.out.versions
}
