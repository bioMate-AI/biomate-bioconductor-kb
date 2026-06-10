#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: baySeq — generic_zinb_analysis
// Identify differential expression using a pre-defined generic distribution (like ZINB) for zero-inflated data.
// Input: zimData
// Container: quay.io/biocontainers/bioconductor-bayseq:2.44.0--r45hdfd78af_0
// R packages: baySeq
// Bioconductor: 3.20 | R: 4.4
// Requires: baySeq
// Visualizations: plot (ggplot/base)
// QC: diagnostic MA/PCA QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create countData object
//  * 2. [Core Analysis] Estimate library sizes
//  * 3. [Core Analysis] Set densityFunction to ZINBDensity
//  * 4. [Core Analysis] Estimate priors using generic getPriors
//  * 5. [Core Analysis] Calculate likelihoods using getLikelihoods

nextflow.enable.dsl = 2

process BIOC_BAYSEQ_GENERIC_ZINB_ANALYSIS {
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
    library(parallel)
    
    # -----------------------------------------------------------------------------
    # 1. Read User Input
    # -----------------------------------------------------------------------------
    # The pipeline expects 'zimData' (matrix of zero-inflated counts) in the working directory.
    # We support CSV, RDS, or TSV/TXT formats.
    zimData <- NULL
    
    if (file.exists("zimData.csv")) {
      zimData <- as.matrix(read.csv("zimData.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("zimData.rds")) {
      zimData <- readRDS("zimData.rds")
      if (!is.matrix(zimData)) {
        zimData <- as.matrix(zimData)
      }
    } else if (file.exists("zimData.txt")) {
      zimData <- as.matrix(read.table("zimData.txt", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE))
    } else {
      stop("Required input file 'zimData' (as zimData.csv, zimData.rds, or zimData.txt) not found in the working directory.")
    }
    
    # Validate dimensions (must have exactly 10 columns to match the replicates/groups)
    if (ncol(zimData) != 10) {
      stop(paste("Input 'zimData' must have exactly 10 columns to match the experimental design. Found:", ncol(zimData)))
    }
    
    # -----------------------------------------------------------------------------
    # 2. Parallel Processing Setup
    # -----------------------------------------------------------------------------
    cores <- min(4, parallel::detectCores() - 1)
    if (is.na(cores) || cores < 1) cores <- 1
    cl <- parallel::makeCluster(cores)
    
    # -----------------------------------------------------------------------------
    # 3. Execute baySeq Generic ZINB Workflow
    # -----------------------------------------------------------------------------
    # Create countData object
    CD <- new("countData", 
              data = zimData, 
              replicates = c("simA", "simA", "simA", "simA", "simA", "simB", "simB", "simB", "simB", "simB"), 
              groups = list(NDE = c(1,1,1,1,1,1,1,1,1,1), DE = c(1,1,1,1,1,2,2,2,2,2)))
    
    # Estimate library sizes
    libsizes(CD) <- getLibsizes(CD)
    
    # Set densityFunction to ZINBDensity
    CDz <- CD
    densityFunction(CDz) <- ZINBDensity
    
    # Estimate priors using generic getPriors
    CDz <- getPriors(CDz, cl = cl)
    
    # Calculate likelihoods using getLikelihoods
    CDz <- getLikelihoods(CDz, cl = cl)
    
    # Stop cluster safely
    if (!is.null(cl)) {
      parallel::stopCluster(cl)
    }
    
    # -----------------------------------------------------------------------------
    # 4. Write Outputs
    # -----------------------------------------------------------------------------
    # Save the complete analyzed object
    saveRDS(CDz, file = "CDz_analyzed.rds")
    
    # Extract and save posterior probabilities
    posteriors_df <- as.data.frame(CDz@posteriors)
    write.csv(posteriors_df, file = "posteriors.csv", row.names = TRUE)
    
    # Extract and save top differentially expressed counts
    # We attempt to extract all rows ordered by likelihood of being DE
    tryCatch({
      top_de <- topCounts(CDz, group = "DE", number = nrow(CDz))
      write.csv(top_de, file = "top_counts_DE.csv", row.names = TRUE)
    }, error = function(e) {
      warning("Could not write topCounts table: ", e\$message)
    })
    
    # Generate and save diagnostic plots
    tryCatch({
      pdf("bayseq_zinb_plots.pdf", width = 7, height = 7)
      
      # Plot MA
      plotMA.CD(CDz, samplesA = "simA", samplesB = "simB",
                main = "MA Plot (ZINB Model)")
      
      # Plot Posteriors
      plotPosteriors(CDz, group = "DE",
                     main = "Posterior Likelihoods of DE")
      
      dev.off()
    }, error = function(e) {
      warning("Could not generate PDF plots: ", e\$message)
    })

    writeLines(c(
        '"BIOC_BAYSEQ_GENERIC_ZINB_ANALYSIS":',
        paste0('    baySeq: ', as.character(packageVersion('baySeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_generic_zinb_analysis.csv versions.yml
    """
}

workflow BIOC_BAYSEQ_GENERIC_ZINB_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ zimData ] ]

    main:
    BIOC_BAYSEQ_GENERIC_ZINB_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_BAYSEQ_GENERIC_ZINB_ANALYSIS.out.tables
    plots    = BIOC_BAYSEQ_GENERIC_ZINB_ANALYSIS.out.plots
    objects  = BIOC_BAYSEQ_GENERIC_ZINB_ANALYSIS.out.objects
    versions = BIOC_BAYSEQ_GENERIC_ZINB_ANALYSIS.out.versions
}
