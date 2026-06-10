#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: baySeq — paired_data_beta_binomial
// Identify differential expression between replicate groups and consistent differences within pairs using a beta-binomial distribution.
// Input: pairData
// Container: quay.io/biocontainers/bioconductor-bayseq:2.44.0--r45hdfd78af_0
// R packages: baySeq
// Bioconductor: 3.20 | R: 4.4
// Requires: baySeq
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create countData object with 3D array and bbDensity
//  * 2. [Core Analysis] Estimate library sizes
//  * 3. [Core Analysis] Estimate priors using getPriors
//  * 4. [Core Analysis] Calculate likelihoods with nullData = TRUE
//  * 5. [Core Analysis] Extract top counts for replicate groups or pairs

nextflow.enable.dsl = 2

process BIOC_BAYSEQ_PAIRED_DATA_BETA_BINOMIAL {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("baySeq")
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
    library(baySeq)
    
    # Setup parallel processing if available
    cl <- NULL
    if (requireNamespace("parallel", quietly = TRUE)) {
      cl <- parallel::makeCluster(min(2, parallel::detectCores()))
    }
    
    # Read user input file 'pairData' from the working directory
    # Supports CSV, TSV, TXT, or RDS formats
    if (file.exists("pairData.csv")) {
      pairData <- as.matrix(read.csv("pairData.csv", row.names = 1))
    } else if (file.exists("pairData.tsv")) {
      pairData <- as.matrix(read.delim("pairData.tsv", row.names = 1))
    } else if (file.exists("pairData.txt")) {
      pairData <- as.matrix(read.table("pairData.txt", header = TRUE, row.names = 1))
    } else if (file.exists("pairData.rds")) {
      pairData <- readRDS("pairData.rds")
    } else if (file.exists("pairData")) {
      pairData <- tryCatch({
        readRDS("pairData")
      }, error = function(e) {
        as.matrix(read.table("pairData", header = TRUE, row.names = 1))
      })
    } else {
      stop("Error: Input file 'pairData' (CSV, TSV, TXT, or RDS) not found in the working directory.")
    }
    
    # Ensure pairData has at least 8 columns as required by the array construction
    if (ncol(pairData) < 8) {
      stop("Error: 'pairData' must have at least 8 columns for paired analysis (4 pairs).")
    }
    
    # 1. Create countData object with 3D array and bbDensity
    pairCD <- new("countData", 
                  data = array(c(pairData[,1:4], pairData[,5:8]), dim = c(nrow(pairData), 4, 2)), 
                  replicates = c(1,1,2,2), 
                  groups = list(NDE = c(1,1,1,1), DE = c(1,1,2,2)), 
                  densityFunction = bbDensity)
    
    # 2. Estimate library sizes
    libsizes(pairCD) <- getLibsizes(pairCD)
    
    # 3. Estimate priors using getPriors
    pairCD <- getPriors(pairCD, samplesize = 1000, cl = cl)
    
    # 4. Calculate likelihoods with nullData = TRUE
    pairCD <- getLikelihoods(pairCD, pET = 'BIC', nullData = TRUE, cl = cl)
    
    # 5. Extract top counts for replicate groups or pairs
    top_DE <- topCounts(pairCD, group = 2)
    top_NDE <- topCounts(pairCD, group = 1)
    
    # Write outputs to the working directory
    write.csv(top_DE, file = "top_counts_DE.csv", row.names = TRUE)
    write.csv(top_NDE, file = "top_counts_NDE.csv", row.names = TRUE)
    saveRDS(pairCD, file = "pairCD_results.rds")
    
    # Clean up cluster if it was created
    if (!is.null(cl)) {
      parallel::stopCluster(cl)
    }

    writeLines(c(
        '"BIOC_BAYSEQ_PAIRED_DATA_BETA_BINOMIAL":',
        paste0('    baySeq: ', as.character(packageVersion('baySeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_paired_data_beta_binomial.csv versions.yml
    """
}

workflow BIOC_BAYSEQ_PAIRED_DATA_BETA_BINOMIAL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pairData ] ]

    main:
    BIOC_BAYSEQ_PAIRED_DATA_BETA_BINOMIAL(ch_input)

    emit:
    tables   = BIOC_BAYSEQ_PAIRED_DATA_BETA_BINOMIAL.out.tables
    plots    = BIOC_BAYSEQ_PAIRED_DATA_BETA_BINOMIAL.out.plots
    objects  = BIOC_BAYSEQ_PAIRED_DATA_BETA_BINOMIAL.out.objects
    versions = BIOC_BAYSEQ_PAIRED_DATA_BETA_BINOMIAL.out.versions
}
